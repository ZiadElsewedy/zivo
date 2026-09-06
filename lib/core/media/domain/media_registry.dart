import 'media_object.dart';

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
}
