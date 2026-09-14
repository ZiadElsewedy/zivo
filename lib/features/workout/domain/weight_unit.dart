import 'muscle_group.dart';

/// The unit a weight is *shown and typed* in — never the unit it is *stored*
/// in. Kilograms are the one canonical representation everywhere in the domain,
/// the repositories, the analytics and the AI pipeline; [WeightUnit] is a
/// presentation/input concern layered on top of that, so a user on an imported
/// pounds machine can read and enter loads in lb while the number that lands in
/// Firestore stays kg.
///
/// It is a device-local UI preference (persisted by the live-session
/// controller in `SharedPreferences`), not account data — switching it changes
/// what you see, never what is saved.
enum WeightUnit {
  kg,
  lb;

  /// The exact factor the product pins: `1 kg = 2.2046226218 lb`. Used for
  /// every conversion so kg↔lb round-trips are accurate rather than the rough
  /// `2.2` a lot of trackers settle for.
  static const double lbPerKg = 2.2046226218;

  /// A value the user typed/stepped *in this unit* → canonical kilograms.
  double toKg(double display) => this == kg ? display : display / lbPerKg;

  /// A canonical kilogram value → the number to show in this unit.
  double fromKg(double value) => this == kg ? value : value * lbPerKg;

  /// The latin unit symbol, lowercase ("kg" / "lb") — for the places a weight
  /// is written as `<number><symbol>` with the symbol riding the numeral
  /// (`weightText`, the review rows, the delta chip). Latin in both languages,
  /// the same convention `trimWeight`'s "kg" already uses.
  String get symbol => this == kg ? 'kg' : 'lb';

  /// The upper-case symbol ("KG" / "LB") — the hero's caps unit label and the
  /// segmented selector.
  String get symbolCaps => this == kg ? 'KG' : 'LB';

  /// A canonical kilogram value formatted for THIS unit's field/hero, at a
  /// gym-friendly precision.
  ///
  /// Kilograms keep [_trim]'s single decimal — byte-identical to how the whole
  /// screen wrote weights before units existed, which is what keeps the KG-mode
  /// output (and the widget suite that asserts on it) unchanged. Pounds snap to
  /// the nearest half-pound, so a stored `86.18 kg` reads "190", not the
  /// literal "189.998" the raw conversion would give.
  String display(double kg) {
    if (this == WeightUnit.kg) return _trim(kg);
    final lb = kg * lbPerKg;
    return _trim((lb * 2).roundToDouble() / 2);
  }

  /// The ± nudge, in THIS unit, for the given equipment context — the fix for
  /// the old hardcoded 2.5. A compound lift steps a plate-pair jump (2.5 kg /
  /// 5 lb); an isolation movement steps the smaller increment its machine or
  /// dumbbells actually offer (1 kg / 2.5 lb). Both stay on clean .0/.5
  /// boundaries so the field never shows a stray quarter.
  double step({required bool small}) => switch (this) {
    WeightUnit.kg => small ? 1.0 : 2.5,
    WeightUnit.lb => small ? 2.5 : 5.0,
  };

  /// Parses a persisted [name] back to a unit, defaulting to [kg] for anything
  /// unrecognised (an absent preference, or a value written by a future
  /// version).
  static WeightUnit fromName(String? name) {
    for (final u in values) {
      if (u.name == name) return u;
    }
    return kg;
  }
}

/// The ± nudge for [unit] given an exercise's free-text muscle group — small
/// muscles get the smaller jump, the same classification the progression
/// engine's own weight step keys off ([isSmallMuscleGroup]).
double weightStepFor(WeightUnit unit, String? muscleGroup) =>
    unit.step(small: isSmallMuscleGroup(muscleGroup));

/// "60" / "22.5" — a weight without a trailing ".0". A domain-local copy of
/// `trimWeight` (which lives in the presentation layer and drags Flutter in
/// with it), so this file stays Flutter-free.
String _trim(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
