import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/scope/app_scope.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/train_tokens.dart';
import '../../../core/util/money.dart';
import '../../../core/util/time_ago.dart';
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
import '../../expenses/domain/expense_category.dart';
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
import '../../workout/domain/session_status.dart';
import '../../workout/domain/up_next_selection.dart';
import '../../workout/domain/workout_plan.dart';
import '../../auth/presentation/pages/settings_page.dart';
import '../../workout/presentation/pages/workout_dashboard_page.dart';

/// The Hub — a light dashboard into each module's depth. A two-column grid
/// of premium module cards, each with a glowing gradient icon chip in its
/// module colour, a barely-there hue wash bleeding into the card's corner,
/// and a live stat line reading straight from that module's own repository
/// (see each `_XTile`) — a snapshot of "what's happening in each area of my
/// life right now", not just a launcher.
///
/// Not one of the design handoff's eleven screens, but it is the doorway
/// into four of them — so it runs on the same material: the green screen
/// wash, single-hue 13%-tint icon tiles instead of glowing gradient chips,
/// mono captions, and the handoff's list rows for Recent. A launcher in the
/// old warm v2 skin would have been the one surface that didn't belong to
/// the world it opens into.
class HubPage extends StatelessWidget {
  const HubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return DecoratedBox(
      // The one soft radial glow this surface gets — the same green wash the
      // Workout hub and Diet carry, since this is where they're opened from.
      decoration: const BoxDecoration(gradient: TrainColors.hubTint),
      child: Stack(
        children: [
          // The page is a single top-aligned scroll view: header, then the grid
          // directly beneath it. The grid is shrink-wrapped (`shrinkWrap: true`
          // + `NeverScrollableScrollPhysics`) so it sizes to its own content —
          // GridView.count derives row height from tile width alone, so left in
          // an `Expanded` its scroll viewport stretched taller than its content
          // and left a large dead band above the nav; shrink-wrapping removes
          // that. The outer `SingleChildScrollView` is the only scroller, so on
          // a short device (or a large text scale) the whole thing scrolls
          // naturally with nothing clipped. The bottom nav lives in
          // `HomeShell`'s Scaffold, independent of this content; because
          // `extendBody: true` draws the page behind it, the bottom scroll
          // padding reserves the bottom object's exact rendered height
          // (`BottomChrome`, safe-area inset and the fused now-playing strip
          // included) so the last row always clears it with a small,
          // consistent breathing room. Reserving the nav alone used to leave
          // the last tile behind the music strip whenever a track was on.
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screen,
                media.padding.top + 24,
                AppSpacing.screen,
                BottomChrome.of(context) + AppSpacing.s,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Header(),
                  const SizedBox(height: 18),
                  // The full "Start Workout" training card lives on Today (and
                  // the Workout dashboard) — the Hub deliberately doesn't
                  // duplicate it here, leading with the module grid instead.
                  // The _WorkoutTile below still surfaces the up-next day.
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    // The tiles lost their chevron with the redesign, so the
                    // old 1.05 ratio left a band of dead space between the
                    // icon tile and the label. 1.22 still clears a two-line
                    // stat at a large text scale without the hollow middle.
                    childAspectRatio: 1.22,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: const [
                      _WorkoutTile(),
                      _DietTile(),
                      _ExpensesTile(),
                      _MomentsTile(),
                    ],
                  ),
                  const _ConnectedSection(),
                  const _RecentSection(),
                ],
              ),
            ),
          ),
        ],
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
            formatTodayShort(DateTime.now()),
            style: TrainType.caption(
              size: 9.5,
              tracking: 0.2,
              color: TrainColors.ink4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Hub',
            style: TrainType.ui(
              size: 27,
              weight: FontWeight.w800,
              tracking: -0.025,
              color: TrainColors.ink,
              height: 1,
            ),
          ),
          // The italic-serif aside is gone: Instrument Serif is the ZIVO
          // assistant's voice and nothing else in the app (identity §3), and
          // a launcher doesn't need a tagline to explain four labelled tiles.
        ],
      ),
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
    return RiseIn(
      delay: const Duration(milliseconds: 40),
      child: StreamBuilder<WorkoutPlan?>(
        stream: scope.workoutPlans.watchActivePlan(),
        initialData: scope.workoutPlans.activePlan,
        builder: (context, planSnapshot) {
          final plan = planSnapshot.data;
          if (plan == null) return _shell(context, stat: 'No plan yet');
          return StreamBuilder<LiveSession?>(
            stream: scope.workoutSessions.watchActiveSession(),
            initialData: scope.workoutSessions.activeSession,
            builder: (context, sessionSnapshot) {
              final selection = resolveUpNext(plan, sessionSnapshot.data);
              final day = selection.day;
              final stat = day == null
                  ? 'No plan yet'
                  : selection.resumable != null
                  ? '${day.label} · resume'
                  : '${day.label} · up next';
              return _shell(context, stat: stat);
            },
          );
        },
      ),
    );
  }

  Widget _shell(BuildContext context, {required String stat}) {
    return _ModuleTileShell(
      icon: AppIcons.workout,
      color: TrainColors.neutralMark,
      label: 'Workout',
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
    return RiseIn(
      delay: const Duration(milliseconds: 90),
      child: StreamBuilder<DietPlan?>(
        stream: scope.diet.watchActivePlan(),
        initialData: scope.diet.activePlan,
        builder: (context, planSnapshot) {
          final now = DateTime.now();
          final day = dayForDate(planSnapshot.data, now);
          if (day == null) return _shell(context, stat: 'No plan yet');
          return StreamBuilder<Set<String>>(
            stream: scope.diet.watchConsumed(now),
            initialData: const <String>{},
            builder: (context, consumedSnapshot) {
              final summary = dietDaySummary(
                day,
                consumedSnapshot.data ?? const <String>{},
              );
              return _shell(
                context,
                stat:
                    // "meals" and "left" dropped — the tile is already
                    // labelled "Diet", so "X of Y" reads unambiguously
                    // without the former, and the latter is what actually
                    // pushed this to a 3rd line at a standard phone width
                    // (measured in hub_page_test.dart) — "of 3" vs "3/3"
                    // barely moved the needle, "left" alone was the
                    // difference between fitting in 2 lines and not.
                    '${summary.eaten} of ${summary.total} · '
                    '${approx(summary.kcalLeftEstimated)}${summary.kcalLeft} kcal',
              );
            },
          );
        },
      ),
    );
  }

  Widget _shell(BuildContext context, {required String stat}) {
    return _ModuleTileShell(
      icon: AppIcons.diet,
      color: TrainColors.neutralMark,
      label: 'Diet',
      stat: stat,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const DietPlanPage())),
    );
  }
}

