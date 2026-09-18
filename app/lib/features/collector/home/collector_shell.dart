import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../account/account_screen.dart';
import '../ledger/earnings_ledger_screen.dart';
import '../lot/create_lot_screen.dart';
import '../lot/my_lots_screen.dart';
import '../price_board/price_board_screen.dart';
import 'collector_home_screen.dart';

/// Persistent bottom-tab shell for the whole collector experience: Home /
/// My Lots / Rate List / [camera -> New Lot] / Wallet / Profile, matching
/// the five-icon bottom bar with a centre-docked camera action. The camera
/// slot is an action (push CreateLotScreen), not a tab -- it doesn't hold
/// its own persisted state the way the other four destinations do.
class CollectorShell extends StatefulWidget {
  const CollectorShell({super.key});

  @override
  State<CollectorShell> createState() => _CollectorShellState();
}

class _CollectorShellState extends State<CollectorShell> {
  int _index = 0; // 0=Home, 1=My Lots, 2=Rate List, 3=Wallet, 4=Profile

  void _goHome() => setState(() => _index = 0);
  void _goTo(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);

    final pages = [
      CollectorHomeScreen(onOpenProfile: () => _goTo(4)),
      MyLotsScreen(onHome: _goHome),
      PriceBoardScreen(onHome: _goHome),
      EarningsLedgerScreen(onHome: _goHome),
      AccountScreen(onHome: _goHome),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: FloatingActionButton(
        tooltip: t('newLot'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateLotScreen())),
        child: const Icon(Icons.camera_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BarItem(icon: Icons.inventory, label: t('myLots'), selected: _index == 1, onTap: () => _goTo(1)),
            _BarItem(icon: Icons.show_chart, label: t('priceBoard'), selected: _index == 2, onTap: () => _goTo(2)),
            const SizedBox(width: 48), // room for the notch/FAB
            _BarItem(icon: Icons.account_balance_wallet, label: t('ledger'), selected: _index == 3, onTap: () => _goTo(3)),
            _BarItem(icon: Icons.account_circle, label: t('profile'), selected: _index == 4, onTap: () => _goTo(4)),
          ],
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BarItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? kBrandGreen : Colors.grey.shade600;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
