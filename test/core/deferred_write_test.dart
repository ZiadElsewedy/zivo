import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/deferred_write.dart';

/// The local-first bargain, in isolation: a screen hands its durable write to
/// [deferWrite] and returns immediately, and a write that never lands is
/// still reported rather than swallowed.
void main() {
  test('returns immediately — the caller never awaits the write', () async {
    final gate = Completer<void>();
    var landed = false;

    deferWrite(
      gate.future.then((_) => landed = true),
      failureMessage: 'nope',
    );

    // Nothing has run yet, and control is already back here: this is the
    // whole point — the capture screen pops on this line.
    expect(landed, isFalse);

    gate.complete();
    await settleDeferredWrites();
    expect(landed, isTrue);
  });

  test('a failed write surfaces on the failures stream with its copy', () async {
    final failures = <DeferredWriteFailure>[];
    final sub = deferredWriteFailures.listen(failures.add);
    addTearDown(sub.cancel);

    deferWrite(
      Future<void>.error(StateError('rules denied')),
      failureMessage: "Couldn't save that expense.",
    );
    await settleDeferredWrites();
    // The stream is async; give the listener its microtask.
    await Future<void>.delayed(Duration.zero);

    expect(failures, hasLength(1));
    expect(failures.single.message, "Couldn't save that expense.");
    expect(failures.single.error, isStateError);
  });

  test('a failure does not escape as an unhandled async error', () async {
    // Deliberately no listener on `deferredWriteFailures`: a broadcast stream
    // with no subscriber must still consume the error, or every offline write
    // would crash the zone.
    deferWrite(
      Future<void>.error(Exception('boom')),
      failureMessage: 'ignored',
    );
    await settleDeferredWrites();
  });
}
