import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/data/in_memory_media_preferences_repository.dart';
import 'package:zivo/core/media/data/in_memory_media_registry.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/domain/media_backup_provider.dart';
import 'package:zivo/core/media/media_service.dart';
import 'package:zivo/core/widgets/train_surfaces.dart';
import 'package:zivo/features/hub/presentation/hub_page.dart';

import '../support/test_app.dart';

/// The Hub's Connected band must follow the real Drive connection, not a copy
/// of it taken the first time the Hub was built.
///
/// The Hub is a tab inside the shell's `IndexedStack`: it is built once and
/// stays mounted, so it is *not* rebuilt when the user comes back from
/// Storage & Sync, nor when they switch tabs. With a one-shot `FutureBuilder`
/// that meant connecting Drive left this row reading "NOT CONNECTED" until the
/// app was restarted — the exact bug this covers. The pumps below deliberately
/// never rebuild `HubPage`; only the service changes.
class _FakeBackup implements MediaBackupProvider {
  _FakeBackup();

  bool deviceConnected = false;
  String? ownerId;

  @override
  Future<BackupAccount?> connect({required String ownerAccountId}) async {
    deviceConnected = true;
    ownerId = ownerAccountId;
    return const BackupAccount(id: 'acc-1', email: 'you@gmail.com');
  }

  @override
  Future<void> disconnect() async {
    deviceConnected = false;
    ownerId = null;
  }

  @override
  bool get hasLiveSession => deviceConnected;

  @override
  String? get liveAccountKey => deviceConnected ? 'acc-1' : null;

  @override
  Future<String?> connectedAccountKey() async =>
      deviceConnected ? 'acc-1' : null;

  @override
  Future<bool> isDeviceConnected() async => deviceConnected;

  @override
  Future<String?> connectedEmail() async =>
      deviceConnected ? 'you@gmail.com' : null;

  @override
  Future<String?> connectedOwnerId() async => ownerId;

  @override
  Future<BackupAccount?> restoreSession() async => deviceConnected
      ? const BackupAccount(id: 'acc-1', email: 'you@gmail.com')
      : null;

  @override
  Future<String?> upload({
    required File file,
    required String fileName,
    required String mimeType,
    required String accountFolder,
    String? replaceRemoteId,
    String? replaceInAccountKey,
  }) async => 'drive-1';

  @override
  Future<RemoteFetch> download(
    String remoteId, {
    required String expectedAccountKey,
  }) async => const RemoteFetch.unavailable();

  @override
  Future<bool> deleteRemote(
    String remoteId, {
    required String expectedAccountKey,
  }) async => true;
}

/// The value printed in the Drive row specifically — the Spotify row above it
/// says "NOT CONNECTED" too, so an unscoped `find.text` matches both.
Finder _driveValue(String text) => find.descendant(
  of: find.ancestor(
    of: find.text('Google Drive'),
    matching: find.byType(TrainListRow),
  ),
  matching: find.text(text),
);

void main() {
  testWidgets('the Hub Drive row follows connect and disconnect live', (
    tester,
  ) async {
    // Tall enough that the whole Hub — grid and the Connected band under it —
    // is on screen, so the assertions below are about the row's state and not
    // about scrolling it into view.
    tester.view.physicalSize = const Size(1179, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backup = _FakeBackup();
    final media = MediaService(
      store: LocalMediaStore(
        rootOverride: Directory.systemTemp.createTempSync('zivo_hub_drive'),
      ),
      registry: InMemoryMediaRegistry(),
      preferences: InMemoryMediaPreferencesRepository(),
      backup: backup,
      currentAccountId: () => 'uid-1',
    );

    await tester.pumpWidget(wrapWithScope(const HubPage(), media: media));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Google Drive'), findsOneWidget);
    expect(_driveValue('NOT CONNECTED'), findsOneWidget);

    // Connect the way Storage & Sync does — the Hub is NOT rebuilt.
    await media.connectBackup();
    await tester.pump();

    expect(
      _driveValue('BACKING UP'),
      findsOneWidget,
      reason: 'the Hub must not keep showing a connection state it read once',
    );
    expect(_driveValue('NOT CONNECTED'), findsNothing);

    await media.disconnectBackup();
    await tester.pump();

    expect(_driveValue('NOT CONNECTED'), findsOneWidget);
  });
}
