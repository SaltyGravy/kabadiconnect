import 'dart:math';
import 'dart:typed_data';

import '../../constants.dart';
import 'detected_item.dart';

/// Web/desktop fallback -- see classifier_service_web.dart for why
/// tflite_flutter can't run here. Returns 1-2 plausible-looking boxes so
/// the "AI detected N materials" UI always has something to show in the
/// web demo; replaced automatically by the real detector on Android (see
/// detector_service_mobile.dart).
class DetectorService {
  Future<void> load() async {}

  Future<List<DetectedItem>> detect(Uint8List imageBytes) async {
    final rnd = Random(imageBytes.isEmpty ? 0 : imageBytes.fold<int>(0, (a, b) => (a + b) % 100003));
    final categories = MaterialCategory.values;
    final n = 1 + rnd.nextInt(2);
    final items = <DetectedItem>[];
    for (var i = 0; i < n; i++) {
      final cat = categories[rnd.nextInt(categories.length)];
      final cx = 0.2 + rnd.nextDouble() * 0.6;
      final cy = 0.2 + rnd.nextDouble() * 0.6;
      final w = 0.22 + rnd.nextDouble() * 0.18;
      final h = 0.22 + rnd.nextDouble() * 0.18;
      items.add(DetectedItem(
        category: cat,
        confidence: 0.5 + rnd.nextDouble() * 0.2,
        isRealModel: false,
        xMin: (cx - w / 2).clamp(0.0, 1.0),
        yMin: (cy - h / 2).clamp(0.0, 1.0),
        xMax: (cx + w / 2).clamp(0.0, 1.0),
        yMax: (cy + h / 2).clamp(0.0, 1.0),
      ));
    }
    return items;
  }
}
