/// One (location, category) rate refreshed on a schedule from a third-party
/// scrap-price feed -- see ml/sync_metalmandi_prices.py, run every few
/// hours by a GitHub Actions cron into Firestore's `live_scrap_prices`
/// collection. [PricingService] layers these over the static, bundled
/// price table so estimates reflect current area-wise rates without an
/// app release, while still falling back to the offline baseline when a
/// category/location has no live data (e.g. Mixed Plastics -- the feed is
/// metal-scrap-focused and doesn't cover it).
class LiveScrapPrice {
  final String location;
  final String category; // MaterialCategory key
  final double ratePerKg;
  final String source;
  final DateTime fetchedAt;

  LiveScrapPrice({
    required this.location,
    required this.category,
    required this.ratePerKg,
    required this.source,
    required this.fetchedAt,
  });

  factory LiveScrapPrice.fromMap(Map<String, dynamic> m) => LiveScrapPrice(
        location: m['location'] as String,
        category: m['category'] as String,
        ratePerKg: (m['rate_per_kg'] as num).toDouble(),
        source: m['source'] as String? ?? '',
        fetchedAt: DateTime.tryParse(m['fetched_at'] as String? ?? '') ?? DateTime.now(),
      );
}
