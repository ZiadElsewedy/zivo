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
    test('copies bytes under media/{owner}/{folder}/{id}.{ext} and returns a '
        'forward-slashed relative path', () async {
      final src = makeSource('pick.PNG', [1, 2, 3, 4]);

      final stored = await store.importFile(
        sourcePath: src.path,
        kind: MediaKind.moment,
        id: 'abc', owner: 'u1',
      );

      expect(stored.relativePath, 'media/u1/moments/abc.png');
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
        id: 'user1', owner: 'u1',
      );
      final second = await store.importFile(
        sourcePath: makeSource('b.jpg', [9, 9]).path,
        kind: MediaKind.avatar,
        id: 'user1', owner: 'u1',
      );

      expect(second.file.readAsBytesSync(), [9, 9]);
      final dir = Directory('${root.path}/media/u1/avatars');
      expect(dir.listSync().whereType<File>().length, 1);
    });

    test('defaults to jpg when the source has no extension', () async {
      final stored = await store.importFile(
        sourcePath: makeSource('noext', [0]).path,
        kind: MediaKind.moment,
        id: 'x', owner: 'u1',
      );
      expect(stored.relativePath, 'media/u1/moments/x.jpg');
      expect(stored.mimeType, 'image/jpeg');
    });
  });

  group('owner scoping', () {
    test('two accounts capturing the same id keep separate files', () async {
      final a = await store.importFile(
        sourcePath: makeSource('a.jpg', [1]).path,
        kind: MediaKind.moment,
        id: 'same-id',
        owner: 'userA',
      );
      final b = await store.importFile(
        sourcePath: makeSource('b.jpg', [2]).path,
        kind: MediaKind.moment,
        id: 'same-id',
        owner: 'userB',
      );

      expect(a.relativePath, isNot(b.relativePath));
      expect(a.file.readAsBytesSync(), [1]);
      expect(b.file.readAsBytesSync(), [2],
          reason: 'one account must not overwrite the other');
    });

    test('an owner that is not a safe path segment cannot escape the store',
        () async {
      final stored = await store.importFile(
        sourcePath: makeSource('x.jpg', [3]).path,
        kind: MediaKind.moment,
        id: 'e1',
        owner: '../../etc',
      );

      expect(stored.relativePath, 'media/etc/moments/e1.jpg');
      expect(stored.file.path, startsWith(root.path));
    });

    test('an empty owner falls back to a named segment, never the media root',
        () async {
      final stored = await store.importFile(
        sourcePath: makeSource('y.jpg', [4]).path,
        kind: MediaKind.moment,
        id: 'e2',
        owner: '',
      );

      expect(stored.relativePath, 'media/_shared/moments/e2.jpg');
    });
  });

  group('LocalMediaStore.resolve', () {
    test('still resolves an unscoped ref written before owner scoping', () async {
      // Exactly what sits in `Moment.imagePath` on every pre-existing record.
      const legacy = 'media/moments/old.jpg';
      final file = await store.writeBytes(legacy, [8, 8, 8]);
      expect(file.existsSync(), isTrue);

      final resolved = await store.resolve(legacy);
      expect(resolved!.existsSync(), isTrue);
      expect(resolved.readAsBytesSync(), [8, 8, 8]);
      expect(resolved.path, endsWith('media/moments/old.jpg'),
          reason: 'no file is moved and no stored ref is rewritten');
    });

    test('maps a relative ref back to an absolute file under the root', () async {
      final stored = await store.importFile(
        sourcePath: makeSource('p.jpg', [7]).path,
        kind: MediaKind.moment,
        id: 'id7', owner: 'u1',
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
        id: 'del', owner: 'u1',
      );
      expect(stored.file.existsSync(), isTrue);
      await store.delete(stored.relativePath);
      expect(stored.file.existsSync(), isFalse);
      await store.delete(stored.relativePath); // no throw
    });
  });
}
