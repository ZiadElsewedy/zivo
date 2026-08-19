import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/features/moments/domain/moment.dart';
import 'package:zivo/features/moments/presentation/moment_metadata.dart';

void main() {
  group('formatters', () {
    test('formatFullDate', () {
      expect(formatFullDate(DateTime(2026, 8, 20)), 'Thu, 20 August 2026');
    });

    test('formatExactTime is 12-hour with seconds', () {
      expect(formatExactTime(DateTime(2026, 1, 1, 13, 5, 9)), '1:05:09 PM');
      expect(formatExactTime(DateTime(2026, 1, 1, 0, 0, 0)), '12:00:00 AM');
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
    test('omits media-only fields when there is no media record', () {
      final moment = Moment(id: 'm', caption: 'Hi', takenAt: DateTime(2026, 1, 1, 9));
      final rows = buildMomentMetadata(moment, null);
      final labels = rows.map((r) => r.label).toList();
      expect(labels, containsAll(['Date', 'Time', 'Time zone']));
      expect(labels, isNot(contains('Captured with')));
      expect(labels, isNot(contains('File size')));
    });

    test('includes source, dimensions, size, type and backup with media', () {
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
        drive: BackupState.done,
      );
      final rows = buildMomentMetadata(moment, media);
      final map = {for (final r in rows) r.label: r.value};
      expect(map['Captured with'], 'Camera');
      expect(map['Dimensions'], '100 × 200');
      expect(map['File size'], '2 KB');
      expect(map['Type'], 'image/jpeg');
      expect(map['Backup'], contains('Google Drive'));
    });
  });
}
