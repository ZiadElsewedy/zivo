import 'package:flutter/material.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/widgets/train_chrome.dart';
import '../../../domain/logged_set.dart';
import '../../../domain/rest_policy.dart';
import '../../../domain/session_exercise.dart';
import '../../../domain/workout_plan_format.dart';
import '../../../../music/domain/music_connection.dart';
import '../../../../music/domain/music_controller.dart';
import '../../../../music/domain/now_playing.dart';
import '../../../../music/presentation/music_player_page.dart';
import '../../../../music/presentation/spotify_strip.dart';
import '../../../../../l10n/l10n.dart';
import 'live_session_format.dart';

/// What's waiting on the other side of the rest — the exercise and the exact
/// numbers to hit, so the countdown ends with you already knowing what to do
/// rather than reading the next screen cold.
class UpNextCard extends StatelessWidget {
  const UpNextCard({
    required this.exercise,
    required this.set,

    /// Overridden by the rest screen, which calls this card something else.
    /// Null means "UP NEXT", resolved at build time because it's localized.
    this.label,
    super.key,
  });

  final SessionExercise? exercise;
  final LoggedSet? set;

  /// "UP NEXT" during rest, "FIRST UP" during the warm-up — the same card
  /// answering the same question at two different points in the session.
  ///
  /// Nullable now that it's localized: a default argument has to be a constant
  /// expression, and a translated string isn't one. Null means "UP NEXT".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final label = this.label ?? l(context).workoutUpNext;
    final exercise = this.exercise;
    final set = this.set;
    if (exercise == null || set == null) {
      // Everything's resolved — rest is the last thing between here and the
      // summary.
      return TrainCard(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        gradient: TrainColors.cardGradient,
        child: Row(
          children: [
            TrainCaption(label),
            const Spacer(),
            Text(
              l(context).liveFinish,
              style: TrainType.ui(
                size: 16,
                weight: FontWeight.w700,
                color: TrainColors.inkPlain,
              ),
            ),
          ],
        ),
      );
    }

    final workingIndex = workingSetIndexOf(exercise, set);
    final reps = repTargetLabel(set.target);
    final weight = set.targetWeightKg;
    return TrainCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      gradient: TrainColors.cardGradient,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TrainCaption(label),
                const SizedBox(height: 9),
                Text(
                  exercise.muscleGroup == null
                      ? exercise.name
                      : '${exercise.name} · ${exercise.muscleGroup}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.ui(
                    size: 16,
                    weight: FontWeight.w700,
                    height: 1.2,
                    color: TrainColors.inkPlain,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weight == null ? reps : '$reps × ${trimWeight(weight)}',
                style: TrainType.mono(size: 20, color: TrainColors.ink),
              ),
              const SizedBox(height: 8),
              Text(
                weight == null
                    ? l(context).liveSetNumberCaps(workingIndex + 1)
                    : l(context).liveSetNumberKg(workingIndex + 1),
                style: TrainType.mono(
                  size: 8.5,
                  weight: FontWeight.w500,
                  tracking: 0.14,
                  color: const Color(0x52F4F4F0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The workout's persistent now-playing companion — one [SpotifyStrip] at
/// [SpotifyStripDensity.bar], docked below the phase content for the WHOLE
/// session so a track is skippable/pausable from warm-up, logging, and rest
/// alike without leaving for Spotify or scrolling to find a strip. When
/// nothing is playable it collapses to nothing (a [SizedBox.shrink]); it never
/// nags to connect, since that belongs on Today / the full player.
///
/// "Change the song" here is next/previous only (`MusicController.next`/
/// `previous`, wired to App Remote's `skipNext`/`skipPrevious`) — there's no
/// browse/search picker. Spotify's App Remote doesn't expose one either
/// without building real Web API search UI, which is a materially bigger
/// feature than this pass.
///
/// **Disconnected is not the same as absent.** On a device that has linked to
/// Spotify (see [MusicController.isLinked]) a dropped connection keeps a slim
/// reconnect row here instead of collapsing: App Remote drops for ordinary
/// reasons, and the moment it happened to matter most — mid-workout, phone on
/// a bench — the bar simply vanished and the only way back was to abandon the
/// session, find Settings, and open the player. A device that has never
/// linked still gets nothing, since connecting Spotify is not a thing to
/// prompt for in the middle of a set.
class SessionNowPlaying extends StatelessWidget {
  const SessionNowPlaying({
    required this.controller,
    required this.density,
    this.padding = EdgeInsets.zero,
    this.accent,
    super.key,
  });

  final MusicController controller;
  final SpotifyStripDensity density;

  /// Inset applied around the strip ONLY — the empty state stays a zero-size
  /// box, so the persistent bar collapses to nothing (no dangling padding)
  /// whenever there's no connected track to control.
  final EdgeInsets padding;

  /// The current track's foreground colour (`SessionAmbience.vividOf`) —
  /// what makes the strip's own play/pause and skip controls follow the song
  /// along with the rest of the screen.
  final Color? accent;

  /// Nothing to control and nothing to reconnect → nothing on screen.
  static const Widget _empty = SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MusicConnection>(
      stream: controller.connection,
      initialData: controller.currentConnection,
      builder: (context, connSnap) {
        final state = connSnap.data ?? MusicConnection.disconnected;
        if (state != MusicConnection.connected) {
          return StreamBuilder<bool>(
            stream: controller.linked,
            initialData: controller.isLinked,
            builder: (context, linkedSnap) => (linkedSnap.data ?? false)
                ? Padding(
                    padding: padding,
                    child: _SessionMusicStatus(
                      controller: controller,
                      state: state,
                    ),
                  )
                : _empty,
          );
        }
        return StreamBuilder<NowPlaying?>(
          stream: controller.nowPlaying,
          initialData: controller.currentNowPlaying,
          builder: (context, nowSnap) {
            final playing = nowSnap.data;
            if (playing == null) return _empty;
            return Padding(
              padding: padding,
              child: SpotifyStrip(
                controller: controller,
                playing: playing,
                density: density,
                accent: accent,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MusicPlayerPage(controller: controller),
                    fullscreenDialog: true,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The reconnect row: same slab as the strip it stands in for, so the bar
/// doesn't change shape when the connection comes and goes mid-session — only
/// its contents.
class _SessionMusicStatus extends StatelessWidget {
  const _SessionMusicStatus({required this.controller, required this.state});

  final MusicController controller;
  final MusicConnection state;

  @override
  Widget build(BuildContext context) {
    final connecting = state == MusicConnection.connecting;
    // No Spotify app on the device is the one state a tap cannot fix, so it
    // states the fact and stays inert rather than pretending to be a button.
    final actionable = state != MusicConnection.noSpotifyApp && !connecting;
    final label = switch (state) {
      MusicConnection.connecting => l(context).musicConnecting,
      MusicConnection.noSpotifyApp => l(context).musicInstallSpotify,
      _ => l(context).musicReconnect,
    };
    return PressableScale(
      enabled: actionable,
      scale: 0.99,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: actionable ? () => controller.connect() : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 10, 14, 10),
            decoration: BoxDecoration(
              color: const Color(0x08FFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x0FFFFFFF)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: connecting
                      ? const CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: TrainColors.green,
                        )
                      : Image.asset(
                          'assets/spotify/spotify-icon.png',
                          opacity: const AlwaysStoppedAnimation(0.55),
                          filterQuality: FilterQuality.medium,
                        ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.ui(
                      size: 12,
                      weight: FontWeight.w700,
                      color: const Color(0xB3F4F4F0),
                    ),
                  ),
                ),
                if (actionable)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: TrainColors.green.withValues(alpha: 0.75),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
