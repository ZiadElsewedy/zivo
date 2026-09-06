import 'media_object.dart';

/// A remote copy that outlived the media it belonged to.
///
/// Deleting a photo deletes its bytes, its registry row and — when the account
/// holding the backup is connected — its cloud copy. When that account is NOT
/// connected, the cloud copy cannot be touched, and removing the row would
/// discard the only record of where it is: the file then sits in the user's
/// Drive forever, unreachable by anything in the app. That is a privacy
/// problem, not just untidiness, since the user explicitly deleted the photo.
///
/// So the coordinates outlive the row, and the next time that account is
/// connected the deletion is completed. A tombstone is deliberately not a
/// [MediaObject]: it has no local path, no bytes and no capture metadata, and
/// keeping it out of the media collection is what stops a deleted photo
/// reappearing in a gallery join or a sync pass.
final class MediaTombstone {
  const MediaTombstone({
    required this.mediaId,
    required this.remoteId,
    required this.remoteAccountKey,
    required this.deletedAt,
  });

  /// The id of the media that was deleted — also this record's document id, so
  /// re-deleting the same media overwrites rather than accumulating.
  final String mediaId;

  /// The provider file id still to be removed.
  final String remoteId;

  /// The account that holds it. Null on a record whose account was never
  /// recorded — the deletion can then only be attempted opportunistically.
  final String? remoteAccountKey;

  final DateTime deletedAt;
}

/// The seam between the app and media *metadata* storage (the [MediaObject]
/// registry). Bytes live in the [MediaStore]; this persists the record that
/// ties those bytes to an account and tracks backup status.
abstract interface class MediaRegistry {
  /// Creates or overwrites the registry entry for [object] (keyed by its id).
  Future<void> put(MediaObject object);

  /// Reads one entry by id for the current account, or null if none.
  Future<MediaObject?> get(String id);

  /// Finds an entry by its stored relative path, or null. Lets a caller that
  /// holds only a store reference (e.g. `Moment.imagePath`) look up the media's
  /// backup metadata without knowing the id↔path convention.
  Future<MediaObject?> getByRelativePath(String relativePath);

  /// All entries for the current account (small, personal collection). The
  /// gallery joins these onto moments for metadata display and filtering.
  Future<List<MediaObject>> getAll();

  /// The work list the "Back up now" / auto-backup flows walk: every entry for
  /// the current account whose backup to some target is still outstanding.
  ///
  /// "Backed up" is a claim about a *destination*, not a property of a photo,
  /// so [forAccountKey] — the cloud account connected right now — is part of
  /// the question. A record already uploaded to a different cloud account is
  /// still outstanding *here*, and returning it is what lets connecting a new
  /// account re-protect the whole library from the local bytes. A null
  /// [forAccountKey] (nothing connected) falls back to the destination-agnostic
  /// answer, since there is no account to compare against.
  Future<List<MediaObject>> pendingBackups({String? forAccountKey});

  /// Removes the entry for [id] (call after deleting the underlying file).
  Future<void> remove(String id);

  /// Records a remote copy that must still be deleted, because the account
  /// holding it was not connected when its media was deleted.
  Future<void> addTombstone(MediaTombstone tombstone);

  /// Every outstanding remote deletion for the current account.
  Future<List<MediaTombstone>> tombstones();

  /// Clears the tombstone for [mediaId] — the remote copy is finally gone.
  Future<void> removeTombstone(String mediaId);
}
