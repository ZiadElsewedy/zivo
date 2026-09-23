import 'package:flutter/material.dart';

import '../../../../core/util/countries.dart';
import '../../../../core/util/parse.dart';
import '../../domain/body_profile.dart';
import '../../domain/diet_goal.dart';
import '../../domain/nutrition_targets.dart';
import '../../domain/plan_preferences.dart';
import '../../domain/target_calculator.dart';

/// Everything the guided Diet Builder has gathered, resolved into the exact
/// things that need saving — the preferences to generate from, the target the
/// day is sized to, and the body data to persist. Produced once, at the moment
/// the user taps Build, so the reveal screen can commit all of it atomically
/// when (and only when) the user saves.
class DietBuilderResult {
  const DietBuilderResult({
    required this.preferences,
    required this.proposal,
    required this.profile,
    required this.newWeightKg,
  });

  /// What the plan is generated from.
  final PlanPreferences preferences;

  /// The computed target and its full working — **not saved yet**. Sizing the
  /// generation to it, and showing it on the reveal, is not the same as
  /// writing it: the Save on the reveal is the user's approval (ADR-007).
  final TargetProposal proposal;

  /// The body data to write on save (height · sex · activity), carrying forward
  /// any stated-maintenance figure the user set elsewhere.
  final BodyProfile profile;

  /// The weight to log as a fresh weigh-in on save, or null when it matched the
  /// latest reading already on file — so re-running the builder doesn't plant a
  /// duplicate in the weight history the workout feature charts.
  final double? newWeightKg;
}

/// The Diet Builder wizard's document — the answers to Goal · About you · How
/// you eat · What you avoid · Meals, and the deterministic target arithmetic
/// they add up to.
///
/// A [ChangeNotifier] rather than a screen's `setState` because the rules
/// outgrew a widget ([ADR-008](../../../../docs/DECISIONS/ADR-008-presentation-controllers.md)):
/// per-step completeness, prefill-vs-edited tracking for the weigh-in, and the
/// same body-data-plus-goal computation the Targets page does — all testable
/// here without pumping a widget. It holds no `BuildContext` and never
/// navigates; the page reads it, shows the steps, and takes [finalize]'s result
/// to the generator and the reveal.
class DietBuilderController extends ChangeNotifier {
  DietBuilderController() {
    for (final c in [_weight, _height, _age, eatingHabits, dislikes, allergies, schedule]) {
      c.addListener(notifyListeners);
    }
  }

  // --- Goal -----------------------------------------------------------------
  DietGoal? _goal;
  DietGoal? get goal => _goal;
  set goal(DietGoal? value) {
    if (_goal == value) return;
    _goal = value;
    notifyListeners();
  }

  // --- About you ------------------------------------------------------------
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _height = TextEditingController();
  final TextEditingController _age = TextEditingController();
  TextEditingController get weightField => _weight;
  TextEditingController get heightField => _height;
  TextEditingController get ageField => _age;

  TargetSex? _sex;
  TargetSex? get sex => _sex;
  set sex(TargetSex? value) {
    if (_sex == value) return;
    _sex = value;
    notifyListeners();
  }

  ActivityLevel? _activity = ActivityLevel.moderate;
  ActivityLevel? get activity => _activity;
  set activity(ActivityLevel? value) {
    if (_activity == value) return;
    _activity = value;
    notifyListeners();
  }

  /// The weigh-in the weight field was prefilled from, and any stated
  /// maintenance figure already on the profile — both preserved so a save from
  /// here neither duplicates a weigh-in nor silently drops a figure the user
  /// entered elsewhere.
  double? _prefilledWeightKg;
  int? _statedMaintenanceKcal;

  /// Whether the age field was prefilled from the account's date of birth. When
  /// it was, the field is shown read-only — age is derived, not re-asked.
  bool _ageFromDob = false;
  bool get ageFromDob => _ageFromDob;

  // --- How you eat / what you avoid / schedule (free text, spoken or typed) --
  final TextEditingController eatingHabits = TextEditingController();

  /// Where the user lives, as an ISO country code ("EG") picked from the full
  /// country list — not typed. Optional, asked alongside how-you-eat so a plan
  /// can be steered toward foods actually realistic and commonly available
  /// where they are, not a generic Western default (see
  /// [PlanPreferences.country]). Seeded from the remembered choice
  /// ([seedCountry]) so the user picks it once, not every build.
  String? _countryCode;
  String? get countryCode => _countryCode;
  set countryCode(String? value) {
    if (_countryCode == value) return;
    _countryCode = value;
    notifyListeners();
  }

  /// The picked country, or null.
  Country? get country => countryByCode(_countryCode);

  /// Prefills the country from what the user chose last time. A choice the
  /// user already made this session wins over a late-arriving seed.
  void seedCountry(String? code) {
    if (_countryCode != null || countryByCode(code) == null) return;
    _countryCode = code!.toUpperCase();
    notifyListeners();
  }
  final TextEditingController dislikes = TextEditingController();
  final TextEditingController allergies = TextEditingController();
  final TextEditingController schedule = TextEditingController();

