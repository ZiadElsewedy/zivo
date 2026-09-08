import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **The one rule ADR-011 adds that the compiler cannot enforce.**
///
/// `TrainColors` resolves through the active skin, so a token has to be read
/// inside `build`. A `static` field is evaluated once, the first time it is
/// touched, and then holds whichever skin the app happened to draw first —
/// which is invisible in dark-only development, invisible in a test that
/// renders straight into light, and shows up in production as one screen of
/// near-white type on a white page.
///
/// `flutter analyze` catches this only where a `const` breaks. Everything
/// else — `static final _timecode = TrainType.mono(color: TrainColors.ink3)`
/// — compiles cleanly and is silently wrong, so it is caught here instead.
void main() {
  /// Anything whose value depends on the active skin.
  final tokens = RegExp(r'\b(TrainColors|TrainType|AppText)\.');

  /// A `static final`/`static const` declaration with an initializer, up to
  /// the `;` that ends it. Getters (`static Color get x => …`) are the fix and
  /// are not matched: `get` cannot appear before the `=`.
  final staticField = RegExp(
    r'static\s+(?:final|const)\s+[^;=]*=[^;]*;',
    dotAll: true,
  );

  test('no static field caches a skin-dependent token', () {
    final offenders = <String>[];

    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in staticField.allMatches(source)) {
        final decl = match.group(0)!;
        if (!tokens.hasMatch(decl)) continue;
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add(
          '${file.path}:$line\n    ${decl.replaceAll(RegExp(r'\s+'), ' ')}',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These fields are evaluated once and will hold whichever skin the '
          'app first drew (ADR-011). Make each one a getter — '
          '`static TextStyle get x => …` — so it resolves per build:\n'
          '  ${offenders.join('\n  ')}',
    );
  });
}
