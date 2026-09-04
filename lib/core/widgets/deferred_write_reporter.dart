import 'dart:async';

import 'package:flutter/material.dart';

import '../util/deferred_write.dart';
import 'zivo_toast.dart';

/// Surfaces the failures of local-first writes (see
/// `core/util/deferred_write.dart`).
///
/// Local-first means the screen that started a write is *gone* by the time it
/// resolves — it popped the moment the local copy was good. So the report has
/// to happen above every screen, once, which is what this is: mounted inside
/// `MaterialApp.builder` in `app.dart`, it turns each
/// [DeferredWriteFailure] into the app's own toast over whatever the user is
/// looking at by then.
///
/// This is the honesty half of the local-first bargain. "Don't make the user
/// wait for the database" is only acceptable if a write that never lands is
/// still told to them rather than silently dropped.
class DeferredWriteReporter extends StatefulWidget {
  const DeferredWriteReporter({required this.child, super.key});

  final Widget child;

  @override
  State<DeferredWriteReporter> createState() => _DeferredWriteReporterState();
}

class _DeferredWriteReporterState extends State<DeferredWriteReporter> {
  StreamSubscription<DeferredWriteFailure>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = deferredWriteFailures.listen((failure) {
      if (!mounted) return;
      showZivoToast(context, failure.message, kind: ToastKind.error);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
