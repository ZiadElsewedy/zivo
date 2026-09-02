import 'dart:typed_data';

/// The material a workout-split extraction reads.
///
/// Four capture routes reach the extractor — a PDF, a photo, a dictated
/// description, a typed one — and they reduce to exactly **two** kinds of
/// material: bytes with a media type, or text. Modelling it as a sealed type
/// rather than three nullable parameters means "a file and some text at once"
/// and "neither" are not expressible at the call site, so nothing downstream
/// has to decide which one wins.
///
/// This mirrors diet's `DietImportInput` exactly — one shape for both
/// importers, because both are "read the user's own plan, however it arrived".
sealed class WorkoutImportInput {
  const WorkoutImportInput();
}

/// A PDF or a photo of a plan — the user's own document, read as data.
final class WorkoutImportDocument extends WorkoutImportInput {
  const WorkoutImportDocument({required this.bytes, required this.mimeType});

  final Uint8List bytes;

  /// `application/pdf`, or an image type for a photo/screenshot.
  final String mimeType;
}

/// The user's own words: a voice note that has already been transcribed, or
/// text they typed. [dictated] records which, so the saved split can say where
/// it came from — the two read differently (a transcript rambles and
/// self-corrects) and the extractor is told so.
final class WorkoutImportDescription extends WorkoutImportInput {
  const WorkoutImportDescription({required this.text, required this.dictated});

  final String text;
  final bool dictated;
}
