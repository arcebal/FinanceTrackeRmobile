import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _db = Supabase.instance.client;
final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _date = DateFormat('MMM d, yyyy');

List<Map<String, dynamic>> _maps(dynamic value) =>
    List<Map<String, dynamic>>.from(value as List);
String _money(Object? value) =>
    _currency.format((value as num?)?.toDouble() ?? 0);
String _error(Object error) =>
    error is PostgrestException ? error.message : error.toString();

Widget _loading() => const Center(child: CircularProgressIndicator());
Widget _problem(Object error, VoidCallback retry) => Center(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 40),
        const SizedBox(height: 12),
        Text(_error(error), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    ),
  ),
);

Widget _empty(String message, {IconData icon = Icons.inbox_outlined}) => Center(
  child: Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: Colors.blueGrey),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.blueGrey),
        ),
      ],
    ),
  ),
);

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    final accounts = _maps(
      await _db
          .from('accounts')
          .select('id,name,type,balance')
          .isFilter('deleted_at', null)
          .order('name'),
    );
    final transactions = _maps(
      await _db
          .from('transactions')
          .select(
            'id,type,amount,description,transaction_date,categories(name,color),accounts(name)',
          )
          .isFilter('deleted_at', null)
          .order('transaction_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(5),
    );
    final monthTransactions = _maps(
      await _db
          .from('transactions')
          .select('category_id,type,amount')
          .isFilter('deleted_at', null)
          .gte('transaction_date', DateFormat('yyyy-MM-dd').format(start))
          .lte('transaction_date', DateFormat('yyyy-MM-dd').format(end)),
    );
    final budgets = _maps(
      await _db
          .from('budgets')
          .select('category_id,amount,categories(name,color)')
          .eq('year', now.year)
          .eq('month', now.month),
    );
    final upcoming = _maps(
      await _db
          .from('recurring_transactions')
          .select('description,type,amount,next_due_date,accounts(name)')
          .eq('type', 'expense')
          .eq('is_active', true)
          .gte(
            'next_due_date',
            DateFormat('yyyy-MM-dd')
                .format(DateTime(now.year, now.month, now.day)),
          )
          .lte(
            'next_due_date',
            DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 7))),
          )
          .order('next_due_date'),
    );
    final income = monthTransactions
        .where((r) => r['type'] == 'income')
        .fold<double>(0, (sum, r) => sum + (r['amount'] as num).toDouble());
    final expense = monthTransactions
        .where((r) => r['type'] == 'expense')
        .fold<double>(0, (sum, r) => sum + (r['amount'] as num).toDouble());
    final balance = accounts.fold<double>(
      0,
      (sum, r) => sum + (r['balance'] as num).toDouble(),
    );
    final spent = <String, double>{};
    for (final row in monthTransactions.where((r) => r['type'] == 'expense')) {
      final id = row['category_id'] as String;
      spent[id] = (spent[id] ?? 0) + (row['amount'] as num).toDouble();
    }
    return {
      'accounts': accounts,
      'transactions': transactions,
      'income': income,
      'expense': expense,
      'balance': balance,
      'budgets': budgets,
      'spent': spent,
      'upcoming': upcoming,
    };
  }

  void _refresh() => setState(() {
    _future = _load();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return _loading();
      if (snapshot.hasError) return _problem(snapshot.error!, _refresh);
      final data = snapshot.data!;
      final accounts = data['accounts'] as List<Map<String, dynamic>>;
      final transactions = data['transactions'] as List<Map<String, dynamic>>;
      final budgets = data['budgets'] as List<Map<String, dynamic>>;
      final spent = data['spent'] as Map<String, double>;
      final upcoming = data['upcoming'] as List<Map<String, dynamic>>;
      return RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              DateFormat('EEEE, MMMM d').format(DateTime.now()),
              style: const TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total balance',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _money(data['balance']),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _metric(
                            'Income this month',
                            _money(data['income']),
                            const Color(0xFF168A59),
                          ),
                        ),
                        Expanded(
                          child: _metric(
                            'Expenses',
                            _money(data['expense']),
                            const Color(0xFFE25572),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _sectionTitle(context, 'My accounts'),
            if (accounts.isEmpty)
              _empty(
                'Add an account to start tracking your money.',
                icon: Icons.account_balance_wallet_outlined,
              )
            else
              SizedBox(
                height: 108,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: accounts.map(_accountCard).toList(),
                ),
              ),
            _sectionTitle(context, 'Budget health'),
            if (budgets.isEmpty)
              _empty(
                'Set a monthly budget to see how your spending is going.',
                icon: Icons.savings_outlined,
              )
            else
              ...budgets.map((b) {
                final category = b['categories'] as Map<String, dynamic>? ?? {};
                final amount = (b['amount'] as num).toDouble();
                final actual = spent[b['category_id'] as String] ?? 0;
                final over = actual > amount;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                category['name'] as String? ?? 'Category',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text('${_money(actual)} / ${_money(amount)}'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: (actual / amount).clamp(0, 1),
                          color: over ? Colors.red : const Color(0xFF168A59),
                          minHeight: 7,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          over
                              ? 'Over by ${_money(actual - amount)}'
                              : '${_money(amount - actual)} remaining',
                          style: TextStyle(
                            color: over ? Colors.red : Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            _sectionTitle(context, 'Due in the next 7 days'),
            if (upcoming.isEmpty)
              _empty(
                'No recurring items are due this week.',
                icon: Icons.event_available_outlined,
              )
            else
              ...upcoming.map(
                (r) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_repeat),
                    title: Text(r['description'] as String),
                    subtitle: Text(
                      '${r['next_due_date']} · ${(r['accounts'] as Map?)?['name'] ?? 'Account'}',
                    ),
                    trailing: Text(_money(r['amount'])),
                  ),
                ),
              ),
            _sectionTitle(context, 'Recent activity'),
            if (transactions.isEmpty)
              _empty(
                'Your recent transactions will appear here.',
                icon: Icons.receipt_long_outlined,
              )
            else
              ...transactions.map((t) => _transactionTile(t)),
          ],
        ),
      );
    },
  );
}

