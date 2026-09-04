import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/body_weight_entry.dart';
import '../../domain/weight_trend.dart';
import 'workout_stats_pages.dart';
import '../../../../core/util/date_format.dart';
import '../../../../l10n/l10n.dart';

/// The Bodyweight tile's page: the full weigh-in history — trend chart,
/// 30-day delta, and every entry newest first with its change vs. the
/// previous weigh-in — plus the same quick log sheet the dashboard uses.
class BodyweightHistoryPage extends StatelessWidget {
  const BodyweightHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bodyWeight = AppScope.of(context).bodyWeight;
    return StreamBuilder<List<BodyWeightEntry>>(
      stream: bodyWeight?.watchAll() ?? const Stream.empty(),
      initialData: bodyWeight?.current ?? const <BodyWeightEntry>[],
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StatDrillDownScaffold(
            title: l(context).workoutBodyweight,
            children: [
              SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    l(context).workoutBodyweightLoadError,
                    style: const TextStyle(color: TrainColors.ink4),
                  ),
                ),
              ),
            ],
          );
        }
        final entries = [...(snapshot.data ?? const <BodyWeightEntry>[])]
          ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
        final trend = computeWeightTrend(entries: entries, now: DateTime.now());
        final latest = trend.latest;
        return StatDrillDownScaffold(
          title: l(context).workoutBodyweight,
          subtitle: entries.isEmpty
              ? null
              : l(context).workoutWeighInsLogged(entries.length),
          children: [
            RiseIn(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: TrainColors.cardGradient,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: TrainColors.green.withValues(alpha: 0.20),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          latest == null ? '—' : _trimKg(latest.weightKg),
                          style: TrainType.mono(
                            size: 40,
                            weight: FontWeight.w300,
                            tracking: -0.05,
                            color: const Color(0xFFF9F9F5),
                          ),
                        ),
                        if (latest != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 7, bottom: 7),
                            child: Text(
                              l(context).workoutUnitKg,
                              style: TrainType.mono(
                                size: 11,
                                weight: FontWeight.w500,
                                tracking: 0.14,
                                color: const Color(0x59F4F4F0),
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (trend.changeKgOverWindow != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            // A delta always states its baseline (identity §7).
                            child: Text(
                              l(context).workoutBodyweightChange30d(
                                '${trend.changeKgOverWindow! > 0 ? '+' : '−'}'
                                '${_trimKg(trend.changeKgOverWindow!.abs())}',
                              ),
                              style: TrainType.caption(
                                size: 9,
                                tracking: 0.12,
                                weight: FontWeight.w600,
                                color: trend.changeKgOverWindow! > 0
                                    ? TrainColors.ember
                                    : TrainColors.green,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (trend.series.length >= 2) ...[
                      const SizedBox(height: 14),
                      TrainAreaChart(
                        values: [for (final e in trend.series) e.weightKg],
                        color: TrainColors.green,
                      ),
                    ],
                    if (entries.isEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        l(context).workoutBodyweightEmpty,
                        style: TrainType.ui(
                          size: 12.5,
                          weight: FontWeight.w400,
                          color: TrainColors.ink4,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            for (final (i, entry) in entries.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RiseIn(
                  delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                  child: _WeighInRow(
                    entry: entry,
                    previous: i + 1 < entries.length ? entries[i + 1] : null,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _trimKg(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// One weigh-in row: value, when, and the delta vs. the entry before it.
class _WeighInRow extends StatelessWidget {
  const _WeighInRow({required this.entry, this.previous});

  final BodyWeightEntry entry;
  final BodyWeightEntry? previous;

  @override
  Widget build(BuildContext context) {
    final delta = previous == null ? null : entry.weightKg - previous!.weightKg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _trimKg(entry.weightKg),
                      style: TrainType.mono(size: 15, color: TrainColors.ink),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      l(context).workoutUnitKg,
                      style: TrainType.caption(
                        size: 8.5,
                        tracking: 0.14,
                        color: TrainColors.ink4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  formatMonthDayCaps(context, entry.loggedAt),
                  style: TrainType.mono(
                    size: 9.5,
                    tracking: 0.08,
                    color: const Color(0x59F4F4F0),
                  ),
                ),
              ],
            ),
          ),
          if (delta != null && (delta.abs() >= 0.05))
            Text(
              '${delta > 0 ? '+' : '−'}${_trimKg(delta.abs())}',
              style: TrainType.mono(
                size: 13,
                color: delta > 0 ? TrainColors.ember : TrainColors.green,
              ),
            ),
        ],
      ),
    );
  }
}
