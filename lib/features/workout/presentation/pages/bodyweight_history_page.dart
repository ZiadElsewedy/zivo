import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/reactive_state_views.dart';
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
              // The shared error view, not a bare line of text: a failed read
              // says what failed, why it might have, and looks the same here
              // as it does on every other stream-backed surface.
              SizedBox(
                height: 200,
                child: ErrorStateView(message: l(context).workoutBodyweightLoadError),
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
                            color: TrainColors.voiceInk,
                          ),
                        ),
                        if (latest != null)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: 7,
                              bottom: 7,
                            ),
                            child: Text(
                              l(context).workoutUnitKg,
                              style: TrainType.mono(
                                size: 11,
                                weight: FontWeight.w500,
                                tracking: 0.14,
                                color: TrainColors.inkAt(0.35),
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
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 22),
              TrainSectionLabel(l(context).workoutBodyweightAllWeighIns),
              const SizedBox(height: 12),
              // A weigh-in history is a column of one number repeated — the
              // one shape that must NOT be drawn as a stack of separate
              // bordered cards, because the frames end up carrying more ink
              // than the readings inside them.
              TrainListCard(
                rows: [
                  for (final (i, entry) in entries.indexed)
                    RiseIn(
                      delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                      child: _WeighInRow(
                        entry: entry,
                        previous: i + 1 < entries.length
                            ? entries[i + 1]
                            : null,
                      ),
                    ),
                ],
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      child: Row(
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
          const Spacer(),
          Text(
            formatMonthDayCaps(context, entry.loggedAt),
            style: TrainType.mono(
              size: 9.5,
              tracking: 0.08,
              color: TrainColors.inkAt(0.35),
            ),
          ),
          const SizedBox(width: 12),
          // The delta column keeps a fixed width so the readings above and
          // below it stay in one line rather than each finding their own.
          SizedBox(
            width: 44,
            child: delta != null && delta.abs() >= 0.05
                ? Text(
                    '${delta > 0 ? '+' : '−'}${_trimKg(delta.abs())}',
                    textAlign: TextAlign.end,
                    style: TrainType.mono(
                      size: 13,
                      color: delta > 0
                          ? TrainColors.ember
                          : TrainColors.green,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
