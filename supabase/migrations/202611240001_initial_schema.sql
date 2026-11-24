create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  currency text not null default 'PHP',
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create function public.create_profile_for_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.create_profile_for_user();

create function public.sync_profile_name()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles
  set display_name = coalesce(new.raw_user_meta_data ->> 'display_name', ''), updated_at = now()
  where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_metadata_updated
  after update of raw_user_meta_data on auth.users
  for each row execute function public.sync_profile_name();

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  type text not null check (type in ('cash', 'e-wallet')),
  balance numeric(15,2) not null default 0 check (balance >= 0),
  description text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  type text not null check (type in ('income', 'expense')),
  color text not null default '#6c757d',
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  unique (id, user_id, type)
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  account_id uuid not null,
  category_id uuid not null,
  type text not null check (type in ('income', 'expense')),
  amount numeric(15,2) not null check (amount > 0),
  description text check (description is null or length(description) <= 255),
  transaction_date date not null default current_date,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (account_id, user_id) references public.accounts(id, user_id),
  foreign key (category_id, user_id, type) references public.categories(id, user_id, type)
);

create function public.require_active_transaction_choices()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not exists (
    select 1 from public.accounts
    where id = new.account_id and user_id = new.user_id and deleted_at is null
  ) then
    raise exception 'Choose an active account.' using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.categories
    where id = new.category_id and user_id = new.user_id
      and type = new.type and deleted_at is null
  ) then
    raise exception 'Choose an active category for this transaction type.' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger transactions_require_active_choices
  before insert or update on public.transactions
  for each row execute function public.require_active_transaction_choices();

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  category_id uuid not null,
  category_type text not null default 'expense' check (category_type = 'expense'),
  year integer not null check (year between 2000 and 2200),
  month integer not null check (month between 1 and 12),
  amount numeric(15,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, category_id, year, month),
  foreign key (category_id, user_id, category_type) references public.categories(id, user_id, type)
);

create table public.recurring_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  account_id uuid not null,
  category_id uuid not null,
  type text not null check (type in ('income', 'expense')),
  amount numeric(15,2) not null check (amount > 0),
  description text not null check (length(trim(description)) between 1 and 255),
  frequency text not null check (frequency in ('weekly', 'monthly')),
  interval smallint not null default 1 check (interval > 0),
  reminder_days_before smallint not null default 3 check (reminder_days_before between 0 and 30),
  start_date date not null,
  next_due_date date,
  ends_on date,
  last_processed_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (account_id, user_id) references public.accounts(id, user_id),
  foreign key (category_id, user_id, type) references public.categories(id, user_id, type),
  check (ends_on is null or ends_on >= start_date)
);

create trigger recurring_transactions_require_active_choices
  before insert or update on public.recurring_transactions
  for each row execute function public.require_active_transaction_choices();

create table public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type text not null,
  title text not null,
  message text not null,
  data jsonb not null default '{}'::jsonb,
  fingerprint text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, fingerprint)
);

create index transactions_user_date_idx on public.transactions(user_id, transaction_date desc) where deleted_at is null;
create index recurring_user_due_idx on public.recurring_transactions(user_id, next_due_date) where is_active;
create index notifications_user_read_idx on public.app_notifications(user_id, read_at, created_at desc);

create function public.apply_transaction_balance()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  old_active boolean := false;
  new_active boolean := false;
  changed integer;
begin
  if tg_op <> 'INSERT' then
    old_active := old.deleted_at is null;
    if old_active then
      update public.accounts
      set balance = balance + case when old.type = 'income' then -old.amount else old.amount end,
          updated_at = now()
      where id = old.account_id and user_id = old.user_id;
    end if;
  end if;

  if tg_op <> 'DELETE' then
    new_active := new.deleted_at is null;
    if new_active then
      update public.accounts
      set balance = balance + case when new.type = 'income' then new.amount else -new.amount end,
          updated_at = now()
      where id = new.account_id and user_id = new.user_id
        and (new.type = 'income' or balance >= new.amount);
      get diagnostics changed = row_count;
      if changed = 0 then
        raise exception 'Insufficient account balance.' using errcode = '23514';
      end if;
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger transactions_update_balance
  after insert or update or delete on public.transactions
  for each row execute function public.apply_transaction_balance();

create function public.confirm_recurring_transaction(p_id uuid)
returns public.recurring_transactions
language plpgsql security invoker set search_path = '' as $$
declare
  item public.recurring_transactions;
  current_due date;
  next_due date;
  target_day integer;
begin
  select * into item from public.recurring_transactions
  where id = p_id and user_id = auth.uid() and is_active
  for update;
  if not found or item.next_due_date is null then
    raise exception 'This recurring item is no longer active.' using errcode = '22023';
  end if;
  if item.next_due_date > current_date then
    raise exception 'This recurring item is not due yet.' using errcode = '22023';
  end if;

  current_due := item.next_due_date;
  insert into public.transactions (user_id, account_id, category_id, type, amount, description, transaction_date)
  values (item.user_id, item.account_id, item.category_id, item.type, item.amount, item.description, current_due);

  if item.frequency = 'weekly' then
    next_due := current_due + (7 * item.interval);
  else
    target_day := extract(day from current_due)::integer;
    next_due := (date_trunc('month', current_due)::date + make_interval(months => item.interval))
      + (least(target_day, extract(day from (date_trunc('month', current_due)::date + make_interval(months => item.interval) + interval '1 month - 1 day'))::integer) - 1);
  end if;
  if item.ends_on is not null and next_due > item.ends_on then next_due := null; end if;

  update public.recurring_transactions
  set last_processed_at = now(), next_due_date = next_due,
      is_active = next_due is not null, updated_at = now()
  where id = item.id returning * into item;
  return item;
end;
$$;

alter table public.profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;
alter table public.recurring_transactions enable row level security;
alter table public.app_notifications enable row level security;

create policy "Users manage own profile" on public.profiles for all to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "Users manage own accounts" on public.accounts for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Users manage own categories" on public.categories for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Users manage own transactions" on public.transactions for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Users manage own budgets" on public.budgets for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Users manage own recurring transactions" on public.recurring_transactions for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Users manage own notifications" on public.app_notifications for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

grant execute on function public.confirm_recurring_transaction(uuid) to authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, currency, updated_at) on public.profiles to authenticated;
grant select, insert, delete on public.accounts, public.categories,
  public.transactions, public.budgets, public.recurring_transactions,
  public.app_notifications to authenticated;
grant update on public.categories, public.transactions,
  public.budgets, public.recurring_transactions, public.app_notifications to authenticated;
grant update (name, type, description, deleted_at, updated_at) on public.accounts to authenticated;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

create policy "Users read own avatars" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Users upload own avatars" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Users update own avatars" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Users delete own avatars" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
