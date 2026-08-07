import 'package:flutter/material.dart';
import '../auth/personal_auth.dart';
import '../theme/app_theme.dart';

class PersonalLoginScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const PersonalLoginScreen({super.key, required this.onUnlocked});

  @override
  State<PersonalLoginScreen> createState() => _PersonalLoginScreenState();
}

class _PersonalLoginScreenState extends State<PersonalLoginScreen> {
  final _idCtl = TextEditingController();
  final _pwCtl = TextEditingController();
  final _adminIdCtl = TextEditingController();
  final _adminPwCtl = TextEditingController();
  bool _obscure = true;
  bool _adminObscure = true;
  String? _error;
  bool _checking = false;
  bool _showForgot = false;

  @override
  void initState() {
    super.initState();
    // Auto-fill the saved login ID — user only needs to type their password.
    _idCtl.text = PersonalAuth.getSavedId();
  }

  @override
  void dispose() {
    _idCtl.dispose();
    _pwCtl.dispose();
    _adminIdCtl.dispose();
    _adminPwCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _checking = true; _error = null; });
    await Future.delayed(const Duration(milliseconds: 200));
    final ok = PersonalAuth.verify(_idCtl.text, _pwCtl.text);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() { _error = 'Incorrect ID or Password.'; _checking = false; });
    }
  }

  Future<void> _submitForgot() async {
    setState(() { _checking = true; _error = null; });
    await Future.delayed(const Duration(milliseconds: 200));
    final ok = PersonalAuth.verifyAdmin(_adminIdCtl.text.trim(), _adminPwCtl.text);
    if (!mounted) return;
    if (ok) {
      await PersonalAuth.clear();
      widget.onUnlocked();
    } else {
      setState(() {
        _error = 'Incorrect Admin ID or Password.';
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slab,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: _showForgot ? _buildForgotView() : _buildLoginView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_person_outlined, color: AppColors.electricBlue, size: 44),
        const SizedBox(height: 12),
        const Text('EasyQuote', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Enter your login to continue', textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB9B4A6), fontSize: 13)),
        const SizedBox(height: 26),
        _darkField(controller: _idCtl, label: 'Login ID', readOnly: true),
        const SizedBox(height: 14),
        _darkField(
          controller: _pwCtl,
          label: 'Password',
          obscure: _obscure,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFFB9B4A6)),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFE08A6B), fontSize: 13)),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _checking ? null : _submit,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.electricBlue,
              padding: const EdgeInsets.symmetric(vertical: 15)),
          child: _checking
              ? const SizedBox(height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Login', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: () => setState(() { _showForgot = true; _error = null; }),
          child: const Text('Forgot Password?', style: TextStyle(color: Color(0xFFB9B4A6))),
        ),
      ],
    );
  }

  Widget _buildForgotView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.admin_panel_settings_outlined, color: AppColors.rebar, size: 44),
        const SizedBox(height: 12),
        const Text('Reset Personal Login', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          'Enter the original Admin ID & Password to clear your personal login.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFB9B4A6), fontSize: 12.5),
        ),
        const SizedBox(height: 24),
        _darkField(controller: _adminIdCtl, label: 'Admin ID'),
        const SizedBox(height: 14),
        _darkField(
          controller: _adminPwCtl,
          label: 'Admin Password',
          obscure: _adminObscure,
          suffixIcon: IconButton(
            icon: Icon(_adminObscure ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFFB9B4A6)),
            onPressed: () => setState(() => _adminObscure = !_adminObscure),
          ),
          onSubmitted: (_) => _submitForgot(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFE08A6B), fontSize: 13)),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _checking ? null : _submitForgot,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.rebar,
              padding: const EdgeInsets.symmetric(vertical: 15)),
          child: _checking
              ? const SizedBox(height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Verify & Reset Login',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() { _showForgot = false; _error = null; }),
          child: const Text('← Back', style: TextStyle(color: Color(0xFFB9B4A6))),
        ),
      ],
    );
  }

  Widget _darkField({
    required TextEditingController controller,
    required String label,
    bool obscure = false,
    bool readOnly = false,
    Widget? suffixIcon,
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      readOnly: readOnly,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFFB9B4A6)),
        filled: true,
        fillColor: const Color(0xFF1A1A1D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF3A3A3D)),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
