import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/data/in_memory_media_preferences_repository.dart';
import 'package:zivo/core/media/data/in_memory_media_registry.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/domain/media_backup_provider.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/core/media/media_service.dart';
import 'package:zivo/core/media/presentation/media_image.dart';
import 'package:zivo/core/media/presentation/storage_sync_page.dart';

import 'package:zivo/core/scope/app_scope.dart';

import '../../support/test_app.dart';

/// Resolving a reference does real disk work, which fake-async `pump` does not
/// advance — and both surfaces carry ambient motion (the tile's resolve pulse,
/// the page's aura blobs), so `pumpAndSettle` would never return either. Give
/// the async work real wall time, then paint.
Future<void> _settleEnough(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// A provider connected to exactly one account, holding nothing. Enough to make
/// a stored reference resolve as "backed up somewhere this device isn't".
class _ConnectedTo implements MediaBackupProvider {
  _ConnectedTo(this.accountKey);

  final String accountKey;

  @override
  bool get hasLiveSession => true;
  @override
  String? get liveAccountKey => accountKey;
  @override
  Future<String?> connectedAccountKey() async => accountKey;
  @override
  Future<bool> isDeviceConnected() async => true;
  @override
  Future<String?> connectedEmail() async => '$accountKey@gmail.com';
  @override
  Future<String?> connectedOwnerId() async => 'u1';
  @override
  Future<BackupAccount?> connect({required String ownerAccountId}) async =>
      BackupAccount(id: accountKey, email: '$accountKey@gmail.com');
  @override
  Future<BackupAccount?> restoreSession() async =>
      BackupAccount(id: accountKey, email: '$accountKey@gmail.com');
  @override
  Future<void> disconnect() async {}
  @override
  Future<String?> upload({
    required File file,
    required String fileName,
    required String mimeType,
    required String accountFolder,
    String? replaceRemoteId,
    String? replaceInAccountKey,
  }) async =>
      null;
  @override
  Future<RemoteFetch> download(String remoteId,
          {required String expectedAccountKey}) async =>
      const RemoteFetch.unavailable();
  @override
  Future<bool> deleteRemote(String remoteId,
          {required String expectedAccountKey}) async =>
      false;
}

void main() {
  late Directory root;
  late InMemoryMediaRegistry registry;
  late MediaService service;

  const ref = 'media/moments/m1.jpg';

  setUp(() async {
    root = Directory.systemTemp.createTempSync('zivo_ui_media');
    registry = InMemoryMediaRegistry();
    service = MediaService(
      store: LocalMediaStore(rootOverride: root),
      registry: registry,
      preferences: InMemoryMediaPreferencesRepository(),
      backup: _ConnectedTo('drive-2'),
      currentAccountId: () => 'u1',
    );
    // One photo, backed up to an account this device is not on, with no local
    // copy — the state an account switch leaves behind.
    await registry.put(MediaObject(
      id: 'm1',
      ownerUid: 'u1',
      kind: MediaKind.moment,
      relativePath: ref,
      mimeType: 'image/jpeg',
      byteSize: 3,
      contentHash: 'h',
      capturedAt: DateTime(2026, 1, 1),
      remoteBackup: BackupState.done,
      remoteId: 'file-1',
      remoteAccountKey: 'drive-1',
    ));
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  testWidgets('a photo in another Drive account renders as such, and schedules '
      'no retry that could never succeed', (tester) async {
    await tester.pumpWidget(
      wrapWithScope(
        const SizedBox(
          width: 120,
          height: 120,
          child: _Host(),
        ),
        media: service,
        auth: signedInAuth(),
      ),
    );
    await _settleEnough(tester);

    expect(find.text('In another Drive account'), findsOneWidget);
    expect(find.text('Captured on another device'), findsNothing);

    // No pending timer: a self-retry here would mean the UI is waiting for
    // bytes that cannot arrive until the user acts. (`cloudOnly` schedules
    // one; this state must not.)
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'the tile must be at rest, not animating a fetch');
  });

  testWidgets('Storage & Sync names the photos left in the other account',
      (tester) async {
    await tester.pumpWidget(
      wrapWithScope(
        const StorageSyncPage(),
        media: service,
        auth: signedInAuth(),
      ),
    );
    await _settleEnough(tester);

    expect(find.text('1 photo in another Google account'), findsOneWidget);
    expect(
      find.textContaining('reconnect that account'),
      findsOneWidget,
      reason: 'the notice must name the route back for photos not on this device',
    );
    // And "Back up now" — the remedy for the ones that ARE still local — is
    // right there.
    expect(find.text('Back up now'), findsOneWidget);
  });
}

/// Hosts the tile with the service from the surrounding scope.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => MediaImage(
        service: AppScope.of(context).requireMedia,
        ref: 'media/moments/m1.jpg',
      );
}
