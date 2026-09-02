import 'dart:async';

import 'package:flutter/foundation.dart';

/// Local-first persistence: hand the durable write to this, and return.
///
/// ## Why this exists
///
/// Every repository in this app is Firestore-backed, and a Firestore write
/// resolves its `Future` when the **server** acknowledges it — not when the
/// local cache has it. The SDK has already applied the write locally and
/// already told every `snapshots()` listener about it (latency compensation)
/// long before that future completes; on a slow connection the gap is
/// seconds, and offline it is *until the network comes back*. So a capture
/// screen that did
///
/// ```dart
/// await repository.add(entity);   // ← seconds of nothing
/// Navigator.pop(context);
/// ```
///
/// froze on Save for the duration of a round-trip, to wait for news the UI
/// did not need: the list behind the screen had the new row from the first
/// millisecond. (Worse for expenses, whose wallet balance runs through
/// `runTransaction`, which does not use the offline cache at all and simply
/// hangs while offline.)
///
/// With [deferWrite] the screen commits to the local truth — pop, toast,
/// update — and the durable write finishes on its own. Nothing is lost by
/// not waiting: the write is durable in the SDK's own on-disk queue the
/// moment it is issued, survives the app being killed, and retries itself
/// when connectivity returns.
///
/// ## What is *not* deferred
///
/// Only the persistence tail. Anything whose **result the screen needs** —
/// a generated id, a picked file's durable local path, a validation the user
/// must see — is still awaited on the UI path. Defer the part whose only
/// answer is "the server got it".
///
/// ## Failures
///
/// A deferred write that genuinely fails (a rules rejection, a bug — not a
/// dropped connection, which the SDK retries silently) is not swallowed: it
/// lands on [deferredWriteFailures], which `DeferredWriteReporter` turns into
/// a toast over whatever screen the user is on by then. Callers therefore
/// pass a [failureMessage] written for the *user*, in the past tense of the
/// thing that didn't stick ("Couldn't save that expense").
void deferWrite(Future<void> work, {required String failureMessage}) {
  _pending.add(work);
  unawaited(
    work
        .catchError((Object error, StackTrace stack) {
          _failures.add(DeferredWriteFailure(failureMessage, error, stack));
          if (kDebugMode) {
            debugPrint('deferWrite failed ($failureMessage): $error\n$stack');
          }
        })
        .whenComplete(() => _pending.remove(work)),
  );
}

/// A deferred write that did not land, described for the user.
@immutable
class DeferredWriteFailure {
  const DeferredWriteFailure(this.message, this.error, this.stackTrace);

  /// User-facing copy supplied by the caller — the toast's text.
  final String message;

  final Object error;
  final StackTrace stackTrace;
}

/// Failures from [deferWrite], for whoever is showing them. Broadcast, so
/// having no listener (a widget test, a background isolate) is not an error.
Stream<DeferredWriteFailure> get deferredWriteFailures => _failures.stream;

final _failures = StreamController<DeferredWriteFailure>.broadcast();
final _pending = <Future<void>>{};

/// Completes once every write handed to [deferWrite] so far has settled.
///
/// For **tests**, which need the deferred tail to have run before asserting
/// on a fake repository's contents — the production UI deliberately never
/// waits on this. Writes started *by* those writes are picked up too, since
/// the set is re-read after each pass.
@visibleForTesting
Future<void> settleDeferredWrites() async {
  while (_pending.isNotEmpty) {
    await Future.wait(
      _pending.map((f) => f.catchError((Object _) {})),
      eagerError: false,
    );
  }
}
