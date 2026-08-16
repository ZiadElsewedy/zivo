import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';

DietPlan _make(String id) => DietPlan(
  id: id,
  name: 'Plan $id',
  status: DietPlanStatus.active,
  source: DietSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  days: const <DietDay>[],
);

void main() {
  test('seeds with a demo plan exposed via activePlan', () {
    final repo = InMemoryDietRepository();
    addTearDown(repo.dispose);

    expect(repo.activePlan, isNotNull);
  });

  test('savePlan replaces the active plan', () async {
    final repo = InMemoryDietRepository();
    addTearDown(repo.dispose);

    await repo.savePlan(_make('p1'));
    expect(repo.activePlan?.id, 'p1');
  });

  test('deletePlan clears the active plan and watchActivePlan emits null', () async {
    final repo = InMemoryDietRepository();
    addTearDown(repo.dispose);
    await repo.savePlan(_make('p1'));

    final seen = <DietPlan?>[];
    final sub = repo.watchActivePlan().listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    expect(seen.last?.id, 'p1');

    await repo.deletePlan('p1');
    await Future<void>.delayed(Duration.zero);

    expect(repo.activePlan, isNull);
    expect(seen.last, isNull);

    await sub.cancel();
  });

  test('deletePlan is a no-op when the id does not match the active plan', () async {
    final repo = InMemoryDietRepository();
    addTearDown(repo.dispose);
    await repo.savePlan(_make('p1'));

    await repo.deletePlan('not-the-active-plan');

    expect(repo.activePlan?.id, 'p1');
  });
}
