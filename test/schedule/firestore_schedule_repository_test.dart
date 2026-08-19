import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/schedule/data/firestore_schedule_repository.dart';
import 'package:zivo/features/schedule/domain/schedule_event.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

ScheduleEvent _make(
  String id, {
  String title = 'Event',
  DateTime? start,
  DateTime? end,
  String? location,
  String? label,
}) => ScheduleEvent(
  id: id,
  title: title,
  start: start ?? DateTime(2026, 1, 1, 9),
  end: end,
  location: location,
  label: label,
);

void main() {
  group('FirestoreScheduleRepository', () {
    test(
      'add writes a doc with the right fields and surfaces via watchAll',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreScheduleRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final seen = <List<ScheduleEvent>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        final event = _make(
          'e1',
          title: 'Data Structures',
          start: DateTime(2026, 1, 1, 9),
          end: DateTime(2026, 1, 1, 10),
          location: 'Hall B',
          label: 'Lecture',
        );
        await repo.add(event);
        await Future<void>.delayed(Duration.zero);

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('schedule')
            .doc('e1')
            .get();
        final data = doc.data()!;
        expect(data['title'], 'Data Structures');
        expect(data['start'], isA<Timestamp>());
        expect(data['end'], isA<Timestamp>());
        expect(data['location'], 'Hall B');
        expect(data['label'], 'Lecture');
        expect(data['schemaVersion'], 1);
        expect(data['createdAt'], isA<Timestamp>());
        expect(data['updatedAt'], isA<Timestamp>());

        expect(seen.last, hasLength(1));
        expect(seen.last.single.id, 'e1');

        await sub.cancel();
      },
    );

    test(
      'a late second subscriber immediately receives the current snapshot '
      'even when the collection is empty (regression: infinite spinner)',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreScheduleRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        // First subscriber (mirrors the always-alive Today dashboard) drains
        // the initial empty snapshot from the shared broadcast controller.
        final first = <List<ScheduleEvent>>[];
        final firstSub = repo.watchAll().listen(first.add);
        await Future<void>.delayed(Duration.zero);
        expect(first, isNotEmpty);
        expect(first.last, isEmpty);

        // A late second subscriber (a Hub detail page opened afterwards) must
        // still receive the current value immediately instead of hanging on
        // ConnectionState.waiting. Against the old raw-broadcast stream this
        // .first never completed and the page spun forever.
        final late = await repo
            .watchAll()
            .first
            .timeout(const Duration(seconds: 1));
        expect(late, isEmpty);

        await firstSub.cancel();
      },
    );

    test('watchAll returns events start-ascending', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreScheduleRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('later', start: DateTime(2026, 1, 5)));
      await repo.add(_make('earlier', start: DateTime(2026, 1, 1)));

      final events = await repo.watchAll().first;
      expect(events.map((e) => e.id).toList(), ['earlier', 'later']);
    });

    test('a minimal event round-trips with end/location/label null', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreScheduleRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('e1'));

      final events = await repo.watchAll().first;
      final event = events.single;
      expect(event.end, isNull);
      expect(event.location, isNull);
      expect(event.label, isNull);
    });

    test(
      'signed-out uid source emits an empty list and guards writes',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreScheduleRepository(
          firestore: firestore,
          uidSource: UidSource(
            currentUid: () => null,
            uidChanges: Stream.value(null),
          ),
        );

        final events = await repo.watchAll().first;
        expect(events, isEmpty);

        expect(() => repo.add(_make('e1')), throwsStateError);
        expect(() => repo.update(_make('e1')), throwsStateError);
        expect(() => repo.remove('e1'), throwsStateError);
      },
    );

    test(
      'update replaces title/start/end/location, preserves id, and is '
      'observed on the stream',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreScheduleRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        await repo.add(
          _make(
            'e1',
            title: 'Data Structures',
            start: DateTime(2026, 1, 1, 9),
            end: DateTime(2026, 1, 1, 10),
            location: 'Hall B',
          ),
        );

        final seen = <List<ScheduleEvent>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        await repo.update(
          _make(
            'e1',
            title: 'Renamed lecture',
            start: DateTime(2026, 1, 2, 14),
            end: DateTime(2026, 1, 2, 15, 30),
            location: 'Hall C',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final updated = seen.last.single;
        expect(updated.id, 'e1');
        expect(updated.title, 'Renamed lecture');
        expect(updated.start, DateTime(2026, 1, 2, 14));
        expect(updated.end, DateTime(2026, 1, 2, 15, 30));
        expect(updated.location, 'Hall C');

        await sub.cancel();
      },
    );

    test('update can clear the end/location to null', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreScheduleRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(
        _make('e1', end: DateTime(2026, 1, 1, 10), location: 'Hall B'),
      );
      await repo.update(_make('e1', end: null, location: null));

      final events = await repo.watchAll().first;
      final updated = events.single;
      expect(updated.end, isNull);
      expect(updated.location, isNull);
    });

    test('remove deletes the doc and is observed on the stream', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreScheduleRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('e1'));
      await repo.add(_make('e2', start: DateTime(2026, 1, 2)));

      final seen = <List<ScheduleEvent>>[];
      final sub = repo.watchAll().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await repo.remove('e1');
      await Future<void>.delayed(Duration.zero);

      expect(seen.last.map((e) => e.id).toList(), ['e2']);

      await sub.cancel();
    });
  });
}
