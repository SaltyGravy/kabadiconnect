/// Platform-conditional facade for [DetectorService]: real on-device
/// multi-item detection (TFLite, see train_detector.py) on Android/iOS/
/// desktop, heuristic fallback on Flutter Web -- same split as
/// [ClassifierService] and for the same reason (tflite_flutter needs
/// dart:ffi, which Flutter Web's compiler rejects). Callers:
///   final detector = DetectorService();
///   await detector.load();
///   final items = await detector.detect(bytes);
library;

export 'detector_service_web.dart' if (dart.library.io) 'detector_service_mobile.dart';
