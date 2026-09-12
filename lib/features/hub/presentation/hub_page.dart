import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/scope/app_scope.dart';
import '../../sleep/domain/sleep_night.dart';
import '../../sleep/presentation/pages/sleep_page.dart';
import '../../sleep/presentation/sleep_labels.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/train_tokens.dart';
import '../../../core/util/money.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/rise_in.dart';
import '../../../core/media/media_service.dart';
import '../../../core/media/presentation/storage_sync_page.dart';
import '../../../core/widgets/google_drive_mark.dart';
import '../../../core/widgets/train_surfaces.dart';
import '../../diet/domain/diet_format.dart';
import '../../diet/domain/diet_plan.dart';
import '../../diet/domain/diet_summary.dart';
import '../../diet/presentation/pages/diet_plan_page.dart';
import '../../diet/presentation/today_diet.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/domain/expense_repository.dart';
import '../../expenses/domain/wallet.dart';
import '../../expenses/presentation/pages/expenses_list_page.dart';
import '../../home/presentation/header_builder.dart';
import '../../moments/domain/moment.dart';
import '../../music/domain/music_connection.dart';
import '../../music/domain/music_controller.dart';
import '../../music/domain/now_playing.dart';
import '../../music/music_config.dart';
import '../../moments/presentation/pages/moments_timeline_page.dart';
import '../../shell/presentation/widgets/bottom_chrome.dart';
import '../../workout/domain/live_session.dart';
import '../../workout/domain/up_next_selection.dart';
import '../../workout/domain/workout_plan.dart';
import '../../auth/presentation/pages/settings_page.dart';
import '../../workout/presentation/pages/workout_dashboard_page.dart';
import '../../../l10n/l10n.dart';

/// The Hub — a calm launcher into each module's depth. It reads top-to-bottom
/// as one editorial column, in the app's own material language rather than the
/// old photo grid:
///
/// * **Your areas** — Workout · Diet · Expenses · Moments as compact rows in a
///   single grouped card. Each leads with its owned hue (green training/diet,
///   amber money, ember moments), the localized label, and a live mono stat
///   read straight from that module's repo (see each `_XTile`). Slim, dense,
///   and identical in voice to Today and Settings — no oversized cards.
/// * **Sleep** — the one intentional image on the page: a full-width nocturnal
///   hero, a painted night sky (violet→indigo, a soft moon, faint stars) drawn
///   in the same gradient language as the Sleep screen itself, with last
///   night's duration set over it. Photography earns its place once, here,
///   instead of five competing photos.
/// * **Connected** — the services ZIVO talks to, real brand marks, live state.
///
/// The photo grid this replaced made every card tall and read as a different,
/// stockier app than the rest of ZIVO; the launcher is presentation-only, so
/// feature logic still lives in the feature (each `_XTile` only fetches).
class HubPage extends StatelessWidget {
  const HubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return DecoratedBox(
      // The one soft radial glow this surface gets — the same green wash the
      // Workout hub and Diet carry, since this is where they're opened from.
      decoration: BoxDecoration(gradient: TrainColors.hubTint),
      child: SingleChildScrollView(
        // A single top-aligned scroll view: header, the areas card, the Sleep
        // hero, then the Connected band. `extendBody: true` draws the page
        // behind the shell's floating nav, so the bottom padding reserves the
        // bottom object's exact rendered height (`BottomChrome`, safe-area
        // inset and the fused now-playing strip included) so the last row
        // always clears it with a small, consistent breathing room.
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          media.padding.top + 24,
          AppSpacing.screen,
          BottomChrome.of(context) + AppSpacing.s,
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(),
            SizedBox(height: 22),
            RiseIn(delay: Duration(milliseconds: 40), child: _AreasCard()),
            SizedBox(height: 14),
            RiseIn(delay: Duration(milliseconds: 120), child: _SleepBand()),
            _ConnectedSection(),
          ],
        ),
      ),
    );
  }
}

