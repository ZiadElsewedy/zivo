import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_scoped_mirror.dart';
import 'package:zivo/core/firebase/uid_source.dart';

/// Direct coverage for the shared mirror that every `Firestore<X>Repository`
/// now delegates its uid-scoping to. The per-repository tests exercise it
/// through real (fake-Firestore-backed) queries; these pin the contract
/// itself, with a hand-driven source so each behaviour is isolated from
/// Firestore's own timing.
void main() {
  group('UidScopedMirror', () {
    test('current reads the signed-out value until the first snapshot', () {
      final mirror = UidScopedMirror<List<String>>(
        uidSource: UidSource(
          currentUid: () => null,
          uidChanges: const Stream.empty(),
        ),
        signedOutValue: const [],
        source: (_) => const Stream.empty(),
      );
      addTearDown(mirror.dispose);

      expect(mirror.current, isEmpty);
      expect(mirror.hasSnapshot, isFalse);
    });

    test(
      'a late subscriber is replayed the cached value instead of waiting '
      'forever on a broadcast stream that already emitted',
      () async {
        final source = StreamController<List<String>>.broadcast();
        addTearDown(source.close);
        final mirror = UidScopedMirror<List<String>>(
          uidSource: UidSource(
            currentUid: () => 'u1',
            uidChanges: const Stream.empty(),
          ),
          signedOutValue: const [],
          source: (_) => source.stream,
        )..start();
        addTearDown(mirror.dispose);
        await Future<void>.delayed(Duration.zero);

        // The first subscriber (Today, alive in the shell's IndexedStack)
        // consumes the only emission.
        final first = <List<String>>[];
        final firstSub = mirror.watch().listen(first.add);
        source.add(const ['a']);
        await Future<void>.delayed(Duration.zero);
        expect(first, [
          ['a'],
        ]);
        await firstSub.cancel();

        // A page opened afterwards must see the value immediately, not sit on
        // ConnectionState.waiting until the next write.
        final late = <List<String>>[];
        final lateSub = mirror.watch().listen(late.add);
        await Future<void>.delayed(Duration.zero);
        addTearDown(lateSub.cancel);
        expect(late, [
          ['a'],
        ]);
      },
    );

    test(
      'the source listener stays live with zero subscribers, so a write made '
      'while nothing is watching is never replayed stale',
      () async {
        final source = StreamController<List<String>>.broadcast();
        addTearDown(source.close);
        final mirror = UidScopedMirror<List<String>>(
          uidSource: UidSource(
            currentUid: () => 'u1',
            uidChanges: const Stream.empty(),
          ),
          signedOutValue: const [],
          source: (_) => source.stream,
        )..start();
        addTearDown(mirror.dispose);
        await Future<void>.delayed(Duration.zero);

        // Subscribe and leave — the "card scrolled off-screen" state.
        final sub = mirror.watch().listen((_) {});
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        // The write lands with nobody watching.
        source.add(const ['fresh']);
        await Future<void>.delayed(Duration.zero);

        expect(mirror.current, ['fresh']);
        final seen = <List<String>>[];
        final resub = mirror.watch().listen(seen.add);
        await Future<void>.delayed(Duration.zero);
        addTearDown(resub.cancel);
        expect(seen.first, ['fresh']);
      },
    );

    test('signing out clears the cache and a new user never bleeds the old one', () async {
      final uidChanges = StreamController<String?>.broadcast();
      addTearDown(uidChanges.close);
      String? uid = 'u1';
      final sources = {
        'u1': StreamController<List<String>>.broadcast(),
        'u2': StreamController<List<String>>.broadcast(),
      };
      addTearDown(() {
        for (final c in sources.values) {
          c.close();
        }
      });

      final mirror = UidScopedMirror<List<String>>(
        uidSource: UidSource(
          currentUid: () => uid,
          uidChanges: uidChanges.stream,
        ),
        signedOutValue: const [],
        source: (forUid) => sources[forUid]!.stream,
      )..start();
      addTearDown(mirror.dispose);
      await Future<void>.delayed(Duration.zero);

      sources['u1']!.add(const ['u1-data']);
      await Future<void>.delayed(Duration.zero);
      expect(mirror.current, ['u1-data']);

      uid = null;
      uidChanges.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(mirror.current, isEmpty);

      uid = 'u2';
      uidChanges.add('u2');
      await Future<void>.delayed(Duration.zero);
      expect(mirror.current, isEmpty);

      // The previous user's source is detached — a late event on it must not
      // resurface under the new user.
      sources['u1']!.add(const ['u1-late']);
      await Future<void>.delayed(Duration.zero);
      expect(mirror.current, isEmpty);

      sources['u2']!.add(const ['u2-data']);
      await Future<void>.delayed(Duration.zero);
      expect(mirror.current, ['u2-data']);
    });

    test('a source error reaches subscribers rather than looking like empty data', () async {
      final source = StreamController<List<String>>.broadcast();
      addTearDown(source.close);
      final mirror = UidScopedMirror<List<String>>(
        uidSource: UidSource(
          currentUid: () => 'u1',
          uidChanges: const Stream.empty(),
        ),
        signedOutValue: const [],
        source: (_) => source.stream,
      )..start();
      addTearDown(mirror.dispose);
      await Future<void>.delayed(Duration.zero);

      Object? seenError;
      final sub = mirror.watch().listen((_) {}, onError: (Object e) => seenError = e);
      addTearDown(sub.cancel);

      source.addError(StateError('permission-denied'));
      await Future<void>.delayed(Duration.zero);

      expect(seenError, isA<StateError>());
    });

    test('a null-value mirror (the single-document shape) reads null when signed out', () async {
      final uidChanges = StreamController<String?>.broadcast();
      addTearDown(uidChanges.close);
      final source = StreamController<String?>.broadcast();
      addTearDown(source.close);
      String? uid = 'u1';

      final mirror = UidScopedMirror<String?>(
        uidSource: UidSource(
          currentUid: () => uid,
          uidChanges: uidChanges.stream,
        ),
        signedOutValue: null,
        source: (_) => source.stream,
      )..start();
      addTearDown(mirror.dispose);
      await Future<void>.delayed(Duration.zero);

      source.add('balance');
      await Future<void>.delayed(Duration.zero);
      expect(mirror.current, 'balance');

      uid = null;
      uidChanges.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(mirror.current, isNull);
    });
  });

  group('UidSource.requireUid', () {
    test('returns the uid when signed in', () {
      final source = UidSource(
        currentUid: () => 'u1',
        uidChanges: const Stream.empty(),
      );
      expect(source.requireUid(_Owner()), 'u1');
    });

    test('throws naming the calling repository when signed out', () {
      final source = UidSource(
        currentUid: () => null,
        uidChanges: const Stream.empty(),
      );
      expect(
        () => source.requireUid(_Owner()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            '_Owner: no signed-in user.',
          ),
        ),
      );
    });
  });
}

class _Owner {}
