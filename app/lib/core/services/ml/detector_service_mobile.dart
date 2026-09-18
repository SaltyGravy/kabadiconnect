import 'dart:math';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../constants.dart';
import 'detected_item.dart';

/// Real on-device inference path: loads the single-anchor, 10x10-grid
/// YOLO-style detector trained in ml/train_detector.py (exported as
/// assets/ml/detector.tflite) and runs it fully offline. Decoding (sigmoid/
/// exp/softmax + box math + NMS) happens here in Dart, mirroring
/// train_detector.py's decode_boxes exactly -- the model itself outputs
/// raw logits, nothing more.
class DetectorService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  static const int _inputSize = 320;
  static const int _grid = 10;
  static const double _anchorCells = 3.0;
  static const double _objThreshold = 0.4;
  static const double _iouThreshold = 0.35;

  Future<void> load() async {
    if (_interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/ml/detector.tflite');
      final labelsRaw = await rootBundle.loadString('assets/ml/detector_labels.txt');
      _labels = labelsRaw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    } catch (_) {
      _interpreter = null;
    }
  }

  Future<List<DetectedItem>> detect(Uint8List imageBytes) async {
    final interpreter = _interpreter;
    if (interpreter == null || _labels.isEmpty) return [];
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return [];
    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);

    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final p = resized.getPixel(x, y);
          return [(p.r / 127.5) - 1.0, (p.g / 127.5) - 1.0, (p.b / 127.5) - 1.0];
        }),
      ),
    );

    final channels = 5 + _labels.length;
    final output = List.generate(1, (_) => List.generate(_grid, (_) => List.generate(_grid, (_) => List.filled(channels, 0.0))));
    interpreter.run(input, output);

    final raw = output[0];
    final candidates = <_Candidate>[];
    for (var gy = 0; gy < _grid; gy++) {
      for (var gx = 0; gx < _grid; gx++) {
        final cell = raw[gy][gx];
        final objScore = _sigmoid(cell[0]);
        if (objScore < _objThreshold) continue;
        final cx = (gx + _sigmoid(cell[1])) / _grid;
        final cy = (gy + _sigmoid(cell[2])) / _grid;
        final w = exp(cell[3]) * _anchorCells / _grid;
        final h = exp(cell[4]) * _anchorCells / _grid;
        var bestIdx = 0;
        var bestVal = cell[5];
        for (var c = 1; c < _labels.length; c++) {
          if (cell[5 + c] > bestVal) {
            bestVal = cell[5 + c];
            bestIdx = c;
          }
        }
        candidates.add(_Candidate(
          score: objScore,
          classIdx: bestIdx,
          xMin: (cx - w / 2).clamp(0.0, 1.0),
          yMin: (cy - h / 2).clamp(0.0, 1.0),
          xMax: (cx + w / 2).clamp(0.0, 1.0),
          yMax: (cy + h / 2).clamp(0.0, 1.0),
        ));
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final kept = <_Candidate>[];
    for (final c in candidates) {
      final cx = (c.xMin + c.xMax) / 2, cy = (c.yMin + c.yMax) / 2;
      final overlaps = kept.any((k) =>
          _iou(c, k) > _iouThreshold ||
          // A large object can make several adjacent grid cells fire on
          // (mostly) the same thing at slightly different offsets, which
          // plain IoU can miss since the boxes are offset rather than
          // concentric -- also treat it as a duplicate if the weaker
          // box's centre falls inside an already-kept box of the same class.
          (c.classIdx == k.classIdx && cx >= k.xMin && cx <= k.xMax && cy >= k.yMin && cy <= k.yMax));
      if (!overlaps) kept.add(c);
    }
    return kept
        .map((c) => DetectedItem(
              category: MaterialCategoryX.fromKey(_labels[c.classIdx]),
              confidence: c.score,
              isRealModel: true,
              xMin: c.xMin,
              yMin: c.yMin,
              xMax: c.xMax,
              yMax: c.yMax,
            ))
        .toList();
  }

  double _sigmoid(double x) => 1 / (1 + exp(-x));

  double _iou(_Candidate a, _Candidate b) {
    final ix1 = max(a.xMin, b.xMin), iy1 = max(a.yMin, b.yMin);
    final ix2 = min(a.xMax, b.xMax), iy2 = min(a.yMax, b.yMax);
    final inter = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1);
    final areaA = (a.xMax - a.xMin) * (a.yMax - a.yMin);
    final areaB = (b.xMax - b.xMin) * (b.yMax - b.yMin);
    return inter / (areaA + areaB - inter + 1e-6);
  }
}

class _Candidate {
  final double score;
  final int classIdx;
  final double xMin, yMin, xMax, yMax;
  _Candidate({required this.score, required this.classIdx, required this.xMin, required this.yMin, required this.xMax, required this.yMax});
}
