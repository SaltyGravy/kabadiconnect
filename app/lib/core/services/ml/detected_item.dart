import '../../constants.dart';

/// One localized item found by [DetectorService] in a photo -- unlike
/// [ClassifierResult] (one label for the whole photo), this carries WHERE
/// in the photo the item is, as a normalized [0,1] box, so several
/// different materials in one photo can each get their own row and their
/// own drawn box.
class DetectedItem {
  final MaterialCategory category;
  final double confidence;
  final bool isRealModel; // false when running the heuristic fallback (web)
  final double xMin, yMin, xMax, yMax; // normalized to the photo's own size

  DetectedItem({
    required this.category,
    required this.confidence,
    required this.isRealModel,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });
}
