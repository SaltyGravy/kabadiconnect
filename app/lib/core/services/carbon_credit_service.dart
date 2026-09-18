import 'dart:convert';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../models/lot.dart';

/// Estimated environmental impact + a real cashback bonus for recycling
/// instead of dumping/burning e-waste. The per-kg CO2 figures are
/// illustrative planning estimates (see assets/ml/carbon_factors.json), NOT
/// certified carbon credits from a registry like Verra/Gold Standard -- the
/// cashback is a KabadiConnect incentive on top of the recycler's own
/// payment for the materials, not something the recycler pays.
class CarbonCreditService {
  Map<String, double>? _co2PerKg;
  double _ratePerKgCo2 = 0;

  Future<void> load() async {
    if (_co2PerKg != null) return;
    final raw = await rootBundle.loadString('assets/ml/carbon_factors.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _co2PerKg = (decoded['co2_per_kg'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));
    _ratePerKgCo2 = (decoded['cashback_rate_per_kg_co2'] as num).toDouble();
  }

  double co2SavedKgFor(List<LotItem> items) {
    return items.fold(0.0, (sum, i) => sum + (_co2PerKg?[i.category.key] ?? 0) * i.weightKg);
  }

  double cashbackFor(double co2SavedKg) => co2SavedKg * _ratePerKgCo2;

  double get ratePerKgCo2 => _ratePerKgCo2;
}
