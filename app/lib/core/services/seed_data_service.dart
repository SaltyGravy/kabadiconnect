import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

/// Demonstrates the "how the dataset is generated, stored, validated,
/// updated" requirement concretely: this service loads the structured
/// datasets built by ml/generate_datasets.py (bundled as an asset) and
/// writes them into Firestore the first time the app runs against an empty
/// backend -- i.e. the app itself is the loader for its own seed data, not
/// a one-off manual import.
///
/// Only seeds public catalogue data (recyclers, price history): the
/// synthetic sample collectors/transactions/traceability in seed.json exist
/// to demo a populated UI against the open-rules local emulator, but don't
/// correspond to any real signed-in identity, so they can't (and, in a real
/// deployment, shouldn't) be written under firestore.rules, which scope
/// every lot/collector write to its owning Firebase Auth uid. Call this
/// only after a successful sign-in -- the rules also require signedIn().
class SeedDataService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<bool> isSeeded() async {
    final snap = await _db.collection('recyclers').limit(1).get();
    return snap.docs.isNotEmpty;
  }

  Future<void> seedIfEmpty() async {
    if (await isSeeded()) return;
    final raw = await rootBundle.loadString('assets/seed/seed.json');
    final seed = jsonDecode(raw) as Map<String, dynamic>;

    // Firestore caps a single WriteBatch at 500 ops, and a committed batch
    // can never be reused -- get a fresh one every time we cross the
    // chunk size, not just reset the counter.
    var batch = _db.batch();
    int ops = 0;

    Future<void> addOp(void Function(WriteBatch) op) async {
      op(batch);
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }

    for (final r in (seed['recyclers'] as List)) {
      final m = r as Map<String, dynamic>;
      await addOp((b) => b.set(_db.collection('recyclers').doc(m['recycler_id'] as String), m));
    }
    for (final p in (seed['prices'] as List)) {
      final m = p as Map<String, dynamic>;
      await addOp((b) => b.set(_db.collection('price_history').doc(m['price_id'] as String), m));
    }
    if (ops > 0) await batch.commit();
  }
}
