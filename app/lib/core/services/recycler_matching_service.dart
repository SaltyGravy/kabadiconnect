import 'dart:math' as math;

import '../constants.dart';
import '../models/recycler.dart';

class RankedRecycler {
  final Recycler recycler;
  final double score;
  final double distanceKm;
  final int categoriesCovered;
  final int categoriesTotal;
  RankedRecycler(this.recycler, this.score, this.distanceKm, this.categoriesCovered, this.categoriesTotal);

  bool get coversAll => categoriesCovered == categoriesTotal;
}

/// Ranks authorized recyclers for a lot by: authorization status, how many
/// of the lot's material categories they accept, offered rate, pickup
/// availability, and distance -- the factors the brief calls out for
/// recycler matching.
///
/// A lot can bundle several distinct materials (see Lot.items), and no
/// single recycler in a 12-facility seed directory necessarily accepts
/// every category in a mixed lot -- so recyclers are ranked by *coverage*
/// (how many of the lot's categories they take) rather than filtered out
/// entirely for missing one. A full-coverage recycler always outranks a
/// partial one; partial matches still show, since "no results" for a mixed
/// lot would be worse than an imperfect but real option.
class RecyclerMatchingService {
  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);

  List<RankedRecycler> rank({
    required List<Recycler> recyclers,
    required List<MaterialCategory> categories,
    required double? collectorLat,
    required double? collectorLng,
    required bool needsPickup,
  }) {
    final candidates = recyclers.where((r) => categories.any((c) => r.materialsAccepted.contains(c))).toList();

    final ranked = candidates.map((r) {
      final covered = categories.where((c) => r.materialsAccepted.contains(c)).length;

      double score = 0;
      score += r.isAuthorized ? 50 : -100; // hard preference for authorized
      // Coverage dominates the score: full coverage should always beat
      // partial coverage regardless of how good the other factors are.
      score += (covered / categories.length) * 100;

      final coveredRates = categories.map((c) => r.offeredRates[c.key] ?? 0).where((rate) => rate > 0);
      final avgRate = coveredRates.isEmpty ? 0 : coveredRates.reduce((a, b) => a + b) / coveredRates.length;
      score += avgRate > 0 ? (avgRate / 10).clamp(0, 30) : 0;
      score += r.pickupAvailable && needsPickup ? 15 : 0;
      score += r.rating * 3;

      double distanceKm = 0;
      if (collectorLat != null && collectorLng != null) {
        distanceKm = _distanceKm(collectorLat, collectorLng, r.lat, r.lng);
        score -= (distanceKm / 5).clamp(0, 25); // closer is better
        if (distanceKm > r.serviceAreaKm) score -= 20; // outside declared service area
      }
      return RankedRecycler(r, score, distanceKm, covered, categories.length);
    }).toList();

    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }
}
