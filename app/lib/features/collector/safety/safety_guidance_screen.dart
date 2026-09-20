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

class SafetyGuidanceScreen extends StatefulWidget {
  const SafetyGuidanceScreen({super.key});

  @override
  State<SafetyGuidanceScreen> createState() => _SafetyGuidanceScreenState();
}

class _SafetyGuidanceScreenState extends State<SafetyGuidanceScreen> {
  // Which card is actively speaking right now (null = nothing playing).
  int? _playingIndex;
  // Next point index to speak for each card -- lets Play resume from where
  // Pause left off instead of always restarting from the top. On-device TTS
  // engines don't support true mid-utterance pause/resume, so this speaks
  // one sentence at a time and treats "pause" as "stop after this sentence".
  final Map<int, int> _nextPoint = {};

  late TtsService _tts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tts = context.read<TtsService>();
    _tts.setCompletionHandler(_onUtteranceComplete);
  }

  @override
  void dispose() {
    _tts.setCompletionHandler(() {});
    super.dispose();
  }

  List<String> _pointsFor(int i, AppState appState) {
    final tip = _tips[i];
    final title = AppStrings.t(tip.titleKey, appState.locale);
    final desc = AppStrings.t(tip.descKey, appState.locale);
    final points = _splitIntoPoints(desc);
    // First point is prefixed with the title so the card is identified by
    // ear too, not just by sight.
    if (points.isNotEmpty) points[0] = '$title. ${points[0]}';
    return points;
  }

  void _onUtteranceComplete() {
    if (!mounted) return;
    final i = _playingIndex;
    if (i == null) return;
    final appState = context.read<AppState>();
    final points = _pointsFor(i, appState);
    final next = (_nextPoint[i] ?? 0) + 1;
    if (next < points.length) {
      setState(() => _nextPoint[i] = next);
      _tts.speak(points[next], appState.locale);
    } else {
      setState(() {
        _nextPoint[i] = 0; // fully finished -- next Play starts over
        _playingIndex = null;
      });
    }
  }

  void _togglePlayPause(int i, AppState appState) {
    if (_playingIndex == i) {
      _tts.stop();
      setState(() => _playingIndex = null);
      return;
    }
    final points = _pointsFor(i, appState);
    final startAt = (_nextPoint[i] ?? 0).clamp(0, points.length - 1);
    setState(() {
      _playingIndex = i;
      _nextPoint[i] = startAt;
    });
    _tts.speak(points[startAt], appState.locale);
  }

  void _replay(int i, AppState appState) {
    if (_playingIndex == i) _tts.stop();
    setState(() {
      _nextPoint[i] = 0;
      _playingIndex = i;
    });
    _tts.speak(_pointsFor(i, appState)[0], appState.locale);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);

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
          final isPlaying = _playingIndex == i;
          final progress = _nextPoint[i] ?? 0;
          final hasProgress = progress > 0 && !isPlaying;

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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isPlaying)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: tip.color),
                              ),
                              const SizedBox(width: 6),
                              Text('${progress + 1}/${points.length}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      else if (hasProgress)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text('${t('pauseBtn')} · ${progress + 1}/${points.length}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _replay(i, appState),
                        icon: const Icon(Icons.replay, size: 18),
                        label: Text(t('replayBtn')),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _togglePlayPause(i, appState),
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 18),
                        label: Text(isPlaying ? t('pauseBtn') : t('listenBtn')),
                      ),
                    ],
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
