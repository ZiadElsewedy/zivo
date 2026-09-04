import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/features/moments/domain/moment.dart';
import 'package:zivo/core/util/date_format.dart';
import 'package:zivo/features/moments/presentation/moment_metadata.dart';
import 'package:zivo/l10n/l10n.dart';

/// Runs [body] under a localized app so the (now locale-aware) date and time
/// formatters have a [Localizations] ancestor to resolve against.
Future<T> _inApp<T>(WidgetTester tester, Locale locale, T Function(BuildContext) body) async {
  late T out;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          out = body(context);
          return const SizedBox();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return out;
}

void main() {
  group('formatters', () {
    testWidgets('the date reads long and day-first', (tester) async {
      expect(
        await _inApp(tester, const Locale('en'),
            (c) => formatFullDateLong(c, DateTime(2026, 8, 20))),
        'Thu, 20 August 2026',
      );
    });

    testWidgets('the exact time is 12-hour with seconds', (tester) async {
      expect(
        await _inApp(tester, const Locale('en'),
            (c) => formatClockTimeWithSeconds(c, DateTime(2026, 1, 1, 13, 5, 9))),
        '1:05:09 PM',
      );
      expect(
        await _inApp(tester, const Locale('en'),
            (c) => formatClockTimeWithSeconds(c, DateTime(2026, 1, 1, 0, 0, 0))),
        '12:00:00 AM',
      );
    });

    testWidgets('an Arabic reader gets an Arabic month and day period', (tester) async {
      final date = await _inApp(tester, const Locale('ar'),
          (c) => formatFullDateLong(c, DateTime(2026, 8, 20)));
      expect(date, isNot(contains('August')));
      expect(date, contains('أغسطس'));

      final time = await _inApp(tester, const Locale('ar'),
          (c) => formatClockTimeWithSeconds(c, DateTime(2026, 1, 1, 13, 5, 9)));
      expect(time, isNot(contains('PM')));
    });

    test('formatBytes', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
    });

    test('formatDimensions includes megapixels', () {
      expect(formatDimensions(3024, 4032), '3024 × 4032 · 12.2 MP');
    });
  });

  group('buildMomentMetadata', () {
    testWidgets('omits media-only fields when there is no media record', (tester) async {
      final moment = Moment(id: 'm', caption: 'Hi', takenAt: DateTime(2026, 1, 1, 9));
      final rows = await _inApp(tester, const Locale('en'),
          (c) => buildMomentMetadata(c, moment, null));
      final labels = rows.map((r) => r.label).toList();
      expect(labels, containsAll(['Date', 'Time', 'Time zone']));
      expect(labels, isNot(contains('Captured with')));
      expect(labels, isNot(contains('File size')));
    });

    testWidgets('includes source, dimensions, size, type and backup with media', (tester) async {
      final moment = Moment(id: 'm', caption: 'Hi', takenAt: DateTime(2026, 1, 1, 9));
      final media = MediaObject(
        id: 'm',
        ownerUid: 'u',
        kind: MediaKind.moment,
        relativePath: 'media/moments/m.jpg',
        mimeType: 'image/jpeg',
        byteSize: 2048,
        contentHash: 'h',
        capturedAt: DateTime(2026, 1, 1, 9),
        source: CaptureSource.camera,
        width: 100,
        height: 200,
        remoteBackup: BackupState.done,
      );
      final rows = await _inApp(tester, const Locale('en'),
          (c) => buildMomentMetadata(c, moment, media));
      final map = {for (final r in rows) r.label: r.value};
      expect(map['Captured with'], 'Camera');
      expect(map['Dimensions'], '100 × 200');
      expect(map['File size'], '2 KB');
      expect(map['Type'], 'image/jpeg');
      expect(map['Backup'], contains('Google Drive'));
    });
  });
}
