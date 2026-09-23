import 'package:flutter/material.dart';

import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';

/// The shared two-line row body used by both the selectable rows and the usage
/// rows — leading mark column, title over subtitle, a trailing widget, and the
/// title-inset hairline unless it's [last]. Metrics match [SettingsRow] so this
/// page's rows line up with the rest of the app's settings.
class AiDetailRow extends StatelessWidget {
  const AiDetailRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.last,
    this.leading,
    this.trailing,
    this.selectedTitle = false,
  });

  final Widget? leading;
  final String title;
  final String subtitle;
  final bool last;
  final Widget? trailing;
  final bool selectedTitle;

  static const _markWidth = 24.0;
  static const _iconColumn = 17.0 + _markWidth + 14.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 17),
          child: Row(
            children: [
              if (leading != null) ...[
                SizedBox(
                  width: _markWidth,
                  child: Center(child: leading),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TrainType.ui(
                        size: 15,
                        weight: selectedTitle
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selectedTitle
                            ? TrainColors.inkPlain
                            : TrainColors.ink2,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.meta.copyWith(
                        color: TrainColors.ink3,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
        if (!last)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: leading != null ? _iconColumn : 17,
            ),
            child: Divider(
              height: 1,
              thickness: 1,
              color: TrainColors.hairline,
            ),
          ),
      ],
    );
  }
}

/// Compact token count: 1_850_000 → "1.9M", 50_600 → "50.6K", 812 → "812".
String compactTokens(int n) {
  if (n >= 1000000) return '${_trim(n / 1000000)}M';
  if (n >= 1000) return '${_trim(n / 1000)}K';
  return n.toString();
}

String _trim(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// A small USD figure: 0 → "\$0", under a cent → "<\$0.01", else two decimals
/// (three under a dollar's tenth, where two would round most requests to 0).
String formatUsd(double c) {
  if (c <= 0) return '\$0';
  if (c < 0.001) return '<\$0.001';
  if (c < 0.1) return '\$${c.toStringAsFixed(3)}';
  return '\$${c.toStringAsFixed(2)}';
}
