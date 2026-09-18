import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/pricing_service.dart';
import '../../../widgets/offline_banner.dart';
import '../safety/safety_guidance_screen.dart';

/// A few safety highlights worth surfacing on the dashboard, not just
/// buried in the Safety tab -- same content SafetyGuidanceScreen shows in
/// full, just teased here as swipeable cards.
const _bannerTips = [
  (Icons.local_fire_department, Colors.deepOrange, 'safety_cables_title'),
  (Icons.science, Colors.purple, 'safety_acid_title'),
  (Icons.battery_alert, Colors.red, 'safety_battery_title'),
  (Icons.tv, Colors.blueGrey, 'safety_crt_title'),
];

/// Four representative categories for the at-a-glance rate grid on the
/// dashboard -- the full breakdown across all categories lives in the Rate
/// List tab; this is just a teaser so the collector doesn't have to leave
/// home to see today's headline numbers.
const _previewCategories = [
  MaterialCategory.cables,
  MaterialCategory.pcb,
  MaterialCategory.batteries,
  MaterialCategory.motorsMagnets,
];

/// The collector dashboard: one tab within [CollectorShell]. Personalized
/// greeting, safety-tip carousel, a live rates teaser, and a quick link
/// into full safety guidance -- everything else (lots, rates, wallet,
/// profile) lives behind the shell's persistent bottom bar.
class CollectorHomeScreen extends StatelessWidget {
  final VoidCallback onOpenProfile;
  const CollectorHomeScreen({super.key, required this.onOpenProfile});

  String _priceLocationKey(AppState appState) {
    final c = appState.collector;
    if (c?.lat != null && c?.lng != null) return nearestServiceLocation(c!.lat!, c.lng!);
    return serviceLocations.first;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final pricing = context.read<PricingService>();
    final location = _priceLocationKey(appState);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('appName')),
        actions: [
          IconButton(icon: const Icon(Icons.settings), tooltip: t('profile'), onPressed: onOpenProfile),
          IconButton(icon: const Icon(Icons.language), onPressed: () => _showLanguagePicker(context)),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text(
                  '${t('welcome')} ${appState.collector?.displayName ?? ''}!',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(appState.collector?.operatingLocation ?? '', style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 18),
                SizedBox(
                  height: 108,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _bannerTips.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final (icon, color, titleKey) = _bannerTips[i];
                      return _BannerCard(
                        icon: icon,
                        color: color,
                        text: t(titleKey),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyGuidanceScreen())),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: Text(t('todaysRates'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                    IconButton(
                      icon: const Icon(Icons.health_and_safety, color: Colors.red),
                      tooltip: t('safety'),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyGuidanceScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 1.6,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: _previewCategories.map((cat) {
                    final entry = pricing.bestEntryFor(cat, location);
                    final rate = entry?.latestInformalPrice;
                    return _RateCard(
                      icon: cat.icon,
                      color: cat.color,
                      label: t('cat_${cat.key}'),
                      rateText: rate == null ? '--' : '₹${rate.toStringAsFixed(0)}${t('perKg')}',
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    final appState = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppLocale.values
              .map((l) => ListTile(
                    title: Text(AppStrings.localeNativeName[l]!),
                    trailing: appState.locale == l ? const Icon(Icons.check, color: kBrandGreen) : null,
                    onTap: () {
                      appState.setLocale(l);
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;
  const _BannerCard({required this.icon, required this.color, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: color))),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String rateText;
  const _RateCard({required this.icon, required this.color, required this.label, required this.rateText});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const Spacer(),
          Text(rateText, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
