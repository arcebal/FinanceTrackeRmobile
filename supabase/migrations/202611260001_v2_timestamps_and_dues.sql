alter table public.transactions
  add column transaction_at timestamptz;

update public.transactions
set transaction_at = (transaction_date + (created_at at time zone 'Asia/Manila')::time)
  at time zone 'Asia/Manila';

alter table public.transactions
  alter column transaction_at set default now(),
  alter column transaction_at set not null;

create index transactions_user_timestamp_idx
  on public.transactions(user_id, transaction_at desc)
  where deleted_at is null;

create table public.dues (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  account_id uuid not null,
  category_id uuid not null,
  type text not null default 'expense' check (type = 'expense'),
  amount numeric(15,2) not null check (amount > 0),
  description text not null check (length(trim(description)) between 1 and 255),
  due_date date not null,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (account_id, user_id) references public.accounts(id, user_id),
  foreign key (category_id, user_id, type) references public.categories(id, user_id, type)
);

create trigger dues_require_active_choices
  before insert or update on public.dues
  for each row execute function public.require_active_transaction_choices();

insert into public.dues
  (id, user_id, account_id, category_id, type, amount, description, due_date, created_at, updated_at)
select id, user_id, account_id, category_id, 'expense', amount, description,
       next_due_date, created_at, updated_at
from public.recurring_transactions
where type = 'expense' and is_active and next_due_date is not null;

create index dues_user_date_idx on public.dues(user_id, due_date) where deleted_at is null;
alter table public.dues enable row level security;
create policy "Users manage own dues" on public.dues for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
grant select, insert, update, delete on public.dues to authenticated;
