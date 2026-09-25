import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/admin_models.dart';
import '../../domain/admin_repository.dart';
import '../admin_labels.dart';
import '../widgets/admin_ui.dart';

/// The dashboard: one engagement ladder (the thing to read first), then
/// three quiet groups of figures — people, training, AI — and one chart.
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({required this.repository, super.key});

  final AdminRepository repository;

  @override
  Widget build(BuildContext context) {
    return AdminLoader<AdminOverview>(
      load: repository.overview,
      builder: (context, o, reload) => AdminPageFrame(
        title: l(context).adminNavDashboard,
        subtitle: l(
          context,
        ).adminUpdatedAt(formatClockTime(context, o.generatedAt)),
        onRefresh: reload,
        actions: [
          AdminButton(
            label: l(context).adminRefresh,
            icon: AppIcons.refresh,
            onPressed: reload,
          ),
          _RebuildButton(repository: repository, onDone: reload),
        ],
        children: [
          _Ladder(overview: o),
          const SizedBox(height: 44),
          _Groups(overview: o),
          const SizedBox(height: 44),
          AdminGroup(
            title: l(context).adminChartTitle,
            // On a phone the legend goes under the chart; beside the title
            // it would squeeze both.
            trailing: adminSizeOf(context) == AdminSize.compact
                ? null
                : _Legend(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 180, child: _DailyBars(series: o.series)),
                if (adminSizeOf(context) == AdminSize.compact) ...[
                  const SizedBox(height: 14),
                  _Legend(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The engagement ladder: the week's active users set large, and beside it
/// the same population at four horizons as bars against every account —
/// the whole "is anyone using this?" answer in one glance.
class _Ladder extends StatelessWidget {
  const _Ladder({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final s = l(context);
    final wide = adminSizeOf(context) != AdminSize.compact;
    final hero = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          adminCount(context, o.active7d),
          style: TrainType.mono(
            size: wide ? 88 : 64,
            weight: FontWeight.w400,
            tracking: -0.05,
            color: TrainColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          s.adminActive7dLabel,
          style: TrainType.ui(
            size: 15,
            weight: FontWeight.w600,
            color: TrainColors.ink2,
          ),
        ),
      ],
    );
    final total = math.max(o.totalUsers, 1);
    final bars = Column(
      children: [
        _LadderRow(
          label: s.adminReachTotal,
          value: o.totalUsers,
          total: total,
          strength: 0.22,
        ),
        _LadderRow(
          label: s.adminReach30,
          value: o.active30d,
          total: total,
          strength: 0.45,
        ),
        _LadderRow(
          label: s.adminReach7,
          value: o.active7d,
          total: total,
          strength: 1,
          accent: true,
        ),
        _LadderRow(
          label: s.adminReachToday,
          value: o.activeToday,
          total: total,
          strength: 0.7,
          accent: true,
        ),
      ],
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [hero, const SizedBox(height: 24), bars],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(flex: 4, child: hero),
        const SizedBox(width: 40),
        Expanded(flex: 6, child: bars),
      ],
    );
  }
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({
    required this.label,
    required this.value,
    required this.total,
    required this.strength,
    this.accent = false,
  });

  final String label;
  final int value;
  final int total;
  final double strength;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fraction = (value / total).clamp(0.0, 1.0);
    final color = accent
        ? TrainColors.violet.withValues(alpha: strength)
        : TrainColors.inkAt(strength);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TrainType.ui(
                size: 12.5,
                weight: FontWeight.w600,
                color: TrainColors.ink3,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: AlignmentDirectional.centerStart,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  height: 14,
                  width: math.max(c.maxWidth * fraction, 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              adminCount(context, value),
              textAlign: TextAlign.end,
              style: TrainType.mono(size: 13, color: TrainColors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Groups extends StatelessWidget {
  const _Groups({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final s = l(context);
    final planShare = o.totalUsers == 0
        ? 0
        : (o.withWorkoutPlan * 100 / o.totalUsers).round();
    final people = AdminGroup(
      title: s.adminSectionPeople,
      child: AdminFigureGrid(
        minWidth: 130,
        children: [
          AdminFigure(
            value: adminCount(context, o.totalUsers),
            label: s.adminKpiTotalUsers,
          ),
          AdminFigure(
            value: adminCount(context, o.newToday),
            label: s.adminKpiNewToday,
          ),
          AdminFigure(
            value: adminCount(context, o.newThisWeek),
            label: s.adminKpiNewWeek,
          ),
          AdminFigure(
            value: adminCount(context, o.disabled),
            label: s.adminKpiDisabled,
          ),
        ],
      ),
    );
    final training = AdminGroup(
      title: s.adminSectionTraining,
      child: AdminFigureGrid(
        minWidth: 150,
        children: [
          AdminFigure(
            value: adminCount(context, o.withWorkoutPlan),
            label: s.adminKpiWithPlan,
            note: s.adminKpiPlanShare(planShare),
            accent: TrainColors.green,
          ),
          AdminFigure(
            value: adminCount(context, o.workoutsCompletedToday),
            label: s.adminKpiWorkoutsToday,
            accent: TrainColors.green,
          ),
        ],
      ),
    );
    final ai = AdminGroup(
      title: s.adminSectionAi,
      child: AdminFigureGrid(
        minWidth: 130,
        children: [
          AdminFigure(
            value: adminCount(context, o.aiRequestsToday),
            label: s.adminKpiAiToday,
          ),
          AdminFigure(
            value: adminCount(context, o.ai30d.requests),
            label: s.adminKpiAi30,
          ),
          AdminFigure(
            value: adminCompact(context, o.ai30d.tokens),
            label: s.adminKpiTokens30,
          ),
          AdminFigure(
            value: adminUsd(context, o.ai30d.costUsd),
            label: s.adminKpiCost30,
            note: s.adminCostNote,
            accent: TrainColors.amber,
          ),
          AdminFigure(
            value: adminCompact(context, o.aiAllTime.tokens),
            label: s.adminKpiTokensAll,
          ),
        ],
      ),
    );
    if (adminSizeOf(context) == AdminSize.expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: people),
              const SizedBox(width: 40),
              Expanded(flex: 2, child: training),
            ],
          ),
          const SizedBox(height: 40),
          ai,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        people,
        const SizedBox(height: 36),
        training,
        const SizedBox(height: 36),
        ai,
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget key(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TrainType.ui(
            size: 12,
            weight: FontWeight.w600,
            color: TrainColors.ink3,
          ),
        ),
      ],
    );
    return Wrap(
      spacing: 14,
      children: [
        key(TrainColors.green, l(context).adminChartWorkouts),
        key(TrainColors.inkAt(0.28), l(context).adminChartOpens),
      ],
    );
  }
}

/// Paired daily bars: completed workouts (green, training's hue) against
/// app opens (quiet ink) — "they came back" beside "they trained".
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.series});

  final List<AdminDayPoint> series;

  @override
  Widget build(BuildContext context) {
    final peak = series.fold<int>(
      1,
      (m, p) => math.max(m, math.max(p.appOpens, p.workoutsCompleted)),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final p in series)
          Expanded(
            child: Tooltip(
              message:
                  '${formatMonthDay(context, p.day)}\n'
                  '${l(context).adminChartWorkouts}: ${p.workoutsCompleted}\n'
                  '${l(context).adminChartOpens}: ${p.appOpens}',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _bar(p.workoutsCompleted / peak, TrainColors.green),
                        const SizedBox(width: 2),
                        _bar(p.appOpens / peak, TrainColors.inkAt(0.28)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${p.day.day}',
                    style: TrainType.mono(size: 10, color: TrainColors.ink4),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _bar(double f, Color c) => Flexible(
    child: FractionallySizedBox(
      heightFactor: f.clamp(0.015, 1.0),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 12),
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

/// Recounts every account from source data, page by page, reporting
/// progress — for accounts that pre-date the event triggers.
class _RebuildButton extends StatefulWidget {
  const _RebuildButton({required this.repository, required this.onDone});

  final AdminRepository repository;
  final Future<void> Function() onDone;

  @override
  State<_RebuildButton> createState() => _RebuildButtonState();
}

class _RebuildButtonState extends State<_RebuildButton> {
  int? _processed;

  Future<void> _run() async {
    if (_processed != null) return;
    setState(() => _processed = 0);
    String? token;
    try {
      do {
        final page = await widget.repository.rebuildSummaries(pageToken: token);
        token = page.nextPageToken;
        if (!mounted) return;
        setState(() => _processed = _processed! + page.processed);
      } while (token != null);
      if (!mounted) return;
      showZivoToast(
        context,
        l(context).adminRebuildDone(_processed!),
        kind: ToastKind.success,
      );
      await widget.onDone();
    } on AdminFailure catch (e) {
      if (mounted) showZivoToast(context, e.message, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _processed = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _processed != null;
    return Tooltip(
      message: l(context).adminRebuildHint,
      child: AdminButton(
        label: running
            ? l(context).adminRebuildRunning(_processed!)
            : l(context).adminRebuild,
        icon: AppIcons.build,
        onPressed: running ? null : _run,
      ),
    );
  }
}
