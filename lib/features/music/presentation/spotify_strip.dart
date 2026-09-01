import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/train_tokens.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/train_chrome.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'equalizer_glyph.dart';

/// The Spotify strips used across the workout-tracking screens.
///
/// Densities:
///
/// * [SpotifyStrip.full] — Today: two rows, with the scrub line and timecodes.
/// * [SpotifyStrip.inline] — Active Set: artwork + title/artist + remaining.
/// * [SpotifyStrip.rest] — Rest: the same, with full prev/play-pause/next.
/// * [SpotifyStrip.bar] — the persistent live-session control: a slim
///   artwork + title/artist + full prev/play-pause/next, docked through every
///   phase so a track is skippable without leaving for Spotify or scrolling.
///
/// **On the artwork tile.** The original design handoff was explicit that
/// there was to be *no* album art here — the music was to read as
/// instrumentation (the [EqualizerGlyph]) so it never competed with the
/// screen's hero number. The owner asked for the artwork back: mid-set, the
/// cover is the fastest way to recognise what's playing, and the Spotify
/// mark on its corner is what makes the strip read as *Spotify* rather than
/// as some generic player. The equalizer survives as a small overlay on the
/// tile, so the "is it actually playing" signal didn't go with it.
///
/// **On [accent].** Everything the strip draws in color — the transport
/// glyphs, the scrub line, the track-change bloom — takes its hue from the
/// current track's artwork when a host provides one (the live session passes
/// `SessionAmbience.vividOf`). With no accent it all falls back to
/// [TrainColors.green], pixel-identical to before.
enum SpotifyStripDensity { full, inline, rest, bar }

class SpotifyStrip extends StatelessWidget {
  const SpotifyStrip({
    required this.controller,
    required this.playing,
    required this.density,
    this.onOpen,
    this.accent,
    super.key,
  });

  const SpotifyStrip.full({
    required MusicController controller,
    required NowPlaying playing,
    VoidCallback? onOpen,
    Color? accent,
    Key? key,
  }) : this(
         controller: controller,
         playing: playing,
         density: SpotifyStripDensity.full,
         onOpen: onOpen,
         accent: accent,
         key: key,
       );

  const SpotifyStrip.inline({
    required MusicController controller,
    required NowPlaying playing,
    VoidCallback? onOpen,
    Color? accent,
    Key? key,
  }) : this(
         controller: controller,
         playing: playing,
         density: SpotifyStripDensity.inline,
         onOpen: onOpen,
         accent: accent,
         key: key,
       );

  const SpotifyStrip.rest({
    required MusicController controller,
    required NowPlaying playing,
    VoidCallback? onOpen,
    Color? accent,
    Key? key,
  }) : this(
         controller: controller,
         playing: playing,
         density: SpotifyStripDensity.rest,
         onOpen: onOpen,
         accent: accent,
         key: key,
       );

  const SpotifyStrip.bar({
    required MusicController controller,
    required NowPlaying playing,
    VoidCallback? onOpen,
    Color? accent,
    Key? key,
  }) : this(
         controller: controller,
         playing: playing,
         density: SpotifyStripDensity.bar,
         onOpen: onOpen,
         accent: accent,
         key: key,
       );

  final MusicController controller;
  final NowPlaying playing;
  final SpotifyStripDensity density;

  /// Opens the full player. Null makes the strip's body inert (the transport
  /// controls still work).
  final VoidCallback? onOpen;

  /// The current track's color, already normalised for foreground use by the
  /// host (see the class doc). Null falls back to [TrainColors.green].
  final Color? accent;

  bool get _isFull => density == SpotifyStripDensity.full;

  /// The one color every tinted element in the strip resolves through, so
  /// "the controls follow the song" is a single decision rather than a dozen
  /// call sites each remembering to opt in.
  Color get _tint => accent ?? TrainColors.green;

