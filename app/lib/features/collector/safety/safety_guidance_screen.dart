import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/tts_service.dart';

class _SafetyTip {
  final IconData icon;
  final Color color;
  final String titleKey;
  final String descKey;
  _SafetyTip(this.icon, this.color, this.titleKey, this.descKey);
}

final _tips = [
  _SafetyTip(Icons.local_fire_department, Colors.deepOrange, 'safety_cables_title', 'safety_cables_desc'),
  _SafetyTip(Icons.science, Colors.purple, 'safety_acid_title', 'safety_acid_desc'),
  _SafetyTip(Icons.battery_alert, Colors.red, 'safety_battery_title', 'safety_battery_desc'),
  _SafetyTip(Icons.tv, Colors.blueGrey, 'safety_crt_title', 'safety_crt_desc'),
];

/// Splits a translated safety description into short, one-idea-at-a-time
/// sentences for bullet rendering -- a dense paragraph is hard to scan
/// quickly, one point per line isn't. Handles both '.' (English) and the
/// Devanagari '।' full stop used in the Hindi/Marathi translations.
List<String> _splitIntoPoints(String text) {
  return text
      .split(RegExp(r'(?<=[.।])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

class SafetyGuidanceScreen extends StatelessWidget {
  const SafetyGuidanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final tts = context.read<TtsService>();

    return Scaffold(
      appBar: AppBar(title: Text(t('safetyTitle'))),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tips.length,
        itemBuilder: (context, i) {
          final tip = _tips[i];
          final title = t(tip.titleKey);
          final desc = t(tip.descKey);
          final points = _splitIntoPoints(desc);
          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(backgroundColor: tip.color.withValues(alpha: 0.15), child: Icon(tip.icon, color: tip.color)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...points.map((point) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Icon(Icons.circle, size: 8, color: tip.color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(point, style: const TextStyle(fontSize: 16, height: 1.4))),
                          ],
                        ),
                      )),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => tts.speak('$title. $desc', appState.locale),
                      icon: const Icon(Icons.volume_up, size: 18),
                      label: Text(t('listenBtn')),
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
