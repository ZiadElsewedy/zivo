import 'package:flutter/widgets.dart';

import '../../../core/media/domain/media_object.dart';
import '../../../core/media/presentation/capture_source_labels.dart';
import '../../../core/util/bidi.dart';
import '../../../l10n/l10n.dart';
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
  // Every value here is a measurement, an identifier or a machine string —
  // dimensions, a byte count, a UTC offset, a MIME type. All of them are
  // digits and neutral punctuation, so each is pinned: unpinned, "3024 × 4032"
  // and "UTC+03:00" render reversed in Arabic.
  final rows = <MetadataRow>[
    MetadataRow(
      l(context).metaDate,
      formatFullDateLong(context, moment.takenAt),
    ),
    MetadataRow(
      l(context).metaTime,
      ltrFor(context, formatClockTimeWithSeconds(context, moment.takenAt)),
    ),
    MetadataRow(
      l(context).metaTimeZone,
      ltrFor(context, formatTimeZone(moment.takenAt)),
    ),
  ];
  if (media != null && media.source != CaptureSource.unknown) {
    rows.add(
      MetadataRow(
        l(context).metaCapturedWith,
        captureSourceText(context, media.source),
      ),
    );
  }
  if (media?.width != null && media?.height != null) {
    rows.add(
      MetadataRow(
        l(context).metaDimensions,
        ltrFor(context, formatDimensions(media!.width!, media.height!)),
      ),
    );
  }
  if (media != null && media.byteSize > 0) {
    rows.add(
      MetadataRow(
        l(context).metaFileSize,
        ltrFor(context, formatBytes(media.byteSize)),
      ),
    );
  }
  if (media != null && media.mimeType.isNotEmpty) {
    rows.add(
      MetadataRow(l(context).metaType, ltrFor(context, media.mimeType)),
    );
  }
  final location = moment.location;
  if (location != null && location.trim().isNotEmpty) {
    // The user's own text, in whichever script they wrote it.
    rows.add(MetadataRow(l(context).metaLocation, isolate(location)));
  }
  if (media != null) {
    rows.add(
      MetadataRow(
        l(context).metaBackup,
        _backupLabel(context, media, photoOnDevice),
      ),
    );
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

String _backupLabel(
  BuildContext context,
  MediaObject media,
  bool photoOnDevice,
) {
  final parts = <String>[];
  if (photoOnDevice) {
    parts.add(l(context).metaOnThisDevice);
    if (media.gallery == BackupState.done) parts.add(l(context).metaInPhotos);
  }
  if (media.remoteBackup == BackupState.done) parts.add('Google Drive');
  if (parts.isEmpty) {
    return photoOnDevice
        ? l(context).metaNotBackedUp
        : l(context).metaInDriveTapToDownload;
  }
  return parts.join(' · ');
}
