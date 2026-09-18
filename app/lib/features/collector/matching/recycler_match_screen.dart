import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/lot.dart';
import '../../../core/models/recycler.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/recycler_matching_service.dart';
import '../lot/lot_detail_screen.dart';

class RecyclerMatchScreen extends StatefulWidget {
  final Lot lot;
  const RecyclerMatchScreen({super.key, required this.lot});

  @override
  State<RecyclerMatchScreen> createState() => _RecyclerMatchScreenState();
}

class _RecyclerMatchScreenState extends State<RecyclerMatchScreen> {
  List<RankedRecycler> _ranked = [];
  bool _loading = true;
  String? _sendingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final firestore = context.read<FirestoreService>();
    final matcher = context.read<RecyclerMatchingService>();
    final recyclers = await firestore.getAllRecyclers();
    final ranked = matcher.rank(
      recyclers: recyclers,
      categories: widget.lot.categories,
      collectorLat: widget.lot.gpsLat,
      collectorLng: widget.lot.gpsLng,
      needsPickup: widget.lot.logisticsOption == LogisticsOption.platformHandled,
    );
    if (mounted) setState(() {
      _ranked = ranked;
      _loading = false;
    });
  }

  Future<void> _send(Recycler recycler) async {
    setState(() => _sendingId = recycler.recyclerId);
    final firestore = context.read<FirestoreService>();
    // Sum the quote per item: this recycler's own rate for that item's
    // category where they have one, otherwise fall back to the item's own
    // estimate (a category they don't quote isn't worth zero).
    final quoted = widget.lot.items.fold<double>(0, (total, item) {
      final rate = recycler.offeredRates[item.category.key];
      return total + (rate != null ? rate * item.weightKg : item.estimatedValue);
    });
    final updated = widget.lot.copyWith(recyclerId: recycler.recyclerId, quotedPrice: quoted, status: LotStatus.matched);
    await firestore.upsertLot(updated);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LotDetailScreen(lotId: updated.lotId)));
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);

    return Scaffold(
      appBar: AppBar(title: Text(t('nearbyRecyclers'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ranked.isEmpty
              ? Center(child: Text(t('nearbyRecyclers')))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _ranked.length,
                  itemBuilder: (context, i) {
                    final ranked = _ranked[i];
                    final r = ranked.recycler;
                    // Single-category lots keep the old per-kg rate pill;
                    // multi-category lots show coverage instead, since one
                    // rate number wouldn't represent the whole lot.
                    final rate = widget.lot.categories.length == 1 ? r.offeredRates[widget.lot.category.key] : null;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                if (r.isAuthorized)
                                  Chip(
                                    avatar: const Icon(Icons.verified, size: 16, color: Colors.white),
                                    label: Text(t('authorized'), style: const TextStyle(color: Colors.white, fontSize: 11)),
                                    backgroundColor: kBrandGreen,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(r.facilityLocation, style: const TextStyle(color: Colors.black54)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                if (rate != null) _InfoPill(icon: Icons.currency_rupee, text: '₹${rate.toStringAsFixed(0)}${t('perKg')}'),
                                if (widget.lot.categories.length > 1)
                                  _InfoPill(
                                    icon: ranked.coversAll ? Icons.check_circle : Icons.info_outline,
                                    text: 'Covers ${ranked.categoriesCovered}/${ranked.categoriesTotal} materials',
                                  ),
                                if (ranked.distanceKm > 0) _InfoPill(icon: Icons.near_me, text: '${ranked.distanceKm.toStringAsFixed(1)} km'),
                                if (r.pickupAvailable) _InfoPill(icon: Icons.local_shipping, text: t('pickupAvailable')),
                                _InfoPill(icon: Icons.star, text: r.rating.toStringAsFixed(1)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _sendingId == null ? () => _send(r) : null,
                                child: _sendingId == r.recyclerId
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : Text(t('sendToRecycler')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}
