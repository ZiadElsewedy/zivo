import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../env/app_environment.dart';
import '../domain/drive_backup_client.dart';

/// The real [DriveBackupClient], backed by `google_sign_in` (v7 incremental
/// authorization) and the Drive v3 REST API. This is the *only* file that
/// touches Google authorization scopes or the `googleapis` Drive surface.
///
/// It requests just the `drive.file` scope, so it can only see and manage files
/// it creates; every upload goes into an app-owned "ZIVO" folder. The OAuth
/// bearer token from google_sign_in is injected into each Drive request via
/// [_BearerClient] — avoiding a dependency on any google_sign_in↔googleapis
/// bridge package whose version may lag behind google_sign_in 7.x.
///
/// NOTE: The Google side (Drive API enabled, `drive.file` on the consent
/// screen, the account added as a test user) must be configured in Cloud
/// project `zivo-63f15` before this works; the flows here need on-device
/// verification once that setup is done.
class GoogleDriveBackupClient implements DriveBackupClient {
  GoogleDriveBackupClient({GoogleSignIn? signIn, this.folderName = 'ZIVO'})
      : _signIn = signIn ?? GoogleSignIn.instance;

  final GoogleSignIn _signIn;

  /// The Drive folder app photos are uploaded into (created on first use).
  final String folderName;

  static const List<String> _scopes = <String>[drive.DriveApi.driveFileScope];

  bool _initTried = false;

  /// google_sign_in requires a one-time `initialize`. The auth layer may have
  /// already called it; a second call can throw on some platforms, so this is
  /// best-effort and guarded — a prior successful init still stands.
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

  Future<GoogleSignInAccount?> _account({required bool interactive}) async {
    await _ensureInit();
    final lightweight = await _signIn.attemptLightweightAuthentication();
    if (lightweight != null) return lightweight;
    if (!interactive || !_signIn.supportsAuthenticate()) return null;
    return _signIn.authenticate(scopeHint: _scopes);
  }

  @override
  Future<DriveAccount?> connect() async {
    final account = await _account(interactive: true);
    if (account == null) return null;
    // Prompt for the drive.file scope if it isn't already granted.
    final authz = await account.authorizationClient.authorizeScopes(_scopes);
    if (authz.accessToken.isEmpty) return null;
    return DriveAccount(id: account.id, email: account.email);
  }

  @override
  Future<bool> isConnected() async {
    final account = await _account(interactive: false);
    if (account == null) return false;
    final authz = await account.authorizationClient.authorizationForScopes(_scopes);
    return authz != null;
  }

  @override
  Future<void> disconnect() async {
    try {
      await _signIn.disconnect();
    } catch (_) {
      // Best-effort revoke.
    }
  }

  @override
  Future<String?> uploadImage({
    required File file,
    required String fileName,
    required String mimeType,
    String? replaceFileId,
  }) async {
    final account = await _account(interactive: false);
    if (account == null) return null;
    final headers = await account.authorizationClient
        .authorizationHeaders(_scopes, promptIfNecessary: false);
    if (headers == null) return null;

    final client = _BearerClient(headers);
    try {
      final api = drive.DriveApi(client);
      final media = drive.Media(file.openRead(), await file.length(), contentType: mimeType);

      if (replaceFileId != null) {
        final updated = await api.files.update(
          drive.File(),
          replaceFileId,
          uploadMedia: media,
        );
        return updated.id;
      }

      final folderId = await _ensureFolder(api);
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
    final account = await _account(interactive: false);
    if (account == null) return null;
    final headers = await account.authorizationClient
        .authorizationHeaders(_scopes, promptIfNecessary: false);
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

  /// Finds the app's Drive folder (among files this app created) or creates it.
  Future<String?> _ensureFolder(drive.DriveApi api) async {
    final escaped = folderName.replaceAll("'", r"\'");
    final existing = await api.files.list(
      q: "mimeType='application/vnd.google-apps.folder' "
          "and name='$escaped' and trashed=false",
      $fields: 'files(id)',
    );
    final files = existing.files;
    if (files != null && files.isNotEmpty) return files.first.id;

    final folder = await api.files.create(
      drive.File(name: folderName, mimeType: 'application/vnd.google-apps.folder'),
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
