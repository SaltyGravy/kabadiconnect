import '../../constants.dart';

class ClassifierResult {
  final MaterialCategory category;
  final double confidence;
  final bool isRealModel; // false when running the heuristic fallback
  ClassifierResult(this.category, this.confidence, this.isRealModel);
}
