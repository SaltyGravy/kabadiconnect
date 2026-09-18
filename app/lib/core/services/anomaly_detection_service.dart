import '../constants.dart';
import '../models/lot.dart';
import 'pricing_service.dart';

/// Robust (median + MAD based) outlier check for transaction final values,
/// per the brief's "identification of abnormal or inconsistent transaction
/// values" requirement. Median/MAD (rather than mean/stddev) is used
/// because a handful of genuinely large industrial lots shouldn't blow out
/// the threshold for everyone else.
class AnomalyDetectionService {
  final PricingService pricing;
  AnomalyDetectionService(this.pricing);

  /// Returns true if [finalValue] for [weightKg] of [category] at [location]
  /// looks abnormal versus the historical per-unit baseline.
  bool isAnomalous({
    required MaterialCategory category,
    required String location,
    required double weightKg,
    required double finalValue,
  }) {
    final entry = pricing.bestEntryFor(category, location);
    if (entry == null || weightKg <= 0) return false;
    final perUnit = finalValue / weightKg;
    final median = entry.baselineMedian;
    final mad = entry.baselineMad == 0 ? median * 0.1 : entry.baselineMad;
    // ~4x MAD from median is a wide, conservative band (robust z-score style).
    final z = (perUnit - median).abs() / mad;
    return z > 4.0;
  }

  /// Multi-item version: a lot can bundle several distinct materials (see
  /// Lot.items), and the recycler enters ONE lump final price for the
  /// whole handover, not a price per item -- so instead of comparing that
  /// single figure against one category's per-kg baseline, this sums each
  /// item's own expected baseline value (median x weight) into one
  /// "expected total," and combines their MADs the same way, before
  /// running the same robust z-score check against the lump sum.
  bool isAnomalousForItems({
    required List<LotItem> items,
    required String location,
    required double finalValue,
  }) {
    double expectedTotal = 0;
    double combinedMad = 0;
    for (final item in items) {
      final entry = pricing.bestEntryFor(item.category, location);
      if (entry == null || item.weightKg <= 0) continue;
      expectedTotal += entry.baselineMedian * item.weightKg;
      final mad = entry.baselineMad == 0 ? entry.baselineMedian * 0.1 : entry.baselineMad;
      combinedMad += mad * item.weightKg;
    }
    if (expectedTotal <= 0 || combinedMad <= 0) return false;
    final z = (finalValue - expectedTotal).abs() / combinedMad;
    return z > 4.0;
  }
}
