import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/train_tokens.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/train_chrome.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'artwork_palette_service.dart';
import 'equalizer_glyph.dart';
import 'music_player_page.dart';
import 'spotify_strip.dart' show TickingPlayhead;

/// Resolves "is there anything to show?" — connected **and** a track loaded.
///
/// The predicate lives here, in one place, because two things depend on it and
/// they must never disagree: the lozenge (which renders the track) and the
/// shell (which reserves the strip's height on every page). The shell watches
/// the same two streams directly so it can rebuild only on the *edge* — when
/// music appears or leaves — rather than on every playback emission.
class NowPlayingResolver extends StatelessWidget {
  const NowPlayingResolver({
    required this.controller,
    required this.builder,
    super.key,
  });

  final MusicController controller;

  /// Called with the live track, or null when there is nothing to show.
  final Widget Function(BuildContext context, NowPlaying? playing) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MusicConnection>(
      stream: controller.connection,
      initialData: controller.currentConnection,
      builder: (context, connectionSnap) {
        if (connectionSnap.data != MusicConnection.connected) {
          return builder(context, null);
        }
        return StreamBuilder<NowPlaying?>(
          stream: controller.nowPlaying,
          initialData: controller.currentNowPlaying,
          builder: (context, snap) => builder(context, snap.data),
        );
      },
    );
  }
}

/// The now-playing strip **fused to the top edge of the nav island**.
///
/// It replaces two things that used to fight each other: a full-height mini
/// bar parked above the nav (a second slab claiming the bottom edge, which
/// made Ask a three-bar stack), and the floating orb it collapsed into (which
/// then docked on top of the Ask composer and over list rows on other tabs).
///
/// The nav island is the anchor and music simply *joins* it — one object, one
/// measured height, so nothing can overlap it by construction. It stays
/// text-first per the handoff: the equalizer glyph carries "it's playing",
/// there is no artwork tile, and the timecode is mono. Tapping the body opens
/// the full player; the two transport controls stay reachable mid-set, which
/// is the whole reason the strip is on screen during training.
///
/// Sized by [kNowPlayingLozengeHeight] — the shell's bottom-chrome metric
/// reads that same constant, so the strip cannot grow without every page's
/// clearance growing with it.
class NowPlayingLozenge extends StatelessWidget {
  const NowPlayingLozenge({required this.controller, super.key});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    // Always exactly [kNowPlayingLozengeHeight] tall while mounted, even in
    // the moment between the shell deciding music is on screen and the track
    // arriving. The shell has already reserved that space on every page, so
    // shrinking here would make the whole stack jump.
    return SizedBox(
      height: kNowPlayingLozengeHeight,
      child: NowPlayingResolver(
        controller: controller,
        builder: (context, playing) => playing == null
            ? const SizedBox.shrink()
            : _Strip(controller: controller, playing: playing),
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.controller, required this.playing});

  final MusicController controller;
  final NowPlaying playing;

  @override
  Widget build(BuildContext context) {
    // The mini bar's album-colour echo (owner-requested) survives the move
    // onto the island — as a wash *behind* the strip rather than a tint on a
    // plate of its own, since the island now owns the fill. Kept very low
    // alpha: it should read as the strip quietly reacting to the song, never
    // as a second coloured surface competing with a screen's hero number.
    return ArtworkPalette(
      trackId: playing.trackId,
      artworkBytes: playing.artworkBytes,
      builder: (context, colours) => DecoratedBox(
        decoration: BoxDecoration(
          color: colours.accent.withValues(alpha: 0.07),
          // The one seam between the strip and the tab row. A hairline, not a
          // gap — the two read as halves of a single object.
          border: const Border(bottom: BorderSide(color: TrainColors.hairline)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            EqualizerGlyph(playing: !playing.isPaused),
            const SizedBox(width: 10),
            Expanded(
              child: _Body(controller: controller, playing: playing),
            ),
            _Transport(
              enabled: playing.hasControl,
              semanticLabel: playing.isPaused ? 'Play' : 'Pause',
              onTap: () =>
                  playing.isPaused ? controller.play() : controller.pause(),
              child: playing.isPaused
                  ? const TrainPlayGlyph(color: TrainColors.green, size: 12)
                  : const TrainPauseGlyph(color: TrainColors.green, size: 12),
            ),
            _Transport(
              enabled: playing.hasControl,
              semanticLabel: 'Next track',
              onTap: controller.next,
              child: const TrainPlayGlyph(
                color: Color(0xBFF4F4F0),
                size: 11,
                bar: true,
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// Title · artist on one line with the remaining time trailing it, all of it
/// one tap target for the full player.
class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.playing});

  final MusicController controller;
  final NowPlaying playing;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.99,
      child: Semantics(
        button: true,
        label:
            'Now playing: ${playing.title} by ${playing.artist}. '
            'Open the player.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MusicPlayerPage(controller: controller),
              fullscreenDialog: true,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  playing.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.ui(
                    size: 12,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  playing.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.mono(
                    size: 9.5,
                    tracking: 0.02,
                    height: 1.2,
                    color: const Color(0x61F4F4F0),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Interpolated forward between the controller's coarse
              // emissions so it ticks every second rather than jumping.
              TickingPlayhead(
                key: ValueKey(playing.trackId),
                position: playing.position,
                duration: playing.duration,
                isPaused: playing.isPaused,
                builder: (context, position, _) => Text(
                  '-${_mmss(playing.duration - position)}',
                  style: TrainType.mono(
                    size: 9,
                    color: const Color(0x59F4F4F0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A transport glyph in a tap target as tall as the strip itself. Disabled
/// (dimmed, inert) when another Spotify Connect device owns playback — the
/// normal multi-device model, not an error.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    required this.enabled,
  });

  final Widget child;
  final Future<void> Function() onTap;
  final String semanticLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: enabled,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: InkResponse(
          radius: 20,
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
              : null,
          child: SizedBox(
            width: 38,
            height: kNowPlayingLozengeHeight,
            child: Center(
              child: Opacity(opacity: enabled ? 1 : 0.4, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lozenge's own height. Lives here (not in the shell) so the strip owns
/// its size and `ZivoBottomBarMetrics` imports the number rather than
/// duplicating it — the drift this whole change exists to remove.
const double kNowPlayingLozengeHeight = 38;

String _mmss(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}