Widget _metric(String label, String value, Color color) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(label, style: const TextStyle(color: Colors.blueGrey)),
    const SizedBox(height: 4),
    Text(
      value,
      style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700),
    ),
  ],
);
Widget _sectionTitle(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
  child: Text(
    title,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w700),
  ),
);
Widget _accountCard(Map<String, dynamic> account) => SizedBox(
  width: 190,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            account['name'] as String,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            _money(account['balance']),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          Text(
            account['type'] == 'cash' ? 'Cash' : 'E-wallet',
            style: const TextStyle(color: Colors.blueGrey),
          ),
        ],
      ),
    ),
  ),
);
Widget _transactionTile(Map<String, dynamic> t) {
  final income = t['type'] == 'income';
  final category = t['categories'] as Map<String, dynamic>?;
  return Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: (income
            ? const Color(0xFFE7F7ED)
            : const Color(0xFFFFEEF0)),
        child: Icon(
          income ? Icons.south_west : Icons.north_east,
          color: income ? const Color(0xFF168A59) : const Color(0xFFE25572),
        ),
      ),
      title: Text(
        (t['description'] as String?)?.isNotEmpty == true
            ? t['description'] as String
            : category?['name'] as String? ?? 'Transaction',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${category?['name'] ?? 'No category'} · ${t['transaction_date']}',
      ),
      trailing: Text(
        '${income ? '+' : '−'}${_money(t['amount'])}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: income ? const Color(0xFF168A59) : const Color(0xFFE25572),
        ),
      ),
    ),
  );
}

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});
  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  bool _archived = false;
  Future<List<Map<String, dynamic>>> _load() async {
    final query = _db.from('accounts').select();
    final result = _archived
        ? await query.not('deleted_at', 'is', null).order('name')
        : await query.isFilter('deleted_at', null).order('name');
    return _maps(result);
  }

  void _refresh() => setState(() {
    _future = _load();
  });

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AccountEditor(initial: row),
    );
    if (result == null) return;
    try {
      if (row == null) {
        await _db.from('accounts').insert(result);
      } else {
        await _db.from('accounts').update(result).eq('id', row['id']);
      }
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(e))));
      }
    }
  }

  Future<void> _archive(Map<String, dynamic> row) async {
    await _db
        .from('accounts')
        .update({
          'deleted_at': _archived
              ? null
              : DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', row['id']);
    _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              const Expanded(child: Text('Cash and e-wallets')),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _archived = !_archived;
                    _future = _load();
                  });
                },
                icon: Icon(_archived ? Icons.list_alt : Icons.archive_outlined),
                label: Text(_archived ? 'Active' : 'Archived'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) return _loading();
              if (s.hasError) return _problem(s.error!, _refresh);
              final rows = s.data!;
              if (rows.isEmpty) {
                return _empty(
                  _archived ? 'No archived accounts.' : 'No accounts yet. Add cash or an e-wallet account to get started.',
                  icon: Icons.account_balance_wallet_outlined,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: rows
                      .map(
                        (r) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                r['type'] == 'cash'
                                    ? Icons.payments_outlined
                                    : Icons.account_balance_wallet_outlined,
                              ),
                            ),
                            title: Text(r['name'] as String),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(r['type'] == 'cash' ? 'Cash' : 'E-wallet'),
                                if ((r['description'] as String?)?.isNotEmpty ==
                                    true)
                                  Text(
                                    r['description'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _money(r['balance']),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (action) {
                                    if (action == 'edit') _edit(r);
                                    if (action == 'archive') _archive(r);
                                  },
                                  itemBuilder: (_) => [
                                    if (!_archived)
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                    PopupMenuItem(
                                      value: 'archive',
                                      child: Text(
                                        _archived ? 'Restore' : 'Archive',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
        ),
      ],
    ),
    floatingActionButton: _archived
        ? null
        : FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Account'),
          ),
  );
}

