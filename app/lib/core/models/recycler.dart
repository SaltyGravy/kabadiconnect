import '../constants.dart';

class Recycler {
  final String recyclerId;
  final String name;
  final String facilityLocation;
  final double lat;
  final double lng;
  final List<MaterialCategory> materialsAccepted;
  final String authorizationType;
  final String registrationNumber;
  final String authorizationStatus; // active | pending_renewal | expired
  final String contactPhone;
  final String contactEmail;
  final Map<String, double> offeredRates; // category key -> rate
  final bool pickupAvailable;
  final int serviceAreaKm;
  final double rating;
  final String? linkedAuthUid;

  Recycler({
    required this.recyclerId,
    required this.name,
    required this.facilityLocation,
    required this.lat,
    required this.lng,
    required this.materialsAccepted,
    required this.authorizationType,
    required this.registrationNumber,
    required this.authorizationStatus,
    required this.contactPhone,
    required this.contactEmail,
    required this.offeredRates,
    required this.pickupAvailable,
    required this.serviceAreaKm,
    required this.rating,
    this.linkedAuthUid,
  });

  bool get isAuthorized => authorizationStatus == 'active';

  Map<String, dynamic> toMap() => {
        'recycler_id': recyclerId,
        'name': name,
        'facility_location': facilityLocation,
        'lat': lat,
        'lng': lng,
        'materials_accepted': materialsAccepted.map((c) => c.key).toList(),
        'authorization_type': authorizationType,
        'registration_number': registrationNumber,
        'authorization_status': authorizationStatus,
        'contact_phone': contactPhone,
        'contact_email': contactEmail,
        'offered_rates': offeredRates,
        'pickup_available': pickupAvailable,
        'service_area_km': serviceAreaKm,
        'rating': rating,
        'linked_auth_uid': linkedAuthUid,
      };

  factory Recycler.fromMap(Map<String, dynamic> m) => Recycler(
        recyclerId: m['recycler_id'] as String,
        name: m['name'] as String,
        facilityLocation: m['facility_location'] as String,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        materialsAccepted: _parseCategories(m['materials_accepted']),
        authorizationType: m['authorization_type'] as String? ?? '',
        registrationNumber: m['registration_number'] as String? ?? '',
        authorizationStatus: m['authorization_status'] as String? ?? 'pending_renewal',
        contactPhone: m['contact_phone'] as String? ?? '',
        contactEmail: m['contact_email'] as String? ?? '',
        offeredRates: _parseRates(m['offered_rates']),
        pickupAvailable: m['pickup_available'] as bool? ?? false,
        serviceAreaKm: (m['service_area_km'] as num?)?.toInt() ?? 25,
        rating: (m['rating'] as num?)?.toDouble() ?? 4.0,
        linkedAuthUid: m['linked_auth_uid'] as String?,
      );

  static List<MaterialCategory> _parseCategories(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => MaterialCategoryX.fromKey(e.toString())).toList();
    }
    return [];
  }

  static Map<String, double> _parseRates(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    }
    return {};
  }
}