/// Expenses' tile: this week's spend, same `weekTotalMinor` + wallet
/// currency Today's Spending glance reads. Always shows a real number — a
/// week with nothing spent is still a fact, not a "no data yet" case.
class _ExpensesTile extends StatelessWidget {
  const _ExpensesTile();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final expenses = scope.expenses;
    final wallet = scope.wallet;
    return RiseIn(
      delay: const Duration(milliseconds: 140),
      child: StreamBuilder<List<Expense>>(
        stream: expenses.watchAll(),
        initialData: expenses.current,
        builder: (context, snapshot) {
          final weekMinor = weekTotalMinor(
            snapshot.data ?? const <Expense>[],
            DateTime.now(),
          );
          if (wallet == null) {
            return _shell(
              context,
              stat: 'EGP ${formatAmount(weekMinor)} this week',
            );
          }
          return StreamBuilder<Wallet?>(
            stream: wallet.watch(),
            initialData: wallet.current,
            builder: (context, walletSnapshot) {
              final currency = walletSnapshot.data?.currency ?? 'EGP';
              return _shell(
                context,
                stat: '$currency ${formatAmount(weekMinor)} this week',
              );
            },
          );
        },
      ),
    );
  }

  Widget _shell(BuildContext context, {required String stat}) {
    return _ModuleTileShell(
      icon: AppIcons.expenses,
      color: TrainColors.neutralMark,
      label: 'Expenses',
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
    return RiseIn(
      delay: const Duration(milliseconds: 190),
      child: StreamBuilder<List<Moment>>(
        stream: scope.moments.watchAll(),
        initialData: scope.moments.current,
        builder: (context, snapshot) {
          final count = (snapshot.data ?? const <Moment>[]).length;
          final stat = count == 0
              ? 'No moments yet'
              : '$count moment${count == 1 ? '' : 's'}';
          return _ModuleTileShell(
            icon: AppIcons.moments,
            color: TrainColors.neutralMark,
            label: 'Moments',
            stat: stat,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MomentsTimelinePage()),
            ),
          );
        },
      ),
    );
  }
}

