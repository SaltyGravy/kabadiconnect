import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/seed_data_service.dart';

/// Shared by LoginScreen and CreateAccountScreen: what happens right after
/// Firebase confirms an identity. Collectors auto-provision a profile (or
/// resume an existing one); recyclers must match a pre-registered
/// facility's contact number -- see RecyclerNotAuthorizedScreen for the
/// no-match case.
Future<void> resolvePostLogin(BuildContext context, AuthResult result) async {
  final appState = context.read<AppState>();
  final firestore = context.read<FirestoreService>();
  final seeder = context.read<SeedDataService>();

  appState.setFirebaseUser(result.user);

  // Public catalogue data (recyclers, price history) is seeded once, after
  // sign-in, per firestore.rules -- see SeedDataService.
  try {
    await seeder.seedIfEmpty();
  } catch (_) {
    // Offline on first-ever login: the app still works, just without a
    // populated recycler directory / price board until connectivity returns.
  }

  if (appState.role == UserRole.collector) {
    final profile = await firestore.watchCollector(result.user.uid).first;
    if (profile != null) await appState.setCollector(profile);
    // else: RootRouter routes to the one-time profile-setup screen, which
    // creates collectors/{uid} on submit.
  } else {
    final recycler = await firestore.findRecyclerByPhone(result.e164Phone);
    if (recycler != null) {
      await firestore.claimRecycler(recycler.recyclerId, result.user.uid);
      final claimed = await firestore.watchRecycler(recycler.recyclerId).first;
      if (claimed != null) await appState.setRecycler(claimed);
    }
    // else: RootRouter shows "not an authorized recycler".
  }
}
