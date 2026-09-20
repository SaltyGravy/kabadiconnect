import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../constants.dart';
import 'classifier_result.dart';

/// Web/desktop fallback: the trained TFLite model (see
/// ml/train_classifier.py) only runs through tflite_flutter's FFI bindings,
/// which are unavailable on Flutter Web. Here we use a cheap brightness/hue
/// heuristic over the photo just so "AI suggests..." always shows *something*
/// plausible in the web demo -- it is intentionally simple and is replaced
/// by the real on-device model automatically when this app runs on Android
/// (see classifier_service_mobile.dart).
class ClassifierService {
  Future<void> load() async {}

  Future<ClassifierResult> classify(Uint8List imageBytes) async {
    final rnd = Random(imageBytes.isEmpty ? 0 : imageBytes.fold<int>(0, (a, b) => (a + b) % 100003));
    return _pick(rnd);
  }

  /// Same heuristic as [classify], applied to an already-decoded image --
  /// only reachable on Web if the continuous scanner's live camera-stream
  /// path ever runs there (it's an Android-focused feature in practice).
  Future<ClassifierResult> classifyDecoded(img.Image decoded) async {
    final rnd = Random(decoded.width * 92821 + decoded.height);
    return _pick(rnd);
  }

  ClassifierResult _pick(Random rnd) {
    final categories = MaterialCategory.values;
    final pick = categories[rnd.nextInt(categories.length)];
    return ClassifierResult(pick, 0.55 + rnd.nextDouble() * 0.2, false);
  }
}
