import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/train_tokens.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/train_chrome.dart';
import '../../../l10n/l10n.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'artwork_palette_service.dart';
import 'equalizer_glyph.dart';
import 'music_player_page.dart';
import 'spotify_strip.dart' show TickingPlayhead;

/// Resolves "is there anything to show?" — connected **and** a track loaded.
///
/// The predicate lives here, in one place, because the surfaces that render a
/// live track must never disagree about when one exists. (The *bottom bar*
/// deliberately shows more than this — see [NowPlayingLozenge] — because the
/// shell also reserves height for the connection states.)
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

/// The music strip **fused to the top edge of the nav island** — the app's
/// one permanent music surface.
///
/// It replaces two things that used to fight each other: a full-height mini
/// bar parked above the nav (a second slab claiming the bottom edge, which
/// made Ask a three-bar stack), and the floating orb it collapsed into (which
/// then docked on top of the Ask composer and over list rows on other tabs).
/// The nav island is the anchor and music simply *joins* it — one object, one
/// measured height, so nothing can overlap it by construction.
///
/// **It is a connection surface as well as a player.** Once this device is
/// linked, the strip stays put through the disconnects that are a normal part
/// of App Remote's life and says what state music is in — connecting,
/// dropped, nothing loaded — with the fix one tap away in each case. It used
/// to render only a live track and vanish otherwise, which meant the only way
/// back from a dropped connection was a Connect button buried on another
/// screen. Reconnecting is the most frequent thing the user does with music,
/// so it lives where music already lives.
///
/// With a track, it carries the full transport — **previous · play/pause ·
/// next** — because changing the song is the other frequent thing, and
/// leaving for Spotify mid-set to do it is the friction this removes. The
/// title/artist block is the tap target for the full player; the playhead is
/// a hairline along the bottom edge rather than a timecode, which reads
/// faster and leaves the row's width to the controls.
///
/// Sized by [kNowPlayingLozengeHeight] — the shell's bottom-chrome metric
/// reads that same constant, so the strip cannot grow without every page's
/// clearance growing with it.
class NowPlayingLozenge extends StatelessWidget {
  const NowPlayingLozenge({required this.controller, super.key});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    // Always exactly [kNowPlayingLozengeHeight] tall while mounted: the shell
    // has already reserved that space on every page, so shrinking here would
    // make the whole stack jump.
    return SizedBox(
      height: kNowPlayingLozengeHeight,
      child: StreamBuilder<MusicConnection>(
        stream: controller.connection,
        initialData: controller.currentConnection,
        builder: (context, connectionSnap) {
          final state = connectionSnap.data ?? MusicConnection.disconnected;
          if (state != MusicConnection.connected) {
            return _StatusStrip(controller: controller, state: state);
          }
          return StreamBuilder<NowPlaying?>(
            stream: controller.nowPlaying,
            initialData: controller.currentNowPlaying,
            builder: (context, snap) {
              final playing = snap.data;
              return playing == null
                  ? _StatusStrip(controller: controller, state: state)
                  : _Strip(controller: controller, playing: playing);
            },
          );
        },
      ),
    );
  }
}

/// The strip's shared chrome: a tinted ground and the hairline that welds it
/// to the tab row below. One widget so the playing and non-playing states are
/// visibly the same object changing contents, not two bars swapping places.
class _StripSurface extends StatelessWidget {
  const _StripSurface({required this.tint, required this.child});

  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        // The one seam between the strip and the tab row. A hairline, not a
        // gap — the two read as halves of a single object.
        border: const Border(bottom: BorderSide(color: TrainColors.hairline)),
      ),
      child: child,
    );
  }
}

