/// Platform-conditional facade for [ClassifierService]: real on-device
/// TFLite inference on Android/iOS/desktop (dart:io available), heuristic
/// fallback on Flutter Web (dart:io unavailable there, and tflite_flutter
/// needs dart:ffi which the web compiler rejects). Callers just do:
///   final classifier = ClassifierService();
///   await classifier.load();
///   final result = await classifier.classify(bytes);
library;

export 'classifier_service_web.dart' if (dart.library.io) 'classifier_service_mobile.dart';
