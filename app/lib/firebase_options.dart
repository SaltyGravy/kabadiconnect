// KabadiConnect Firebase configuration.
//
// Points at the real `kabadiconnect` Firebase project (Firestore + Phone
// Auth; Cloud Storage is intentionally not used -- see PhotoCodec /
// AuthService comments for why). Set `useEmulators = true` to instead run
// against the Firebase Local Emulator Suite for offline-friendly local dev
// (see README.md); when doing that, update `emulatorHost` to the dev
// machine's LAN IP so a real Android device on the same WiFi can reach it.
//
// Regenerate the FirebaseOptions blocks below (only) by running
// `flutterfire configure --project=kabadiconnect` from `app/` -- it patches
// this file in place rather than overwriting the emulator toggle above it.
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';

const bool useEmulators = false;
const String emulatorHost = '192.168.0.106';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (Platform.isAndroid) return android;
    return web;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDCeXojMVR3z4FaS0MB0mjjFFoKSSITrlQ',
    appId: '1:191302356358:web:620241fd5ec888e59bf007',
    messagingSenderId: '191302356358',
    projectId: 'kabadiconnect',
    authDomain: 'kabadiconnect.firebaseapp.com',
    storageBucket: 'kabadiconnect.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAbXB0gdmok9wBeGgpAUwJPFMWafoQkRBY',
    appId: '1:191302356358:android:64859de2a02753c19bf007',
    messagingSenderId: '191302356358',
    projectId: 'kabadiconnect',
    storageBucket: 'kabadiconnect.firebasestorage.app',
  );
}
