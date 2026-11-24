import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'finance_pages.dart';

const appName = 'FinanceTrackerReminder';
const primaryColor = Color(0xFF1679D3);
const accentColor = Color(0xFFE85D8E);
const authRedirect = 'personal-finance://auth-callback';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  if (url.isNotEmpty && publishableKey.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }
  runApp(FinanceApp(configured: url.isNotEmpty && publishableKey.isNotEmpty));
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key, required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: appName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: primaryColor)
          .copyWith(primary: primaryColor, secondary: accentColor),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF6F8FC),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF6F8FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: configured ? const AuthGate() : const SetupPage(),
  );
}

class FtrLogo extends StatelessWidget {
  const FtrLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: appName,
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(size * .24),
      ),
      child: Text(
        'FTR',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .32,
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
        ),
      ),
    ),
  );
}

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FtrLogo(size: 48),
                  const SizedBox(height: 20),
                  Text(
                    'Connect your Supabase project',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Create a Supabase project, run the SQL file in supabase/migrations, then launch with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY. See README.md for the exact steps.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: Supabase.instance.client.auth.onAuthStateChange,
    builder: (context, snapshot) {
      if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
        return const PasswordRecoveryPage();
      }
      final session =
          snapshot.data?.session ??
          Supabase.instance.client.auth.currentSession;
      return session == null ? const AuthPage() : const FinanceShell();
    },
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_register) {
        final result = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          emailRedirectTo: authRedirect,
          data: {'display_name': _name.text.trim()},
        );
        if (result.session == null) {
          _message = 'Check your email to confirm your account, then sign in.';
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      _error = e.message;
    } catch (_) {
      _error =
          'Could not connect. Check your internet connection and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: authRedirect,
      );
      if (mounted) {
        setState(() {
          _error = null;
          _message =
              'If that address is registered, a reset email is on its way.';
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: FtrLogo(size: 52)),
                      const SizedBox(height: 16),
                      Text(
                        _register ? 'Create your account' : 'Welcome back',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _register
                            ? 'Start with a few details. Your finances stay private.'
                            : 'Sign in to see your finances.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (_register) ...[
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Name'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter your name.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (v) => v == null || !v.contains('@')
                            ? 'Enter a valid email.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        validator: (v) => v == null || v.length < 8
                            ? 'Use at least 8 characters.'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          style: const TextStyle(color: Colors.green),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_register ? 'Create account' : 'Sign in'),
                      ),
                      if (!_register)
                        TextButton(
                          onPressed: _resetPassword,
                          child: const Text('Forgot password?'),
                        ),
                      TextButton(
                        onPressed: () => setState(() {
                          _register = !_register;
                          _error = null;
                          _message = null;
                        }),
                        child: Text(
                          _register
                              ? 'Already have an account? Sign in'
                              : 'Create an account',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final _key = GlobalKey<FormState>();
  String _password = '';
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    _key.currentState!.save();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password),
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose a new password')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (v) => v == null || v.length < 8
                      ? 'Use at least 8 characters.'
                      : null,
                  onSaved: (v) => _password = v!,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save password'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class FinanceShell extends StatefulWidget {
  const FinanceShell({super.key});

  @override
  State<FinanceShell> createState() => _FinanceShellState();
}

class _FinanceShellState extends State<FinanceShell> {
  int _index = 0;
  int _dashboardVersion = 0;
  List<Widget> get _pages => [
    DashboardPage(key: ValueKey(_dashboardVersion)),
    TransactionsPage(),
    AccountsPage(),
    BudgetsPage(),
    RecurringPage(),
  ];
  final _titles = const [
    'Transactions',
    'Accounts',
    'Budgets',
    'Recurring expenses',
  ];

  @override
  void initState() {
    super.initState();
    _seedCategories();
  }

  Future<void> _seedCategories() async {
    final client = Supabase.instance.client;
    final existing = await client.from('categories').select('id').limit(1);
    if ((existing as List).isNotEmpty) return;
    await client.from('categories').insert([
      {'name': 'Salary & Income', 'type': 'income', 'color': '#16a34a'},
      {'name': 'Freelance & Side Hustle', 'type': 'income', 'color': '#0f766e'},
      {'name': 'Gifts & Extras', 'type': 'income', 'color': '#2563eb'},
      {'name': 'Food & Dining', 'type': 'expense', 'color': '#ea580c'},
      {'name': 'Groceries', 'type': 'expense', 'color': '#84cc16'},
      {'name': 'Transport', 'type': 'expense', 'color': '#7c3aed'},
      {'name': 'Bills & Utilities', 'type': 'expense', 'color': '#dc2626'},
      {'name': 'Health & Pharmacy', 'type': 'expense', 'color': '#db2777'},
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: _index == 0 ? const FtrLogo() : Text(_titles[_index - 1]),
      actions: [
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const MorePage()),
          ),
          icon: const Icon(Icons.more_horiz),
          tooltip: 'More',
        ),
      ],
    ),
    body: IndexedStack(index: _index, children: _pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() {
        if (i == 0) _dashboardVersion++;
        _index = i;
      }),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'Activity',
        ),
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: 'Accounts',
        ),
        NavigationDestination(
          icon: Icon(Icons.savings_outlined),
          selectedIcon: Icon(Icons.savings),
          label: 'Budgets',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_repeat_outlined),
          selectedIcon: Icon(Icons.event_repeat),
          label: 'Recurring',
        ),
      ],
    ),
  );
}
