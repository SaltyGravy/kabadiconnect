import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/services/auth_service.dart';
import 'resolve_post_login.dart';

/// New-user registration: phone + password + confirm password. See
/// LoginScreen for why this is a separate screen rather than an implicit
/// first-use signup.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});
  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').length >= 10 &&
      _passwordCtrl.text.length >= 6 &&
      _passwordCtrl.text == _confirmCtrl.text;

  Future<void> _submit() async {
    // Captured once, up front -- see LoginScreen._submit's comment for why.
    final appState = context.read<AppState>();
    final auth = context.read<AuthService>();

    setState(() {
      _busy = true;
      _error = null;
    });
    appState.setResolvingProfile(true);
    try {
      final result = await auth.register(phone: _phoneCtrl.text, password: _passwordCtrl.text);
      await resolvePostLogin(context, result);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      appState.setResolvingProfile(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.read<AppState>().setShowCreateAccount(false),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('yourPhone'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 20),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(border: OutlineInputBorder(), prefixText: '+91 ', hintText: '98765 43210'),
            ),
            const SizedBox(height: 20),
            const Text('Choose a password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              style: const TextStyle(fontSize: 20),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                helperText: 'At least 6 characters',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Confirm password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmCtrl,
              obscureText: _obscure,
              style: const TextStyle(fontSize: 20),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_canSubmit && !_busy) ? _submit : null,
              child: _busy ? const CircularProgressIndicator(color: Colors.white) : const Text('Create Account'),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => context.read<AppState>().setShowCreateAccount(false),
                child: const Text('Already have an account? Log in'),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
