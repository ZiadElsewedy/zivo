import 'package:flutter/material.dart';

import '../../../../../../core/scope/app_scope.dart';
import '../../../../../../core/widgets/train_chrome.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../../music/music_config.dart';
import '../../../../../music/presentation/spotify_strip.dart';
import '../../../../domain/logged_set.dart';
import '../../../../domain/session_exercise.dart';
import '../rest_ring.dart';
import '../session_header.dart';
import '../up_next_card.dart';
import 'phase_scaffold.dart';

/// The two countdown phases — pre-workout warm-up and inter-set rest.
///
/// **One widget on purpose.** These were two ~90-line builders that the code
/// itself described as "the SAME screen, element for element: eyebrow → ring →
/// what's coming → music → adjust → skip", because warm-up had once stated it
/// in a different dialect — no card, no music, a ring that ignored the
/// ambience — and the first thing you saw in a session looked like a different
/// app from the screen you then spent the whole workout on. Keeping them as
/// two copies meant that intent was a comment. Here it is the structure: the
/// only things a phase gets to choose are its hue, its words, and what its
/// buttons do.
class CountdownPhase extends StatelessWidget {
  const CountdownPhase({
    required this.remaining,
    required this.totalSeconds,
    required this.isPaused,
    required this.hue,
    required this.label,
    required this.pausedLabel,
    required this.upNextLabel,
    required this.exercise,
    required this.set,
    required this.skipLabel,
    required this.adjustKeyPrefix,
    required this.onTogglePause,
    required this.onAdjust,
    required this.onSkip,
    this.accent,
    this.runningIcon,
    this.runningGlyph,
    super.key,
  });

  final Duration remaining;
  final int totalSeconds;
  final bool isPaused;

  /// The phase's identity — ember for warm-up, Pulse green for rest. It owns
  /// the eyebrow and the RING only: skip stays a ghost secondary in both, so
  /// the screen's most prominent control never changes hue between phases.
  final Color hue;

  /// The ambience tint pulled from the current artwork, when there is any.
  final Color? accent;

  final String label;
  final String pausedLabel;

  /// Names what the card underneath is showing ("First up" for warm-up).
  /// Null lets [UpNextCard] use its own default.
  final String? upNextLabel;
  final SessionExercise? exercise;
  final LoggedSet? set;

  final String skipLabel;

  /// Keys the ±15s buttons (`'warmup'` → `warmup-minus-15`). Tests drive the
  /// two phases separately, so the keys stay distinct.
  final String adjustKeyPrefix;

  final VoidCallback onTogglePause;
  final void Function(int seconds) onAdjust;
  final VoidCallback onSkip;

  /// The eyebrow's running-state mark. Warm-up shows a streak icon, rest a
  /// pause glyph; both swap to a play glyph while held.
  final IconData? runningIcon;
  final Widget? runningGlyph;

  @override
  Widget build(BuildContext context) {
    return PhaseScroll(
      children: [
        // The pill is a real pause control (so is the ring) — it used to carry
        // a pause glyph and do nothing, the most button-shaped thing on the
        // screen, inert.
        Center(
          child: PhaseEyebrow(
            isPaused ? pausedLabel : label,
            color: hue,
            icon: isPaused ? null : runningIcon,
            glyph: isPaused
                ? TrainPlayGlyph(color: hue, size: 11)
                : runningGlyph,
            onTap: onTogglePause,
            semanticLabel: isPaused
                ? l(context).workoutResume
                : l(context).workoutPause,
          ),
        ),
        const SizedBox(height: 26),
        // The ring is the screen's one hero number.
        Center(
          child: RestRing(
            remaining: remaining,
            total: totalSeconds,
            animate: !isPaused,
            hue: hue,
            accent: accent,
            onTap: onTogglePause,
            isPaused: isPaused,
          ),
        ),
        const SizedBox(height: 26),
        UpNextCard(label: upNextLabel, exercise: exercise, set: set),
        // A hard minimum gap, not just the Spacer below it: on a short screen
        // the Spacer collapses to zero and the card ends up welded to the
        // music strip, reading as one two-storey slab.
        const SizedBox(height: 18),
        const Spacer(),
        if (kMusicEnabled) ...[
          // Degrades to nothing when there's no music — unlike the logging
          // slot, this screen is Spacer-balanced and a "connect" chip would
          // just nag mid-rest.
          SessionNowPlaying(
            controller: AppScope.of(context).requireMusic,
            density: SpotifyStripDensity.rest,
            connectFallback: false,
            accent: accent,
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: TrainGhostButton(
                key: Key('$adjustKeyPrefix-minus-15'),
                label: '−15s',
                onTap: () => onAdjust(-15),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: TrainGhostButton(
                key: Key('$adjustKeyPrefix-plus-15'),
                label: '+15s',
                onTap: () => onAdjust(15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        // One rule across all three phases: **skip is always the secondary**,
        // and the phase's hue owns the RING only. The running phase already
        // worked this way (ghost Skip beside the ember Log set); warm-up and
        // rest each promoted their skip to a full primary instead, and in two
        // different colours — so the screen's most prominent control changed
        // hue depending on which phase you were in, for no reason a user could
        // feel. Ember stays reserved for the action that actually commits.
        TrainGhostButton(
          label: skipLabel,
          mono: false,
          height: 60,
          icon: const TrainPlayGlyph(
            color: Color(0x99F4F4F0),
            size: 13,
            bar: true,
          ),
          onTap: onSkip,
        ),
      ],
    );
  }
}
