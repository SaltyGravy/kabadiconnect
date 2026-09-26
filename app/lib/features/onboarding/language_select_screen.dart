import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/l10n/app_strings.dart';

class LanguageSelectScreen extends StatelessWidget {
  const LanguageSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return Scaffold(
      backgroundColor: kBrandGreen,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('assets/branding/logo_full.png', width: 160, height: 160),
              ),
              const SizedBox(height: 40),
              const Text('भाषा / Language', style: TextStyle(color: Colors.white, fontSize: 20)),
              const SizedBox(height: 20),
              ...AppLocale.values.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kBrandGreenDark),
                        onPressed: () => appState.setLocale(l),
                        child: Text(AppStrings.localeNativeName[l]!, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
