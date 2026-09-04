import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// The file-picking half of a plan import, shared by the workout and diet
/// import flows. Both read the *same* document types the *same* way and map
/// the *same* backend rejections to the *same* copy — the only per-feature
/// difference is the one word in the final fallback ("split" vs "plan"), which
/// [importErrorMessage] takes as an argument. Keeping this in one place is why
/// the two importers can't drift on which files they accept or how a network
/// failure reads.

/// The largest file the import flow will upload. Cloud Functions callables
/// reject requests past ~10 MiB at the transport layer — before the server's
/// own size check ever runs — and base64 inflates bytes by ~4/3, so anything
/// bigger than this dies with a cryptic platform error instead of a clear one.
const int kMaxImportFileBytes = 7 * 1024 * 1024;

/// The file types the import flow accepts, mapped to the media type sent to
/// the backend — PDFs are read natively; photos ride as image blocks.
const Map<String, String> kImportAllowedExtensions = <String, String>{
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
};

/// A picked plan document: its bytes and the media type the backend reads it
/// as.
typedef PickedImportFile = ({Uint8List bytes, String mimeType});

/// Picks a plan document (PDF or photo) and returns its bytes plus media type
/// — null means the user backed out of the picker (not an error); a picked
/// file with no readable bytes throws, same as any other read failure, so
/// callers only need two branches.
Future<PickedImportFile?> pickImportFile() async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: List.unmodifiable(kImportAllowedExtensions.keys),
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.single;
  final mimeType = kImportAllowedExtensions[file.extension?.toLowerCase()];
  if (mimeType == null) {
    throw StateError('Unsupported file type: ${file.extension}');
  }
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    throw StateError("Couldn't read that file.");
  }
  return (bytes: bytes, mimeType: mimeType);
}

/// Maps a raw import failure to a user-facing line, recognising the common
/// backend rejections so the message points at the real cause instead of
/// blaming the document. Classifies from the error's string form deliberately
/// — the presentation layer must not import the `cloud_functions` SDK (its
/// exception types are confined to the data layer), and callable failures
/// render their code/message into `toString()` (e.g.
/// `[firebase_functions/unauthenticated]`).
///
/// The import callables deliberately never require sign-in (they read and
/// extract a document, nothing more — see each callable's own doc comment in
/// `functions/index.js`), so an `unauthenticated`/`permission-denied`
/// rejection can only be Firebase App Check declining the request, never a
/// real "you need to sign in" case — Firebase's own App Check enforcement
/// message doesn't reliably say "app check" at all, so treating those codes as
/// a separate, lower-priority branch left the real cause misreported as a
/// sign-in problem.
///
/// [manualFallback] is the one clause that differs between importers — the
/// "…or build the split/plan manually" tail on the generic message.
String importErrorMessage(Object error, {required String manualFallback}) {
  final text = error.toString().toLowerCase();
  if (text.contains('app-check') ||
      text.contains('app check') ||
      text.contains('appcheck') ||
      text.contains('unauthenticated') ||
      text.contains('permission-denied') ||
      text.contains('permission denied')) {
    return kDebugMode
        ? "The app couldn't verify itself (App Check). Register this "
              "build's debug token in the Firebase console, then try again."
        : "Couldn't verify this app install. Please try again in a moment.";
  }
  if (text.contains('not-found')) {
    // The callable itself is missing — an undeployed or renamed backend
    // function. Nothing about the picked file is wrong; blaming it sends
    // people re-scanning a perfectly good plan.
    return "The import service isn't available right now — please try "
        'again later.';
  }
  if (text.contains('deadline') ||
      text.contains('timeout') ||
      text.contains('unavailable') ||
      text.contains('network')) {
    return 'Network problem reaching the import service — check your '
        'connection and try again.';
  }
  return "Couldn't read that plan — try a clearer photo or PDF, or "
      '$manualFallback';
}