  @override
  Widget build(BuildContext context) {
    final radius = _isFull ? 20.0 : 16.0;
    return _TrackBloom(
      trackId: playing.trackId,
      accent: _tint,
      builder: (context, bloom) {
        return PressableScale(
          scale: 0.99,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onOpen,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOut,
                padding: _isFull
                    ? const EdgeInsets.fromLTRB(13, 12, 15, 12)
                    : const EdgeInsets.fromLTRB(11, 10, 14, 10),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    _isFull ? TrainColors.glass : const Color(0x08FFFFFF),
                    _tint.withValues(alpha: 0.10),
                    bloom,
                  ),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: Color.lerp(
                      _isFull
                          ? TrainColors.hairline
                          : const Color(0x0FFFFFFF),
                      _tint.withValues(alpha: 0.45),
                      bloom,
                    )!,
                  ),
                  // The bloom itself: a short wash of the incoming track's
                  // own color around the strip, so a song change registers
                  // peripherally even when you're looking at the timer.
                  boxShadow: bloom <= 0.01
                      ? null
                      : [
                          BoxShadow(
                            color: _tint.withValues(alpha: 0.26 * bloom),
                            blurRadius: 26 * bloom,
                            spreadRadius: 1 * bloom,
                          ),
                        ],
                ),
                // The persistent bar carries no timecode, so it skips the
                // playhead ticker entirely — it's on screen for the whole
                // workout, and there's no reason to rebuild it every frame.
                child: density == SpotifyStripDensity.bar
                    ? _bar(context)
                    : TickingPlayhead(
                        position: playing.position,
                        duration: playing.duration,
                        isPaused: playing.isPaused,
                        builder: (context, position, fraction) =>
                            switch (density) {
                              SpotifyStripDensity.full => _full(
                                context,
                                position,
                                fraction,
                              ),
                              SpotifyStripDensity.inline => _inline(
                                context,
                                position,
                              ),
                              SpotifyStripDensity.rest => _rest(
                                context,
                                position,
                              ),
                              SpotifyStripDensity.bar => _bar(context),
                            },
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The leading album-art tile, swapped with a spring whenever the track
  /// changes (the visible half of the "hype" on a skip — the other half is
  /// [_TrackBloom]'s wash around the whole strip).
  Widget _artwork(double size) => _SwapOnTrack(
    trackId: playing.trackId,
    child: _StripArtwork(
      key: ValueKey(playing.trackId),
      playing: playing,
      size: size,
      tint: _tint,
    ),
  );

  // ---- Today ---------------------------------------------------------------

  Widget _full(BuildContext context, Duration position, double fraction) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _artwork(44),
            const SizedBox(width: 12),
            Expanded(
              child: _SwapOnTrack(
                trackId: playing.trackId,
                child: Column(
                  key: ValueKey(playing.trackId),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Title(playing.title, size: 13),
                    const SizedBox(height: 3),
                    _Artist(playing.artist, size: 10.5),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            _TransportButton(
              enabled: playing.hasControl,
              semanticLabel: playing.isPaused ? 'Play' : 'Pause',
              onTap: () =>
                  playing.isPaused ? controller.play() : controller.pause(),
              child: playing.isPaused
                  ? TrainPlayGlyph(color: _tint, size: 15)
                  : TrainPauseGlyph(color: _tint, size: 15),
            ),
            const SizedBox(width: 8),
            _TransportButton(
              enabled: playing.hasControl,
              semanticLabel: 'Next track',
              onTap: controller.next,
              child: const TrainPlayGlyph(
                color: TrainColors.inkPlain,
                size: 13,
                bar: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            Text(_mmss(position), style: _timecode),
            const SizedBox(width: 9),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 2,
                  backgroundColor: const Color(0x1FFFFFFF),
                  valueColor: AlwaysStoppedAnimation(_tint),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Text('-${_mmss(playing.duration - position)}', style: _timecode),
            const SizedBox(width: 9),
            Text(
              'SPOTIFY',
              style: TrainType.mono(
                size: 8,
                weight: FontWeight.w600,
                tracking: 0.14,
                color: _tint.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---- Active Set ----------------------------------------------------------

  Widget _inline(BuildContext context, Duration position) {
    return Row(
      children: [
        _artwork(38),
        const SizedBox(width: 11),
        Expanded(
          child: _SwapOnTrack(
            trackId: playing.trackId,
            child: Column(
              key: ValueKey(playing.trackId),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Title(playing.title, size: 12),
                const SizedBox(height: 3),
                _Artist(playing.artist, size: 9.5),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '-${_mmss(playing.duration - position)}',
          style: TrainType.mono(size: 9, color: const Color(0x59F4F4F0)),
        ),
        const SizedBox(width: 6),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: playing.isPaused ? 'Play' : 'Pause',
          size: 36,
          onTap: () =>
              playing.isPaused ? controller.play() : controller.pause(),
          child: playing.isPaused
              ? TrainPlayGlyph(color: _tint, size: 12)
              : TrainPauseGlyph(color: _tint, size: 12),
        ),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: 'Next track',
          size: 36,
          onTap: controller.next,
          child: const TrainPlayGlyph(
            color: Color(0xBFF4F4F0),
            size: 11,
            bar: true,
          ),
        ),
      ],
    );
  }

  // ---- Rest ----------------------------------------------------------------

  Widget _rest(BuildContext context, Duration position) {
    return Row(
      children: [
        _artwork(42),
        const SizedBox(width: 11),
        Expanded(
          child: _SwapOnTrack(
            trackId: playing.trackId,
            child: Column(
              key: ValueKey(playing.trackId),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Title(playing.title, size: 12),
                const SizedBox(height: 3),
                _Artist(
                  '${playing.artist} · ${_mmss(playing.duration - position)} LEFT',
                  size: 9.5,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: 'Previous track',
          size: 38,
          onTap: controller.previous,
          child: Transform.rotate(
            angle: 3.14159,
            child: const TrainPlayGlyph(
              color: Color(0xBFF4F4F0),
              size: 11,
              bar: true,
            ),
          ),
        ),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: playing.isPaused ? 'Play' : 'Pause',
          size: 38,
          onTap: () =>
              playing.isPaused ? controller.play() : controller.pause(),
          child: playing.isPaused
              ? TrainPlayGlyph(color: _tint, size: 13)
              : TrainPauseGlyph(color: _tint, size: 13),
        ),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: 'Next track',
          size: 38,
          onTap: controller.next,
          child: const TrainPlayGlyph(
            color: Color(0xBFF4F4F0),
            size: 11,
            bar: true,
          ),
        ),
      ],
    );
  }

  // ---- Persistent session bar ----------------------------------------------

  /// The always-on control docked through the whole live session. Every phase
  /// shows this same slim row, so a track is skippable/pausable without
  /// leaving for Spotify and without scrolling to find a strip. Deliberately
  /// spare — artwork, title/artist, and the full prev/play-pause/next
  /// transport, nothing else — so it rides under the hero without competing
  /// with the goal card or the ring. No timecode: the position is the full
  /// player's job, and dropping it is what keeps the ticker off a control
  /// that is on screen for the entire workout.
  Widget _bar(BuildContext context) {
    return Row(
      children: [
        _artwork(34),
        const SizedBox(width: 11),
        Expanded(
          child: _SwapOnTrack(
            trackId: playing.trackId,
            child: Column(
              key: ValueKey(playing.trackId),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Title(playing.title, size: 12),
                const SizedBox(height: 3),
                _Artist(playing.artist, size: 9.5),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: 'Previous track',
          size: 36,
          onTap: controller.previous,
          child: Transform.rotate(
            angle: 3.14159,
            child: const TrainPlayGlyph(
              color: Color(0xBFF4F4F0),
              size: 11,
              bar: true,
            ),
          ),
        ),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: playing.isPaused ? 'Play' : 'Pause',
          size: 36,
          onTap: () =>
              playing.isPaused ? controller.play() : controller.pause(),
          child: playing.isPaused
              ? TrainPlayGlyph(color: _tint, size: 12)
              : TrainPauseGlyph(color: _tint, size: 12),
        ),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: 'Next track',
          size: 36,
          onTap: controller.next,
          child: const TrainPlayGlyph(
            color: Color(0xBFF4F4F0),
            size: 11,
            bar: true,
          ),
        ),
      ],
    );
  }

  static final _timecode = TrainType.mono(
    size: 9,
    color: const Color(0x66F4F4F0),
  );
}

/// The album-art tile with the Spotify mark on its corner.
///
/// The mark is the shipped asset drawn at its own colors — never recoloured
/// or redrawn, per the trademark note in the music feature map. When there's
/// no artwork yet (App Remote fetches it a beat after the track lands, and
/// some tracks never return any) the tile falls back to a tinted ground with
/// the equalizer alone, so the strip's leading element never pops in and out
/// of existence between songs.
class _StripArtwork extends StatelessWidget {
  const _StripArtwork({
    required this.playing,
    required this.size,
    required this.tint,
    super.key,
  });

  final NowPlaying playing;
  final double size;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final bytes = playing.artworkBytes;
    final radius = BorderRadius.circular(size * 0.26);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: tint.withValues(alpha: 0.12),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: bytes == null || bytes.isEmpty
                    ? Center(
                        child: EqualizerGlyph(
                          width: size * 0.42,
                          height: size * 0.38,
                          color: tint,
                          playing: !playing.isPaused,
                        ),
                      )
                    : Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
            ),
          ),
          // The playing/paused signal the equalizer used to carry on its own,
          // kept alive over the cover: a scrim strip at the tile's foot so the
          // bars stay legible against a bright album.
          if (bytes != null && bytes.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  bottomLeft: radius.bottomLeft,
                  bottomRight: radius.bottomRight,
                ),
                child: Container(
                  height: size * 0.42,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xB3000000)],
                    ),
                  ),
                  child: EqualizerGlyph(
                    width: size * 0.34,
                    height: size * 0.22,
                    color: Colors.white,
                    playing: !playing.isPaused,
                  ),
                ),
              ),
            ),
          // The brand mark, breaking the tile's top-left corner so it reads as
          // a source badge rather than as part of the cover.
          Positioned(
            left: -3,
            top: -3,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xF2080908),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/spotify/spotify-icon.png',
                width: size * 0.30,
                height: size * 0.30,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Swaps [child] with a spring-ish rise whenever the track changes — the
/// per-element half of the song-change transition. Keyed on the track id, so
/// a position tick or a late-arriving artwork byte doesn't re-run it.
class _SwapOnTrack extends StatelessWidget {
  const _SwapOnTrack({required this.trackId, required this.child});

  final String trackId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      // Both tracks share the row for one beat mid-swap; without this the
      // outgoing one drags the row's height/width around as it leaves.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [
          ...previous.map(
            (c) => Positioned.fill(
              child: Align(alignment: Alignment.centerLeft, child: c),
            ),
          ),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.55),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// The whole-strip half of the song-change transition: a one-shot wash of the
/// incoming track's own color that rises fast and decays slowly, handed to
/// [builder] as a 0..1 `bloom`. Fires only on a real track change (never on
/// the first build, and never on a position/artwork update), and is a flat 0
/// under reduced motion.
class _TrackBloom extends StatefulWidget {
  const _TrackBloom({
    required this.trackId,
    required this.accent,
    required this.builder,
  });

  final String trackId;
  final Color accent;
  final Widget Function(BuildContext context, double bloom) builder;

  @override
  State<_TrackBloom> createState() => _TrackBloomState();
}

class _TrackBloomState extends State<_TrackBloom>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Snap up, ease down — the shape of something landing, rather than a
  // symmetrical pulse that reads as a loading blink.
  late final Animation<double> _bloom = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: 1.0).chain(
        CurveTween(curve: Curves.easeOutCubic),
      ),
      weight: 22,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.0).chain(
        CurveTween(curve: Curves.easeOutCubic),
      ),
      weight: 78,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant _TrackBloom old) {
    super.didUpdateWidget(old);
    if (old.trackId == widget.trackId) return;
    if (reducedMotion(context)) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bloom,
      builder: (context, _) => widget.builder(context, _bloom.value),
    );
  }
}

