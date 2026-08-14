/// A lightweight memory — a log entity. Caption + time, with an optional
/// photo and optional place.
class Moment {
  const Moment({
    required this.id,
    required this.caption,
    required this.takenAt,
    this.imagePath,
    this.location,
  });

  final String id;
  final String caption;
  final DateTime takenAt;
  final String? imagePath;
  final String? location;
}
