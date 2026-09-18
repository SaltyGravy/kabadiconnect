import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'models/collector_profile.dart';
import 'models/recycler.dart';

/// Central app state: locale, role, active profile, connectivity/sync status.
/// Persisted to shared_preferences so returning users skip onboarding.
class AppState extends ChangeNotifier {
  AppLocale locale = AppLocale.en;
  bool localeChosen = false;
  UserRole? role;
  String? profileId;
  CollectorProfile? collector;
  Recycler? recycler;
  bool isOnline = true;
  int pendingSyncCount = 0;

  /// Firebase Auth identity, kept in sync by RootRouter's subscription to
  /// AuthService.authStateChanges(). null means not signed in.
  User? firebaseUser;

  /// Toggles which of the two separate auth screens RootRouter shows while
  /// signed out (see LoginScreen / CreateAccountScreen).
  bool showCreateAccount = false;

  void setShowCreateAccount(bool value) {
    showCreateAccount = value;
    notifyListeners();
  }

  /// True from the moment a login/create-account attempt starts until
  /// resolvePostLogin finishes loading the resulting profile. Firebase's
  /// own authStateChanges stream flips [firebaseUser] non-null the instant
  /// sign-in succeeds -- independent of and often *before* our own code
  /// finishes fetching the collector/recycler profile -- so RootRouter
  /// must gate on this flag (not just "firebaseUser != null") to avoid
  /// rendering ProfileSetupScreen/RecyclerNotAuthorizedScreen for a
  /// flashed frame before the real profile is known.
  bool resolvingProfile = false;

  void setResolvingProfile(bool value) {
    resolvingProfile = value;
    notifyListeners();
  }

  void setFirebaseUser(User? user) {
    firebaseUser = user;
    if (user == null) {
      // Signed out: drop any loaded profile so RootRouter routes back to login.
      collector = null;
      recycler = null;
      profileId = null;
      showCreateAccount = false;
    }
    notifyListeners();
  }

  Future<void> loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final localeStr = prefs.getString('locale');
    if (localeStr != null) {
      locale = AppLocale.values.firstWhere((l) => l.name == localeStr, orElse: () => AppLocale.en);
      localeChosen = true;
    }
    final roleStr = prefs.getString('role');
    if (roleStr != null) {
      role = UserRole.values.firstWhere((r) => r.name == roleStr, orElse: () => UserRole.collector);
    }
    profileId = prefs.getString('profileId');
    notifyListeners();
  }

  Future<void> setLocale(AppLocale l) async {
    locale = l;
    localeChosen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', l.name);
    notifyListeners();
  }

  Future<void> setRole(UserRole r) async {
    role = r;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('role', r.name);
    notifyListeners();
  }

  /// Undoes setRole's persistence so RootRouter falls back to
  /// RoleSelectScreen. Role choice otherwise survives sign-out (by design --
  /// most returning users want the same role every time), so this is the
  /// deliberate escape hatch for "I picked the wrong one" -- surfaced from
  /// the login screens, the stuck-mid-setup screens, and the account screen.
  Future<void> clearRole() async {
    role = null;
    collector = null;
    recycler = null;
    profileId = null;
    showCreateAccount = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('role');
    await prefs.remove('profileId');
    notifyListeners();
  }

  Future<void> setCollector(CollectorProfile c) async {
    collector = c;
    profileId = c.collectorId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profileId', c.collectorId);
    notifyListeners();
  }

  Future<void> setRecycler(Recycler r) async {
    recycler = r;
    profileId = r.recyclerId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profileId', r.recyclerId);
    notifyListeners();
  }

  void setOnline(bool online) {
    isOnline = online;
    notifyListeners();
  }

  void setPendingSyncCount(int n) {
    pendingSyncCount = n;
    notifyListeners();
  }

  bool get hasProfile => role == UserRole.collector ? collector != null : recycler != null;
}
