import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/scope/app_scope.dart';
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

/// The Hub — a light dashboard into each module's depth. A two-column grid of
/// premium module cards, each led by the module's own hero photograph with a
/// hue-tinted icon chip and a live stat line read straight from that module's
/// repository (see each `_XTile`) — a snapshot of "what's happening in each
/// area of my life right now", not just a launcher.
///
/// The photographs give the four modules an instant, distinct identity the
/// old neutral-icon grid couldn't: each card carries a cropped, unified image
/// (the source's baked-in title is cropped off in `assets/hub/` so the app's
/// own localized label reads over clean photography), melting into the card
/// surface along a bottom fade so the seam reads as depth. The icon chips then
/// echo each area's owned hue — green for training and diet, amber for money,
/// ember for moments — so the grid differentiates by image *and* colour while
/// staying inside the four-hue system (ADR-006). Below the grid, the
/// **Connected** band shows the services ZIVO talks to with their real brand
/// marks and live state.
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
          // The page is a single top-aligned scroll view: header, then the
          // grid, then the Connected band. The grid is shrink-wrapped
          // (`shrinkWrap: true` + `NeverScrollableScrollPhysics`) so it sizes
          // to its own content and the outer `SingleChildScrollView` is the
          // only scroller — on a short device (or a large text scale) the whole
          // thing scrolls naturally with nothing clipped. `extendBody: true`
          // draws the page behind the shell's floating nav, so the bottom
          // padding reserves the bottom object's exact rendered height
          // (`BottomChrome`, safe-area inset and the fused now-playing strip
          // included) so the last row always clears it with a small, consistent
          // breathing room.
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
                  const SizedBox(height: 20),
                  // The full "Start Workout" training card lives on Today (and
                  // the Workout dashboard) — the Hub deliberately doesn't
                  // duplicate it here, leading with the module grid instead.
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    // The cards carry a fixed-height hero photo plus a
                    // flex-centred content block, so they're taller than wide.
                    // 0.82 leaves the content (label + up-to-two-line stat,
                    // clamped to 1.3×) clear room even on the narrowest phone at
                    // a large accessibility scale; the centring absorbs the
                    // slack at the default scale so there's no hollow gap.
                    childAspectRatio: 0.82,
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
          // assistant's voice and nothing else in the app (identity §3), and a
          // launcher doesn't need a tagline to explain four labelled tiles.
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
          if (plan == null) return _card(context, stat: l(context).hubNoPlanYet);
          return StreamBuilder<LiveSession?>(
            stream: scope.workoutSessions.watchActiveSession(),
            initialData: scope.workoutSessions.activeSession,
            builder: (context, sessionSnapshot) {
              final selection = resolveUpNext(plan, sessionSnapshot.data);
              final day = selection.day;
              final stat = day == null
                  ? l(context).hubNoPlanYet
                  : selection.resumable != null
                  ? '${day.label} · resume'
                  : '${day.label} · up next';
              return _card(context, stat: stat);
            },
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, {required String stat}) {
    return _ModuleCard(
      image: 'assets/hub/workout.jpg',
      icon: AppIcons.workout,
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
    return RiseIn(
      delay: const Duration(milliseconds: 90),
      child: StreamBuilder<DietPlan?>(
        stream: scope.diet.watchActivePlan(),
        initialData: scope.diet.activePlan,
        builder: (context, planSnapshot) {
          final now = DateTime.now();
          final day = dayForDate(planSnapshot.data, now);
          if (day == null) return _card(context, stat: l(context).hubNoPlanYet);
          return StreamBuilder<Set<String>>(
            stream: scope.diet.watchConsumed(now),
            initialData: const <String>{},
            builder: (context, consumedSnapshot) {
              final summary = dietDaySummary(
                day,
                consumedSnapshot.data ?? const <String>{},
              );
              return _card(
                context,
                // "meals" and "left" dropped — the card is already labelled
                // "Diet", so "X of Y" reads unambiguously without the former,
                // and the latter is what pushed this to a 3rd line at a
                // standard phone width (measured in hub_page_test.dart).
                stat:
                    '${summary.eaten} of ${summary.total} · '
                    '${approx(summary.kcalLeftEstimated)}${summary.kcalLeft} kcal',
              );
            },
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, {required String stat}) {
    return _ModuleCard(
      image: 'assets/hub/diet.jpg',
      icon: AppIcons.diet,
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
            return _card(
              context,
              stat: 'EGP ${formatAmount(weekMinor)} this week',
            );
          }
          return StreamBuilder<Wallet?>(
            stream: wallet.watch(),
            initialData: wallet.current,
            builder: (context, walletSnapshot) {
              final currency = walletSnapshot.data?.currency ?? 'EGP';
              return _card(
                context,
                stat: '$currency ${formatAmount(weekMinor)} this week',
              );
            },
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, {required String stat}) {
    return _ModuleCard(
      image: 'assets/hub/expenses.jpg',
      icon: AppIcons.expenses,
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
    return RiseIn(
      delay: const Duration(milliseconds: 190),
      child: StreamBuilder<List<Moment>>(
        stream: scope.moments.watchAll(),
        initialData: scope.moments.current,
        builder: (context, snapshot) {
          final count = (snapshot.data ?? const <Moment>[]).length;
          final stat = count == 0
              ? l(context).hubNoMomentsYet
              : '$count moment${count == 1 ? '' : 's'}';
          return _ModuleCard(
            image: 'assets/hub/moments.jpg',
            icon: AppIcons.moments,
            accent: TrainColors.ember,
            label: l(context).hubMoments,
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

/// The shared visual shell for a Hub module card: a hero photograph up top, a
/// hue-tinted icon chip, the module label, and a live stat line underneath.
/// Data-fetching lives entirely in each concrete `_XTile` above — this is
/// presentation only, reused so every card shares one exact language.
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.image,
    required this.icon,
    required this.accent,
    required this.label,
    required this.stat,
    required this.onTap,
  });

  final String image;
  final IconData icon;
  final Color accent;
  final String label;
  final String stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Both the label and the stat are clamped so a large accessibility text
    // scale can't blow past the card's fixed height (the hero photo is a fixed
    // 92px, so the content block owns the rest).
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return PressableScale(
      scale: 0.985,
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
            // Clip so the photo's top corners follow the card radius; the 1px
            // hairline from the Ink decoration reads just outside it.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroPhoto(image: image, accent: accent),
                  // The content owns whatever height the fixed hero leaves, and
                  // sits centred within it — so a default-scale card reads as
                  // balanced rather than bottom-heavy, while a large text scale
                  // simply consumes the slack instead of overflowing.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(15, 10, 15, 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              TrainIconTile(
                                icon: icon,
                                accent: accent,
                                size: 34,
                                iconSize: 17,
                                radius: 11,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: scaler,
                                  style: TrainType.ui(
                                    size: 15.5,
                                    weight: FontWeight.w700,
                                    color: TrainColors.inkPlain,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Text(
                            stat.toUpperCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textScaler: scaler,
                            style: TrainType.mono(
                              size: 9.5,
                              tracking: 0.06,
                              color: TrainColors.ink4,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// A module card's hero photograph: the section image, cover-fit into a fixed
/// strip, with a fade to the screen base along its bottom edge so it melts into
/// the card body rather than butting against it with a hard line. Falls back to
/// a hue wash if the asset is ever missing, so the card never shows a broken
/// image slot.
class _HeroPhoto extends StatelessWidget {
  const _HeroPhoto({required this.image, required this.accent});

  final String image;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            image,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            // Decode near the widest a tile is drawn (×~2 for hi-DPI) rather
            // than at the source's full resolution.
            cacheWidth: 640,
            errorBuilder: (context, error, stack) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.30),
                    accent.withValues(alpha: 0.06),
                  ],
                ),
              ),
            ),
          ),
          // The seam-softening fade: transparent over the top half, deepening
          // to the screen base at the very bottom edge.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00080908),
                  Color(0x00080908),
                  Color(0xC2080908),
                ],
                stops: [0.0, 0.52, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
              // Music is green throughout the app; the accent tints the state
              // dot, not the always-on brand mark.
              accent: connected ? TrainColors.green : TrainColors.ink3,
              iconTile: const _BrandTile(child: _SpotifyMark(size: 18)),
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
          const Icon(AppIcons.music, size: 16, color: TrainColors.green),
    );
  }
}
