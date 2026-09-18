import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/l10n/app_strings.dart';

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    return Scaffold(
      appBar: AppBar(title: Text(t('appName'))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text(t('whoAreYou'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            _RoleCard(
              icon: Icons.two_wheeler,
              color: kBrandGreen,
              title: t('roleCollector'),
              subtitle: t('roleCollectorSub'),
              onTap: () => context.read<AppState>().setRole(UserRole.collector),
            ),
            const SizedBox(height: 16),
            _RoleCard(
              icon: Icons.factory,
              color: kAmber,
              title: t('roleRecycler'),
              subtitle: t('roleRecyclerSub'),
              onTap: () => context.read<AppState>().setRole(UserRole.recycler),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(radius: 32, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 32)),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 15, color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
