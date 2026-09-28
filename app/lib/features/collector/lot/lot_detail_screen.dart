import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/lot.dart';
import '../../../core/models/recycler.dart';
import '../../../core/models/traceability_record.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/geo_service.dart';
import '../../../core/utils/photo_codec.dart';
import '../../../widgets/status_chip.dart';
import 'receipt_screen.dart';

class LotDetailScreen extends StatefulWidget {
  final String lotId;
  const LotDetailScreen({super.key, required this.lotId});

  @override
  State<LotDetailScreen> createState() => _LotDetailScreenState();
}

class _LotDetailScreenState extends State<LotDetailScreen> {
  bool _generating = false;

  Future<void> _generateHandover(Lot lot) async {
    setState(() => _generating = true);
    final firestore = context.read<FirestoreService>();
    final geo = context.read<GeoService>();
    final position = await geo.getCurrentPosition();

    final record = TraceabilityRecord(
      lotId: lot.lotId,
      // Reference only -- the photo itself lives on the lot document
      // (lot.photoBase64) so it isn't duplicated across two documents.
      photoRefs: ['lots/${lot.lotId}'],
      weightKg: lot.weightKg,
      timestamp: DateTime.now(),
      handoverReferenceNumber: 'HR-${const Uuid().v4().substring(0, 8).toUpperCase()}',
      gpsLat: position?.latitude ?? lot.gpsLat,
      gpsLng: position?.longitude ?? lot.gpsLng,
      recyclerConfirmation: false,
      subsequentStatus: 'handed_over',
    );
    await firestore.upsertTraceability(record);
    await firestore.upsertLot(lot.copyWith(status: LotStatus.handedOver));
    if (mounted) setState(() => _generating = false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final firestore = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(title: Text(widget.lotId)),
      body: StreamBuilder<Lot?>(
        stream: firestore.watchLot(widget.lotId),
        builder: (context, lotSnap) {
          if (!lotSnap.hasData || lotSnap.data == null) return const Center(child: CircularProgressIndicator());
          final lot = lotSnap.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (lot.photoBase64.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(decodeBase64Photo(lot.photoBase64), height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
              if (lot.photoBase64.isNotEmpty) const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lot.isMultiItem ? '${lot.items.length} materials in this lot' : t('cat_${lot.category.key}'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  StatusChip(status: lot.status, label: t('status_${lot.status.key}')),
                ],
              ),
              const SizedBox(height: 12),
              ...lot.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(item.category.icon, size: 28, color: item.category.color),
                        const SizedBox(width: 10),
                        Expanded(child: Text(t('cat_${item.category.key}'))),
                        Text('${item.weightKg} kg', style: const TextStyle(color: Colors.black54)),
                      ],
                    ),
                  )),
              // Recycler this lot has been matched with, while still
              // pending pickup/drop-off -- once handed over the receipt
              // below already has the full record.
              if (lot.recyclerId != null && lot.status.index < LotStatus.handedOver.index)
                StreamBuilder<Recycler?>(
                  stream: firestore.watchRecycler(lot.recyclerId!),
                  builder: (context, recyclerSnap) {
                    final name = recyclerSnap.data?.name;
                    if (name == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: kBrandGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.recycling, color: kBrandGreenDark, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t('matchedWith'), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const Divider(height: 32),
              _row(t('weight'), '${lot.weightKg} kg'),
              _row(t('estimatedValue'), '₹${lot.estimatedValue.toStringAsFixed(0)}'),
              if (lot.quotedPrice != null) _row(t('quotedPrice'), '₹${lot.quotedPrice!.toStringAsFixed(0)}'),
              if (lot.finalPrice != null) _row(t('finalPrice'), '₹${lot.finalPrice!.toStringAsFixed(0)}'),
              if (lot.carbonCashback > 0) _row(t('greenBonus'), '+₹${lot.carbonCashback.toStringAsFixed(0)}'),
              if (lot.logisticsFee > 0) _row(t('logisticsFeeLabel'), '-₹${lot.logisticsFee.toStringAsFixed(0)}'),
              const Divider(height: 20),
              _row(t('estimatedTotalPayout'), '₹${lot.collectorPayout.toStringAsFixed(0)}'),
              _row(t('paymentStatus'), lot.paymentStatus),
              if (lot.flaggedAnomaly)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.warning, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t('anomalyFlag'), style: const TextStyle(color: Colors.red))),
                  ]),
                ),
              const SizedBox(height: 24),
              if (lot.status == LotStatus.matched)
                ElevatedButton.icon(
                  onPressed: _generating ? null : () => _generateHandover(lot),
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(_generating ? '...' : t('generateHandover')),
                ),
              if (lot.status.index >= LotStatus.confirmed.index)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptScreen(lotId: lot.lotId))),
                    icon: const Icon(Icons.receipt_long),
                    label: Text(t('viewReceipt')),
                  ),
                ),
              if (lot.status.index >= LotStatus.handedOver.index)
                StreamBuilder<TraceabilityRecord?>(
                  stream: firestore.watchTraceability(lot.lotId),
                  builder: (context, traceSnap) {
                    final record = traceSnap.data;
                    if (record == null) return const SizedBox.shrink();
                    return Column(
                      children: [
                        Text(t('showToRecycler'), style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
                            child: QrImageView(data: record.handoverReferenceNumber, size: 180),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('${t('referenceNumber')}: ${record.handoverReferenceNumber}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 6),
                        Text('${record.timestamp}'.substring(0, 16), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        if (record.gpsLat != null)
                          Text('GPS: ${record.gpsLat!.toStringAsFixed(4)}, ${record.gpsLng!.toStringAsFixed(4)}',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        const SizedBox(height: 16),
                        if (!record.recyclerConfirmation)
                          Text(t('waitingConfirmation'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                        if (record.recyclerConfirmation)
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.check_circle, color: kBrandGreen),
                            const SizedBox(width: 6),
                            Text(t('status_confirmed'), style: const TextStyle(color: kBrandGreen, fontWeight: FontWeight.w600)),
                          ]),
                      ],
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label, style: const TextStyle(color: Colors.black54)), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))],
        ),
      );
}
