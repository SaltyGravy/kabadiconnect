import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/services/auth_service.dart';
import '../../widgets/switch_role_link.dart';
import 'resolve_post_login.dart';

/// Returning-user login: phone + password only.
///
/// Collectors additionally see a "Create an account" link to
/// CreateAccountScreen -- self-service registration is fine for informal
/// collectors, which is the whole point of lowering that barrier.
///
/// Recyclers do NOT get that link. A recycler is a government-authorized
/// facility (CPCB/SPCB-vetted -- see docs/dataset_documentation.md); letting
/// anyone who types the right registered phone number set their own
/// password would make "authorized" meaningless. Recycler credentials are
/// provisioned by the platform admin (see ml/provision_recyclers.py) and
/// handed to the facility out-of-band; this screen is their only door in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').length >= 10 && _passwordCtrl.text.length >= 6;

  Future<void> _submit() async {
    // Captured once, up front, while context is definitely valid --
    // AppState itself is a plain object independent of BuildContext, so
    // calling methods on this reference later (in `finally`, possibly
    // after this widget has been swapped out by RootRouter) is safe even
    // when re-doing `context.read` at that point would not be.
    final appState = context.read<AppState>();
    final auth = context.read<AuthService>();

    setState(() {
      _busy = true;
      _error = null;
    });
    // Set before calling auth.login(): Firebase's authStateChanges stream
    // can flip AppState.firebaseUser non-null as soon as sign-in succeeds,
    // racing ahead of resolvePostLogin's profile fetch below -- this flag
    // is what stops RootRouter from rendering the wrong screen in between
    // (see AppState.resolvingProfile's doc comment). Always cleared in
    // `finally` below, whatever the outcome, so it can never get stuck.
    appState.setResolvingProfile(true);
    try {
      final result = await auth.login(phone: _phoneCtrl.text, password: _passwordCtrl.text);
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
      appBar: AppBar(title: Text(t('appName'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Log In as ${appState.role == UserRole.collector ? 'Collector' : 'Recycler'}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
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
            const Text('Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              style: const TextStyle(fontSize: 20),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_canSubmit && !_busy) ? _submit : null,
              child: _busy ? const CircularProgressIndicator(color: Colors.white) : const Text('Log In'),
            ),
            if (appState.role == UserRole.collector) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => context.read<AppState>().setShowCreateAccount(true),
                  child: const Text('New here? Create an account'),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Recycler accounts are set up by the platform team. If you haven\'t received a login, contact the platform admin.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 8),
            const SwitchRoleLink(),
          ],
        ),
      ),
    );
  }
}