/// Date eyebrow over the display title — the same editorial cadence Today's
/// header uses, so every dashboard opens with the same voice.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatTodayShort(
              DateTime.now(),
              Localizations.localeOf(context).toLanguageTag(),
            ),
            style: TrainType.caption(
              size: 9.5,
              tracking: 0.2,
              color: TrainColors.ink4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l(context).hubTitle,
            style: TrainType.ui(
              size: 27,
              weight: FontWeight.w800,
              tracking: -0.025,
              color: TrainColors.ink,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// The four action areas in one grouped card — each row a `_ModuleRow` built by
/// its own `_XTile`, separated by an inset hairline so the rules start at the
/// label the way every list card in the app does.
class _AreasCard extends StatelessWidget {
  const _AreasCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: TrainColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: const Column(
        children: [
          _WorkoutTile(),
          _RowDivider(),
          _DietTile(),
          _RowDivider(),
          _ExpensesTile(),
          _RowDivider(),
          _MomentsTile(),
        ],
      ),
    );
  }
}

/// The hairline between two `_ModuleRow`s, inset past the icon column so it
/// begins at the label (directional, so it clears the leading column in Arabic
/// too).
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: _ModuleRow.labelInset),
      child: Divider(height: 1, thickness: 1, color: TrainColors.hairline),
    );
  }
}

/// Workout's tile: the same up-next day + resume/start signal as Today's own
/// Training card (`resolveUpNext`), so Hub can't drift from it.
class _WorkoutTile extends StatelessWidget {
  const _WorkoutTile();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<WorkoutPlan?>(
      stream: scope.workoutPlans.watchActivePlan(),
      initialData: scope.workoutPlans.activePlan,
      builder: (context, planSnapshot) {
        final plan = planSnapshot.data;
        if (plan == null) return _row(context, stat: l(context).hubNoPlanYet);
        return StreamBuilder<LiveSession?>(
          stream: scope.workoutSessions.watchActiveSession(),
          initialData: scope.workoutSessions.activeSession,
          builder: (context, sessionSnapshot) {
            final selection = resolveUpNext(
              plan,
              sessionSnapshot.data,
              // A session left open on Tuesday must not still be offering
              // itself as "resume" on Thursday, in place of the day due.
              now: DateTime.now(),
              maxSessionDuration: AppScope.of(context).maxSessionDuration,
            );
            final day = selection.day;
            // Localized whole, not assembled from a translated word and a
            // separator: an English fragment inside an Arabic paragraph is
            // reordered by the bidi algorithm, which is what turned this
            // line into scrambled text in Arabic.
            final stat = day == null
                ? l(context).hubNoPlanYet
                : selection.resumable != null
                ? l(context).hubWorkoutResume(day.label)
                : l(context).hubWorkoutUpNext(day.label);
            return _row(context, stat: stat);
          },
        );
      },
    );
  }

  Widget _row(BuildContext context, {required String stat}) {
    return _ModuleRow(
      image: 'assets/hub/workout.jpg',
      accent: TrainColors.green,
      label: l(context).hubWorkout,
      stat: stat,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const WorkoutDashboardPage())),
    );
  }
}

/// Diet's tile: today's eaten/kcal-left summary, same `dietDaySummary` the
/// Diet page's own hero and Today's glance row read.
class _DietTile extends StatelessWidget {
  const _DietTile();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<DietPlan?>(
      stream: scope.diet.watchActivePlan(),
      initialData: scope.diet.activePlan,
      builder: (context, planSnapshot) {
        final now = DateTime.now();
        final day = dayForDate(planSnapshot.data, now);
        if (day == null) return _row(context, stat: l(context).hubNoPlanYet);
        return StreamBuilder<Set<String>>(
          stream: scope.diet.watchConsumed(now),
          initialData: const <String>{},
          builder: (context, consumedSnapshot) {
            final summary = dietDaySummary(
              day,
              consumedSnapshot.data ?? const <String>{},
            );
            return _row(
              context,
              // "meals" and "left" dropped — the row is already labelled
              // "Diet", so "X of Y" reads unambiguously without the former,
              // and the latter is what pushed this to a 3rd line at a
              // standard phone width (measured in hub_page_test.dart).
              stat: l(context).hubDietStat(
                summary.eaten,
                summary.total,
                '${approx(summary.kcalLeftEstimated)}${summary.kcalLeft}',
              ),
            );
          },
        );
      },
    );
  }

  Widget _row(BuildContext context, {required String stat}) {
    return _ModuleRow(
      image: 'assets/hub/diet.jpg',
      accent: TrainColors.green,
      label: l(context).hubDiet,
      stat: stat,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const DietPlanPage())),
    );
  }
}