/// Everything that isn't a playing track: connecting, dropped, authorization
/// refused, no Spotify app, or connected with nothing loaded.
///
/// Each state says what is true and — where a tap can change it — *is* the
/// control that changes it, rather than pointing at a screen elsewhere. The
/// two states a tap can't fix (no Spotify app installed; nothing loaded in
/// the player) open the full player, which has the room to explain.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.controller, required this.state});

  final MusicController controller;
  final MusicConnection state;

  bool get _connecting => state == MusicConnection.connecting;

  /// True where tapping should attempt a connection rather than open the
  /// player. `authFailed` is included on purpose: the retry has to be the
  /// user's own tap, since the controller deliberately never re-attempts an
  /// authorization failure on its own.
  bool get _tapConnects =>
      state == MusicConnection.disconnected ||
      state == MusicConnection.authFailed ||
      state == MusicConnection.needsPremium;

  String _label(BuildContext context) => switch (state) {
    MusicConnection.connecting => l(context).musicConnecting,
    MusicConnection.noSpotifyApp => l(context).musicInstallSpotify,
    MusicConnection.connected => l(context).musicNothingPlaying,
    // Linked but down is the common case and reads as "reconnect"; an
    // unlinked device says "connect". Same tap either way.
    MusicConnection.disconnected ||
    MusicConnection.authFailed ||
    MusicConnection.needsPremium => controller.isLinked
        ? l(context).musicReconnect
        : l(context).musicConnect,
  };

  @override
  Widget build(BuildContext context) {
    final label = _label(context);
    final live = state == MusicConnection.connected;
    return _StripSurface(
      tint: live
          ? TrainColors.green.withValues(alpha: 0.05)
          : const Color(0x0AFFFFFF),
      child: PressableScale(
        scale: 0.995,
        child: Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              if (_tapConnects) {
                controller.connect();
              } else {
                _openPlayer(context, controller);
              }
            },
            child: Row(
              children: [
                const SizedBox(width: 14),
                SizedBox(
                  width: 14,
                  height: 14,
                  child: _connecting
                      ? const CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: TrainColors.green,
                        )
                      : Image.asset(
                          'assets/spotify/spotify-icon.png',
                          // Dimmed rather than recoloured — the mark is a
                          // trademark and must not be restyled, but a strip
                          // that isn't connected shouldn't wear it at full
                          // strength either.
                          opacity: const AlwaysStoppedAnimation(0.55),
                          filterQuality: FilterQuality.medium,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.ui(
                      size: 11.5,
                      weight: FontWeight.w700,
                      color: const Color(0xB3F4F4F0),
                    ),
                  ),
                ),
                if (_tapConnects)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 14),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: TrainColors.green.withValues(alpha: 0.75),
                    ),
                  )
                else
                  const SizedBox(width: 14),
              ],
            ),
          ),
        ),
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
      builder: (context, colours) => _StripSurface(
        tint: colours.accent.withValues(alpha: 0.07),
        child: Stack(
          children: [
            Row(
              children: [
                const SizedBox(width: 14),
                EqualizerGlyph(playing: !playing.isPaused),
                const SizedBox(width: 10),
                Expanded(
                  child: _Body(controller: controller, playing: playing),
                ),
                _Transport(
                  enabled: playing.hasControl,
                  semanticLabel: l(context).musicPrevious,
                  onTap: controller.previous,
                  width: 32,
                  // The next glyph turned around — one painter, so the pair
                  // can never drift apart visually.
                  child: Transform.rotate(
                    angle: 3.14159,
                    child: const TrainPlayGlyph(
                      color: Color(0xBFF4F4F0),
                      size: 10.5,
                      bar: true,
                    ),
                  ),
                ),
                _Transport(
                  enabled: playing.hasControl,
                  semanticLabel: playing.isPaused
                      ? l(context).musicPlay
                      : l(context).musicPause,
                  onTap: () =>
                      playing.isPaused ? controller.play() : controller.pause(),
                  // The one control that is bigger and coloured: it is the
                  // one you reach for without looking.
                  width: 38,
                  child: playing.isPaused
                      ? const TrainPlayGlyph(color: TrainColors.green, size: 13)
                      : const TrainPauseGlyph(
                          color: TrainColors.green,
                          size: 13,
                        ),
                ),
                _Transport(
                  enabled: playing.hasControl,
                  semanticLabel: l(context).musicNext,
                  onTap: controller.next,
                  width: 32,
                  child: const TrainPlayGlyph(
                    color: Color(0xBFF4F4F0),
                    size: 10.5,
                    bar: true,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            // The playhead, as a hairline on the strip's own bottom edge.
            // It replaces the mono timecode that used to trail the title: at
            // 9pt in a 38pt bar that number was unreadable at a glance and
            // cost the width the transport now uses, while a line answers
            // "how far in are we" without being read at all.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Playhead(playing: playing, accent: colours.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 1.5px progress rule across the foot of the strip, interpolated forward
/// between the controller's coarse emissions so it advances smoothly rather
/// than jumping a few seconds at a time.
class _Playhead extends StatelessWidget {
  const _Playhead({required this.playing, required this.accent});

  final NowPlaying playing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return TickingPlayhead(
      key: ValueKey(playing.trackId),
      position: playing.position,
      duration: playing.duration,
      isPaused: playing.isPaused,
      builder: (context, position, _) {
        final total = playing.duration.inMilliseconds;
        final progress = total <= 0
            ? 0.0
            : (position.inMilliseconds / total).clamp(0.0, 1.0);
        return FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: progress,
          child: Container(
            height: 1.5,
            color: accent.withValues(alpha: 0.55),
          ),
        );
      },
    );
  }
}

/// Title · artist on one line, the whole block a tap target for the full
/// player.
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
          onTap: () => _openPlayer(context, controller),
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
            ],
          ),
        ),
      ),
    );
  }
}

void _openPlayer(BuildContext context, MusicController controller) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MusicPlayerPage(controller: controller),
      fullscreenDialog: true,
    ),
  );
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
    this.width = 38,
  });

  final Widget child;
  final Future<void> Function() onTap;
  final String semanticLabel;
  final bool enabled;
  final double width;

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
            width: width,
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
