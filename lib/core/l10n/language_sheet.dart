import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../scope/app_scope.dart';
import '../theme/app_typography.dart';
import '../theme/train_tokens.dart';

/// The language picker: Arabic, English, or whatever the phone is set to.
///
/// Three taps' worth of screen, and deliberately no explanation text — the
/// options are written **in their own language**, which is the only label that
/// works for someone who can't read the current one. That is also why it can't
/// be a row that cycles: a user who lands in a language they don't read has to
/// be able to see their own listed and tap it.
Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).requireLocale;
    final strings = l(context);
    return Container(
      decoration: const BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      child: ValueListenableBuilder<Locale?>(
        valueListenable: controller.locale,
        builder: (context, current, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.settingsLanguage, style: AppText.rowTitle),
            const SizedBox(height: 18),
            for (final (key, locale, label) in <(String, Locale?, String)>[
              ('language-system', null, strings.settingsLanguageSystem),
              ('language-en', const Locale('en'), strings.settingsLanguageEnglish),
              ('language-ar', const Locale('ar'), strings.settingsLanguageArabic),
            ])
              _Option(
                key: Key(key),
                label: label,
                selected: current?.languageCode == locale?.languageCode,
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.set(locale);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.rowTitle.copyWith(
                  color: selected ? TrainColors.inkPlain : TrainColors.ink2,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 19,
                color: TrainColors.violetGlyph,
              ),
          ],
        ),
      ),
    );
  }
}
