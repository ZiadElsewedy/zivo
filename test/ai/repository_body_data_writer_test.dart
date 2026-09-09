import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/data/repository_body_data_writer.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/body_profile.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';

/// Phase 3: the Ask input form writing height/weight through the app's own
/// body-data repositories.
void main() {
  BodyProfile profile({double heightCm = 175}) => BodyProfile(
    heightCm: heightCm,
    sex: TargetSex.male,
    activity: ActivityLevel.moderate,
    updatedAt: DateTime(2026, 1, 1),
  );

  test('saveWeightKg records a weigh-in', () async {
    final weight = InMemoryBodyWeightRepository();
    final w = RepositoryBodyDataWriter(
      diet: InMemoryDietRepository(),
      bodyWeight: weight,
    );

    await w.saveWeightKg(74.5);

    expect(weight.current.single.weightKg, 74.5);
  });

  test('an implausible weight is ignored (typo guard)', () async {
    final weight = InMemoryBodyWeightRepository();
    final w = RepositoryBodyDataWriter(
      diet: InMemoryDietRepository(),
      bodyWeight: weight,
    );

    await w.saveWeightKg(5); // below the floor
    await w.saveWeightKg(900); // above the ceiling

    expect(weight.current, isEmpty);
  });

  test('saveHeightCm merges into an existing profile, keeping sex/activity',
      () async {
    final diet = InMemoryDietRepository();
    await diet.saveBodyProfile(profile(heightCm: 170));
    final w = RepositoryBodyDataWriter(
      diet: diet,
      bodyWeight: InMemoryBodyWeightRepository(),
    );

    final saved = await w.saveHeightCm(183);

    expect(saved, isTrue);
    expect(diet.currentBodyProfile!.heightCm, 183);
    expect(diet.currentBodyProfile!.sex, TargetSex.male);
    expect(diet.currentBodyProfile!.activity, ActivityLevel.moderate);
  });

  test('saveHeightCm is a no-op when there is no profile to merge into',
      () async {
    final diet = InMemoryDietRepository();
    final w = RepositoryBodyDataWriter(
      diet: diet,
      bodyWeight: InMemoryBodyWeightRepository(),
    );

    final saved = await w.saveHeightCm(183);

    // Height alone can't build a valid BodyProfile (sex/activity required).
    expect(saved, isFalse);
    expect(diet.currentBodyProfile, isNull);
  });

  test('an implausible height is ignored and never touches the profile',
      () async {
    final diet = InMemoryDietRepository();
    await diet.saveBodyProfile(profile(heightCm: 170));
    final w = RepositoryBodyDataWriter(
      diet: diet,
      bodyWeight: InMemoryBodyWeightRepository(),
    );

    final saved = await w.saveHeightCm(40); // a height in the wrong unit

    expect(saved, isFalse);
    expect(diet.currentBodyProfile!.heightCm, 170);
  });

  test('weight is simply skipped when no bodyWeight repo is wired', () async {
    final w = RepositoryBodyDataWriter(
      diet: InMemoryDietRepository(),
      bodyWeight: null,
    );

    // Must not throw — persistence is best-effort.
    await w.saveWeightKg(74);
  });
}
