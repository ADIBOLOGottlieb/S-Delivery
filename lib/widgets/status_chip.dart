import 'package:flutter/material.dart';

import '../models/delivery.dart';
import '../utils/colors.dart';

/// Pastille de statut : point de couleur + libellé, sur fond gris clair.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const StatusChip({super.key, required this.label, required this.color});

  factory StatusChip.delivery(Delivery d) => StatusChip(
        label: d.statusLabel,
        color: switch (d.status) {
          DeliveryStatus.assigned => AppColors.info,
          DeliveryStatus.pickedUp => AppColors.info,
          DeliveryStatus.delivered => AppColors.success,
          DeliveryStatus.cancelled => AppColors.error,
          _ => AppColors.textSecondary,
        },
      );

  factory StatusChip.payment(Delivery d) => StatusChip(
        label: d.paymentStatusLabel,
        color: switch (d.paymentStatus) {
          PaymentStatus.submitted => AppColors.warning,
          PaymentStatus.verified => AppColors.success,
          PaymentStatus.rejected => AppColors.error,
          _ => AppColors.textSecondary,
        },
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ],
      ),
    );
  }
}
