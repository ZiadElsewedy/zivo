import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../scope/app_scope.dart';
import '../theme/app_typography.dart';
import '../theme/train_tokens.dart';
import '../widgets/zivo_choice_row.dart';
import '../widgets/zivo_sheet.dart';

/// The language picker: Arabic, English, or whatever the phone is set to.
///
/// Three taps' worth of screen, and deliberately no explanation text — the
/// options are written **in their own language**, which is the only label that
/// works for someone who can't read the current one. That is also why it can't
/// be a row that cycles: a user who lands in a language they don't read has to
/// be able to see their own listed and tap it.
Future<void> showLanguageSheet(BuildContext context) {
  return showZivoSheet<void>(
    context: context,
    isScrollControlled: false,
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
      decoration: BoxDecoration(
        color: TrainColors.raised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
              (
                'language-en',
                const Locale('en'),
                strings.settingsLanguageEnglish,
              ),
              (
                'language-ar',
                const Locale('ar'),
                strings.settingsLanguageArabic,
              ),
            ])
              ZivoChoiceRow(
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
