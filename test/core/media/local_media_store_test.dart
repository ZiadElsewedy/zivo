import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/domain/media_kind.dart';

void main() {
  late Directory root;
  late Directory sourceDir;
  late LocalMediaStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zivo_store_root');
    sourceDir = Directory.systemTemp.createTempSync('zivo_store_src');
    store = LocalMediaStore(rootOverride: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
  });

  File makeSource(String name, List<int> bytes) {
    final f = File('${sourceDir.path}/$name')..writeAsBytesSync(bytes);
    return f;
  }

  group('LocalMediaStore.importFile', () {
    test('copies bytes under media/{folder}/{id}.{ext} and returns a '
        'forward-slashed relative path', () async {
      final src = makeSource('pick.PNG', [1, 2, 3, 4]);

      final stored = await store.importFile(
        sourcePath: src.path,
        kind: MediaKind.moment,
        id: 'abc',
      );

      expect(stored.relativePath, 'media/moments/abc.png');
      expect(stored.byteSize, 4);
      expect(stored.mimeType, 'image/png');
      expect(stored.contentHash, isNotEmpty);
      expect(stored.file.existsSync(), isTrue);
      expect(stored.file.readAsBytesSync(), [1, 2, 3, 4]);
    });

    test('re-import with the same id overwrites in place (no orphan)', () async {
      await store.importFile(
        sourcePath: makeSource('a.jpg', [1]).path,
        kind: MediaKind.avatar,
        id: 'user1',
      );
      final second = await store.importFile(
        sourcePath: makeSource('b.jpg', [9, 9]).path,
        kind: MediaKind.avatar,
        id: 'user1',
      );

      expect(second.file.readAsBytesSync(), [9, 9]);
      final dir = Directory('${root.path}/media/avatars');
      expect(dir.listSync().whereType<File>().length, 1);
    });

    test('defaults to jpg when the source has no extension', () async {
      final stored = await store.importFile(
        sourcePath: makeSource('noext', [0]).path,
        kind: MediaKind.moment,
        id: 'x',
      );
      expect(stored.relativePath, 'media/moments/x.jpg');
      expect(stored.mimeType, 'image/jpeg');
    });
  });

  group('LocalMediaStore.resolve', () {
    test('maps a relative ref back to an absolute file under the root', () async {
      final stored = await store.importFile(
        sourcePath: makeSource('p.jpg', [7]).path,
        kind: MediaKind.moment,
        id: 'id7',
      );
      final resolved = await store.resolve(stored.relativePath);
      expect(resolved, isNotNull);
      expect(resolved!.existsSync(), isTrue);
      expect(resolved.readAsBytesSync(), [7]);
    });

    test('returns a legacy absolute path unchanged', () async {
      final legacy = makeSource('legacy.jpg', [5]);
      final resolved = await store.resolve(legacy.path);
      expect(resolved!.path, legacy.path);
    });

    test('returns null for null/empty refs', () async {
      expect(await store.resolve(null), isNull);
      expect(await store.resolve(''), isNull);
    });
  });

  group('LocalMediaStore.delete', () {
    test('removes a stored file and is a no-op when already gone', () async {
      final stored = await store.importFile(
        sourcePath: makeSource('d.jpg', [1]).path,
        kind: MediaKind.moment,
        id: 'del',
      );
      expect(stored.file.existsSync(), isTrue);
      await store.delete(stored.relativePath);
      expect(stored.file.existsSync(), isFalse);
      await store.delete(stored.relativePath); // no throw
    });
  });
}
