import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/services/auth_service.dart';

/// Shared account screen for both roles: who's signed in, and a logout
/// button. Logging out clears AppState.firebaseUser (via RootRouter's
/// auth-state subscription), which routes straight back to the login screen.
class AccountScreen extends StatelessWidget {
  final VoidCallback? onHome;
  const AccountScreen({super.key, this.onHome});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final isCollector = appState.role == UserRole.collector;

    final name = isCollector ? (appState.collector?.displayName ?? '') : (appState.recycler?.name ?? '');
    final location = isCollector ? (appState.collector?.operatingLocation ?? '') : (appState.recycler?.facilityLocation ?? '');
    final phone = isCollector ? (appState.collector?.phone ?? '') : (appState.recycler?.contactPhone ?? '');

    return Scaffold(
      appBar: AppBar(
        title: Text(t('profile')),
        leading: onHome == null ? null : IconButton(icon: const Icon(Icons.home), onPressed: onHome),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: isCollector ? kBrandGreen : kAmber,
              child: Icon(isCollector ? Icons.person : Icons.factory, color: Colors.white, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          Center(child: Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          Center(
            child: Chip(
              label: Text(isCollector ? t('roleCollector') : t('roleRecycler')),
              backgroundColor: (isCollector ? kBrandGreen : kAmber).withValues(alpha: 0.15),
            ),
          ),
          const Divider(height: 32),
          _row(Icons.location_on, location),
          if (phone.isNotEmpty) _row(Icons.phone, phone),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.sync_alt, size: 18),
            label: const Text('Switch to the other role'),
            onPressed: () => _confirmSwitchRole(context),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [Icon(icon, size: 18, color: Colors.black54), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontSize: 16)))]),
      );

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can log back in any time with your phone number and password.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed == true) {
      await context.read<AuthService>().signOut();
      if (context.mounted) Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  Future<void> _confirmSwitchRole(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch role?'),
        content: const Text('You\'ll be logged out and asked to pick Collector or Recycler again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Switch')),
        ],
      ),
    );
    if (confirmed == true) {
      await context.read<AuthService>().signOut();
      await context.read<AppState>().clearRole();
      if (context.mounted) Navigator.popUntil(context, (route) => route.isFirst);
    }
  }
}
