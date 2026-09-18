import '../constants.dart';

/// One material line within a lot -- a lot is one photo + one handover, but
/// can bundle several distinct materials (e.g. a mixed pile with cables, a
/// battery, and a PCB) rather than forcing one category per lot.
class LotItem {
  final MaterialCategory category;
  final String condition; // intact | partially_damaged | burnt/tampered | mixed_lot
  final double weightKg;
  final double estimatedValue; // instant on-device estimate for this item alone

  LotItem({
    required this.category,
    required this.condition,
    required this.weightKg,
    required this.estimatedValue,
  });

  Map<String, dynamic> toMap() => {
        'category': category.key,
        'condition': condition,
        'weight_kg': weightKg,
        'estimated_value': estimatedValue,
      };

  factory LotItem.fromMap(Map<String, dynamic> m) => LotItem(
        category: MaterialCategoryX.fromKey(m['category'] as String),
        condition: m['condition'] as String? ?? 'mixed_lot',
        weightKg: (m['weight_kg'] as num?)?.toDouble() ?? 0,
        estimatedValue: (m['estimated_value'] as num?)?.toDouble() ?? 0,
      );
}

/// A material lot. Combines the brief's "Material Dataset" and
/// "Transaction Dataset" fields into one document per lot -- a lot IS the
/// transaction unit collectors create and recyclers act on. One photo and
/// one handover cover the whole lot; [items] is the (possibly
/// multi-category) breakdown of what's actually in it.
class Lot {
  final String lotId;
  final String collectorId;
  final List<LotItem> items; // always at least one
  final String sourceType;
  final String photoBase64; // compressed JPEG, base64-encoded, stored inline (no Cloud Storage)
  final double? quotedPrice; // recycler's quote once matched (sum across items)
  final double? finalPrice; // agreed value at handover/confirmation
  final String? recyclerId;
  final String collectionLocation;
  final double? gpsLat;
  final double? gpsLng;
  final DateTime createdAt;
  final LotStatus status;
  final String paymentStatus; // pending | partial | paid
  final bool flaggedAnomaly;
  final bool pendingSync;
  final double co2SavedKg; // estimated environmental impact, informational
  final double carbonCashback; // real bonus added on top of the materials price
  final LogisticsOption logisticsOption;
  final double logisticsFee; // >0 only when logisticsOption == platformHandled

  Lot({
    required this.lotId,
    required this.collectorId,
    required this.items,
    required this.sourceType,
    required this.photoBase64,
    required this.collectionLocation,
    required this.createdAt,
    this.quotedPrice,
    this.finalPrice,
    this.recyclerId,
    this.gpsLat,
    this.gpsLng,
    this.status = LotStatus.created,
    this.paymentStatus = 'pending',
    this.flaggedAnomaly = false,
    this.pendingSync = false,
    this.co2SavedKg = 0,
    this.carbonCashback = 0,
    this.logisticsOption = LogisticsOption.selfHandled,
    this.logisticsFee = 0,
  }) : assert(items.isNotEmpty, 'a lot must have at least one item');

  /// The lot's headline category for icon/label purposes where only one
  /// representative value fits (list tiles etc.) -- the first item added.
  MaterialCategory get category => items.first.category;
  List<MaterialCategory> get categories => items.map((i) => i.category).toSet().toList();
  double get weightKg => items.fold(0.0, (a, i) => a + i.weightKg);
  double get estimatedValue => items.fold(0.0, (a, i) => a + i.estimatedValue);
  bool get isMultiItem => items.length > 1;

  /// What the collector actually walks away with: the agreed materials
  /// price (final once paid, otherwise the recycler's quote, otherwise the
  /// on-device estimate) plus the carbon-credit cashback bonus, minus any
  /// platform logistics fee.
  double get collectorPayout => (finalPrice ?? quotedPrice ?? estimatedValue) + carbonCashback - logisticsFee;

