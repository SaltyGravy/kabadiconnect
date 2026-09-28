import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/lot.dart';
import '../../../core/models/recycler.dart';
import '../../../core/services/firestore_service.dart';
import '../../../widgets/status_chip.dart';
import 'lot_detail_screen.dart';

/// Statuses at/after which the lot has already been physically handed
/// over -- once that's happened the recycler's name matters less (the
/// receipt/detail screen has the full record); before that, a collector
/// waiting on pickup or drop-off wants to know who they're dealing with.
const _handedOverOrLater = {
  LotStatus.handedOver,
  LotStatus.confirmed,
  LotStatus.paid,
  LotStatus.completed,
};

class MyLotsScreen extends StatelessWidget {
  final VoidCallback? onHome;
  const MyLotsScreen({super.key, this.onHome});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final firestore = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(t('myLots')),
        leading: onHome == null ? null : IconButton(icon: const Icon(Icons.home), onPressed: onHome),
      ),
      body: StreamBuilder<List<Lot>>(
        stream: firestore.lotsForCollector(appState.collector!.collectorId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final lots = snapshot.data!;
          if (lots.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t('noLotsYet'), textAlign: TextAlign.center)));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: lots.length,
            itemBuilder: (context, i) {
              final lot = lots[i];
              final showRecycler = lot.recyclerId != null && !_handedOverOrLater.contains(lot.status);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(lot.category.icon, color: lot.category.color, size: 32),
                  title: Text(lot.isMultiItem ? '${t('cat_${lot.category.key}')} +${lot.items.length - 1} more' : t('cat_${lot.category.key}')),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${lot.weightKg} kg · ${lot.collectionLocation}'),
                      if (showRecycler)
                        StreamBuilder<Recycler?>(
                          stream: firestore.watchRecycler(lot.recyclerId!),
                          builder: (context, recyclerSnap) {
                            final name = recyclerSnap.data?.name;
                            if (name == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${t('matchedWith')}: $name',
                                style: TextStyle(color: kBrandGreenDark, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  isThreeLine: showRecycler,
                  trailing: StatusChip(status: lot.status, label: t('status_${lot.status.key}')),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LotDetailScreen(lotId: lot.lotId))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
