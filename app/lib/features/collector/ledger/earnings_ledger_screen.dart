import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/lot.dart';
import '../../../core/services/firestore_service.dart';
import '../../../widgets/status_chip.dart';
import '../lot/lot_detail_screen.dart';

class EarningsLedgerScreen extends StatelessWidget {
  final VoidCallback? onHome;
  const EarningsLedgerScreen({super.key, this.onHome});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final firestore = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(t('earningsLedger')),
        leading: onHome == null ? null : IconButton(icon: const Icon(Icons.home), onPressed: onHome),
      ),
      body: StreamBuilder<List<Lot>>(
        stream: firestore.lotsForCollector(appState.collector!.collectorId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final lots = snapshot.data!;
          final totalEarned = lots.where((l) => l.paymentStatus == 'paid').fold<double>(0, (a, l) => a + (l.finalPrice ?? 0));
          final pendingDues = lots
              .where((l) => l.paymentStatus != 'paid' && (l.finalPrice != null || l.quotedPrice != null))
              .fold<double>(0, (a, l) => a + (l.finalPrice ?? l.quotedPrice ?? 0));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _SummaryCard(label: t('totalEarned'), value: totalEarned, color: kBrandGreen)),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard(label: t('pendingDues'), value: pendingDues, color: kAmber)),
                ],
              ),
              const SizedBox(height: 20),
              ...lots.map((lot) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(lot.category.icon, color: lot.category.color),
                      title: Text(lot.isMultiItem
                          ? '${t('cat_${lot.category.key}')} +${lot.items.length - 1} more · ${lot.weightKg} kg'
                          : '${t('cat_${lot.category.key}')} · ${lot.weightKg} kg'),
                      subtitle: Text('${lot.createdAt}'.substring(0, 10)),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('₹${(lot.finalPrice ?? lot.quotedPrice ?? lot.estimatedValue).toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          StatusChip(status: lot.status, label: t('status_${lot.status.key}')),
                        ],
                      ),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LotDetailScreen(lotId: lot.lotId))),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _SummaryCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 13)),
          const SizedBox(height: 6),
          Text('₹${value.toStringAsFixed(0)}', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
