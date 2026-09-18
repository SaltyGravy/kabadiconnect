import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/l10n/app_strings.dart';

/// Always-visible sync status strip -- the concrete UI proof of the
/// offline-first requirement: collectors should never wonder "did that
/// save?" even with no signal.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final online = appState.isOnline;
    return Container(
      width: double.infinity,
      color: online ? Colors.green.shade50 : Colors.orange.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(online ? Icons.cloud_done : Icons.cloud_off, size: 16, color: online ? Colors.green.shade700 : Colors.orange.shade800),
          const SizedBox(width: 8),
          Text(
            online ? t('syncedBanner') : t('offlineBanner'),
            style: TextStyle(fontSize: 12, color: online ? Colors.green.shade700 : Colors.orange.shade800),
          ),
        ],
      ),
    );
  }
}
