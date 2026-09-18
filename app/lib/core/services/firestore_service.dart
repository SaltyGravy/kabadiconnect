import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/collector_profile.dart';
import '../models/live_scrap_price.dart';
import '../models/lot.dart';
import '../models/recycler.dart';
import '../models/traceability_record.dart';

/// Single point of access to Firestore. Offline reads/writes -- including
/// lot photos, which are stored as a compressed base64 string directly on
/// the lot document rather than in Cloud Storage -- are all handled by the
/// SDK's own persistence cache (enabled in main.dart), so callers never need
/// to special-case connectivity.
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _lots => _db.collection('lots');
  CollectionReference<Map<String, dynamic>> get _traceability => _db.collection('traceability');
  CollectionReference<Map<String, dynamic>> get _recyclers => _db.collection('recyclers');
  CollectionReference<Map<String, dynamic>> get _collectors => _db.collection('collectors');
  CollectionReference<Map<String, dynamic>> get _priceHistory => _db.collection('price_history');
  CollectionReference<Map<String, dynamic>> get _liveScrapPrices => _db.collection('live_scrap_prices');

  // ---- Live scrap prices (see ml/sync_metalmandi_prices.py) ----
  Stream<List<LiveScrapPrice>> watchLiveScrapPrices() {
    return _liveScrapPrices.snapshots().map((s) => s.docs.map((d) => LiveScrapPrice.fromMap(d.data())).toList());
  }

  // ---- Lots ----
  Future<void> upsertLot(Lot lot) => _lots.doc(lot.lotId).set(lot.toMap(), SetOptions(merge: true));

  Stream<List<Lot>> lotsForCollector(String collectorId) {
    return _lots
        .where('collector_id', isEqualTo: collectorId)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Lot.fromMap(d.data())).toList());
  }

  Stream<List<Lot>> lotsForRecycler(String recyclerId) {
    return _lots
        .where('recycler_id', isEqualTo: recyclerId)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Lot.fromMap(d.data())).toList());
  }

  Future<Lot?> getLot(String lotId) async {
    final doc = await _lots.doc(lotId).get();
    if (!doc.exists) return null;
    return Lot.fromMap(doc.data()!);
  }

  Stream<Lot?> watchLot(String lotId) {
    return _lots.doc(lotId).snapshots().map((d) => d.exists ? Lot.fromMap(d.data()!) : null);
  }

  Stream<TraceabilityRecord?> watchTraceability(String lotId) {
    return _traceability.doc(lotId).snapshots().map((d) => d.exists ? TraceabilityRecord.fromMap(d.data()!) : null);
  }

  // ---- Traceability ----
  Future<void> upsertTraceability(TraceabilityRecord record) =>
      _traceability.doc(record.lotId).set(record.toMap(), SetOptions(merge: true));

  Future<TraceabilityRecord?> getTraceability(String lotId) async {
    final doc = await _traceability.doc(lotId).get();
    if (!doc.exists) return null;
    return TraceabilityRecord.fromMap(doc.data()!);
  }

  // ---- Recyclers ----
  Future<void> upsertRecycler(Recycler recycler) =>
      _recyclers.doc(recycler.recyclerId).set(recycler.toMap(), SetOptions(merge: true));

  Future<List<Recycler>> getAllRecyclers() async {
    final snap = await _recyclers.get();
    return snap.docs.map((d) => Recycler.fromMap(d.data())).toList();
  }

  Stream<Recycler?> watchRecycler(String recyclerId) {
    return _recyclers.doc(recyclerId).snapshots().map((d) => d.exists ? Recycler.fromMap(d.data()!) : null);
  }

  /// Finds the pre-registered recycler facility whose contact number matches
  /// the phone number that just completed OTP verification. Recyclers are
  /// admin/seed-provisioned (see docs/dataset_documentation.md), not
  /// self-registered, so this is a lookup, not a signup.
  Future<Recycler?> findRecyclerByPhone(String e164Phone) async {
    final snap = await _recyclers.where('contact_phone', isEqualTo: e164Phone).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Recycler.fromMap(snap.docs.first.data());
  }

  /// Restores a returning recycler's session: finds whichever facility this
  /// uid previously claimed (see claimRecycler).
  Future<Recycler?> findRecyclerByLinkedUid(String uid) async {
    final snap = await _recyclers.where('linked_auth_uid', isEqualTo: uid).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Recycler.fromMap(snap.docs.first.data());
  }

  /// Claims a pre-registered recycler facility for the signed-in uid. Only
  /// succeeds (per firestore.rules) if the facility is unclaimed or already
  /// claimed by this same uid, so one facility can't be hijacked by another
  /// verified phone number later.
  Future<void> claimRecycler(String recyclerId, String authUid) {
    return _recyclers.doc(recyclerId).set({'linked_auth_uid': authUid}, SetOptions(merge: true));
  }

  /// Lets a recycler correct their facility's precise location (set via
  /// Places search) -- allowed by firestore.rules only for whoever has
  /// already claimed that facility.
  Future<void> updateRecyclerLocation(String recyclerId, {required double lat, required double lng, required String facilityLocation}) {
    return _recyclers.doc(recyclerId).set({'lat': lat, 'lng': lng, 'facility_location': facilityLocation}, SetOptions(merge: true));
  }

  // ---- Collectors ----
  Future<void> upsertCollector(CollectorProfile profile) =>
      _collectors.doc(profile.collectorId).set(profile.toMap(), SetOptions(merge: true));

  Stream<CollectorProfile?> watchCollector(String collectorId) {
    return _collectors.doc(collectorId).snapshots().map((d) => d.exists ? CollectorProfile.fromMap(d.data()!) : null);
  }

  Future<int> countDocs(String collection) async {
    final agg = await _db.collection(collection).count().get();
    return agg.count ?? 0;
  }

  // ---- Price history (updatable dataset; app also ships a bundled
  // snapshot for pure-offline first run -- see PricingService) ----
  Future<void> addPriceObservation(Map<String, dynamic> row) => _priceHistory.add(row);
}
