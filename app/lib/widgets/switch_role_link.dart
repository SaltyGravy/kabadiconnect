import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/services/auth_service.dart';

/// "Wrong role? Switch" escape hatch. Role choice persists across sign-out
/// by design (see AppState.clearRole's doc comment), so this is the one
/// deliberate way out -- shown on every screen where picking the wrong
/// role at the very start could otherwise leave someone stuck (login,
/// create-account, mid-profile-setup, not-authorized).
///
/// Signs out first (harmless no-op if not signed in) so any half-finished
/// session for the wrong role is discarded, not left dangling.
class SwitchRoleLink extends StatelessWidget {
  const SwitchRoleLink({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        icon: const Icon(Icons.sync_alt, size: 16),
        label: const Text('Wrong role? Switch'),
        onPressed: () async {
          await context.read<AuthService>().signOut();
          await context.read<AppState>().clearRole();
        },
      ),
    );
  }
}
