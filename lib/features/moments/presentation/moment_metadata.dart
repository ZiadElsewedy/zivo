import 'package:flutter/widgets.dart';

import '../../../core/media/domain/media_object.dart';
import '../domain/moment.dart';
import '../../../core/util/date_format.dart';

/// One labelled metadata field shown in the photo detail panel.
class MetadataRow {
  const MetadataRow(this.label, this.value);
  final String label;
  final String value;
}

/// Builds the ordered metadata for a moment + its (optional) media record —
/// what the gallery's detail panel shows: when it was taken, the exact time and
/// time zone, how it was captured, dimensions, size, type, location, and backup
/// status. Fields with no data are omitted rather than shown blank.
///
/// [photoOnDevice] reflects whether the BYTES are actually on this device —
/// distinct from the metadata existing at all. On a second device a moment can
/// be fully present as data while its image lives only in Drive; claiming
/// "On this device" then would be a lie, so callers that know better pass
/// false (the panel then shows exactly which copy IS authoritative).
List<MetadataRow> buildMomentMetadata(
  BuildContext context,
  Moment moment,
  MediaObject? media, {
  bool photoOnDevice = true,
}) {
  final rows = <MetadataRow>[
    MetadataRow('Date', formatFullDateLong(context, moment.takenAt)),
    MetadataRow('Time', formatClockTimeWithSeconds(context, moment.takenAt)),
    MetadataRow('Time zone', formatTimeZone(moment.takenAt)),
  ];
  if (media != null && media.source != CaptureSource.unknown) {
    rows.add(MetadataRow('Captured with', media.source.label));
  }
  if (media?.width != null && media?.height != null) {
    rows.add(MetadataRow('Dimensions', formatDimensions(media!.width!, media.height!)));
  }
  if (media != null && media.byteSize > 0) {
    rows.add(MetadataRow('File size', formatBytes(media.byteSize)));
  }
  if (media != null && media.mimeType.isNotEmpty) {
    rows.add(MetadataRow('Type', media.mimeType));
  }
  final location = moment.location;
  if (location != null && location.trim().isNotEmpty) {
    rows.add(MetadataRow('Location', location));
  }
  if (media != null) {
    rows.add(MetadataRow('Backup', _backupLabel(media, photoOnDevice)));
  }
  return rows;
}

/// e.g. "UTC+03:00 (EEST)" — from the DateTime's local offset and zone name.
String formatTimeZone(DateTime t) {
  final offset = t.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final hh = abs.inHours.toString().padLeft(2, '0');
  final mm = (abs.inMinutes % 60).toString().padLeft(2, '0');
  final name = t.timeZoneName.trim();
  final base = 'UTC$sign$hh:$mm';
  return name.isEmpty || name == base ? base : '$base ($name)';
}

/// e.g. "3024 × 4032 · 12.2 MP".
String formatDimensions(int width, int height) {
  final mp = (width * height) / 1000000;
  final mpText = mp >= 1 ? ' · ${mp.toStringAsFixed(1)} MP' : '';
  return '$width × $height$mpText';
}

/// e.g. "2.3 MB", "812 KB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

String _backupLabel(MediaObject media, bool photoOnDevice) {
  final parts = <String>[];
  if (photoOnDevice) {
    parts.add('On this device');
    if (media.gallery == BackupState.done) parts.add('Photos');
  }
  if (media.remoteBackup == BackupState.done) parts.add('Google Drive');
  if (parts.isEmpty) {
    return photoOnDevice ? 'Not backed up yet' : 'In Google Drive — tap to download';
  }
  return parts.join(' · ');
}
