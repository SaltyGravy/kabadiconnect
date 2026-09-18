import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/lot.dart';
import '../../../core/services/carbon_credit_service.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/geo_service.dart';
import '../../../core/utils/photo_codec.dart';
import '../matching/recycler_match_screen.dart';

/// Review-before-you-submit step between building a lot (CreateLotScreen)
/// and actually creating it: shows exactly what's being sold, what the
/// collector stands to receive (materials + carbon-credit cashback, minus
/// any logistics fee), and lets them pick who moves the lot to the
/// recycler. Confirming here is what actually writes the lot to Firestore.
class CheckoutScreen extends StatefulWidget {
  final List<LotItem> items;
  final Uint8List photoBytes;
  final String sourceType;
  const CheckoutScreen({super.key, required this.items, required this.photoBytes, required this.sourceType});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  LogisticsOption _logistics = LogisticsOption.selfHandled;
  bool _saving = false;

  String _priceLocationKey(AppState appState) {
    final c = appState.collector;
    if (c?.lat != null && c?.lng != null) return nearestServiceLocation(c!.lat!, c.lng!);
    return serviceLocations.first;
  }

  double get _totalWeight => widget.items.fold(0.0, (a, i) => a + i.weightKg);
  double get _materialsSubtotal => widget.items.fold(0.0, (a, i) => a + i.estimatedValue);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final carbon = context.read<CarbonCreditService>();

    final co2Saved = carbon.co2SavedKgFor(widget.items);
    final cashback = carbon.cashbackFor(co2Saved);
    final logisticsFee = _logistics == LogisticsOption.platformHandled ? platformLogisticsFee(_totalWeight) : 0.0;
    final total = _materialsSubtotal + cashback - logisticsFee;

    return Scaffold(
      appBar: AppBar(title: Text(t('checkoutTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(widget.photoBytes, height: 180, width: double.infinity, fit: BoxFit.cover),
          ),
          const SizedBox(height: 20),
          Text('${t('itemsInLot')} (${widget.items.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...widget.items.asMap().entries.map(
                (e) => _CheckoutItemRow(index: e.key + 1, item: e.value, label: t('cat_${e.value.category.key}'), t: t),
              ),
          const SizedBox(height: 8),
          _row(t('weight'), '${_totalWeight.toStringAsFixed(1)} kg'),
          _row(t('materialsSubtotal'), '₹${_materialsSubtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: kBrandGreen.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.eco, color: kBrandGreen),
                  const SizedBox(width: 8),
                  Text(t('greenBonus'), style: const TextStyle(fontWeight: FontWeight.w700, color: kBrandGreenDark)),
                ]),
                const SizedBox(height: 10),
                _row(t('co2Saved'), '${co2Saved.toStringAsFixed(1)} kg CO₂e'),
                _row(t('greenBonus'), '+₹${cashback.toStringAsFixed(0)}'),
                const SizedBox(height: 6),
                Text(t('carbonDisclaimer'), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(t('logisticsTitle'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _LogisticsOptionCard(
            selected: _logistics == LogisticsOption.selfHandled,
            icon: Icons.directions_walk,
            title: t('logisticsSelf'),
            subtitle: t('logisticsSelfSub'),
            trailing: t('free'),
            onTap: () => setState(() => _logistics = LogisticsOption.selfHandled),
          ),
          const SizedBox(height: 10),
          _LogisticsOptionCard(
            selected: _logistics == LogisticsOption.platformHandled,
            icon: Icons.local_shipping,
            title: t('logisticsPlatform'),
            subtitle: t('logisticsPlatformSub'),
            trailing: '-₹${platformLogisticsFee(_totalWeight).toStringAsFixed(0)}',
            onTap: () => setState(() => _logistics = LogisticsOption.platformHandled),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                Text(t('estimatedTotalPayout'), style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 6),
                Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: kBrandGreenDark)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : () => _confirm(context, co2Saved, cashback, logisticsFee),
            child: _saving ? const CircularProgressIndicator(color: Colors.white) : Text(t('confirmCheckout')),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label, style: const TextStyle(color: Colors.black54)), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))],
        ),
      );

  Future<void> _confirm(BuildContext context, double co2Saved, double cashback, double logisticsFee) async {
    setState(() => _saving = true);
    final appState = context.read<AppState>();
    final firestore = context.read<FirestoreService>();
    final geo = context.read<GeoService>();

    final lotId = 'KC-${DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '')}-${const Uuid().v4().substring(0, 6).toUpperCase()}';
    final position = await geo.getCurrentPosition();
    final collector = appState.collector;
    final lat = position?.latitude ?? collector?.lat;
    final lng = position?.longitude ?? collector?.lng;
    final photoBase64 = compressPhotoToBase64(widget.photoBytes);

    final lot = Lot(
      lotId: lotId,
      collectorId: collector!.collectorId,
      items: List.of(widget.items),
      sourceType: widget.sourceType,
      photoBase64: photoBase64,
      collectionLocation: _priceLocationKey(appState),
      createdAt: DateTime.now(),
      gpsLat: lat,
      gpsLng: lng,
      co2SavedKg: co2Saved,
      carbonCashback: cashback,
      logisticsOption: _logistics,
      logisticsFee: logisticsFee,
    );
    await firestore.upsertLot(lot);

    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RecyclerMatchScreen(lot: lot)));
  }
}

class _CheckoutItemRow extends StatelessWidget {
  final int index;
  final LotItem item;
  final String label;
  final String Function(String) t;
  const _CheckoutItemRow({required this.index, required this.item, required this.label, required this.t});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: item.category.color,
          child: Text('$index', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        title: Row(children: [
          Icon(item.category.icon, size: 18, color: item.category.color),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        subtitle: Text('${item.weightKg} kg · ${t('cond_${item.condition}')}'),
        trailing: Text('₹${item.estimatedValue.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _LogisticsOptionCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;
  const _LogisticsOptionCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kBrandGreen.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? kBrandGreen : Colors.grey.shade300, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? kBrandGreen : Colors.grey.shade600),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Text(trailing, style: TextStyle(fontWeight: FontWeight.bold, color: selected ? kBrandGreenDark : Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }
}
