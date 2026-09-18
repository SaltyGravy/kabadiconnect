import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/services/firestore_service.dart';
import '../../widgets/location_search_field.dart';

class RecyclerProfileScreen extends StatelessWidget {
  const RecyclerProfileScreen({super.key});

  Future<void> _editLocation(BuildContext context) async {
    final appState = context.read<AppState>();
    final firestore = context.read<FirestoreService>();
    final recycler = appState.recycler!;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Update facility location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            LocationSearchField(
              initialText: recycler.facilityLocation,
              label: 'Search for the facility address',
              onResolved: (place) async {
                await firestore.updateRecyclerLocation(
                  recycler.recyclerId,
                  lat: place.lat,
                  lng: place.lng,
                  facilityLocation: place.formattedAddress,
                );
                final updated = await firestore.watchRecycler(recycler.recyclerId).first;
                if (updated != null) await appState.setRecycler(updated);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final r = appState.recycler!;

    return Scaffold(
      appBar: AppBar(title: Text(t('recyclerProfile'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(radius: 36, backgroundColor: kAmber, child: Text(r.name.substring(0, 1), style: const TextStyle(fontSize: 28, color: Colors.white))),
          ),
          const SizedBox(height: 12),
          Center(child: Text(r.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          Center(
            child: Chip(
              avatar: Icon(r.isAuthorized ? Icons.verified : Icons.warning_amber, color: Colors.white, size: 16),
              label: Text(r.authorizationStatus, style: const TextStyle(color: Colors.white)),
              backgroundColor: r.isAuthorized ? kBrandGreen : Colors.orange,
            ),
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(child: _row(Icons.location_on, r.facilityLocation)),
              TextButton(onPressed: () => _editLocation(context), child: const Text('Edit')),
            ],
          ),
          _row(Icons.badge, r.registrationNumber),
          _row(Icons.phone, r.contactPhone),
          _row(Icons.email, r.contactEmail),
          _row(Icons.local_shipping, r.pickupAvailable ? t('pickupAvailable') : '—'),
          _row(Icons.map, '${r.serviceAreaKm} km service area'),
          _row(Icons.star, r.rating.toStringAsFixed(1)),
          const SizedBox(height: 16),
          Text('Materials accepted & offered rates', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...r.materialsAccepted.map((cat) => Card(
                child: ListTile(
                  leading: Icon(cat.icon, color: cat.color),
                  title: Text(t('cat_${cat.key}')),
                  trailing: Text('₹${(r.offeredRates[cat.key] ?? 0).toStringAsFixed(0)}'),
                ),
              )),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [Icon(icon, size: 18, color: Colors.black54), const SizedBox(width: 10), Expanded(child: Text(text))]),
      );
}
