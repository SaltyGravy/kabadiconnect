import 'package:geolocator/geolocator.dart';

class GeoService {
  /// A collector who never answers (or whose browser/OS never surfaces) the
  /// location permission prompt must not be stuck on a spinner forever --
  /// every awaited Geolocator call here is time-boxed so lot creation always
  /// completes, with or without GPS.
  static const _timeout = Duration(seconds: 5);

  Future<Position?> getCurrentPosition() async {
    try {
      final permission = await Geolocator.checkPermission().timeout(_timeout);
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission().timeout(_timeout);
        if (requested == LocationPermission.denied || requested == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) return null;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(_timeout);
      if (!serviceEnabled) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(_timeout);
    } catch (_) {
      // Offline / permission-denied / permission-prompt-never-answered /
      // unsupported browser context -- the app must keep working without
      // GPS (manual location text remains the fallback everywhere this is used).
      return null;
    }
  }
}