/// Track title — the app's own UI face, never wrapped to a second line.
class _Title extends StatelessWidget {
  const _Title(this.text, {required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TrainType.ui(
      size: size,
      weight: FontWeight.w700,
      color: TrainColors.inkPlain,
    ),
  );
}

class _Artist extends StatelessWidget {
  const _Artist(this.text, {required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TrainType.mono(
      size: size,
      tracking: 0.02,
      height: 1.2,
      color: const Color(0x61F4F4F0),
    ),
  );
}

/// A transport glyph with a real tap target around it. Disabled (dimmed,
/// inert) when another Spotify Connect device owns playback — visible but not
/// drivable, which is Spotify's normal multi-device model, not an error.
class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    required this.enabled,
    this.size = 40,
  });

  final Widget child;
  final Future<void> Function() onTap;
  final String semanticLabel;
  final bool enabled;

  /// The tap target's edge. Trimmed from 40 on the one-row densities, where
  /// three of these sit beside the artwork tile and the text needs the room.
  final double size;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: enabled,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: InkResponse(
          radius: size * 0.55,
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
              : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Opacity(opacity: enabled ? 1 : 0.4, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Interpolates the playhead forward between the controller's coarse
/// emissions so timecodes and the scrub line tick every frame instead of
/// jumping once a second — the same trick the full player's scrubber uses.
/// Re-anchors (and corrects drift) on every emission.
class TickingPlayhead extends StatefulWidget {
  const TickingPlayhead({
    required this.position,
    required this.duration,
    required this.isPaused,
    required this.builder,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final bool isPaused;

  /// Called with the interpolated position and the 0..1 fraction.
  final Widget Function(BuildContext, Duration, double) builder;

  @override
  State<TickingPlayhead> createState() => _TickingPlayheadState();
}

class _TickingPlayheadState extends State<TickingPlayhead>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this)
    ..value = _fraction;

  double get _fraction {
    if (widget.duration.inMilliseconds <= 0) return 0;
    return (widget.position.inMilliseconds / widget.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _retarget());
  }

  void _retarget() {
    if (!mounted) return;
    _c.stop();
    _c.value = _fraction;
    if (widget.isPaused || reducedMotion(context)) return;
    final remaining = widget.duration - widget.position;
    if (remaining > Duration.zero) {
      _c.animateTo(1, duration: remaining, curve: Curves.linear);
    }
  }

  @override
  void didUpdateWidget(covariant TickingPlayhead old) {
    super.didUpdateWidget(old);
    _retarget();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final fraction = _c.value.clamp(0.0, 1.0);
        final position = Duration(
          milliseconds: (widget.duration.inMilliseconds * fraction).round(),
        );
        return widget.builder(context, position, fraction);
      },
    );
  }
}

String _mmss(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}
