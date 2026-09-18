import 'dart:convert';
import 'package:http/http.dart' as http;

import '../api_keys.dart';

class PlaceSuggestion {
  final String placeId;
  final String description;
  PlaceSuggestion(this.placeId, this.description);
}

class ResolvedPlace {
  final double lat;
  final double lng;
  final String formattedAddress;
  ResolvedPlace(this.lat, this.lng, this.formattedAddress);
}

/// Address search backing the "set precise location by searching" flow for
/// collector profiles and recycler facility records -- separate from the
/// live GPS captured per-lot (see GeoService), this is for a *registered*
/// base location that survives even when a device's GPS fix fails.
class PlacesService {
  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    if (input.trim().length < 3) return [];
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
      'input': input,
      'components': 'country:in', // India-first, per the brief's pilot geography
      'key': googleMapsApiKey,
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return [];
      return (body['predictions'] as List)
          .map((p) => PlaceSuggestion(p['place_id'] as String, p['description'] as String))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<ResolvedPlace?> resolve(String placeId) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': placeId,
      'fields': 'geometry,formatted_address',
      'key': googleMapsApiKey,
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return null;
      final result = body['result'] as Map<String, dynamic>;
      final loc = (result['geometry'] as Map<String, dynamic>)['location'] as Map<String, dynamic>;
      return ResolvedPlace(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
        result['formatted_address'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
