import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../scope/app_scope.dart';
import '../widgets/zivo_choice_row.dart';
import '../widgets/zivo_sheet.dart';
import 'app_typography.dart';
import 'train_tokens.dart';

/// The skin picker: dark, light, or whatever the phone is set to.
///
/// Same shape as the language sheet next door, and for the same reason — three
/// mutually exclusive options, no explanation text, tap and it's done. The one
/// thing it does *not* do is preview: the sheet sits on the app, so choosing
/// a skin re-dresses everything behind it instantly. A swatch would be a
/// smaller, worse version of the answer already filling the screen.
Future<void> showThemeSheet(BuildContext context) {
  return showZivoSheet<void>(
    context: context,
    isScrollControlled: false,
    builder: (sheetContext) => const _ThemeSheet(),
  );
}

class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).requireTheme;
    final strings = l(context);
    return Container(
      decoration: BoxDecoration(
        color: TrainColors.raised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: controller.mode,
        builder: (context, current, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.settingsTheme, style: AppText.rowTitle),
            const SizedBox(height: 18),
            for (final (key, mode, label) in themeModeOptions(context))
              ZivoChoiceRow(
                key: Key(key),
                label: label,
                selected: current == mode,
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.set(mode);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// The three options, in the order the sheet and the Settings readout both
/// use. `ThemeMode` is a Flutter enum persisted by `name`, so — like every
/// domain enum in the app — it is an **id** and carries no copy; the labels
/// live here, keyed off a [BuildContext].
List<(String, ThemeMode, String)> themeModeOptions(BuildContext context) {
  final strings = l(context);
  return [
    ('theme-system', ThemeMode.system, strings.settingsThemeSystem),
    ('theme-light', ThemeMode.light, strings.settingsThemeLight),
    ('theme-dark', ThemeMode.dark, strings.settingsThemeDark),
  ];
}

/// The label for the currently chosen skin — the Settings row's right-hand
/// value.
String themeModeLabel(BuildContext context, ThemeMode mode) => switch (mode) {
  ThemeMode.system => l(context).settingsThemeSystem,
  ThemeMode.light => l(context).settingsThemeLight,
  ThemeMode.dark => l(context).settingsThemeDark,
};
