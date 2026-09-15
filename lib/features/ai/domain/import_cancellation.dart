import 'dart:async';

/// A one-shot cancel handle the importer UI hands to the repository so pressing
/// **X** propagates all the way to the backend rather than only dismissing the
/// screen.
///
/// The repository races the import against [whenCancelled]; on cancel it closes
/// the streaming callable connection, which fires the function's
/// `response.signal` and aborts the in-flight model generation — so a cancelled
/// import stops the work (and the billing) instead of running to completion for
/// output nobody will read.
class ImportCancellation {
  final Completer<void> _completer = Completer<void>();

  /// Completes the moment [cancel] is called.
  Future<void> get whenCancelled => _completer.future;

  bool get isCancelled => _completer.isCompleted;

  /// Idempotent — a second X, or one arriving after the import already
  /// finished, is a no-op.
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Thrown by an import method that was cancelled via [ImportCancellation]. The
/// page catches this to show its cancelled state, distinct from a real error.
class ImportCancelledException implements Exception {
  const ImportCancelledException();

  @override
  String toString() => 'ImportCancelledException';
}
