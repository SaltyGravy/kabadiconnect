import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../constants.dart';
import 'classifier_result.dart';

/// Real on-device inference path: loads the MobileNetV2-transfer-learning
/// model trained in ml/train_classifier.py (exported as
/// assets/ml/classifier.tflite, ~2.4MB after dynamic-range quantization) and
/// runs it fully offline via tflite_flutter. This is what actually ships on
/// Android; see classifier_service_web.dart for why the web demo build
/// can't use this path.
class ClassifierService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  static const int _inputSize = 224;

  Future<void> load() async {
    if (_interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/ml/classifier.tflite');
      final labelsRaw = await rootBundle.loadString('assets/ml/labels.txt');
      _labels = labelsRaw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    } catch (_) {
      _interpreter = null;
    }
  }

  Future<ClassifierResult> classify(Uint8List imageBytes) async {
    final interpreter = _interpreter;
    if (interpreter == null || _labels.isEmpty) {
      return ClassifierResult(MaterialCategory.mixedOther, 0.0, false);
    }
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      return ClassifierResult(MaterialCategory.mixedOther, 0.0, false);
    }
    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);

    // Normalize to [-1, 1], matching the Rescaling(1/127.5, offset=-1) layer
    // baked into the trained model during export.
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final p = resized.getPixel(x, y);
          return [
            (p.r / 127.5) - 1.0,
            (p.g / 127.5) - 1.0,
            (p.b / 127.5) - 1.0,
          ];
        }),
      ),
    );
    final output = List.generate(1, (_) => List.filled(_labels.length, 0.0));
    interpreter.run(input, output);

    final scores = output[0];
    var bestIdx = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[bestIdx]) bestIdx = i;
    }
    final rawLabel = _labels[bestIdx];
    final isNonCollectible = rawLabel == 'NON_COLLECTIBLE';
    final category = isNonCollectible ? MaterialCategory.mixedOther : MaterialCategoryX.fromKey(rawLabel);
    return ClassifierResult(
      category,
      scores[bestIdx].toDouble(),
      true,
      isCollectible: !isNonCollectible,
      rejectionReason: isNonCollectible
          ? 'This item is recognized as non-collectible trash (bottles, packaging, paper, food waste, or general non-electronic debris).'
          : null,
    );
  }
}
