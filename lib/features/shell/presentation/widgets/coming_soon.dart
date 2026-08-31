import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/l10n.dart';

/// Placeholder for tabs not yet built, kept intentional rather than blank.
class ComingSoon extends StatelessWidget {
  const ComingSoon(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppText.cardTitle),
          const SizedBox(height: 8),
          Text(l(context).comingNext, style: AppText.aside),
        ],
      ),
    );
  }
}