/// Expenses' tile: this week's spend, same `weekTotalMinor` + wallet currency
/// Today's Spending glance reads. Always shows a real number — a week with
/// nothing spent is still a fact, not a "no data yet" case.
class _ExpensesTile extends StatelessWidget {
  const _ExpensesTile();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final expenses = scope.expenses;
    final wallet = scope.wallet;
    return StreamBuilder<List<Expense>>(
      stream: expenses.watchAll(),
      initialData: expenses.current,
      builder: (context, snapshot) {
        final weekMinor = weekTotalMinor(
          snapshot.data ?? const <Expense>[],
          DateTime.now(),
        );
        if (wallet == null) {
          return _row(
            context,
            stat: l(context).hubExpensesStat('EGP ${formatAmount(weekMinor)}'),
          );
        }
        return StreamBuilder<Wallet?>(
          stream: wallet.watch(),
          initialData: wallet.current,
          builder: (context, walletSnapshot) {
            final currency = walletSnapshot.data?.currency ?? 'EGP';
            return _row(
              context,
              stat: l(
                context,
              ).hubExpensesStat('$currency ${formatAmount(weekMinor)}'),
            );
          },
        );
      },
    );
  }

  Widget _row(BuildContext context, {required String stat}) {
    return _ModuleRow(
      image: 'assets/hub/expenses.jpg',
      accent: TrainColors.amber,
      label: l(context).hubExpenses,
      stat: stat,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ExpensesListPage())),
    );
  }
}

/// Moments' tile: a simple honest count — no fabricated "last added X ago"
/// beyond what's actually there.
class _MomentsTile extends StatelessWidget {
  const _MomentsTile();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<Moment>>(
      stream: scope.moments.watchAll(),
      initialData: scope.moments.current,
      builder: (context, snapshot) {
        final count = (snapshot.data ?? const <Moment>[]).length;
        final stat = count == 0
            ? l(context).hubNoMomentsYet
            : l(context).hubMomentsCount(count);
        return _ModuleRow(
          image: 'assets/hub/moments.jpg',
          accent: TrainColors.ember,
          label: l(context).hubMoments,
          stat: stat,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MomentsTimelinePage()),
          ),
        );
      },
    );
  }
}

