import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/collector_profile.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/firestore_service.dart';
import '../../widgets/location_search_field.dart';
import '../../widgets/switch_role_link.dart';

/// One-time collector profile completion, shown only after login/account
/// creation succeeds and no collectors/{uid} document exists yet.
/// Recyclers never see this screen -- a phone number either matches a
/// pre-registered facility (see LoginScreen/CreateAccountScreen) or the
/// login flow shows RecyclerNotAuthorizedScreen instead.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  String _location = '';
  double? _lat;
  double? _lng;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    return Scaffold(
      appBar: AppBar(title: Text(t('createProfile'))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('yourName'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 20),
            LocationSearchField(
              label: t('yourLocation'),
              onResolved: (place) => setState(() {
                _location = place.formattedAddress;
                _lat = place.lat;
                _lng = place.lng;
              }),
            ),
            if (_lat != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Location set: $_location', style: const TextStyle(fontSize: 13, color: Colors.black54))),
                ]),
              ),
            const Spacer(),
            ElevatedButton(
              onPressed: (_saving || _location.isEmpty) ? null : () => _save(context),
              child: _saving ? const CircularProgressIndicator(color: Colors.white) : Text(t('createProfile')),
            ),
            const SizedBox(height: 8),
            const SwitchRoleLink(),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    setState(() => _saving = true);
    final appState = context.read<AppState>();
    final firestore = context.read<FirestoreService>();
    final auth = context.read<AuthService>();
    final user = appState.firebaseUser!;
    final profile = CollectorProfile(
      collectorId: user.uid,
      displayName: _nameCtrl.text.trim().isEmpty ? 'Collector' : _nameCtrl.text.trim(),
      phone: auth.phoneFromUser(user) ?? '',
      preferredLanguage: appState.locale.name,
      operatingLocation: _location,
      lat: _lat,
      lng: _lng,
    );
    await firestore.upsertCollector(profile);
    await appState.setCollector(profile);
  }
}
