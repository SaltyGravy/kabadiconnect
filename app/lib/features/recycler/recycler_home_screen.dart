import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/lot.dart';
import '../../core/services/firestore_service.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/status_chip.dart';
import '../account/account_screen.dart';
import 'recycler_lot_review_screen.dart';
import 'recycler_profile_screen.dart';

class RecyclerHomeScreen extends StatelessWidget {
  const RecyclerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final firestore = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(appState.recycler?.name ?? t('appName')),
        actions: [
          IconButton(icon: const Icon(Icons.factory), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecyclerProfileScreen()))),
          IconButton(icon: const Icon(Icons.account_circle), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen()))),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text(t('incomingLots'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ),
          Expanded(
            child: StreamBuilder<List<Lot>>(
              stream: firestore.lotsForRecycler(appState.recycler!.recyclerId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final lots = snapshot.data!;
                if (lots.isEmpty) return const Center(child: Text('No incoming lots yet.'));
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: lots.length,
                  itemBuilder: (context, i) {
                    final lot = lots[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(lot.category.icon, color: lot.category.color, size: 32),
                        title: Text(lot.isMultiItem
                            ? '${t('cat_${lot.category.key}')} +${lot.items.length - 1} more · ${lot.weightKg} kg'
                            : '${t('cat_${lot.category.key}')} · ${lot.weightKg} kg'),
                        subtitle: Text('${lot.collectionLocation} · ₹${(lot.quotedPrice ?? lot.estimatedValue).toStringAsFixed(0)}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            StatusChip(status: lot.status, label: t('status_${lot.status.key}')),
                            if (lot.flaggedAnomaly) const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.warning, color: Colors.red, size: 16)),
                          ],
                        ),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecyclerLotReviewScreen(lotId: lot.lotId))),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