/// The shared visual shell for a Hub tile: a gradient-glowing icon chip, the
/// module label, and a live stat line underneath, on a card whose top corner
/// carries a whisper of the module hue. Data-fetching lives entirely in each
/// concrete `_XTile` above — this is presentation only, reused so every tile
/// shares one exact card language.
///
/// The decoration lives on `Ink` (not an inner `Container`) so the InkWell's
/// splash composites over the gradient rather than beneath it.
class _ModuleTileShell extends StatelessWidget {
  const _ModuleTileShell({
    required this.icon,
    required this.color,
    required this.label,
    required this.stat,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: TrainColors.cardGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: TrainColors.hairline),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // A bigger glyph on a lighter plate. At the shared
                  // defaults a neutral tile is a grey block with a grey-
                  // looking glyph on it: the plate and the mark are the same
                  // colour, so neither reads. Letting the glyph grow and the
                  // plate recede makes the module identifiable at a glance
                  // without spending a hue on decoration (see ADR-006).
                  TrainIconTile(
                    icon: icon,
                    accent: color,
                    size: 44,
                    iconSize: 22,
                    radius: 14,
                    fillAlpha: 0.07,
                    borderAlpha: 0.14,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TrainType.ui(
                          size: 16,
                          weight: FontWeight.w700,
                          color: TrainColors.inkPlain,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.3),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        stat.toUpperCase(),
                        style: TrainType.mono(
                          size: 10,
                          tracking: 0.06,
                          color: TrainColors.ink4,
                          height: 1.35,
                        ),
                        // 2 lines, not 1 — a couple of stats (Diet's "X of Y
                        // meals · N kcal left") run long enough to ellipsize
                        // the unit off the end at default text scale on a
                        // standard phone width. The taller 1.05-ratio tile has
                        // the headroom, and the other tiles' shorter stats
                        // just naturally sit on one line.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One thing that happened, from any module — the shared shape [_mergeRecent]
/// folds Workout/Expenses/Moments into before sorting.
class _RecentItem {
  const _RecentItem({
    required this.at,
    required this.icon,
    required this.color,
    required this.text,
    required this.onTap,
  });

  final DateTime at;
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;
}

/// "Recent" — the last few things that happened across Workout, Expenses,
/// and Moments, newest first. Diet is deliberately excluded: `watchConsumed`
/// carries no order/timestamp, and a real cross-day "recently eaten" query
/// would need a new Firestore composite index — real infra, not a
/// client-only add, so it waits for whenever Diet next touches the backend
/// rather than being faked here.
///
/// Three streams the tiles above already pay for, merged client-side (same
/// nested-`StreamBuilder` idiom used everywhere else in this codebase) —
/// nothing renders at all when every source is empty, matching how the rest
/// of the app degrades (Today's own "Get started" card already carries that
/// message; Hub doesn't need to repeat it).
class _RecentSection extends StatelessWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, sessionsSnapshot) {
        return StreamBuilder<List<Expense>>(
          stream: scope.expenses.watchAll(),
          initialData: scope.expenses.current,
          builder: (context, expensesSnapshot) {
            return StreamBuilder<List<Moment>>(
              stream: scope.moments.watchAll(),
              initialData: scope.moments.current,
              builder: (context, momentsSnapshot) {
                final items = _mergeRecent(
                  context,
                  sessions: sessionsSnapshot.data ?? const <LiveSession>[],
                  expenses: expensesSnapshot.data ?? const <Expense>[],
                  moments: momentsSnapshot.data ?? const <Moment>[],
                );
                if (items.isEmpty) return const SizedBox.shrink();
                return RiseIn(
                  delay: const Duration(milliseconds: 240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 11),
                        child: TrainSectionLabel('Recent'),
                      ),
                      Material(
                        // The rows' own InkWell needs a Material ancestor —
                        // Hub has no Scaffold of its own (only HomeShell's,
                        // in production), same reasoning as `_ModuleTileShell`
                        // above.
                        color: const Color(0x08FFFFFF),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: TrainColors.hairline),
                          ),
                          child: Column(
                            children: [
                              for (var i = 0; i < items.length; i++)
                                _RecentRow(
                                  item: items[i],
                                  last: i == items.length - 1,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Folds the three modules' already-loaded lists into one time-sorted,
/// capped list. Pure function of the snapshots (no I/O) so it's cheap to
/// recompute on every rebuild.
List<_RecentItem> _mergeRecent(
  BuildContext context, {
  required List<LiveSession> sessions,
  required List<Expense> expenses,
  required List<Moment> moments,
}) {
  final items = <_RecentItem>[];

  for (final s in sessions) {
    // Only completed sessions read as "activity" — an abandoned one wasn't
    // really a workout, and an active one is already the Workout tile's job.
    final completedAt = s.completedAt;
    if (s.status != SessionStatus.completed || completedAt == null) continue;
    items.add(
      _RecentItem(
        at: completedAt,
        icon: AppIcons.workout,
        color: TrainColors.neutralMark,
        text: 'Completed ${s.dayLabel}',
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WorkoutDashboardPage())),
      ),
    );
  }

  for (final e in expenses) {
    items.add(
      _RecentItem(
        at: e.spentAt,
        icon: AppIcons.expenses,
        color: TrainColors.neutralMark,
        text:
            '${formatAmount(e.amountMinor)} ${e.currency} on '
            '${_expenseCategoryLabel(e.categoryId)}',
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ExpensesListPage())),
      ),
    );
  }

  for (final m in moments) {
    final caption = m.caption.trim();
    items.add(
      _RecentItem(
        at: m.takenAt,
        icon: AppIcons.moments,
        color: TrainColors.neutralMark,
        text: caption.isEmpty
            ? 'Added a moment'
            : (caption.length > 40 ? '${caption.substring(0, 40)}…' : caption),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MomentsTimelinePage())),
      ),
    );
  }

  items.sort((a, b) => b.at.compareTo(a.at));
  return items.take(5).toList(growable: false);
}

/// Maps a stored expense `categoryId` to a display label — built-ins only.
/// A custom category's id is an opaque `microsecondsSinceEpoch` string (see
/// `add_category_sheet.dart`), never a readable slug, so anything not in
/// [kBuiltInCategories] degrades to a generic label rather than leaking a
/// raw id into the row. Deliberately skips `resolveCategory` (which would
/// need the nullable `CategoryRepository` as a 4th stream just to prettify
/// one label in a small activity row).
String _expenseCategoryLabel(String categoryId) {
  for (final category in kBuiltInCategories) {
    if (category.id == categoryId) return category.label;
  }
  return 'Expense';
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.item, required this.last});

  final _RecentItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        item.onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: TrainColors.hairline)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
        child: Row(
          children: [
            TrainIconTile(icon: item.icon, accent: item.color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TrainType.ui(
                  size: 14,
                  weight: FontWeight.w600,
                  color: TrainColors.inkPlain,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              timeAgo(item.at, DateTime.now()).toUpperCase(),
              style: TrainType.caption(
                size: 9,
                tracking: 0.1,
                color: TrainColors.ink4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Hub's "Connected" band — the services ZIVO talks to, with their real
/// brand marks and their **live** state.
///
/// This fills what was a screenful of dead space between the module grid and
/// Recent, and it answers a question the Hub is the natural place to ask: is
/// my music hooked up, are my photos backed up? Both facts previously lived
/// only inside Settings, two taps away, with nothing on the Hub hinting they
/// existed. Each row is a shortcut to the screen that owns the setting.
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
          const TrainSectionLabel('Connected'),
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
            final value = switch (state) {
              MusicConnection.connected =>
                playing == null
                    ? 'CONNECTED'
                    : playing.isPaused
                    ? 'PAUSED'
                    : 'PLAYING',
              MusicConnection.connecting => 'CONNECTING…',
              MusicConnection.authFailed => "COULDN'T CONNECT",
              MusicConnection.needsPremium => 'PREMIUM REQUIRED',
              MusicConnection.noSpotifyApp => 'INSTALL SPOTIFY',
              MusicConnection.disconnected => 'NOT CONNECTED',
            };
            final connected = state == MusicConnection.connected;
            return TrainListRow(
              icon: AppIcons.music,
              // Music is green throughout the app; a disconnected service is
              // a neutral fact, not a warning, so it simply goes quiet.
              accent: connected ? TrainColors.green : TrainColors.ink3,
              label: 'Spotify',
              value: value,
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

/// Google Drive backup, read once per build of this row. `isBackupConnected`
/// is a per-device SharedPreferences fact with no stream behind it, so a
/// [FutureBuilder] is the honest shape — and it resolves fast enough that the
/// row never visibly flickers.
class _DriveRow extends StatelessWidget {
  const _DriveRow({required this.media});

  final MediaService media;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: media.isBackupConnected(),
      builder: (context, snap) {
        final connected = snap.data ?? false;
        return TrainListRow(
          icon: AppIcons.driveCloud,
          accent: connected ? TrainColors.green : TrainColors.ink3,
          iconTile: const _BrandTile(child: GoogleDriveMark(size: 17)),
          label: 'Google Drive',
          value: snap.connectionState == ConnectionState.waiting
              ? ''
              : connected
              ? 'BACKING UP'
              : 'NOT CONNECTED',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const StorageSyncPage()),
          ),
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
