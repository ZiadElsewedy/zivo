/// The category of an app-managed media file. Determines which on-disk folder
/// a file lives in (`media/{folder}/...`) and lets backup targets and the UI
/// treat, say, a profile avatar differently from a moment photo.
///
/// This is deliberately a small, closed set — every place that stores media in
/// ZIVO routes through the media module, so adding a new media-bearing feature
/// means adding a case here (and nothing else in the storage layer).
enum MediaKind {
  /// A photo attached to a [Moment].
  moment('moments', 'Moments'),

  /// A user's profile picture (avatar).
  avatar('avatars', 'Profile');

  const MediaKind(this.folder, this.remoteFolder);

  /// The on-disk (and remote) folder segment for this kind. Stable — persisted
  /// inside relative paths, so renaming a value's folder would strand existing
  /// files. Add new kinds; don't repurpose folders.
  final String folder;

  /// The folder this kind is filed under in the cloud backup
  /// (`ZIVO/{account}/{remoteFolder}/`). A display name, not an identity:
  /// files are addressed by their remote id, so renaming it only changes
  /// where *new* uploads land.
  final String remoteFolder;

  static MediaKind fromName(String name) =>
      MediaKind.values.firstWhere((k) => k.name == name, orElse: () => MediaKind.moment);
}
