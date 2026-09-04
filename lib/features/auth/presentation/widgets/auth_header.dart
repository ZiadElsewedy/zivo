import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';

/// The shared header for every pushed auth surface (verify, reset, change
/// password): title in the display face, then the one italic-serif aside the
/// brand system allows per screen.
///
/// Typography here is size-specific rather than a blanket `copyWith(fontSize:)`
/// — the display face is tracked tighter as it grows and the aside is dropped
/// from its 21px hero size to 17px with *looser* leading, so the title clearly
/// outranks it instead of the two competing for the same weight (which is what
/// a 28px title over a 21px italic was doing).
class AuthHeader extends StatelessWidget {
  const AuthHeader({required this.title, this.aside, this.asideSpan, super.key})
    : assert(
        aside == null || asideSpan == null,
        'Provide either a plain aside or a rich asideSpan, not both.',
      );

  final String title;

  /// The plain-text aside line.
  final String? aside;

  /// A rich aside, for surfaces that emphasise a fragment (a masked email).
  /// Spans inherit [asideStyle] — override only the parts that differ.
  final InlineSpan? asideSpan;

  /// The base style rich asides should build on, so a caller's emphasised
  /// span stays in the same optical size as the rest of the line.
  static TextStyle get asideStyle => AppText.aside.copyWith(
    fontSize: 17,
    height: 1.42,
    color: TrainColors.ink2,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppText.greeting.copyWith(fontSize: 30, letterSpacing: -0.6),
        ),
        if (aside != null || asideSpan != null) ...[
          const SizedBox(height: 12),
          if (asideSpan != null)
            Text.rich(asideSpan!, style: asideStyle)
          else
            Text(aside!, style: asideStyle),
        ],
      ],
    );
  }
}

/// A small tracked label that names a group of fields.
///
/// Grouping is what turns a stack of identical password pills into a form you
/// can read at a glance: proximity says which fields belong together, and this
/// says what the group *is*. Deliberately quiet — it labels, it doesn't shout.
class AuthSectionLabel extends StatelessWidget {
  const AuthSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(text.toUpperCase(), style: AppText.sectionLabel),
    );
  }
}
