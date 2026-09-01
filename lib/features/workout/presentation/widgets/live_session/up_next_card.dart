import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/theme/app_icons.dart';
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

/// The workout's now-playing companion.
///
/// Renders the handoff's text-first [SpotifyStrip] at the density the host
/// phase asks for — one line while logging, a two-line one with full
/// transport during rest. When nothing is playable it degrades to
/// [ConnectMusicChip] (logging) or to nothing at all (rest, which is
/// Spacer-balanced around the ring and shouldn't nag).
///
/// "Change the song" here is next/previous only (`MusicController.next`/
/// `previous`, wired to App Remote's `skipNext`/`skipPrevious`) — there's no
/// browse/search picker. Spotify's App Remote doesn't expose one either
/// without building real Web API search UI, which is a materially bigger
/// feature than this pass.
class SessionNowPlaying extends StatelessWidget {
  const SessionNowPlaying({
    required this.controller,
    required this.density,
    this.connectFallback = true,
    this.accent,
    super.key,
  });

  final MusicController controller;
  final SpotifyStripDensity density;

  /// False during rest, where an empty slot beats a connect prompt.
  final bool connectFallback;

  /// The current track's foreground colour (`SessionAmbience.vividOf`) —
  /// what makes the strip's own play/pause and skip controls follow the song
  /// along with the rest of the screen.
  final Color? accent;

  Widget get _empty => connectFallback
      ? ConnectMusicChip(controller: controller)
      : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MusicConnection>(
      stream: controller.connection,
      initialData: controller.currentConnection,
      builder: (context, connSnap) {
        if (connSnap.data != MusicConnection.connected) return _empty;
        return StreamBuilder<NowPlaying?>(
          stream: controller.nowPlaying,
          initialData: controller.currentNowPlaying,
          builder: (context, nowSnap) {
            final playing = nowSnap.data;
            if (playing == null) return _empty;
            return SpotifyStrip(
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
            );
          },
        );
      },
    );
  }
}

/// The logging slot's fallback when there's no track to show (disconnected,
/// connecting, or connected with nothing loaded) — a small always-reachable
/// way into [MusicPlayerPage]'s connect flow, so the slot never goes fully
/// blank the way rest's does. Generic glyph, no brand mark: the Spotify logo
/// marks a track that is genuinely playing FROM Spotify (the strips' artwork
/// tile, the player's source badge), and stamping it on a dead slot would
/// claim a connection that isn't there.
class ConnectMusicChip extends StatelessWidget {
  const ConnectMusicChip({required this.controller, super.key});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MusicPlayerPage(controller: controller),
              fullscreenDialog: true,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0x08FFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x0FFFFFFF)),
          ),
          child: Row(
            children: [
              const Icon(AppIcons.music, size: 14, color: Color(0x66F4F4F0)),
              const SizedBox(width: 10),
              Text(
                l(context).liveConnectMusic,
                style: TrainType.mono(
                  size: 9,
                  weight: FontWeight.w500,
                  tracking: 0.16,
                  color: const Color(0x66F4F4F0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
