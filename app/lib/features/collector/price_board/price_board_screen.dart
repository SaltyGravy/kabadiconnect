import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/pricing_service.dart';
import '../../../core/services/tts_service.dart';

class PriceBoardScreen extends StatefulWidget {
  final VoidCallback? onHome;
  const PriceBoardScreen({super.key, this.onHome});
  @override
  State<PriceBoardScreen> createState() => _PriceBoardScreenState();
}

class _PriceBoardScreenState extends State<PriceBoardScreen> {
  late String _location;
  bool _locationInitializedFromCollector = false;

  @override
  void initState() {
    super.initState();
    _location = serviceLocations.first;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final pricing = context.read<PricingService>();
    final tts = context.read<TtsService>();
    // collector.operatingLocation is now a full Places address (e.g. "Pune,
    // Maharashtra, India"), not one of the six city keys the price table is
    // indexed by -- snap it the same way create_lot_screen.dart does,
    // otherwise this silently falls through to bestEntryFor's "any
    // location" fallback and shows an arbitrary city's prices by default.
    if (!_locationInitializedFromCollector) {
      final c = appState.collector;
      if (c?.lat != null && c?.lng != null) {
        _location = nearestServiceLocation(c!.lat!, c.lng!);
      }
      _locationInitializedFromCollector = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t('priceBoard')),
        leading: widget.onHome == null ? null : IconButton(icon: const Icon(Icons.home), onPressed: widget.onHome),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DropdownButtonFormField<String>(
              initialValue: serviceLocations.contains(_location) ? _location : serviceLocations.first,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: serviceLocations.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setState(() => _location = v ?? _location),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: MaterialCategory.values.map((cat) {
                final entry = pricing.bestEntryFor(cat, _location);
                if (entry == null) return const SizedBox.shrink();
                final trendIcon = entry.trendDirection == 'up'
                    ? Icons.trending_up
                    : entry.trendDirection == 'down'
                        ? Icons.trending_down
                        : Icons.trending_flat;
                final trendColor = entry.trendDirection == 'up'
                    ? Colors.green
                    : entry.trendDirection == 'down'
                        ? Colors.red
                        : Colors.grey;
                final trendKey = entry.trendDirection == 'up' ? 'trendUp' : (entry.trendDirection == 'down' ? 'trendDown' : 'trendStable');

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: cat.color.withValues(alpha: 0.15), child: Icon(cat.icon, color: cat.color)),
                    title: Text(t('cat_${cat.key}')),
                    subtitle: Row(
                      children: [
                        Icon(trendIcon, size: 14, color: trendColor),
                        const SizedBox(width: 4),
                        Text(t(trendKey), style: TextStyle(color: trendColor, fontSize: 12)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₹${entry.latestInformalPrice.toStringAsFixed(0)}${entry.unit == 'per piece' ? '' : t('perKg')}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.volume_up, size: 20, color: kBrandGreen),
                          onPressed: () => tts.speak(
                            '${t('cat_${cat.key}')}. ${t('priceBoard')}: ${entry.latestInformalPrice.toStringAsFixed(0)} rupees. ${t(trendKey)}.',
                            appState.locale,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