  /// Allergen chips tapped alongside the free-text field — kept as clean tokens
  /// for the server's deterministic allergen gate, which stem-matches each one.
  final List<String> allergenChips = <String>[];

  /// Replaces the tapped-allergen selection wholesale — [FoodChipPicker] hands
  /// back the complete new list, not a delta.
  void setAllergenChips(List<String> ids) {
    allergenChips
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  int _mealsPerDay = 3;
  int get mealsPerDay => _mealsPerDay;
  set mealsPerDay(int value) {
    if (_mealsPerDay == value) return;
    _mealsPerDay = value;
    notifyListeners();
  }

  /// Prefills the About-you step from what ZIVO already knows, so the user
  /// confirms rather than re-enters. Called once, after the page's async load.
  void seedBody({
    BodyProfile? profile,
    double? latestWeightKg,
    int? dobAge,
  }) {
    if (profile != null) {
      _height.text = _trim(profile.heightCm);
      _sex = profile.sex;
      _activity = profile.activity;
      _statedMaintenanceKcal = profile.statedMaintenanceKcal;
    }
    if (latestWeightKg != null) {
      _prefilledWeightKg = latestWeightKg;
      _weight.text = _trim(latestWeightKg);
    }
    if (dobAge != null) {
      _age.text = dobAge.toString();
      _ageFromDob = true;
    }
    notifyListeners();
  }

  // --- Parsed inputs --------------------------------------------------------
  double? get weightKg => parsePositiveDecimal(_weight.text);
  double? get heightCm => parsePositiveDecimal(_height.text);
  int? get age => parsePositiveInt(_age.text);

  bool get heightInRange {
    final cm = heightCm;
    return cm != null && heightIsPlausible(cm);
  }

  /// Whether Goal is answered — gates leaving the first step.
  bool get goalComplete => _goal != null;

  /// Whether every equation input is present and sane — gates leaving About you
  /// and, with a goal, enables Build.
  bool get bodyComplete =>
      weightKg != null &&
      heightInRange &&
      age != null &&
      _sex != null &&
      _activity != null;

  bool get canBuild => goalComplete && bodyComplete;

  /// The maintenance figure the current answers imply, shown live so the user
  /// sees what "moderate" vs "high" means before building. Null until complete.
  int? get previewMaintenance {
    if (!bodyComplete) return null;
    final bmr = basalMetabolicRate(
      weightKg: weightKg!,
      heightCm: heightCm!,
      age: age!,
      sex: _sex!,
    );
    return (bmr * activityFactor(_activity!)).round();
  }

  PlanPreferences _buildPreferences() => PlanPreferences(
    mealsPerDay: _mealsPerDay,
    avoid: splitNaturalFoodList(dislikes.text),
    allergies: _allergyTokens(),
    eatingHabits: _trimmedOrNull(eatingHabits.text),
    // The English name: the generator reasons in English, and the name is
    // what it knows the food culture by — a bare "EG" is a weaker steer.
    country: country?.en,
    scheduleNotes: _trimmedOrNull(schedule.text),
  );

  /// The chip ids and the free-text allergies together, de-duplicated. Both are
  /// kept as tokens because the allergen gate matches on them.
  List<String> _allergyTokens() {
    final seen = <String>{};
    final out = <String>[];
    for (final token in [...allergenChips, ...splitNaturalFoodList(allergies.text)]) {
      final key = token.toLowerCase();
      if (seen.add(key)) out.add(token);
    }
    return out;
  }

  /// Resolves everything into a [DietBuilderResult], or null when Goal or body
  /// data is incomplete (the Build button is disabled in that case, so this is
  /// belt-and-braces). [now] is injected so the arithmetic is deterministic.
  DietBuilderResult? finalize(DateTime now) {
    final goal = _goal;
    if (goal == null || !bodyComplete) return null;
    final proposal = calculateTargets(
      weightKg: weightKg!,
      heightCm: heightCm!,
      age: age!,
      sex: _sex!,
      activity: _activity!,
      goal: goal,
      now: now,
    );
    return DietBuilderResult(
      preferences: _buildPreferences(),
      proposal: proposal,
      profile: BodyProfile(
        heightCm: heightCm!,
        sex: _sex!,
        activity: _activity!,
        statedMaintenanceKcal: _statedMaintenanceKcal,
        updatedAt: now,
      ),
      // A fresh weigh-in only when the number actually changed.
      newWeightKg:
          (weightKg != null && weightKg != _prefilledWeightKg) ? weightKg : null,
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  static String? _trimmedOrNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  @override
  void dispose() {
    for (final c in [_weight, _height, _age, eatingHabits, dislikes, allergies, schedule]) {
      c.removeListener(notifyListeners);
      c.dispose();
    }
    super.dispose();
  }
}
