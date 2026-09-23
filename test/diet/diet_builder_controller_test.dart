import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/body_profile.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/domain/target_calculator.dart';
import 'package:zivo/features/diet/presentation/controllers/diet_builder_controller.dart';

void main() {
  final now = DateTime(2026, 9, 14);

  DietBuilderController complete() {
    final c = DietBuilderController();
    c.goal = DietGoal.maintain;
    c.weightField.text = '81';
    c.heightField.text = '178';
    c.ageField.text = '30';
    c.sex = TargetSex.male;
    c.activity = ActivityLevel.moderate;
    return c;
  }

  test('is incomplete — and refuses to finalize — until goal and body are set', () {
    final c = DietBuilderController();
    addTearDown(c.dispose);
    expect(c.goalComplete, isFalse);
    expect(c.bodyComplete, isFalse);
    expect(c.canBuild, isFalse);
    expect(c.finalize(now), isNull);

    c.goal = DietGoal.fatLoss;
    expect(c.canBuild, isFalse, reason: 'body still missing');
  });

  test('finalize maps every input to the deterministic target', () {
    final c = complete();
    addTearDown(c.dispose);
    expect(c.canBuild, isTrue);

    final result = c.finalize(now)!;
    // The same numbers the calculator would produce from these exact inputs —
    // proves the controller wired weight/height/age/sex/activity/goal through
    // without swapping any of them.
    final direct = calculateTargets(
      weightKg: 81,
      heightCm: 178,
      age: 30,
      sex: TargetSex.male,
      activity: ActivityLevel.moderate,
      goal: DietGoal.maintain,
      now: now,
    );
    expect(result.proposal.targets.calories, direct.targets.calories);
    expect(result.proposal.targets.source, TargetSource.calculated);
    expect(result.proposal.targets.basis, isNotNull);
    expect(result.preferences.mealsPerDay, 3);
  });

  test('surfaces the safety floor rather than clamping', () {
    final c = complete()
      ..goal = DietGoal.fatLoss
      ..weightField.text = '42'
      ..heightField.text = '150'
      ..ageField.text = '25'
      ..sex = TargetSex.female
      ..activity = ActivityLevel.sedentary;
    addTearDown(c.dispose);
    final result = c.finalize(now)!;
    expect(result.proposal.belowSafetyFloor, isTrue);
  });

  group('weigh-in', () {
    test('an untouched prefill logs no new weigh-in', () {
      final c = DietBuilderController();
      addTearDown(c.dispose);
      c.seedBody(latestWeightKg: 80);
      c.goal = DietGoal.maintain;
      c.heightField.text = '178';
      c.ageField.text = '30';
      c.sex = TargetSex.male;
      c.activity = ActivityLevel.moderate;
      expect(c.finalize(now)!.newWeightKg, isNull);
    });

    test('a changed weight is logged', () {
      final c = DietBuilderController();
      addTearDown(c.dispose);
      c.seedBody(latestWeightKg: 80);
      c.goal = DietGoal.maintain;
      c.weightField.text = '82';
      c.heightField.text = '178';
      c.ageField.text = '30';
      c.sex = TargetSex.male;
      c.activity = ActivityLevel.moderate;
      expect(c.finalize(now)!.newWeightKg, 82);
    });
  });

  test('seedBody prefills from the profile and marks age as derived', () {
    final c = DietBuilderController();
    addTearDown(c.dispose);
    c.seedBody(
      profile: BodyProfile(
        heightCm: 175,
        sex: TargetSex.female,
        activity: ActivityLevel.high,
        statedMaintenanceKcal: 2100,
        updatedAt: now,
      ),
      dobAge: 41,
    );
    expect(c.heightField.text, '175');
    expect(c.sex, TargetSex.female);
    expect(c.activity, ActivityLevel.high);
    expect(c.ageFromDob, isTrue);
    expect(c.ageField.text, '41');

    // A stated maintenance figure the user set elsewhere survives the save.
    c.goal = DietGoal.maintain;
    c.weightField.text = '68';
    final result = c.finalize(now)!;
    expect(result.profile.statedMaintenanceKcal, 2100);
  });

  group('free-text intake', () {
    test('dislikes prose becomes clean avoid tokens', () {
      final c = complete();
      addTearDown(c.dispose);
      c.dislikes.text = "I don't like fish, broccoli, or cottage cheese";
      final avoid = c.finalize(now)!.preferences.avoid;
      expect(avoid, containsAll(<String>['fish', 'broccoli', 'cottage cheese']));
    });

    test('allergies merge the free-text field and the tapped chips', () {
      final c = complete();
      addTearDown(c.dispose);
      c.allergies.text = 'peanuts and shellfish';
      c.setAllergenChips(['eggs']);
      final allergies = c.finalize(now)!.preferences.allergies;
      expect(allergies, containsAll(<String>['peanuts', 'shellfish', 'eggs']));
    });

    test('how-you-eat and schedule fold into the generator notes payload', () {
      final c = complete();
      addTearDown(c.dispose);
      c.eatingHabits.text = 'eggs for breakfast, chicken and rice for lunch';
      c.schedule.text = 'I train at 6am';
      final notes = c.finalize(now)!.preferences.toPayload()['notes'] as String;
      expect(notes, contains('eggs for breakfast'));
      expect(notes, contains('I train at 6am'));
    });
  });

  test('the picked country reaches the generator by its English name', () {
    final c = complete();
    addTearDown(c.dispose);
    expect(c.finalize(now)!.preferences.country, isNull);

    c.countryCode = 'EG';
    expect(c.finalize(now)!.preferences.country, 'Egypt');
    expect(c.finalize(now)!.preferences.toPayload()['country'], 'Egypt');
  });

  test('seedCountry prefills once, never over a pick, and ignores junk', () {
    final c = DietBuilderController();
    addTearDown(c.dispose);
    c.seedCountry('zz');
    expect(c.countryCode, isNull);
    c.seedCountry('gb');
    expect(c.countryCode, 'GB');

    final picked = DietBuilderController()..countryCode = 'EG';
    addTearDown(picked.dispose);
    picked.seedCountry('GB');
    expect(picked.countryCode, 'EG');
  });
}
