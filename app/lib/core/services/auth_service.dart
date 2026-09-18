import 'package:firebase_auth/firebase_auth.dart';

/// Phone-number identity, backed by Firebase's Email/Password provider under
/// the hood (a real phone-number provider needs SMS delivery, which
/// requires the paid Blaze plan -- see docs/dataset_documentation.md for
/// why this project uses password auth instead). The UI never shows an
/// email field; phone numbers are mapped to a synthetic address so
/// Firebase's free Email/Password sign-in can be reused as-is.
///
/// Login and account-creation are deliberately separate calls (not an
/// implicit "first use registers you" flow) so a typo'd phone number on
/// login surfaces as a clear error instead of silently spawning a second
/// account.
///
/// KNOWN LIMITATION: without SMS/OTP verification, a phone number is
/// self-asserted, not proven. This matters most for recycler login, where
/// an unclaimed facility is claimed by whoever first signs in with its
/// registered contact number (see firestore.rules) -- anyone who knows or
/// guesses that number could claim it first. Fine for a demo with 12
/// fictional recyclers; a real deployment should add a claim PIN
/// communicated to the facility out-of-band before removing this note.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String toE164(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return '+91$digits'; // India-first, per the brief's pilot geography
    if (raw.startsWith('+')) return raw;
    return '+$digits';
  }

  String _syntheticEmail(String e164Phone) {
    final digits = e164Phone.replaceAll(RegExp(r'[^0-9]'), '');
    return '$digits@phone.kabadiconnect.app';
  }

  /// Recovers the E.164 phone number from a signed-in user's synthetic
  /// email (User.phoneNumber is never populated by the Email/Password
  /// provider this app uses under the hood -- see the class doc above).
  String? phoneFromUser(User user) {
    final email = user.email;
    if (email == null || !email.endsWith('@phone.kabadiconnect.app')) return null;
    final digits = email.split('@').first;
    return '+$digits';
  }

  Future<AuthResult> login({required String phone, required String password}) async {
    final e164 = toE164(phone);
    try {
      final result = await _auth.signInWithEmailAndPassword(email: _syntheticEmail(e164), password: password);
      return AuthResult(user: result.user!, e164Phone: e164);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        throw AuthFailure('No account found for $e164, or the password is wrong. New here? Use "Create account" instead.');
      }
      throw AuthFailure(e.message ?? 'Sign-in failed (${e.code})');
    }
  }

  Future<AuthResult> register({required String phone, required String password}) async {
    final e164 = toE164(phone);
    try {
      final result = await _auth.createUserWithEmailAndPassword(email: _syntheticEmail(e164), password: password);
      return AuthResult(user: result.user!, e164Phone: e164);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw AuthFailure('$e164 already has an account. Use "Log in" instead.');
      }
      throw AuthFailure(e.message ?? 'Could not create account (${e.code})');
    }
  }

  Future<void> signOut() => _auth.signOut();
}

class AuthResult {
  final User user;
  final String e164Phone;
  AuthResult({required this.user, required this.e164Phone});
}

class AuthFailure implements Exception {
  final String message;
  AuthFailure(this.message);
  @override
  String toString() => message;
}
