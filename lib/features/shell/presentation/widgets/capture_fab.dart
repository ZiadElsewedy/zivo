import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The global Quick Capture entry — one Ember action, reachable from Today.
class CaptureFab extends StatelessWidget {
  const CaptureFab({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.ember,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.ember.withValues(alpha: 0.55),
            blurRadius: 32,
            spreadRadius: -8,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}
