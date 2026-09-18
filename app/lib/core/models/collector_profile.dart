/// Minimal collector profile -- deliberately avoids unnecessary personal
/// information (no address, no ID documents; just what's needed to run
/// the app and pay the collector).
class CollectorProfile {
  final String collectorId;
  final String displayName;
  final String phone;
  final String preferredLanguage; // en | hi | mr
  final String operatingLocation;
  final double? lat;
  final double? lng;

  CollectorProfile({
    required this.collectorId,
    required this.displayName,
    required this.phone,
    required this.preferredLanguage,
    required this.operatingLocation,
    this.lat,
    this.lng,
  });

  CollectorProfile copyWith({
    String? preferredLanguage,
    String? operatingLocation,
    double? lat,
    double? lng,
  }) => CollectorProfile(
        collectorId: collectorId,
        displayName: displayName,
        phone: phone,
        preferredLanguage: preferredLanguage ?? this.preferredLanguage,
        operatingLocation: operatingLocation ?? this.operatingLocation,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
      );

  Map<String, dynamic> toMap() => {
        'collector_id': collectorId,
        'display_name': displayName,
        'phone': phone,
        'preferred_language': preferredLanguage,
        'operating_location': operatingLocation,
        'lat': lat,
        'lng': lng,
      };

  factory CollectorProfile.fromMap(Map<String, dynamic> m) => CollectorProfile(
        collectorId: m['collector_id'] as String,
        displayName: m['display_name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        preferredLanguage: m['preferred_language'] as String? ?? 'en',
        operatingLocation: m['operating_location'] as String? ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
      );
}
