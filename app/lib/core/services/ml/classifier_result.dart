import '../../constants.dart';

class ClassifierResult {
  final MaterialCategory category;
  final double confidence;
  final bool isRealModel; // false when running the heuristic fallback
  final bool isCollectible;
  final String? rejectionReason;

  ClassifierResult(
    this.category,
    this.confidence,
    this.isRealModel, {
    this.isCollectible = true,
    this.rejectionReason,
  });
}
