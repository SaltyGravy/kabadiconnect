import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/auth_service.dart';
import '../../widgets/switch_role_link.dart';

/// Shown when a verified phone number doesn't match any pre-registered
/// recycler facility. Recyclers are admin/seed-provisioned (see
/// docs/dataset_documentation.md) precisely so the "authorized recycler"
/// label keeps meaning something -- this is not a signup form.
class RecyclerNotAuthorizedScreen extends StatelessWidget {
  const RecyclerNotAuthorizedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'This phone number is not registered as an authorized recycler facility.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Recycler accounts are set up by the platform team using CPCB/SPCB authorization records. '
                'If you believe this is an error, contact the platform admin to register your facility\'s contact number.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => context.read<AuthService>().signOut(),
                child: const Text('Try a different number'),
              ),
              const SizedBox(height: 4),
              const SwitchRoleLink(),
            ],
          ),
        ),
      ),
    );
  }
}
