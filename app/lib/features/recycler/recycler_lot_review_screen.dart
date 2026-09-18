import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/lot.dart';
import '../../core/models/traceability_record.dart';
import '../../core/services/anomaly_detection_service.dart';
import '../../core/services/firestore_service.dart';
import '../../core/utils/photo_codec.dart';
import '../../widgets/status_chip.dart';
import '../collector/lot/receipt_screen.dart';

class RecyclerLotReviewScreen extends StatefulWidget {
  final String lotId;
  const RecyclerLotReviewScreen({super.key, required this.lotId});

  @override
  State<RecyclerLotReviewScreen> createState() => _RecyclerLotReviewScreenState();
}

class _RecyclerLotReviewScreenState extends State<RecyclerLotReviewScreen> {
  final _finalPriceCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _finalPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmHandover(Lot lot) async {
    setState(() => _busy = true);
    final firestore = context.read<FirestoreService>();
    final record = await firestore.getTraceability(lot.lotId);
    if (record != null) {
      await firestore.upsertTraceability(record.copyWith(recyclerConfirmation: true, subsequentStatus: 'confirmed'));
    }
    await firestore.upsertLot(lot.copyWith(status: LotStatus.confirmed));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _markPaid(Lot lot) async {
    setState(() => _busy = true);
    final firestore = context.read<FirestoreService>();
    final anomaly = context.read<AnomalyDetectionService>();
    final finalPrice = double.tryParse(_finalPriceCtrl.text) ?? lot.quotedPrice ?? lot.estimatedValue;

    final isAnomalous = anomaly.isAnomalousForItems(
      items: lot.items,
      location: lot.collectionLocation.split(',').first.trim(),
      finalValue: finalPrice,
    );

    await firestore.upsertLot(lot.copyWith(
      finalPrice: finalPrice,
      status: LotStatus.paid,
      paymentStatus: 'paid',
      flaggedAnomaly: isAnomalous,
    ));
    if (mounted) setState(() => _busy = false);
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
          if (_finalPriceCtrl.text.isEmpty) {
            _finalPriceCtrl.text = (lot.quotedPrice ?? lot.estimatedValue).toStringAsFixed(0);
          }

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
              const Divider(height: 32),
              _row(t('weight'), '${lot.weightKg} kg'),
              _row('Location', lot.collectionLocation),
              _row(t('quotedPrice'), '₹${(lot.quotedPrice ?? 0).toStringAsFixed(0)}'),
              if (lot.logisticsOption == LogisticsOption.platformHandled)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _InfoBanner(icon: Icons.local_shipping, text: t('platformLogisticsRequested'), color: kBrandGreen),
                ),
              const SizedBox(height: 24),
              if (lot.status == LotStatus.matched)
                const _InfoBanner(icon: Icons.hourglass_top, text: 'Waiting for collector to hand over the lot.'),
              if (lot.status == LotStatus.handedOver)
                StreamBuilder<TraceabilityRecord?>(
                  stream: firestore.watchTraceability(lot.lotId),
                  builder: (context, traceSnap) {
                    final record = traceSnap.data;
                    return Column(
                      children: [
                        if (record != null) ...[
                          _row(t('referenceNumber'), record.handoverReferenceNumber),
                          if (record.gpsLat != null) _row('GPS', '${record.gpsLat!.toStringAsFixed(4)}, ${record.gpsLng!.toStringAsFixed(4)}'),
                          const SizedBox(height: 16),
                        ],
                        ElevatedButton.icon(
                          onPressed: _busy ? null : () => _confirmHandover(lot),
                          icon: const Icon(Icons.check_circle),
                          label: Text(t('confirmPickup')),
                        ),
                      ],
                    );
                  },
                ),
              if (lot.status == LotStatus.confirmed) ...[
                Text(t('finalPrice'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _finalPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(border: OutlineInputBorder(), prefixText: '₹'),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _busy ? null : () => _markPaid(lot),
                  icon: const Icon(Icons.payments),
                  label: Text(t('markPaid')),
                ),
              ],
              if (lot.status.index >= LotStatus.paid.index)
                _InfoBanner(icon: Icons.check_circle, text: '${t('finalPrice')}: ₹${(lot.finalPrice ?? 0).toStringAsFixed(0)} · ${t('status_paid')}', color: kBrandGreen),
              if (lot.status.index >= LotStatus.confirmed.index)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptScreen(lotId: lot.lotId))),
                    icon: const Icon(Icons.receipt_long),
                    label: Text(t('viewReceipt')),
                  ),
                ),
              if (lot.flaggedAnomaly)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _InfoBanner(icon: Icons.warning, text: t('anomalyFlag'), color: Colors.red),
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
          children: [Text(label, style: const TextStyle(color: Colors.black54)), Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)))],
        ),
      );
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoBanner({required this.icon, required this.text, this.color = Colors.orange});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [Icon(icon, color: color), const SizedBox(width: 10), Expanded(child: Text(text, style: TextStyle(color: color)))]),
    );
  }
}
