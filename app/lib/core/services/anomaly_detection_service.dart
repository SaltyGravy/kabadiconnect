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
    final mad = _floorMad(entry.baselineMad, median);
    // ~4x MAD from median is a wide, conservative band (robust z-score style).
    final z = (perUnit - median).abs() / mad;
    return z > 4.0;
  }

  /// The seed price table's `baseline_mad` values are unrealistically
  /// tight (measured: ~1.8-6% of the median across every category/
  /// location, averaging ~3.3%) -- a snapshot of a low-variance synthetic
  /// dataset, not real scrap-market spread from grade, condition, and
  /// negotiation. Taken at face value, a 4x-MAD band ends up only
  /// +/-15-25% wide, so routine, perfectly normal price variation was
  /// getting flagged as "anomalous" on nearly every transaction. Flooring
  /// MAD at 12% of the median keeps the same robust z-score approach but
  /// widens the "normal" band to roughly +/-48%, while a genuinely wild
  /// price (2x+ off, e.g. a typo) still trips it.
  double _floorMad(double rawMad, double median) {
    final floor = median * 0.12;
    return rawMad < floor ? floor : rawMad;
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
      final mad = _floorMad(entry.baselineMad, entry.baselineMedian);
      combinedMad += mad * item.weightKg;
    }
    if (expectedTotal <= 0 || combinedMad <= 0) return false;
    final z = (finalValue - expectedTotal).abs() / combinedMad;
    return z > 4.0;
  }
}
