import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/deferred_write.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/moments/domain/moment.dart';
import 'package:zivo/features/moments/domain/moment_repository.dart';
import 'package:zivo/features/moments/presentation/pages/moment_capture_page.dart';

import '../support/test_app.dart';

/// The save flow's two promises, together:
///
/// 1. **Local-first** — Save does not wait for the database. Every repository
///    here is Firestore-backed in production, and a Firestore write resolves
///    on the SERVER's acknowledgement, not on the local cache the UI already
///    reflects. Awaiting it froze Save for a round trip (forever, offline).
/// 2. **Exactly once** — the button is guarded, so an impatient double-tap
///    cannot mint a second `microsecondsSinceEpoch` id and write a second
///    moment.
///
/// The blocking repository is what makes both testable: with a store that
/// completes immediately, a page that *did* await would still look instant.
class _BlockingMomentRepository implements MomentRepository {
  _BlockingMomentRepository(this._inner);

  final InMemoryMomentRepository _inner;
  final List<Completer<void>> _pending = [];

  /// Every write attempt that reached the repository.
  int writes = 0;

  void release() {
    for (final c in _pending) {
      if (!c.isCompleted) c.complete();
    }
    _pending.clear();
  }

  @override
  List<Moment> get current => _inner.current;

  @override
  Stream<List<Moment>> watchAll() => _inner.watchAll();

  @override
  Future<void> add(Moment moment) async {
    writes++;
    final gate = Completer<void>();
    _pending.add(gate);
    await gate.future;
    await _inner.add(moment);
  }

  @override
  Future<void> update(Moment moment) => _inner.update(moment);

  @override
  Future<void> remove(String id) => _inner.remove(id);
}

void main() {
  /// A phone-shaped surface. The capture page is a full-height column with a
  /// 3:2 photo tile in it, and the 800x600 default overflows before anything
  /// under test happens.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Save pops immediately, without waiting for the write', (
    tester,
  ) async {
    useTallSurface(tester);
    // The in-memory repo ships one seeded demo moment; count from there.
    final inner = InMemoryMomentRepository();
    final seeded = inner.current.length;
    final moments = _BlockingMomentRepository(inner);

    await tester.pumpWidget(
      wrapWithScope(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<Object>(
                builder: (_) => const MomentCapturePage(),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        moments: moments,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Squat PR');
    await tester.pump();

    await tester.tap(find.text('Add moment'));
    await tester.pumpAndSettle();

    // The write is still hanging — and the screen is already gone. This is
    // the whole point: the user is back on the timeline while the durable
    // write finishes behind them.
    expect(moments.writes, 1);
    expect(find.byType(MomentCapturePage), findsNothing);

    moments.release();
    await settleDeferredWrites();
    expect(inner.current, hasLength(seeded + 1));
    expect(inner.current.first.caption, 'Squat PR');
  });

  testWidgets('a rapid double-tap on Save writes exactly one moment', (
    tester,
  ) async {
    useTallSurface(tester);
    final inner = InMemoryMomentRepository();
    final seeded = inner.current.length;
    final moments = _BlockingMomentRepository(inner);

    await tester.pumpWidget(
      wrapWithScope(const MomentCapturePage(), moments: moments),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Deadlift');
    await tester.pump();

    final save = find.text('Add moment');
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();

    expect(
      moments.writes,
      1,
      reason: 'the second tap must be swallowed by the re-entrancy guard',
    );

    moments.release();
    await settleDeferredWrites();
    expect(inner.current, hasLength(seeded + 1));
  });
}
