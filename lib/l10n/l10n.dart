import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'app_localizations_en.dart';

export 'app_localizations.dart';

/// The one way to read a user-facing string: `l(context).dietTitle`.
///
/// It resolves the [AppLocalizations] installed by the app's delegates, and
/// falls back to English when there are none. That fallback exists for **widget
/// tests**, which pump a page under a bare `MaterialApp` with no delegates —
/// 120-odd of them, and a screen shouldn't need a localization harness to be
/// testable. In the running app `ZivoApp` always installs the delegates, so the
/// fallback is unreachable there.
///
/// Never call `AppLocalizations.of(context)` directly — it throws in exactly
/// that test case.
///
/// **Not callable from `initState`.** This reads an inherited widget, so it is
/// only legal from `build`, `didChangeDependencies`, or a callback. If you need
/// a string during initialisation, you almost certainly want a value rather
/// than copy — see `kAmrapLabel` in `workout/domain/progression.dart`, which
/// exists because a sentinel that was compared against a *translated* string
/// silently changed meaning in Arabic.
AppLocalizations l(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations) ??
    AppLocalizationsEn();
