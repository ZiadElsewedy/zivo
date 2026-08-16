import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/diet/data/firestore_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

DietPlan _makePlan(
  String id, {
  DietPlanStatus status = DietPlanStatus.active,
  DateTime? createdAt,
  List<DietDay>? days,
}) => DietPlan(
  id: id,
  name: 'Plan $id',
  status: status,
  source: DietSource.manual,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  updatedAt: createdAt ?? DateTime(2026, 1, 1),
  days:
      days ??
      const [
        DietDay(
          weekday: null,
          label: 'Every day',
          meals: [
            Meal(
              id: 'meal-1',
              label: 'Lunch',
              order: 0,
              items: [
                FoodItem(name: 'Rice', quantity: 150, unit: 'g', calories: 210, carbsG: 45),
                FoodItem(
                  name: 'Chicken breast',
                  quantity: 200,
                  unit: 'g',
                  calories: 330,
                  proteinG: 62,
                ),
              ],
            ),
          ],
        ),
      ],
);

void main() {
  group('FirestoreDietRepository', () {
    test(
      'savePlan writes the embedded days/meals/items shape and surfaces via watchActivePlan',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreDietRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final seen = <DietPlan?>[];
        final sub = repo.watchActivePlan().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        final plan = _makePlan('p1');
        await repo.savePlan(plan);
        await Future<void>.delayed(Duration.zero);

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('dietPlans')
            .doc('p1')
            .get();
        final data = doc.data()!;
        expect(data['name'], 'Plan p1');
        expect(data['status'], 'active');
        expect(data['source'], 'manual');
        expect(data['schemaVersion'], 1);
        expect(data['createdAt'], isA<Timestamp>());
        expect(data['updatedAt'], isA<Timestamp>());
        final days = data['days'] as List<dynamic>;
        expect(days, hasLength(1));
        final meals = (days.single as Map)['meals'] as List<dynamic>;
        expect(meals, hasLength(1));
        final items = (meals.single as Map)['items'] as List<dynamic>;
        expect(items, hasLength(2));
        expect((items.first as Map)['name'], 'Rice');

        expect(seen.last?.id, 'p1');
        expect(seen.last?.days.single.meals.single.items, hasLength(2));

        await sub.cancel();
      },
    );

    test('only the active-status plan is returned by watchActivePlan', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreDietRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.savePlan(
        _makePlan('archived', status: DietPlanStatus.archived, createdAt: DateTime(2026, 1, 1)),
      );
      await repo.savePlan(
        _makePlan('active', status: DietPlanStatus.active, createdAt: DateTime(2026, 1, 2)),
      );

      final plan = await repo.watchActivePlan().first;
      expect(plan?.id, 'active');
    });

    test(
      'setMealEaten writes a dietEntries doc and watchConsumed reflects it; toggling false '
      'removes it from the set without deleting the doc',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreDietRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );
        final day = DateTime(2026, 1, 5);

        final seen = <Set<String>>[];
        final sub = repo.watchConsumed(day).listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        await repo.setMealEaten(mealId: 'meal-1', day: day, eaten: true);
        await Future<void>.delayed(Duration.zero);

        expect(seen.last, {'meal-1'});

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('dietEntries')
            .doc('2026-01-05__meal-1')
            .get();
        final data = doc.data()!;
        expect(data['dayKey'], '2026-01-05');
        expect(data['mealId'], 'meal-1');
        expect(data['eaten'], isTrue);
        expect(data['schemaVersion'], 1);
        expect(data['date'], isA<Timestamp>());

        await repo.setMealEaten(mealId: 'meal-1', day: day, eaten: false);
        await Future<void>.delayed(Duration.zero);

        expect(seen.last, isEmpty);

        // The doc still exists (never deleted) — just flipped to eaten: false.
        final stillThere = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('dietEntries')
            .doc('2026-01-05__meal-1')
            .get();
        expect(stillThere.exists, isTrue);
        expect(stillThere.data()!['eaten'], isFalse);

        await sub.cancel();
      },
    );

    test('deletePlan removes the doc, watchActivePlan emits null', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreDietRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.savePlan(_makePlan('p1'));

      final seen = <DietPlan?>[];
      final sub = repo.watchActivePlan().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last?.id, 'p1');

      await repo.deletePlan('p1');
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, isNull);

      final doc = await firestore
          .collection('users')
          .doc('test-uid')
          .collection('dietPlans')
          .doc('p1')
          .get();
      expect(doc.exists, isFalse);

      await sub.cancel();
    });

    test('signed-out uid source emits null/empty and guards writes', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreDietRepository(
        firestore: firestore,
        uidSource: UidSource(currentUid: () => null, uidChanges: Stream.value(null)),
      );

      final plan = await repo.watchActivePlan().first;
      expect(plan, isNull);

      final consumed = await repo.watchConsumed(DateTime(2026, 1, 5)).first;
      expect(consumed, isEmpty);

      expect(() => repo.savePlan(_makePlan('p1')), throwsStateError);
      expect(() => repo.deletePlan('p1'), throwsStateError);
      expect(
        () => repo.setMealEaten(mealId: 'meal-1', day: DateTime(2026, 1, 5), eaten: true),
        throwsStateError,
      );
    });
  });
}
