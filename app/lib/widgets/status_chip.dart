import 'package:flutter/material.dart';

import '../core/constants.dart';

Color statusColor(LotStatus status) {
  switch (status) {
    case LotStatus.created:
      return Colors.grey;
    case LotStatus.matched:
      return Colors.blue;
    case LotStatus.inTransit:
      return Colors.indigo;
    case LotStatus.handedOver:
      return Colors.orange;
    case LotStatus.confirmed:
      return Colors.teal;
    case LotStatus.paid:
      return Colors.green;
    case LotStatus.completed:
      return Colors.green.shade800;
    case LotStatus.disputed:
      return Colors.red;
  }
}

class StatusChip extends StatelessWidget {
  final LotStatus status;
  final String label;
  const StatusChip({super.key, required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: c,
      visualDensity: VisualDensity.compact,
    );
  }
}