  Lot copyWith({
    double? quotedPrice,
    double? finalPrice,
    String? recyclerId,
    LotStatus? status,
    String? paymentStatus,
    bool? flaggedAnomaly,
    bool? pendingSync,
  }) {
    return Lot(
      lotId: lotId,
      collectorId: collectorId,
      items: items,
      sourceType: sourceType,
      photoBase64: photoBase64,
      collectionLocation: collectionLocation,
      createdAt: createdAt,
      quotedPrice: quotedPrice ?? this.quotedPrice,
      finalPrice: finalPrice ?? this.finalPrice,
      recyclerId: recyclerId ?? this.recyclerId,
      gpsLat: gpsLat,
      gpsLng: gpsLng,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      flaggedAnomaly: flaggedAnomaly ?? this.flaggedAnomaly,
      pendingSync: pendingSync ?? this.pendingSync,
      co2SavedKg: co2SavedKg,
      carbonCashback: carbonCashback,
      logisticsOption: logisticsOption,
      logisticsFee: logisticsFee,
    );
  }

  Map<String, dynamic> toMap() => {
        'lot_id': lotId,
        'collector_id': collectorId,
        'items': items.map((i) => i.toMap()).toList(),
        // Kept alongside `items` (not read back by fromMap on this app
        // version) purely so older app builds / external tooling reading
        // this dataset still see a single representative category+weight+
        // value rather than nothing.
        'material_category': category.key,
        'weight_kg': weightKg,
        'estimated_value': estimatedValue,
        'source_type': sourceType,
        'photo_base64': photoBase64,
        'quoted_price': quotedPrice,
        'final_price': finalPrice,
        'recycler_id': recyclerId,
        'collection_location': collectionLocation,
        'gps_lat': gpsLat,
        'gps_lng': gpsLng,
        'created_at': createdAt.toIso8601String(),
        'status': status.key,
        'payment_status': paymentStatus,
        'flagged_anomaly': flaggedAnomaly,
        'co2_saved_kg': co2SavedKg,
        'carbon_cashback': carbonCashback,
        'logistics_option': logisticsOption.key,
        'logistics_fee': logisticsFee,
      };

  factory Lot.fromMap(Map<String, dynamic> m) {
    final rawItems = m['items'] as List?;
    final items = (rawItems != null && rawItems.isNotEmpty)
        ? rawItems.map((e) => LotItem.fromMap(e as Map<String, dynamic>)).toList()
        : [
            // Backward compat: lots created before multi-item support (a
            // handful of real ones already exist in production from
            // earlier testing) stored one category/weight/value directly
            // on the lot document instead of an `items` array.
            LotItem(
              category: MaterialCategoryX.fromKey(m['material_category'] as String? ?? 'MIXED_OTHER'),
              condition: m['condition'] as String? ?? 'mixed_lot',
              weightKg: (m['weight_kg'] as num?)?.toDouble() ?? 0,
              estimatedValue: (m['estimated_value'] as num?)?.toDouble() ?? 0,
            ),
          ];
    return Lot(
      lotId: m['lot_id'] as String,
      collectorId: m['collector_id'] as String,
      items: items,
      sourceType: m['source_type'] as String? ?? 'household',
      photoBase64: m['photo_base64'] as String? ?? '',
      quotedPrice: (m['quoted_price'] as num?)?.toDouble(),
      finalPrice: (m['final_price'] as num?)?.toDouble(),
      recyclerId: m['recycler_id'] as String?,
      collectionLocation: m['collection_location'] as String? ?? '',
      gpsLat: (m['gps_lat'] as num?)?.toDouble(),
      gpsLng: (m['gps_lng'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
      status: LotStatusX.fromKey(m['status'] as String? ?? 'created'),
      paymentStatus: m['payment_status'] as String? ?? 'pending',
      flaggedAnomaly: m['flagged_anomaly'] as bool? ?? false,
      co2SavedKg: (m['co2_saved_kg'] as num?)?.toDouble() ?? 0,
      carbonCashback: (m['carbon_cashback'] as num?)?.toDouble() ?? 0,
      logisticsOption: LogisticsOptionX.fromKey(m['logistics_option'] as String? ?? 'selfHandled'),
      logisticsFee: (m['logistics_fee'] as num?)?.toDouble() ?? 0,
    );
  }
}
