import 'dart:convert';
import 'package:flutter/services.dart';

import '../constants.dart';

class PriceEntry {
  final String unit;
  final double latestInformalPrice;
  final double latestRecyclerOffer;
  final double trendPerDay;
  final String trendDirection;
  final double baselineMedian;
  final double baselineMad;
  final double marketRangeLow;
  final double marketRangeHigh;

  PriceEntry({
    required this.unit,
    required this.latestInformalPrice,
    required this.latestRecyclerOffer,
    required this.trendPerDay,
    required this.trendDirection,
    required this.baselineMedian,
    required this.baselineMad,
    required this.marketRangeLow,
    required this.marketRangeHigh,
  });

  factory PriceEntry.fromMap(Map<String, dynamic> m) => PriceEntry(
        unit: m['unit'] as String,
        latestInformalPrice: (m['latest_informal_price'] as num).toDouble(),
        latestRecyclerOffer: (m['latest_recycler_offer'] as num).toDouble(),
        trendPerDay: (m['trend_per_day'] as num).toDouble(),
        trendDirection: m['trend_direction'] as String,
        baselineMedian: (m['baseline_median'] as num).toDouble(),
        baselineMad: (m['baseline_mad'] as num).toDouble(),
        marketRangeLow: (m['market_range_low'] as num).toDouble(),
        marketRangeHigh: (m['market_range_high'] as num).toDouble(),
      );
}

/// Reads the distilled price table (trained offline by
/// ml/train_price_model.py, see that file for the real regression model and
/// its accuracy metrics) bundled as an asset, so valuation works fully
/// offline and instantly on-device. When online, SeedDataService/Firestore
/// can refresh this table with newer transaction-derived prices.
class PricingService {
  Map<String, Map<String, PriceEntry>>? _table; // category -> location -> entry

  Future<void> load() async {
    if (_table != null) return;
    final raw = await rootBundle.loadString('assets/ml/price_table.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _table = decoded.map((cat, locMap) => MapEntry(
          cat,
          (locMap as Map<String, dynamic>).map((loc, entry) => MapEntry(loc, PriceEntry.fromMap(entry as Map<String, dynamic>))),
        ));
  }

  PriceEntry? entryFor(MaterialCategory category, String location) {
    return _table?[category.key]?[location];
  }

  /// Falls back to averaging across known locations if the exact location
  /// isn't in the table (e.g. a new collector-entered town).
  PriceEntry? bestEntryFor(MaterialCategory category, String location) {
    final direct = entryFor(category, location);
    if (direct != null) return direct;
    final byLoc = _table?[category.key];
    if (byLoc == null || byLoc.isEmpty) return null;
    return byLoc.values.first;
  }

  /// Instant on-device valuation shown right after weight entry.
  double estimateValue({
    required MaterialCategory category,
    required String location,
    required double weightKg,
    required String condition,
  }) {
    final entry = bestEntryFor(category, location);
    // A weight of 0 means "not entered yet," not "at least one piece" -- the
    // per-piece clamp below is for rounding up fractional piece counts
    // (e.g. 0.5 -> 1), not for treating an unset weight as one piece.
    if (entry == null || weightKg <= 0) return 0;
    double perUnit = entry.latestInformalPrice;
    // condition adjustment -- simple, explainable multiplier (documented
    // heuristic layered on top of the trained price model's output).
    switch (condition) {
      case 'intact':
        perUnit *= 1.1;
        break;
      case 'burnt/tampered':
        perUnit *= 0.55;
        break;
      case 'partially_damaged':
        perUnit *= 0.85;
        break;
      default:
        break;
    }
    final isPerPiece = entry.unit == 'per piece';
    return isPerPiece ? perUnit * weightKg.clamp(1, double.infinity) : perUnit * weightKg;
  }

  List<String> get locations => serviceLocations;
}
