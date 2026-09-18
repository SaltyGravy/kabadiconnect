import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/firestore_service.dart';
import '../collector/home/collector_shell.dart';
import '../recycler/recycler_home_screen.dart';
import 'create_account_screen.dart';
import 'language_select_screen.dart';
import 'login_screen.dart';
import 'profile_setup_screen.dart';
import 'recycler_not_authorized_screen.dart';
import 'role_select_screen.dart';

/// Decides which screen to show at app start: restores a returning user's
/// Firebase Auth session and profile (offline cache serves this instantly
/// if there's no network), then routes through
/// language -> role -> phone login -> profile-setup (collector only) -> home.
class RootRouter extends StatefulWidget {
  const RootRouter({super.key});

  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> {
  bool _ready = false;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final appState = context.read<AppState>();
    final firestore = context.read<FirestoreService>();
    final connectivity = context.read<ConnectivityService>();
    final auth = context.read<AuthService>();

    appState.setOnline(await connectivity.isOnline());
    _connectivitySub = connectivity.onStatusChange().listen(appState.setOnline);
    _authSub = auth.authStateChanges.listen(appState.setFirebaseUser);

    final user = auth.currentUser;
    if (user != null) {
      appState.setFirebaseUser(user);
      try {
        if (appState.role == UserRole.collector) {
          final profile = await firestore.watchCollector(user.uid).first.timeout(const Duration(seconds: 4));
          if (profile != null) await appState.setCollector(profile);
        } else if (appState.role == UserRole.recycler) {
          final recycler = await firestore.findRecyclerByLinkedUid(user.uid).timeout(const Duration(seconds: 4));
          if (recycler != null) await appState.setRecycler(recycler);
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const _Splash();
    }

    final appState = context.watch<AppState>();
    if (!appState.localeChosen) return const LanguageSelectScreen();
    if (appState.role == null) return const RoleSelectScreen();
    if (appState.firebaseUser == null) {
      // Recyclers never self-register (see LoginScreen's doc comment) --
      // CreateAccountScreen is collector-only regardless of showCreateAccount.
      final showCreate = appState.showCreateAccount && appState.role == UserRole.collector;
      return showCreate ? const CreateAccountScreen() : const LoginScreen();
    }
    // firebaseUser flips non-null the instant Firebase Auth succeeds, which
    // can race ahead of our own profile fetch (see resolvingProfile's doc
    // comment) -- hold the splash rather than flash ProfileSetupScreen /
    // RecyclerNotAuthorizedScreen / the wrong home screen for a frame.
    if (appState.resolvingProfile) {
      return const _Splash();
    }

    if (appState.role == UserRole.collector) {
      return appState.collector == null ? const ProfileSetupScreen() : const CollectorShell();
    }
    return appState.recycler == null ? const RecyclerNotAuthorizedScreen() : const RecyclerHomeScreen();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBrandGreen,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.recycling, color: Colors.white, size: 72),
            SizedBox(height: 16),
            Text('KabadiConnect', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 24),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