/// One area row: the module's own photo as a small leading thumbnail, its
/// label, and a live mono stat beneath, with a trailing chevron. Data-fetching
/// lives entirely in each `_XTile` above — this is presentation only, reused so
/// every row shares one exact language.
///
/// The stat sits *under* the label (rather than on the row's trailing edge)
/// so a long line like "Full arm (Day 4) · Up next" wraps within the row
/// instead of being squeezed against the chevron. The photo carries the
/// module's identity; [accent] is kept for the wash the thumbnail falls back to
/// if its asset is ever missing.
class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.image,
    required this.accent,
    required this.label,
    required this.stat,
    required this.onTap,
  });

  final String image;
  final Color accent;
  final String label;
  final String stat;
  final VoidCallback onTap;

  static const double _thumb = 48;

  /// Where the label starts — the thumbnail column's width (padding + thumb +
  /// gap). The [_RowDivider] insets to this so each rule begins at the label.
  static const double labelInset = 16 + _thumb + 13;

  @override
  Widget build(BuildContext context) {
    // Clamp so a large accessibility text scale can't run the two-line stat
    // past a sensible height — the card grows with the text, it just doesn't
    // scale without bound.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              _RowThumb(image: image, accent: accent, size: _thumb),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: scaler,
                      style: TrainType.ui(
                        size: 15.5,
                        weight: FontWeight.w700,
                        color: TrainColors.inkPlain,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stat.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textScaler: scaler,
                      style: TrainType.mono(
                        size: 9.5,
                        tracking: 0.06,
                        color: TrainColors.ink4,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: TrainColors.inkAt(0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A module row's leading photograph — the section image, cover-fit into a
/// small rounded square. Falls back to a hue wash if the asset is ever missing,
/// so the row never shows a broken image slot.
class _RowThumb extends StatelessWidget {
  const _RowThumb({
    required this.image,
    required this.accent,
    required this.size,
  });

  final String image;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          // Decode near the widest the thumb is drawn (×~3 for hi-DPI) rather
          // than at the source's full resolution.
          cacheWidth: 160,
          errorBuilder: (context, error, stack) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.32),
                  accent.withValues(alpha: 0.08),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sleep — last night's duration, with how it was known.
///
/// The stat carries the **method**, not just the figure, for the same reason
/// every sleep surface does: "7h 12m" alone is a claim ZIVO cannot stand
/// behind without saying where it came from (`docs/SLEEP_SYSTEM.md` §11). This
/// is the page's one hero image — a painted night, in Sleep's own violet-blue
/// hue (ADR-010).
class _SleepBand extends StatelessWidget {
  const _SleepBand();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sleep = scope.sleep;
    return StreamBuilder<List<SleepNight>>(
      stream: sleep?.watchNights(),
      initialData: sleep?.current ?? const <SleepNight>[],
      builder: (context, snapshot) {
        final nights = snapshot.data ?? const <SleepNight>[];
        SleepNight? last;
        for (final night in nights) {
          if (night.hasData) {
            last = night;
            break;
          }
        }
        final duration = last == null
            ? null
            : sleepDurationText(context, last.main!.asleepDuration);
        final method = last == null
            ? null
            : sleepMethodLabel(context, last.main!.provenance.method);
        return _SleepHero(
          duration: duration,
          method: method,
          emptyText: l(context).hubNoSleepYet,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SleepPage())),
        );
      },
    );
  }
}

/// The Sleep hero: a full-width nocturnal card. A painted night sky sits
/// behind last night's duration, with a legibility scrim deepening toward the
/// bottom where the figure reads. Always dark — a night is a night, the same
/// way the old photo never themed — so the text is white for vibrancy over it.
class _SleepHero extends StatelessWidget {
  const _SleepHero({
    required this.duration,
    required this.method,
    required this.emptyText,
    required this.onTap,
  });

  /// Last night's asleep duration, or null when there is no night to show.
  final String? duration;

  /// How that duration was known (Apple Health, entered by hand, …).
  final String? method;

  /// What to say in place of a duration when there is no night yet.
  final String emptyText;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    final hasNight = duration != null;
    return PressableScale(
      scale: 0.99,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: 156,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B0D22).withValues(alpha: 0.45),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _NightSkyPainter(glow: TrainColors.sleepGlyph),
                ),
                // Legibility scrim — the figure sits at the bottom-left, so the
                // night deepens there without dimming the moon and stars up top.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00000000),
                        Color(0x00000000),
                        Color(0x66000000),
                      ],
                      stops: [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Icon(
                                  AppIcons.sleep,
                                  size: 18,
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                l(context).hubSleep.toUpperCase(),
                                style: TrainType.caption(
                                  size: 10,
                                  tracking: 0.22,
                                  weight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasNight) ...[
                            Text(
                              duration!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TrainType.mono(
                                size: 27,
                                weight: FontWeight.w600,
                                tracking: -0.01,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              method!.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TrainType.caption(
                                size: 9.5,
                                tracking: 0.14,
                                color: Colors.white.withValues(alpha: 0.62),
                              ),
                            ),
                          ] else
                            Text(
                              emptyText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TrainType.ui(
                                size: 16,
                                weight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.9),
                                height: 1.2,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A painted night: a violet→indigo sky, a low violet aurora, a soft glowing
/// moon and a scatter of faint stars. Deterministic (fixed star field, no
/// per-frame randomness) so it never shimmers between builds, and cheap enough
/// to repaint never.
///
/// The dark base tones are *imagery* — the same licence the old hero photo had
/// to fall outside the token palette — but the [glow] accent is passed in from
/// Sleep's own hue so the illustration stays in the family the Sleep screen
/// uses (ADR-010).
class _NightSkyPainter extends CustomPainter {
  const _NightSkyPainter({required this.glow});

  final Color glow;

  // The star field, as fractions of the card's width/height, each with a
  // radius and an opacity — hand-placed to sit around (not over) the moon.
  static const List<List<double>> _stars = [
    [0.10, 0.24, 1.1, 0.65],
    [0.20, 0.52, 0.9, 0.45],
    [0.30, 0.18, 1.3, 0.80],
    [0.38, 0.40, 0.8, 0.40],
    [0.46, 0.14, 1.0, 0.55],
    [0.52, 0.62, 0.9, 0.50],
    [0.60, 0.30, 0.8, 0.42],
    [0.68, 0.55, 1.1, 0.60],
    [0.90, 0.60, 0.9, 0.48],
    [0.94, 0.30, 1.0, 0.55],
    [0.16, 0.72, 0.8, 0.35],
    [0.74, 0.20, 0.9, 0.5],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Base sky.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B0D22), Color(0xFF15173A), Color(0xFF241F52)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // A low aurora in Sleep's own violet, rising from the bottom-left.
    final auroraCenter = Offset(size.width * 0.16, size.height * 1.08);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [glow.withValues(alpha: 0.34), glow.withValues(alpha: 0.0)],
        ).createShader(
          Rect.fromCircle(center: auroraCenter, radius: size.width * 0.72),
        ),
    );

    // The moon — a soft halo, then the disc.
    final moon = Offset(size.width * 0.84, size.height * 0.30);
    canvas.drawCircle(
      moon,
      50,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.42),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: moon, radius: 50)),
    );
    canvas.drawCircle(moon, 15, Paint()..color = const Color(0xFFF4F1FF));

    // Stars.
    final star = Paint();
    for (final s in _stars) {
      star.color = Colors.white.withValues(alpha: s[3]);
      canvas.drawCircle(Offset(size.width * s[0], size.height * s[1]), s[2], star);
    }
  }

  @override
  bool shouldRepaint(_NightSkyPainter oldDelegate) => oldDelegate.glow != glow;
}

