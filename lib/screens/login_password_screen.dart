import 'package:flutter/material.dart';
import '../auth/personal_auth.dart';
import '../theme/app_theme.dart';

class LoginPasswordScreen extends StatefulWidget {
  const LoginPasswordScreen({super.key});

  @override
  State<LoginPasswordScreen> createState() => _LoginPasswordScreenState();
}

class _LoginPasswordScreenState extends State<LoginPasswordScreen> {
  final _idCtl = TextEditingController();
  final _pwCtl = TextEditingController();
  final _confirmCtl = TextEditingController();
  bool _obscurePw = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  bool get _isSet => PersonalAuth.isSet();

  @override
  void initState() {
    super.initState();
    if (_isSet) _idCtl.text = PersonalAuth.getSavedId();
  }

  @override
  void dispose() {
    _idCtl.dispose();
    _pwCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _idCtl.text.trim();
    final pw = _pwCtl.text;
    final confirm = _confirmCtl.text;

    if (id.isEmpty) {
      _show('Login ID cannot be empty.');
      return;
    }
    if (pw.length < 4) {
      _show('Password must be at least 4 characters.');
      return;
    }
    if (pw != confirm) {
      _show('Passwords do not match.');
      return;
    }

    setState(() => _saving = true);
    await PersonalAuth.set(id, pw);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Personal login saved. Active from next cold start.')),
    );
    _pwCtl.clear();
    _confirmCtl.clear();
    setState(() {});
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove personal login?'),
        content: const Text('The app will open without asking for a login next time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PersonalAuth.clear();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personal login removed.')),
      );
    }
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login ID & Password')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (_isSet)
            Card(
              color: const Color(0xFFEFF8F1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.ok),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Personal login is active',
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ok)),
                          Text('ID: ${PersonalAuth.getSavedId()}',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _remove,
                      child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            'Set a personal login that is asked every time you open the app from scratch '
            '(cold start). Backgrounding the app and coming back does not re-ask.\n\n'
            'If you forget your password, use the "Forgot Password?" link on the login '
            'screen — it accepts the original Admin credentials to reset this.',
            style: TextStyle(color: AppColors.inkSoft, height: 1.5, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _idCtl,
            decoration: const InputDecoration(labelText: 'Login ID *'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pwCtl,
            obscureText: _obscurePw,
            decoration: InputDecoration(
              labelText: _isSet ? 'New Password *' : 'Password *',
              suffixIcon: IconButton(
                icon: Icon(_obscurePw ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePw = !_obscurePw),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirmCtl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm Password *',
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_isSet ? 'Update Login' : 'Set Login'),
          ),
        ],
      ),
    );
  }
}
