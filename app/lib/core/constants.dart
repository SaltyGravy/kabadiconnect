import 'package:flutter/material.dart';

/// The 8 material categories from the problem brief.
enum MaterialCategory {
  crt,
  lcdLed,
  pcb,
  cables,
  batteries,
  motorsMagnets,
  mixedPlastics,
  mixedOther,
}

extension MaterialCategoryX on MaterialCategory {
  /// Key used in datasets / Firestore / the ML label files.
  String get key {
    switch (this) {
      case MaterialCategory.crt:
        return 'CRT';
      case MaterialCategory.lcdLed:
        return 'LCD_LED';
      case MaterialCategory.pcb:
        return 'PCB';
      case MaterialCategory.cables:
        return 'CABLES';
      case MaterialCategory.batteries:
        return 'BATTERIES';
      case MaterialCategory.motorsMagnets:
        return 'MOTORS_MAGNETS';
      case MaterialCategory.mixedPlastics:
        return 'MIXED_PLASTICS';
      case MaterialCategory.mixedOther:
        return 'MIXED_OTHER';
    }
  }

  IconData get icon {
    switch (this) {
      case MaterialCategory.crt:
        return Icons.tv;
      case MaterialCategory.lcdLed:
        return Icons.desktop_windows;
      case MaterialCategory.pcb:
        return Icons.memory;
      case MaterialCategory.cables:
        return Icons.cable;
      case MaterialCategory.batteries:
        return Icons.battery_full;
      case MaterialCategory.motorsMagnets:
        return Icons.settings_input_component;
      case MaterialCategory.mixedPlastics:
        return Icons.category;
      case MaterialCategory.mixedOther:
        return Icons.inventory_2;
    }
  }

  Color get color {
    switch (this) {
      case MaterialCategory.crt:
        return const Color(0xFF455A64);
      case MaterialCategory.lcdLed:
        return const Color(0xFF1E88E5);
      case MaterialCategory.pcb:
        return const Color(0xFF2E7D32);
      case MaterialCategory.cables:
        return const Color(0xFFEF6C00);
      case MaterialCategory.batteries:
        return const Color(0xFFC62828);
      case MaterialCategory.motorsMagnets:
        return const Color(0xFF6D4C41);
      case MaterialCategory.mixedPlastics:
        return const Color(0xFF00838F);
      case MaterialCategory.mixedOther:
        return const Color(0xFF616161);
    }
  }

  static MaterialCategory fromKey(String key) {
    return MaterialCategory.values.firstWhere(
      (c) => c.key == key,
      orElse: () => MaterialCategory.mixedOther,
    );
  }
}

const List<String> serviceLocations = [
  'Pune',
  'Mumbai',
  'Nagpur',
  'Nashik',
  'Chhatrapati Sambhajinagar',
  'Pimpri-Chinchwad',
];

/// Coordinates for the fixed set of cities the price dataset and recycler
/// directory are keyed by (see ml/generate_datasets.py's LOCATIONS). Address
/// search (Places API) resolves to arbitrary real-world coordinates, so
/// [nearestServiceLocation] snaps a resolved lat/lng back to whichever of
/// these the price board/anomaly detection actually has data for.
const Map<String, (double, double)> serviceLocationCoords = {
  'Pune': (18.5204, 73.8567),
  'Mumbai': (19.0760, 72.8777),
  'Nagpur': (21.1458, 79.0882),
  'Nashik': (19.9975, 73.7898),
  'Chhatrapati Sambhajinagar': (19.8762, 75.3433),
  'Pimpri-Chinchwad': (18.6298, 73.7997),
};

String nearestServiceLocation(double lat, double lng) {
  String best = serviceLocations.first;
  double bestDist = double.infinity;
  for (final entry in serviceLocationCoords.entries) {
    final (clat, clng) = entry.value;
    final dLat = lat - clat;
    final dLng = lng - clng;
    final dist = dLat * dLat + dLng * dLng; // squared distance is fine for nearest-of-6 comparison
    if (dist < bestDist) {
      bestDist = dist;
      best = entry.key;
    }
  }
  return best;
}

enum AppLocale { en, hi, mr }

enum UserRole { collector, recycler }

enum LotStatus {
  created,
  matched,
  inTransit,
  handedOver,
  confirmed,
  paid,
  completed,
  disputed,
}

extension LotStatusX on LotStatus {
  String get key => toString().split('.').last;

  static LotStatus fromKey(String key) {
    return LotStatus.values.firstWhere(
      (s) => s.key == key,
      orElse: () => LotStatus.created,
    );
  }
}

/// Who moves the lot from the collector to the recycler after handover.
enum LogisticsOption { selfHandled, platformHandled }

extension LogisticsOptionX on LogisticsOption {
  String get key => toString().split('.').last;

  static LogisticsOption fromKey(String key) {
    return LogisticsOption.values.firstWhere((o) => o.key == key, orElse: () => LogisticsOption.selfHandled);
  }
}

/// Nominal fee for KabadiConnect to arrange pickup/transport instead of the
/// collector handling it themselves -- a flat base plus a small per-kg
/// component so heavier lots (more effort to move) cost a little more.
double platformLogisticsFee(double weightKg) => 20 + (3 * weightKg);

const kBrandGreen = Color(0xFF1B7A43);
const kBrandGreenDark = Color(0xFF0F5A30);
const kAmber = Color(0xFFF2A900);
