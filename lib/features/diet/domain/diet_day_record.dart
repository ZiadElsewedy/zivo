/// One day of diet history, as the server records it at
/// `users/{uid}/dietDays/{dayKey}` (`functions/diet/day_record.js`).
///
/// A **read model**, never written by the app: the server rebuilds it from
/// `dietPlans` + `dietEntries` + `foodLogs` whenever any of them changes. It
/// keeps what was *planned* that day (a meal-level snapshot, frozen once the
/// day is past, so editing the plan today never rewrites yesterday) beside
/// what *happened* — which meals were eaten, modified, skipped, and what was
/// eaten outside them. The foods themselves stay in `foodLogs`.
///
/// Today's screen does not read this: it is built live from the sources
/// (`DietState`), because a record can trail a tap by a moment. History does.
library;

/// What happened to one planned meal on one day.
enum MealTrackingStatus {
  /// Ticked, and the foods logged for it are exactly the plan's.
  eaten,

  /// Ticked, but an item was removed or an amount changed afterwards.
  modified,

  /// The user said they skipped it.
  skipped,

  /// Nothing was recorded. **Not** the same as skipped — an unticked meal
  /// might have been eaten and never ticked.
  unmarked,
}

MealTrackingStatus _statusFrom(Object? v) => switch (v) {
  'eaten' => MealTrackingStatus.eaten,
  'modified' => MealTrackingStatus.modified,
  'skipped' => MealTrackingStatus.skipped,
  _ => MealTrackingStatus.unmarked,
};

double? _num(Object? v) => v is num ? v.toDouble() : null;

/// Calories and macros. Any of them may be null when nothing stated one.
class NutritionFigures {
  const NutritionFigures({this.kcal, this.proteinG, this.carbsG, this.fatG});

  final double? kcal;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  static NutritionFigures? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return NutritionFigures(
      kcal: _num(raw['kcal']),
      proteinG: _num(raw['proteinG']),
      carbsG: _num(raw['carbsG']),
      fatG: _num(raw['fatG']),
    );
  }
}

/// One planned meal on the day, with what happened to it.
class MealTrackingRecord {
  const MealTrackingRecord({
    required this.mealId,
    required this.label,
    required this.order,
    required this.isSupplement,
    required this.status,
    this.planned,
    this.plannedEstimated = false,
    this.actual,
  });

  final String mealId;
  final String label;
  final int order;
  final bool isSupplement;
  final MealTrackingStatus status;

  /// What the plan said this meal was, that day. Null for a meal ticked on
  /// the day that the day's plan no longer holds.
  final NutritionFigures? planned;
  final bool plannedEstimated;

  /// The sum of the foods logged for it, when it was eaten.
  final NutritionFigures? actual;

  bool get consumed =>
      status == MealTrackingStatus.eaten ||
      status == MealTrackingStatus.modified;
}

/// The day's consumption — the same basis vocabulary as `ConsumedBasis`.
class DayConsumed {
  const DayConsumed({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.basis,
    required this.estimated,
  });

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// `logged` · `tickedPlanMeals` · `nothingLogged`.
  final String basis;
  final bool estimated;
}

/// The day's recorded target, when the user had one that day.
class DayTarget {
  const DayTarget({required this.calories, this.proteinG});

  final double calories;
  final double? proteinG;
}

class DietDayRecord {
  const DietDayRecord({
    required this.dayKey,
    required this.planName,
    required this.planReconstructed,
    required this.target,
    required this.meals,
    required this.consumed,
    required this.planned,
    required this.unplanned,
    required this.unplannedCount,
  });

  /// `yyyy-MM-dd` — the user's local calendar day.
  final String dayKey;
  final String? planName;

  /// The day was first recorded after it ended, so its plan side is the plan
  /// as it is now, not as it was then. Shown, never hidden.
  final bool planReconstructed;
  final DayTarget? target;

  /// In plan order.
  final List<MealTrackingRecord> meals;
  final DayConsumed consumed;
  final NutritionFigures planned;

  /// Everything eaten outside the day's ticked meals.
  final NutritionFigures unplanned;
  final int unplannedCount;

  DateTime get day {
    final p = dayKey.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  Iterable<MealTrackingRecord> get _countedMeals =>
      meals.where((m) => !m.isSupplement && m.planned != null);

  int get mealsPlanned => _countedMeals.length;
  int get mealsConsumed => _countedMeals.where((m) => m.consumed).length;
  int count(MealTrackingStatus s) =>
      _countedMeals.where((m) => m.status == s).length;

  /// Parses a stored record, or null when it can't be read as one — a
  /// malformed document is dropped, never rendered as zeros.
  static DietDayRecord? fromMap(Map<String, dynamic> data) {
    final dayKey = data['dayKey'];
    final consumed = data['consumed'];
    if (dayKey is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dayKey) ||
        consumed is! Map) {
      return null;
    }
    final plan = data['plan'];
    final targets = data['targets'];
    final unplanned = data['unplanned'];
    final meals = <MealTrackingRecord>[];
    for (final raw in (data['meals'] as List?) ?? const []) {
      if (raw is! Map || raw['mealId'] is! String) continue;
      final planned = raw['planned'];
      meals.add(
        MealTrackingRecord(
          mealId: raw['mealId'] as String,
          label: (raw['label'] as String?) ?? '',
          order: (raw['order'] as num?)?.toInt() ?? meals.length,
          isSupplement: raw['isSupplement'] == true,
          status: _statusFrom(raw['status']),
          planned: NutritionFigures.fromMap(planned),
          plannedEstimated: planned is Map && planned['estimated'] == true,
          actual: NutritionFigures.fromMap(raw['actual']),
        ),
      );
    }
    meals.sort((a, b) => a.order.compareTo(b.order));
    final calories = targets is Map ? _num(targets['calories']) : null;
    return DietDayRecord(
      dayKey: dayKey,
      planName: plan is Map ? plan['name'] as String? : null,
      planReconstructed: data['plannedReconstructed'] == true,
      target: calories == null
          ? null
          : DayTarget(
              calories: calories,
              proteinG: _num((targets as Map)['proteinG']),
            ),
      meals: meals,
      consumed: DayConsumed(
        kcal: _num(consumed['kcal']) ?? 0,
        proteinG: _num(consumed['proteinG']) ?? 0,
        carbsG: _num(consumed['carbsG']) ?? 0,
        fatG: _num(consumed['fatG']) ?? 0,
        basis: (consumed['basis'] as String?) ?? 'nothingLogged',
        estimated: consumed['estimated'] == true,
      ),
      planned:
          NutritionFigures.fromMap(data['planned']) ?? const NutritionFigures(),
      unplanned:
          NutritionFigures.fromMap(unplanned) ?? const NutritionFigures(),
      unplannedCount: unplanned is Map
          ? (unplanned['count'] as num?)?.toInt() ?? 0
          : 0,
    );
  }
}
