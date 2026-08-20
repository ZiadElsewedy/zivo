import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../env/app_environment.dart';
import '../domain/media_backup_provider.dart';
import 'drive_connection_store.dart';

/// The real [MediaBackupProvider], backed by `google_sign_in` (v7 incremental
/// authorization) and the Drive v3 REST API. The only file that touches Google
/// authorization scopes or the `googleapis` Drive surface.
///
/// It requests just the `drive.file` scope and uploads into a per-account
/// subfolder `ROOT/{accountFolder}` under an app-owned "ZIVO" folder. The OAuth
/// bearer token is injected into each Drive request via [_BearerClient].
///
/// The Google SDK is engaged only from user-initiated calls ([connect],
/// [restoreSession], and the uploads/downloads they drive); passive callers
/// check [hasLiveSession] first, so day-to-day use never shows a sign-in sheet.
///
/// NOTE: needs the Google side configured in Cloud project `zivo-63f15` (Drive
/// API on, `drive.file` on the consent screen); the live flows need on-device
/// verification.
class GoogleDriveBackupClient implements MediaBackupProvider {
  GoogleDriveBackupClient({
    GoogleSignIn? signIn,
    DriveConnectionStore? connectionStore,
    this.rootFolderName = 'ZIVO',
  })  : _signIn = signIn ?? GoogleSignIn.instance,
        _store = connectionStore ?? DriveConnectionStore();

  final GoogleSignIn _signIn;
  final DriveConnectionStore _store;

  /// The top-level Drive folder; each ZIVO account gets a subfolder beneath it.
  final String rootFolderName;

  static const List<String> _scopes = <String>[drive.DriveApi.driveFileScope];

  bool _initTried = false;
  GoogleSignInAccount? _liveAccount;

  @override
  bool get hasLiveSession => _liveAccount != null;

  @override
  Future<bool> isDeviceConnected() => _store.isConnected();

  @override
  Future<String?> connectedEmail() => _store.email();

  Future<void> _ensureInit() async {
    if (_initTried) return;
    _initTried = true;
    try {
      await _signIn.initialize(
        serverClientId: AppEnvironment.googleServerClientId.isEmpty
            ? null
            : AppEnvironment.googleServerClientId,
      );
    } catch (_) {
      // Already initialized elsewhere (e.g. by the auth layer) — fine.
    }
  }

  @override
  Future<BackupAccount?> connect() async {
    await _ensureInit();
    if (!_signIn.supportsAuthenticate()) return null;
    final account = await _signIn.authenticate(scopeHint: _scopes);
    final authz = await account.authorizationClient.authorizeScopes(_scopes);
    if (authz.accessToken.isEmpty) return null;
    _liveAccount = account;
    await _store.setConnected(account.email);
    return BackupAccount(id: account.id, email: account.email);
  }

  @override
  Future<BackupAccount?> restoreSession() async {
    if (_liveAccount != null) {
      return BackupAccount(id: _liveAccount!.id, email: _liveAccount!.email);
    }
    if (!await _store.isConnected()) return null;
    await _ensureInit();
    final account = await _signIn.attemptLightweightAuthentication();
    if (account == null) return null;
    final authz = await account.authorizationClient.authorizationForScopes(_scopes);
    if (authz == null) return null;
    _liveAccount = account;
    return BackupAccount(id: account.id, email: account.email);
  }

  @override
  Future<void> disconnect() async {
    _liveAccount = null;
    await _store.clear();
    try {
      await _signIn.disconnect();
    } catch (_) {
      // Best-effort revoke.
    }
  }

  Future<Map<String, String>?> _headers() async {
    final account = _liveAccount;
    if (account == null) return null;
    return account.authorizationClient
        .authorizationHeaders(_scopes, promptIfNecessary: false);
  }

  @override
  Future<String?> upload({
    required File file,
    required String fileName,
    required String mimeType,
    required String accountFolder,
    String? replaceRemoteId,
  }) async {
    final headers = await _headers();
    if (headers == null) return null;

    final client = _BearerClient(headers);
    try {
      final api = drive.DriveApi(client);
      final media = drive.Media(file.openRead(), await file.length(), contentType: mimeType);

      if (replaceRemoteId != null) {
        final updated = await api.files.update(drive.File(), replaceRemoteId, uploadMedia: media);
        return updated.id;
      }

      final folderId = await _ensureAccountFolder(api, accountFolder);
      final created = await api.files.create(
        drive.File(name: fileName, parents: folderId == null ? null : <String>[folderId]),
        uploadMedia: media,
      );
      return created.id;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  @override
  Future<List<int>?> download(String fileId) async {
    final headers = await _headers();
    if (headers == null) return null;

    final client = _BearerClient(headers);
    try {
      final api = drive.DriveApi(client);
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final chunks = <int>[];
      await for (final chunk in media.stream) {
        chunks.addAll(chunk);
      }
      return chunks;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Finds/creates `rootFolderName` then its `accountFolder` child, returning
  /// the child's id so each ZIVO account's photos live in their own folder.
  Future<String?> _ensureAccountFolder(drive.DriveApi api, String accountFolder) async {
    final rootId = await _ensureFolder(api, rootFolderName, null);
    if (rootId == null) return null;
    return _ensureFolder(api, accountFolder, rootId);
  }

  Future<String?> _ensureFolder(drive.DriveApi api, String name, String? parentId) async {
    final escaped = name.replaceAll("'", r"\'");
    final parentClause = parentId == null ? '' : "and '$parentId' in parents ";
    final existing = await api.files.list(
      q: "mimeType='application/vnd.google-apps.folder' "
          "and name='$escaped' $parentClause and trashed=false",
      $fields: 'files(id)',
    );
    final files = existing.files;
    if (files != null && files.isNotEmpty) return files.first.id;

    final folder = await api.files.create(
      drive.File(
        name: name,
        mimeType: 'application/vnd.google-apps.folder',
        parents: parentId == null ? null : <String>[parentId],
      ),
      $fields: 'id',
    );
    return folder.id;
  }
}

/// A minimal [http.Client] that stamps fixed authorization headers onto every
/// request — enough for the Drive API calls made here.
class _BearerClient extends http.BaseClient {
  _BearerClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
