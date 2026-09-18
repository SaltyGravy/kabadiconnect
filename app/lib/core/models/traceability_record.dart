/// The brief's "Traceability Dataset": a verifiable handover record,
/// separate from the lot/transaction, that a recycler confirms.
class TraceabilityRecord {
  final String lotId;
  final List<String> photoRefs;
  final double weightKg;
  final DateTime timestamp;
  final double? gpsLat;
  final double? gpsLng;
  final String handoverReferenceNumber;
  final bool recyclerConfirmation;
  final String subsequentStatus;

  TraceabilityRecord({
    required this.lotId,
    required this.photoRefs,
    required this.weightKg,
    required this.timestamp,
    required this.handoverReferenceNumber,
    this.gpsLat,
    this.gpsLng,
    this.recyclerConfirmation = false,
    this.subsequentStatus = 'handed_over',
  });

  Map<String, dynamic> toMap() => {
        'lot_id': lotId,
        'photo_refs': photoRefs,
        'weight_kg': weightKg,
        'timestamp': timestamp.toIso8601String(),
        'gps_lat': gpsLat,
        'gps_lng': gpsLng,
        'handover_reference_number': handoverReferenceNumber,
        'recycler_confirmation': recyclerConfirmation,
        'subsequent_status': subsequentStatus,
      };

  factory TraceabilityRecord.fromMap(Map<String, dynamic> m) => TraceabilityRecord(
        lotId: m['lot_id'] as String,
        photoRefs: (m['photo_refs'] as List?)?.map((e) => e.toString()).toList() ?? [],
        weightKg: (m['weight_kg'] as num).toDouble(),
        timestamp: DateTime.tryParse(m['timestamp'] as String? ?? '') ?? DateTime.now(),
        gpsLat: (m['gps_lat'] as num?)?.toDouble(),
        gpsLng: (m['gps_lng'] as num?)?.toDouble(),
        handoverReferenceNumber: m['handover_reference_number'] as String? ?? '',
        recyclerConfirmation: m['recycler_confirmation'] as bool? ?? false,
        subsequentStatus: m['subsequent_status'] as String? ?? 'handed_over',
      );

  TraceabilityRecord copyWith({bool? recyclerConfirmation, String? subsequentStatus}) => TraceabilityRecord(
        lotId: lotId,
        photoRefs: photoRefs,
        weightKg: weightKg,
        timestamp: timestamp,
        handoverReferenceNumber: handoverReferenceNumber,
        gpsLat: gpsLat,
        gpsLng: gpsLng,
        recyclerConfirmation: recyclerConfirmation ?? this.recyclerConfirmation,
        subsequentStatus: subsequentStatus ?? this.subsequentStatus,
      );
}
