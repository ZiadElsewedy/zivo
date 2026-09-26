import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/diet_day_record.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_state.dart';
import '../../domain/nutrition/food_log_entry.dart';
import '../diet_labels.dart';

/// How far back the history list reads: two weeks of one small record each.
const int kDietHistoryDays = 14;

/// The day-by-day history: what was planned and what happened, newest first.
///
/// Reads the server's daily records (`dietDays`) — one small document per
/// day, never the log rows behind them. A day with nothing recorded has no
/// record and no row: it is absent, not a day of zero.
class DietHistoryPage extends StatefulWidget {
  const DietHistoryPage({super.key});

  @override
  State<DietHistoryPage> createState() => _DietHistoryPageState();
}

class _DietHistoryPageState extends State<DietHistoryPage> {
  Stream<List<DietDayRecord>>? _days;
  late final DateTime _now = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final today = DateTime(_now.year, _now.month, _now.day);
    _days ??= AppScope.of(context).diet.watchDietDays(
      from: today.subtract(const Duration(days: kDietHistoryDays - 1)),
      to: today,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TrainScreen(
      tint: TrainColors.dietTint,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              12,
              AppSpacing.screen,
              0,
            ),
            child: TrainPageHeader(title: l(context).dietHistoryTitle),
          ),
          Expanded(
            child: StreamBuilder<List<DietDayRecord>>(
              stream: _days,
              builder: (context, snapshot) {
                final days = (snapshot.data ?? const <DietDayRecord>[]).reversed
                    .toList();
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    18,
                    AppSpacing.screen,
                    TrainBottomInset.of(context),
                  ),
                  children: [
                    if (snapshot.hasData && days.isEmpty)
                      Text(
                        l(context).dietHistoryEmpty,
                        key: const Key('diet-history-empty'),
                        style: AppText.body.copyWith(color: TrainColors.ink3),
                      ),
                    for (final day in days)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _DayRow(
                          record: day,
                          label: dietDayLabel(context, day.day, _now),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DietDayPage(
                                record: day,
                                title: dietDayLabel(context, day.day, _now),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Today" / "Yesterday" / "Tue, Sep 23".
String dietDayLabel(BuildContext context, DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return l(context).dateToday;
  if (day == today.subtract(const Duration(days: 1))) {
    return l(context).dateYesterday;
  }
  return formatWeekdayDate(context, day);
}

ConsumedBasis _basis(DayConsumed c) => ConsumedBasis.values.firstWhere(
  (b) => b.name == c.basis,
  orElse: () => ConsumedBasis.nothingLogged,
);

String _kcal(BuildContext context, double v, {bool estimated = false}) =>
    ltrFor(context, '${approx(estimated)}${v.round()}');

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.record,
    required this.label,
    required this.onTap,
  });

  final DietDayRecord record;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final skipped = record.count(MealTrackingStatus.skipped);
    final meals = [
      if (record.mealsPlanned > 0)
        strings.dietHistoryMeals(record.mealsConsumed, record.mealsPlanned),
      if (skipped > 0) strings.dietSkippedCount(skipped),
    ].join(' · ');
    return PressableScale(
      scale: 0.99,
      child: GestureDetector(
        key: Key('diet-history-day-${record.dayKey}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TrainCard(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppText.rowTitle),
                    if (meals.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        ltrFor(context, meals),
                        style: AppText.meta.copyWith(color: TrainColors.ink3),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_kcal(context, record.consumed.kcal, estimated: record.consumed.estimated)} ${strings.unitKcal}',
                    style: TrainType.ui(
                      size: 15,
                      weight: FontWeight.w700,
                      color: TrainColors.inkPlain,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // A consumed figure always travels with what it's based on.
                  Text(
                    consumedBasisShortText(context, _basis(record.consumed)),
                    style: AppText.meta.copyWith(color: TrainColors.ink4),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: TrainColors.ink3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One past day: consumed against that day's target, each planned meal with
/// what happened to it, and what was eaten outside the plan.
class DietDayPage extends StatefulWidget {
  const DietDayPage({super.key, required this.record, required this.title});

  final DietDayRecord record;
  final String title;

  @override
  State<DietDayPage> createState() => _DietDayPageState();
}

class _DietDayPageState extends State<DietDayPage> {
  Stream<List<FoodLogEntry>>? _log;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _log ??= AppScope.of(context).diet.watchFoodLog(widget.record.day);
  }

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final r = widget.record;
    final c = r.consumed;
    final eatenMeals = {
      for (final m in r.meals)
        if (m.consumed) m.mealId,
    };
    return TrainScreen(
      tint: TrainColors.dietTint,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              12,
              AppSpacing.screen,
              0,
            ),
            child: TrainPageHeader(title: widget.title),
          ),
          Expanded(
            child: StreamBuilder<List<FoodLogEntry>>(
              stream: _log,
              initialData: const <FoodLogEntry>[],
              builder: (context, snapshot) {
                final offPlan = (snapshot.data ?? const <FoodLogEntry>[])
                    .where(
                      (e) =>
                          e.origin == FoodLogOrigin.logged ||
                          !eatenMeals.contains(e.mealId),
                    )
                    .toList();
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    18,
                    AppSpacing.screen,
                    TrainBottomInset.of(context),
                  ),
                  children: [
                    Text(
                      '${_kcal(context, c.kcal, estimated: c.estimated)} ${strings.unitKcal}',
                      key: const Key('diet-day-consumed'),
                      style: TrainType.ui(
                        size: 30,
                        weight: FontWeight.w800,
                        color: TrainColors.inkPlain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        consumedBasisShortText(context, _basis(c)),
                        if (r.target != null)
                          strings.dietDayOfTarget(
                            ltrFor(context, '${r.target!.calories.round()}'),
                          ),
                      ].join(' · '),
                      style: AppText.meta.copyWith(color: TrainColors.ink3),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ltrFor(
                        context,
                        'P ${trimNumber(c.proteinG)}g · C ${trimNumber(c.carbsG)}g · F ${trimNumber(c.fatG)}g',
                      ),
                      style: AppText.meta.copyWith(color: TrainColors.ink4),
                    ),
                    if (r.planReconstructed) ...[
                      const SizedBox(height: 12),
                      Text(
                        strings.dietPlanReconstructed,
                        key: const Key('diet-day-reconstructed'),
                        style: AppText.meta.copyWith(color: TrainColors.ink3),
                      ),
                    ],
                    if (r.meals.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.l),
                      TrainSectionLabel(
                        r.planName == null ? '' : isolate(r.planName!),
                      ),
                      const SizedBox(height: AppSpacing.m),
                      TrainListCard(
                        rows: [
                          for (final m in r.meals) _MealStatusRow(meal: m),
                        ],
                      ),
                    ],
                    if (offPlan.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.l),
                      TrainSectionLabel(
                        strings.dietOffPlan,
                        trailing: '${offPlan.length}',
                      ),
                      const SizedBox(height: AppSpacing.m),
                      TrainListCard(
                        rows: [for (final e in offPlan) _FoodRow(entry: e)],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String mealStatusText(BuildContext context, MealTrackingStatus s) =>
    switch (s) {
      MealTrackingStatus.eaten => l(context).dietMealStatusEaten,
      MealTrackingStatus.modified => l(context).dietMealStatusModified,
      MealTrackingStatus.skipped => l(context).dietMealStatusSkipped,
      MealTrackingStatus.unmarked => l(context).dietMealStatusUnmarked,
    };

class _MealStatusRow extends StatelessWidget {
  const _MealStatusRow({required this.meal});

  final MealTrackingRecord meal;

  @override
  Widget build(BuildContext context) {
    final planned = meal.planned?.kcal;
    final actual = meal.actual?.kcal;
    final figures = [
      if (planned != null)
        l(context).dietDayPlannedKcal(
          _kcal(context, planned, estimated: meal.plannedEstimated),
        ),
      // What was actually eaten, only when it differs from the plan.
      if (actual != null &&
          planned != null &&
          actual.round() != planned.round())
        '→ ${_kcal(context, actual)}',
    ].join(' ');
    final done = meal.consumed;
    return Padding(
      key: Key('diet-day-meal-${meal.mealId}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : meal.status == MealTrackingStatus.skipped
                ? Icons.remove_circle_outline_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: done ? TrainColors.green : TrainColors.ink4,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.label.isEmpty ? '—' : isolate(meal.label),
                  style: AppText.rowTitle,
                ),
                if (figures.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    ltrFor(context, figures),
                    style: AppText.meta.copyWith(color: TrainColors.ink4),
                  ),
                ],
              ],
            ),
          ),
          Text(
            mealStatusText(context, meal.status),
            style: AppText.meta.copyWith(
              color: done ? TrainColors.green : TrainColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.entry});

  final FoodLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isolate(entry.foodName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.rowTitle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            ltrFor(
              context,
              '${trimNumber(entry.quantity)} ${entry.unit} · '
              '${approx(entry.estimated)}${entry.kcal} ${l(context).unitKcal}',
            ),
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
        ],
      ),
    );
  }
}
