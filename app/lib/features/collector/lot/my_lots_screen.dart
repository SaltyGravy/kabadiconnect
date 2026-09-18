import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/lot.dart';
import '../../../core/services/firestore_service.dart';
import '../../../widgets/status_chip.dart';
import 'lot_detail_screen.dart';

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
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(lot.category.icon, color: lot.category.color, size: 32),
                  title: Text(lot.isMultiItem ? '${t('cat_${lot.category.key}')} +${lot.items.length - 1} more' : t('cat_${lot.category.key}')),
                  subtitle: Text('${lot.weightKg} kg · ${lot.collectionLocation}'),
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
