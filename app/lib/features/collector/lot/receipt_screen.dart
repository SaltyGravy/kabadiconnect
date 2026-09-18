import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/lot.dart';
import '../../../core/models/recycler.dart';
import '../../../core/models/traceability_record.dart';
import '../../../core/services/firestore_service.dart';

/// Generated once a lot has been confirmed received by the recycler --
/// available to both the collector and the recycler as a single-source
/// summary of what was sold, for how much, and what environmental credit
/// and logistics choice applied.
class ReceiptScreen extends StatelessWidget {
  final String lotId;
  const ReceiptScreen({super.key, required this.lotId});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final firestore = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(title: Text(t('receiptTitle'))),
      body: StreamBuilder<Lot?>(
        stream: firestore.watchLot(lotId),
        builder: (context, lotSnap) {
          if (!lotSnap.hasData || lotSnap.data == null) return const Center(child: CircularProgressIndicator());
          final lot = lotSnap.data!;
          return FutureBuilder<TraceabilityRecord?>(
            future: firestore.getTraceability(lotId),
            builder: (context, traceSnap) {
              final record = traceSnap.data;
              return StreamBuilder<Recycler?>(
                stream: lot.recyclerId != null ? firestore.watchRecycler(lot.recyclerId!) : const Stream.empty(),
                builder: (context, recyclerSnap) {
                  final recycler = recyclerSnap.data;
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(child: Icon(Icons.receipt_long, size: 48, color: kBrandGreen)),
                      const SizedBox(height: 8),
                      Center(child: Text(lot.lotId, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                      Center(child: Text('${lot.createdAt}'.substring(0, 16), style: TextStyle(color: Colors.grey.shade600, fontSize: 12))),
                      const Divider(height: 32),
                      Text('${t('itemsInLot')} (${lot.items.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      ...lot.items.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: e.value.category.color,
                                  child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                Icon(e.value.category.icon, size: 18, color: e.value.category.color),
                                const SizedBox(width: 6),
                                Expanded(child: Text(t('cat_${e.value.category.key}'))),
                                Text('${e.value.weightKg} kg', style: const TextStyle(color: Colors.black54)),
                              ],
                            ),
                          )),
                      const Divider(height: 32),
                      _row(t('weight'), '${lot.weightKg} kg'),
                      _row(t('materialsSubtotal'), '₹${(lot.finalPrice ?? lot.quotedPrice ?? lot.estimatedValue).toStringAsFixed(0)}'),
                      if (lot.carbonCashback > 0) ...[
                        _row(t('co2Saved'), '${lot.co2SavedKg.toStringAsFixed(1)} kg CO₂e'),
                        _row(t('greenBonus'), '+₹${lot.carbonCashback.toStringAsFixed(0)}'),
                      ],
                      if (lot.logisticsFee > 0) _row(t('logisticsFeeLabel'), '-₹${lot.logisticsFee.toStringAsFixed(0)}'),
                      const Divider(height: 20),
                      _row(t('netTotal'), '₹${lot.collectorPayout.toStringAsFixed(0)}', bold: true),
                      const SizedBox(height: 20),
                      if (recycler != null) _row(t('recyclerProfile'), recycler.name),
                      if (record != null) _row(t('referenceNumber'), record.handoverReferenceNumber),
                      if (lot.gpsLat != null) _row('GPS', '${lot.gpsLat!.toStringAsFixed(4)}, ${lot.gpsLng!.toStringAsFixed(4)}'),
                      _row(t('paymentStatus'), lot.paymentStatus),
                      const SizedBox(height: 20),
                      Text(t('carbonDisclaimer'), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: bold ? Colors.black : Colors.black54, fontWeight: bold ? FontWeight.w700 : FontWeight.normal, fontSize: bold ? 17 : 14)),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: bold ? 20 : 14, color: bold ? kBrandGreenDark : Colors.black)),
            ),
          ],
        ),
      );
}
