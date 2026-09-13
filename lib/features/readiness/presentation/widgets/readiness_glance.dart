import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../l10n/l10n.dart';
import '../../../home/presentation/widgets/common.dart';
import '../../../sleep/domain/sleep_night.dart';
import '../../../sleep/domain/sleep_targets.dart';
import '../../../sleep/domain/sleep_window.dart';
import '../../../workout/domain/body_weight_entry.dart';
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/weight_trend.dart';
import '../../domain/readiness.dart';
import '../pages/readiness_page.dart';
import '../readiness_labels.dart';

/// The Daily Readiness "call" on Today — the coach opening with one honest
/// train-hard / go-light / rest recommendation, each factor citing its number.
///
/// It composes the SAME streams the other sections read (sessions, sleep,
/// body-weight), so it can never disagree with them, and it **hides itself**
/// when [computeReadiness] returns null — the same rule the sleep glance
/// follows: an absent section is a statement about the data, a zero would be a
/// false statement about the user.
class ReadinessSection extends StatelessWidget {
  const ReadinessSection({this.onOpenAsk, DateTime Function()? now, super.key})
    : now = now ?? DateTime.now;

  /// Switches to the Ask tab so the coach can be asked about the call. Threaded
  /// from Today; when null the "Ask" affordance is simply not shown.
  final VoidCallback? onOpenAsk;

  /// The clock the call is judged against — injectable so a test asserts a
  /// fixed morning rather than whenever it happens to run.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sleep = scope.sleep;
    final bodyWeight = scope.bodyWeight;

    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, sessionsSnap) {
        return StreamBuilder<List<SleepNight>>(
          stream: sleep?.watchNights() ?? const Stream.empty(),
          initialData: sleep?.current ?? const <SleepNight>[],
          builder: (context, nightsSnap) {
            return StreamBuilder<SleepTargets?>(
              stream: sleep?.watchTargets() ?? const Stream.empty(),
              initialData: sleep?.currentTargets,
              builder: (context, targetsSnap) {
                return StreamBuilder<List<BodyWeightEntry>>(
                  stream: bodyWeight?.watchAll() ?? const Stream.empty(),
                  initialData: bodyWeight?.current ?? const <BodyWeightEntry>[],
                  builder: (context, weightSnap) {
                    return _build(
                      context,
                      sessions: sessionsSnap.data ?? const <LiveSession>[],
                      nights: nightsSnap.data ?? const <SleepNight>[],
                      targets: targetsSnap.data,
                      weightEntries:
                          weightSnap.data ?? const <BodyWeightEntry>[],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _build(
    BuildContext context, {
    required List<LiveSession> sessions,
    required List<SleepNight> nights,
    required SleepTargets? targets,
    required List<BodyWeightEntry> weightEntries,
  }) {
    final at = now();
    final lastNight = SleepWindow.latestWithData(nights);
    final weight = weightEntries.isEmpty
        ? null
        : computeWeightTrend(entries: weightEntries, now: at);

    final readiness = computeReadiness(
      now: at,
      lastNight: lastNight,
      fallbackTargets: targets,
      sessions: sessions,
      weight: weight,
    );
    if (readiness == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l(context).readinessTitle),
        PressableScale(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ReadinessPage(readiness: readiness, onOpenAsk: onOpenAsk),
                ),
              );
            },
            child: _ReadinessCard(readiness: readiness),
          ),
        ),
      ],
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.readiness});

  final Readiness readiness;

  @override
  Widget build(BuildContext context) {
    final verdict = readinessVerdictCopy(context, readiness.verdict);
    // The top two factors on the card; the rest live on the detail page.
    final shown = readiness.factors.take(2).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: TrainColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: verdict.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(AppIcons.readiness, size: 21, color: verdict.color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verdict.word,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TrainType.ui(
                        size: 21,
                        weight: FontWeight.w800,
                        tracking: -0.02,
                        color: verdict.color,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      verdict.blurb,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(
                        fontSize: 12.5,
                        height: 1.25,
                        color: TrainColors.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: TrainColors.ink3,
              ),
            ],
          ),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: TrainColors.hairline),
            const SizedBox(height: 12),
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              ReadinessFactorRow(factor: shown[i]),
            ],
          ],
        ],
      ),
    );
  }
}

/// One factor line — icon, reason, and the number it cites. Shared by the card
/// and the detail page so a factor reads identically in both.
class ReadinessFactorRow extends StatelessWidget {
  const ReadinessFactorRow({required this.factor, super.key});

  final ReadinessFactor factor;

  @override
  Widget build(BuildContext context) {
    final copy = readinessFactorCopy(context, factor);
    return Row(
      children: [
        Icon(copy.icon, size: 15, color: copy.color),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            copy.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.rowTitle.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: TrainColors.ink,
            ),
          ),
        ),
        if (copy.detail.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            copy.detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TrainType.caption(
              size: 11,
              tracking: 0.1,
              color: TrainColors.ink3,
            ),
          ),
        ],
      ],
    );
  }
}