class AccountEditor extends StatefulWidget {
  const AccountEditor({super.key, this.initial});
  final Map<String, dynamic>? initial;
  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  final _key = GlobalKey<FormState>();
  late String _name = widget.initial?['name'] as String? ?? '';
  late String _description = widget.initial?['description'] as String? ?? '';
  late String _type = widget.initial?['type'] as String? ?? 'cash';
  late String _balance = widget.initial?['balance']?.toString() ?? '0';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'New account' : 'Edit account'),
    content: Form(
      key: _key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            initialValue: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a name.' : null,
            onSaved: (v) => _name = v!.trim(),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'e-wallet', child: Text('E-wallet')),
            ],
            onChanged: (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: 10),
          if (widget.initial == null)
            TextFormField(
              initialValue: _balance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Starting balance'),
              validator: (v) =>
                  double.tryParse(v ?? '') == null || double.parse(v!) < 0
                  ? 'Enter a valid balance.'
                  : null,
              onSaved: (v) => _balance = v!,
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'The balance changes when you add or edit transactions.',
              ),
            ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: _description,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
            onSaved: (v) => _description = v?.trim() ?? '',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          _key.currentState!.save();
          Navigator.pop(context, {
            'name': _name,
            'type': _type,
            if (widget.initial == null) 'balance': double.parse(_balance),
            'description': _description.isEmpty ? null : _description,
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});
  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  bool _archived = false;
  int _visibleCount = 10;
  Future<List<Map<String, dynamic>>> _load() async {
    var query = _db
        .from('transactions')
        .select('*,accounts(name),categories(name,color)');
    final result = _archived
        ? await query
              .not('deleted_at', 'is', null)
              .order('transaction_date', ascending: false)
              .order('created_at', ascending: false)
              .limit(250)
        : await query
              .isFilter('deleted_at', null)
              .order('transaction_date', ascending: false)
              .order('created_at', ascending: false)
              .limit(250);
    return _maps(result);
  }

  void _refresh() => setState(() {
    _future = _load();
    _visibleCount = 10;
  });

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => TransactionEditor(initial: row),
    );
    if (result == null) return;
    try {
      if (row == null) {
        await _db.from('transactions').insert(result);
      } else {
        await _db.from('transactions').update(result).eq('id', row['id']);
      }
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(e))));
      }
    }
  }

  Future<void> _changeDeleted(Map<String, dynamic> row, bool restore) async {
    try {
      await _db
          .from('transactions')
          .update({
            'deleted_at': restore
                ? null
                : DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', row['id']);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              const Expanded(child: Text('Income and expenses')),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _archived = !_archived;
                    _future = _load();
                    _visibleCount = 10;
                  });
                },
                icon: Icon(_archived ? Icons.list_alt : Icons.archive_outlined),
                label: Text(_archived ? 'Active' : 'Trash'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) return _loading();
              if (s.hasError) return _problem(s.error!, _refresh);
              final rows = s.data!;
              if (rows.isEmpty) {
                return _empty(
                  _archived
                      ? 'Trash is empty.'
                      : 'Add your first income or expense.',
                  icon: Icons.receipt_long_outlined,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 90),
                  children: [
                    ...rows
                        .take(_visibleCount)
                        .map(
                          (r) => Dismissible(
                            key: ValueKey(r['id']),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) async {
                              await _changeDeleted(r, !_archived);
                              return false;
                            },
                            background: Container(
                              color: Colors.blue,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: Icon(
                                _archived
                                    ? Icons.restore
                                    : Icons.delete_outline,
                                color: Colors.white,
                              ),
                            ),
                            child: InkWell(
                              onTap: _archived ? null : () => _edit(r),
                              child: _transactionTile(r),
                            ),
                          ),
                        ),
                    if (rows.length > _visibleCount)
                      Center(
                        child: TextButton(
                          onPressed: () => setState(() {
                            _visibleCount += 10;
                          }),
                          child: const Text('See more'),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
    floatingActionButton: _archived
        ? null
        : FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Transaction'),
          ),
  );
}

class TransactionEditor extends StatefulWidget {
  const TransactionEditor({super.key, this.initial});
  final Map<String, dynamic>? initial;
  @override
  State<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<TransactionEditor> {
  final _key = GlobalKey<FormState>();
  late String _type = widget.initial?['type'] as String? ?? 'expense';
  late String? _account = widget.initial?['account_id'] as String?;
  late String? _category = widget.initial?['category_id'] as String?;
  late String _amount = widget.initial?['amount']?.toString() ?? '';
  late String _description = widget.initial?['description'] as String? ?? '';
  late DateTime _dateValue =
      DateTime.tryParse(widget.initial?['transaction_date'] as String? ?? '') ??
      DateTime.now();
  late Future<List<Map<String, dynamic>>> _options = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final accounts = _maps(
      await _db
          .from('accounts')
          .select('id,name,balance')
          .isFilter('deleted_at', null)
          .order('name'),
    );
    final categories = _maps(
      await _db
          .from('categories')
          .select('id,name,type')
          .isFilter('deleted_at', null)
          .eq('type', _type)
          .order('name'),
    );
    return [
      {'accounts': accounts, 'categories': categories},
    ];
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'New transaction' : 'Edit transaction',
    ),
    content: FutureBuilder<List<Map<String, dynamic>>>(
      future: _options,
      builder: (context, s) {
        if (!s.hasData) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final accounts =
            s.data!.first['accounts'] as List<Map<String, dynamic>>;
        final categories =
            s.data!.first['categories'] as List<Map<String, dynamic>>;
        if (accounts.isEmpty || categories.isEmpty) {
          return SizedBox(
            width: 300,
            child: Text(
              accounts.isEmpty
                  ? 'Create an account before adding transactions.'
                  : 'Create a $_type category first.',
            ),
          );
        }
        _account ??= accounts.first['id'] as String;
        if (!accounts.any((a) => a['id'] == _account)) {
          _account = accounts.first['id'] as String;
        }
        _category ??= categories.first['id'] as String;
        if (!categories.any((a) => a['id'] == _category)) {
          _category = categories.first['id'] as String;
        }
        return SizedBox(
          width: 360,
          child: Form(
            key: _key,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(
                        value: 'expense',
                        child: Text('Expense'),
                      ),
                      DropdownMenuItem(value: 'income', child: Text('Income')),
                    ],
                    onChanged: (v) => setState(() {
                      _type = v!;
                      _category = null;
                      _options = _load();
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _account,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text(
                              '${a['name']} · ${_money(a['balance'])}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _account = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: categories
                        .map(
                          (a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text(a['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _category = v),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount (₱)'),
                    validator: (v) =>
                        double.tryParse(v ?? '') == null ||
                            double.parse(v!) <= 0
                        ? 'Enter an amount above zero.'
                        : null,
                    onSaved: (v) => _amount = v!,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: _description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    onSaved: (v) => _description = v?.trim() ?? '',
                  ),
                  const SizedBox(height: 6),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date'),
                    subtitle: Text(_date.format(_dateValue)),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dateValue,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2200),
                      );
                      if (picked != null) setState(() => _dateValue = picked);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final state = _key.currentState;
          if (state == null || !state.validate()) return;
          state.save();
          Navigator.pop(context, {
            'account_id': _account,
            'category_id': _category,
            'type': _type,
            'amount': double.parse(_amount),
            'description': _description.isEmpty ? null : _description,
            'transaction_date': DateFormat('yyyy-MM-dd').format(_dateValue),
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});
  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<Map<String, dynamic>>> _future = _load();
  Future<List<Map<String, dynamic>>> _load() async {
    final categories = _maps(
      await _db
          .from('categories')
          .select('id,name,color')
          .isFilter('deleted_at', null)
          .eq('type', 'expense')
          .order('name'),
    );
    final budgets = _maps(
      await _db
          .from('budgets')
          .select('id,category_id,amount')
          .eq('year', _month.year)
          .eq('month', _month.month),
    );
    final start = DateFormat('yyyy-MM-dd').format(_month);
    final end = DateFormat('yyyy-MM-dd')
        .format(DateTime(_month.year, _month.month + 1, 0));
    final transactions = _maps(
      await _db
          .from('transactions')
          .select('category_id,amount')
          .eq('type', 'expense')
          .isFilter('deleted_at', null)
          .gte('transaction_date', start)
          .lte('transaction_date', end),
    );
    final spent = <String, double>{};
    for (final t in transactions) {
      final id = t['category_id'] as String;
      spent[id] = (spent[id] ?? 0) + (t['amount'] as num).toDouble();
    }
    return categories.map((c) {
      final matches = budgets.where((b) => b['category_id'] == c['id']);
      return {
        'category': c,
        'budget': matches.isEmpty ? null : matches.first,
        'spent': spent[c['id']] ?? 0.0,
      };
    }).toList();
  }

  void _refresh() => setState(() {
    _future = _load();
  });

  Future<void> _edit(Map<String, dynamic> row) async {
    final category = row['category'] as Map<String, dynamic>;
    final value = await showDialog<double>(
      context: context,
      builder: (context) => _AmountDialog(
        title: 'Budget for ${category['name']}',
        initial: (row['budget'] as Map?)?['amount']?.toString() ?? '',
      ),
    );
    if (value == null) return;
    try {
      if (value == 0) {
        final old = row['budget'] as Map?;
        if (old != null) await _db.from('budgets').delete().eq('id', old['id']);
      } else {
        await _db.from('budgets').upsert({
          'category_id': category['id'],
          'year': _month.year,
          'month': _month.month,
          'amount': value,
        }, onConflict: 'user_id,category_id,year,month');
      }
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month - 1);
                _future = _load();
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              DateFormat('MMMM yyyy').format(_month),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month + 1);
                _future = _load();
              }),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) return _loading();
            if (s.hasError) return _problem(s.error!, _refresh);
            if (s.data!.isEmpty) {
              return _empty(
                'Add expense categories before setting budget targets.',
                icon: Icons.savings_outlined,
              );
            }
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                children: s.data!.map((row) {
                  final cat = row['category'] as Map<String, dynamic>;
                  final budget = row['budget'] as Map?;
                  final target = (budget?['amount'] as num?)?.toDouble() ?? 0;
                  final spent = row['spent'] as double;
                  final over = target > 0 && spent > target;
                  return Card(
                    child: ListTile(
                      onTap: () => _edit(row),
                      title: Text(cat['name'] as String),
                      subtitle: target == 0
                          ? const Text('No target set · Tap to add')
                          : Text(
                              '${_money(spent)} spent · ${_money(target)} target',
                            ),
                      trailing: target == 0
                          ? const Icon(Icons.add_circle_outline)
                          : SizedBox(
                              width: 88,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _money(target - spent),
                                    style: TextStyle(
                                      color: over ? Colors.red : Colors.green,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  LinearProgressIndicator(
                                    value: (spent / target).clamp(0, 1),
                                    color: over ? Colors.red : Colors.green,
                                  ),
                                ],
                              ),
                            ),
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  Future<void> _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More')),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('Categories'),
                subtitle: const Text('Manage income and expense types'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, const CategoriesPage()),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Profile'),
                subtitle: Text(
                  Supabase.instance.client.auth.currentUser?.email ?? '',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, const ProfilePage()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Supabase.instance.client.auth.signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});
  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  bool _archived = false;
  Future<List<Map<String, dynamic>>> _load() async {
    final query = _db.from('categories').select();
    final result = _archived
        ? await query.not('deleted_at', 'is', null).order('type').order('name')
        : await query.isFilter('deleted_at', null).order('type').order('name');
    return _maps(result);
  }

  void _refresh() => setState(() {
    _future = _load();
  });

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => CategoryEditor(initial: row),
    );
    if (value == null) return;
    try {
      if (row == null) {
        await _db.from('categories').insert(value);
      } else {
        await _db.from('categories').update(value).eq('id', row['id']);
      }
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Categories'),
      actions: [
        TextButton.icon(
          onPressed: () {
            setState(() {
              _archived = !_archived;
              _future = _load();
            });
          },
          icon: Icon(_archived ? Icons.list_alt : Icons.archive_outlined),
          label: Text(_archived ? 'Active' : 'Archived'),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return _loading();
        if (s.hasError) return _problem(s.error!, _refresh);
        if (s.data!.isEmpty) {
          return _empty(
            _archived
                ? 'No archived categories.'
                : 'Create categories to sort income and expenses.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: s.data!
              .map(
                (r) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.label_outline),
                    title: Text(r['name'] as String),
                    subtitle: Text((r['type'] as String).toUpperCase()),
                    trailing: _archived
                        ? IconButton(
                            tooltip: 'Restore',
                            icon: const Icon(Icons.restore),
                            onPressed: () async {
                              await _db
                                  .from('categories')
                                  .update({'deleted_at': null})
                                  .eq('id', r['id']);
                              _refresh();
                            },
                          )
                        : PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') {
                                await _edit(r);
                              } else {
                                await _db
                                    .from('categories')
                                    .update({
                                      'deleted_at': _archived
                                          ? null
                                          : DateTime.now()
                                                .toUtc()
                                                .toIso8601String(),
                                    })
                                    .eq('id', r['id']);
                                _refresh();
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'archive',
                                child: Text('Archive'),
                              ),
                            ],
                          ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
    floatingActionButton: _archived
        ? null
        : FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Category'),
          ),
  );
}

class CategoryEditor extends StatefulWidget {
  const CategoryEditor({super.key, this.initial});
  final Map<String, dynamic>? initial;
  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  final _key = GlobalKey<FormState>();
  late String _name = widget.initial?['name'] as String? ?? '';
  late String _type = widget.initial?['type'] as String? ?? 'expense';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'New category' : 'Edit category'),
    content: Form(
      key: _key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            initialValue: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a name.' : null,
            onSaved: (v) => _name = v!.trim(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'expense', child: Text('Expense')),
              DropdownMenuItem(value: 'income', child: Text('Income')),
            ],
            onChanged: (v) => setState(() => _type = v!),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          _key.currentState!.save();
          Navigator.pop(context, {
            'name': _name,
            'type': _type,
            'color': '#1679D3',
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key});
  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  Future<List<Map<String, dynamic>>> _load() async => _maps(
    await _db
        .from('recurring_transactions')
        .select('*,accounts(name),categories(name)')
        .eq('type', 'expense')
        .order('next_due_date'),
  );
  void _refresh() => setState(() {
    _future = _load();
  });

  Future<void> _create() async {
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const RecurringEditor(),
    );
    if (value == null) return;
    try {
      await _db.from('recurring_transactions').insert(value);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(e))));
      }
    }
  }

  Future<void> _confirm(Map<String, dynamic> row) async {
    try {
      await _db.rpc(
        'confirm_recurring_transaction',
        params: {'p_id': row['id']},
      );
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recurring expenses')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return _loading();
        if (s.hasError) return _problem(s.error!, _refresh);
        if (s.data!.isEmpty) {
          return _empty(
            'Review upcoming expenses and bills here.',
            icon: Icons.event_repeat_outlined,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: s.data!.map((r) {
            final due = r['next_due_date'] as String?;
            final isDue =
                due != null && !DateTime.parse(due).isAfter(DateTime.now());
            return Card(
              child: ListTile(
                leading: const Icon(Icons.event_repeat_outlined),
                title: Text(r['description'] as String),
                subtitle: Text(
                  '${r['frequency']} · ${due ?? 'No next date'} · ${(r['accounts'] as Map?)?['name'] ?? ''}',
                ),
                trailing: isDue
                    ? TextButton(
                        onPressed: () => _confirm(r),
                        child: const Text('Confirm'),
                      )
                    : Text(_money(r['amount'])),
              ),
            );
          }).toList(),
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('Recurring'),
    ),
  );
}

class RecurringEditor extends StatefulWidget {
  const RecurringEditor({super.key});
  @override
  State<RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<RecurringEditor> {
  final _key = GlobalKey<FormState>();
  String _frequency = 'monthly', _description = '', _amount = '';
  String? _account, _category;
  final _start = DateTime.now();
  late final Future<List<List<Map<String, dynamic>>>> _options = _load();
  Future<List<List<Map<String, dynamic>>>> _load() async => [
    _maps(
      await _db
          .from('accounts')
          .select('id,name')
          .isFilter('deleted_at', null)
          .order('name'),
    ),
    _maps(
      await _db
          .from('categories')
          .select('id,name')
          .isFilter('deleted_at', null)
          .eq('type', 'expense')
          .order('name'),
    ),
  ];
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New recurring item'),
    content: SizedBox(
      width: 360,
      child: FutureBuilder<List<List<Map<String, dynamic>>>>(
        future: _options,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (s.hasError) {
            return SizedBox(
              width: 300,
              child: Text('Could not load form options: ${_error(s.error!)}'),
            );
          }
          final accounts = s.data![0], categories = s.data![1];
          if (accounts.isEmpty || categories.isEmpty) {
            return Text(
              accounts.isEmpty
                  ? 'Create an account first.'
                  : 'Create a matching category first.',
            );
          }
          _account ??= accounts.first['id'] as String;
          if (!accounts.any((a) => a['id'] == _account)) {
            _account = accounts.first['id'] as String;
          }
          _category ??= categories.first['id'] as String;
          if (!categories.any((a) => a['id'] == _category)) {
            _category = categories.first['id'] as String;
          }
          return Form(
            key: _key,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: _description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter a description.'
                        : null,
                    onSaved: (v) => _description = v!.trim(),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _account,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text(a['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _account = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: categories
                        .map(
                          (a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text(a['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _category = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _frequency,
                    decoration: const InputDecoration(labelText: 'Frequency'),
                    items: const [
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text('Monthly'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _frequency = v!),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount (₱)'),
                    validator: (v) =>
                        double.tryParse(v ?? '') == null ||
                            double.parse(v!) <= 0
                        ? 'Enter an amount above zero.'
                        : null,
                    onSaved: (v) => _amount = v!,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final s = _key.currentState;
          if (s == null || !s.validate()) return;
          s.save();
          final date = DateFormat('yyyy-MM-dd').format(_start);
          Navigator.pop(context, {
            'account_id': _account,
            'category_id': _category,
            'type': 'expense',
            'frequency': _frequency,
            'description': _description,
            'amount': double.parse(_amount),
            'start_date': date,
            'next_due_date': date,
            'interval': 1,
            'reminder_days_before': 3,
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String get _name =>
      _db.auth.currentUser?.userMetadata?['display_name'] as String? ?? '';

  Future<void> _editName() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _ProfileTextDialog(
        title: 'Display name',
        label: 'Name',
        initial: _name,
      ),
    );
    if (value == null) return;
    try {
      await _db.auth.updateUser(UserAttributes(data: {'display_name': value}));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(e))));
      }
    }
  }

  Future<void> _changePassword() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => const _ProfileTextDialog(
        title: 'Change password',
        label: 'New password',
        password: true,
      ),
    );
    if (value == null) return;
    try {
      await _db.auth.updateUser(UserAttributes(password: value));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Password updated.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _db.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(_name.isEmpty ? 'Your profile' : _name),
              subtitle: Text(user?.email ?? ''),
              trailing: IconButton(
                onPressed: _editName,
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changePassword,
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('Your data is private'),
              subtitle: Text(
                'Database policies restrict records to the signed-in account.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _db.auth.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _ProfileTextDialog extends StatefulWidget {
  const _ProfileTextDialog({
    required this.title,
    required this.label,
    this.initial = '',
    this.password = false,
  });
  final String title, label, initial;
  final bool password;
  @override
  State<_ProfileTextDialog> createState() => _ProfileTextDialogState();
}

class _ProfileTextDialogState extends State<_ProfileTextDialog> {
  final _key = GlobalKey<FormState>();
  late String _value = widget.initial;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _key,
      child: TextFormField(
        initialValue: _value,
        obscureText: widget.password,
        decoration: InputDecoration(labelText: widget.label),
        validator: (v) =>
            v == null || v.trim().length < (widget.password ? 8 : 1)
            ? (widget.password ? 'Use at least 8 characters.' : 'Enter a name.')
            : null,
        onSaved: (v) => _value = v!.trim(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          _key.currentState!.save();
          Navigator.pop(context, _value);
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _key = GlobalKey<FormState>();
  late String _value = widget.initial;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _key,
      child: TextFormField(
        initialValue: _value,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Monthly amount'),
        validator: (v) =>
            double.tryParse(v ?? '') == null || double.parse(v!) < 0
            ? 'Enter a valid amount.'
            : null,
        onSaved: (v) => _value = v!,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          _key.currentState!.save();
          Navigator.pop(context, double.parse(_value));
        },
        child: const Text('Save'),
      ),
    ],
  );
}
