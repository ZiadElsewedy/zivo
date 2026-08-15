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
      },
    );
  });
}