/// The Hub's "Connected" band — the services ZIVO talks to, with their real
/// brand marks and their **live** state.
///
/// It answers a question the Hub is the natural place to ask: is my music
/// hooked up, are my photos backed up? Both facts otherwise live only inside
/// Settings, two taps away. Each row is a shortcut to the screen that owns the
/// setting.
class _ConnectedSection extends StatelessWidget {
  const _ConnectedSection();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final music = kMusicEnabled ? scope.music : null;
    final media = scope.media;
    if (music == null && media == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TrainSectionLabel(l(context).hubConnected),
          const SizedBox(height: 12),
          TrainListCard(
            rows: [
              if (music != null) _SpotifyRow(controller: music),
              if (media != null) _DriveRow(media: media),
            ],
          ),
        ],
      ),
    );
  }
}

/// Spotify's live connection, in the same words Settings uses so the two
/// surfaces can never disagree about what "connected" means.
///
/// The row leads with Spotify's **real brand mark on a neutral plate, always
/// at full colour** — the same treatment the Drive row gets — rather than a
/// generic music glyph that dimmed to near-invisible when disconnected. The
/// connection state is carried entirely by the trailing value, so a
/// not-connected Spotify still shows its icon clearly (the affordance to
/// connect it has to be visible precisely when it isn't connected).
class _SpotifyRow extends StatelessWidget {
  const _SpotifyRow({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MusicConnection>(
      stream: controller.connection,
      initialData: controller.currentConnection,
      builder: (context, connSnap) {
        final state = connSnap.data ?? MusicConnection.disconnected;
        return StreamBuilder<NowPlaying?>(
          stream: controller.nowPlaying,
          initialData: controller.currentNowPlaying,
          builder: (context, nowSnap) {
            final playing = nowSnap.data;
            // Keyed in sentence case and upper-cased at the call site (the
            // band's micro-caps are a type decision, not part of the string):
            // `toUpperCase` is a no-op on Arabic, so one key serves both.
            final value = switch (state) {
              MusicConnection.connected =>
                playing == null
                    ? l(context).connectedConnected
                    : playing.isPaused
                    ? l(context).connectedPaused
                    : l(context).connectedPlaying,
              MusicConnection.connecting => l(context).connectedConnecting,
              MusicConnection.authFailed => l(context).connectedCouldntConnect,
              MusicConnection.needsPremium =>
                l(context).connectedPremiumRequired,
              MusicConnection.noSpotifyApp => l(context).connectedInstallSpotify,
              MusicConnection.disconnected => l(context).connectedNotConnected,
            };
            final connected = state == MusicConnection.connected;
            return TrainListRow(
              icon: AppIcons.music,
              // Music is green throughout the app; the accent tints the state
              // dot, not the always-on brand mark.
              accent: connected ? TrainColors.green : TrainColors.ink3,
              iconTile: const _BrandTile(child: _SpotifyMark(size: 18)),
              label: 'Spotify',
              value: value.toUpperCase(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
            );
          },
        );
      },
    );
  }
}

/// Google Drive backup, watching [MediaService.backupConnected] rather than
/// reading the connection once.
///
/// A one-shot `FutureBuilder` was the wrong shape here and it showed: the Hub
/// is a tab inside the shell's `IndexedStack`, so it stays mounted forever —
/// it is not rebuilt when the user returns from Storage & Sync, and not
/// rebuilt when they switch tabs either. Connecting Drive therefore left this
/// row reading "NOT CONNECTED" until the app was restarted, which is the one
/// thing a status row must never do. The notifier is updated by the service
/// itself on connect/disconnect, so the row follows the fact wherever it is
/// changed from.
///
/// The state lives on disk, so there is nothing synchronous to seed the
/// notifier with: this kicks one read on mount (and again whenever the row
/// comes back into view via [didChangeDependencies], which covers a ZIVO
/// account switch invalidating the connection) and shows nothing at all until
/// that first answer lands, rather than flashing a "NOT CONNECTED" it has not
/// verified.
class _DriveRow extends StatefulWidget {
  const _DriveRow({required this.media});

  final MediaService media;

  @override
  State<_DriveRow> createState() => _DriveRowState();
}

class _DriveRowState extends State<_DriveRow> {
  /// Null until the first read resolves — "we don't know yet", which is a
  /// different thing from "not connected" and reads as an empty value.
  bool? _known;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    await widget.media.isBackupConnected(); // publishes into the notifier
    if (mounted) setState(() => _known = widget.media.backupConnected.value);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.media.backupConnected,
      builder: (context, connected, _) {
        final resolved = _known == null ? null : connected;
        return TrainListRow(
          icon: AppIcons.driveCloud,
          accent: resolved == true ? TrainColors.green : TrainColors.ink3,
          iconTile: const _BrandTile(child: GoogleDriveMark(size: 17)),
          label: 'Google Drive',
          value:
              (resolved == null
                      ? ''
                      : resolved
                      ? l(context).connectedBackingUp
                      : l(context).connectedNotConnected)
                  .toUpperCase(),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StorageSyncPage()),
            );
            // The notifier already covers connect/disconnect done on that
            // page; this re-read covers the rest (a connection revoked from
            // the Google account, say), so returning here is always a
            // refresh — which is what makes a manual refresh control on this
            // band unnecessary.
            if (mounted) await _read();
          },
        );
      },
    );
  }
}

/// A neutral plate for a **brand** mark. Brand marks carry their own colours,
/// so unlike [TrainIconTile] this one never tints them.
class _BrandTile extends StatelessWidget {
  const _BrandTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: child,
    );
  }
}

/// Spotify's brand mark — the bundled icon asset, always at full colour.
class _SpotifyMark extends StatelessWidget {
  const _SpotifyMark({this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/spotify/spotify-icon.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) =>
          Icon(AppIcons.music, size: 16, color: TrainColors.green),
    );
  }
}
