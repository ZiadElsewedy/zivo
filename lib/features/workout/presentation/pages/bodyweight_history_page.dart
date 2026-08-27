import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/body_weight_entry.dart';
import '../../domain/weight_trend.dart';
import '../widgets/trend_chart.dart';
import 'workout_stats_pages.dart';

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
          return const StatDrillDownScaffold(
            title: 'Bodyweight',
            children: [
              SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    "Couldn't load weigh-ins.",
                    style: TextStyle(color: AppColors.ink3),
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
          title: 'Bodyweight',
          subtitle: entries.isEmpty ? null : '${entries.length} weigh-ins logged',
          children: [
            RiseIn(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.solar.withValues(alpha: 0.16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          latest == null ? '—' : _trimKg(latest.weightKg),
                          style: AppText.heroNumber.copyWith(
                            fontSize: 40,
                            color: AppColors.ink,
                          ),
                        ),
                        if (latest != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, bottom: 6),
                            child: Text(
                              'kg',
                              style: AppText.meta.copyWith(color: AppColors.ink3),
                            ),
                          ),
                        const Spacer(),
                        if (trend.changeKgOverWindow != null)
                          Text(
                            '${trend.changeKgOverWindow! > 0 ? '+' : ''}'
                            '${_trimKg(trend.changeKgOverWindow!)}kg / 30d',
                            style: AppText.meta.copyWith(
                              fontWeight: FontWeight.w700,
                              color: trend.changeKgOverWindow! > 0
                                  ? AppColors.flareText
                                  : AppColors.pulseText,
                            ),
                          ),
                      ],
                    ),
                    if (trend.series.length >= 2) ...[
                      const SizedBox(height: 14),
                      TrendChart(
                        values: [for (final e in trend.series) e.weightKg],
                        color: AppColors.solar,
                      ),
                    ],
                    if (entries.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Log your first weigh-in to start the trend.',
                        style: AppText.meta.copyWith(color: AppColors.ink3),
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
                  child: _WeighInRow(entry: entry, previous: i + 1 < entries.length ? entries[i + 1] : null),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_trimKg(entry.weightKg)} kg',
                  style: AppText.rowTitle.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDayLabel(entry.loggedAt),
                  style: AppText.meta.copyWith(color: AppColors.ink3),
                ),
              ],
            ),
          ),
          if (delta != null && (delta.abs() >= 0.05))
            Text(
              '${delta > 0 ? '+' : ''}${_trimKg(delta)}',
              style: AppText.rowTitle.copyWith(
                fontWeight: FontWeight.w700,
                color: delta > 0 ? AppColors.flareText : AppColors.pulseText,
              ),
            ),
        ],
      ),
    );
  }
}
