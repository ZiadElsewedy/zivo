import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/train_tokens.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/train_chrome.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'equalizer_glyph.dart';

/// The text-first Spotify strips used across the workout-tracking screens.
///
/// From the design handoff: **there is no album-art tile.** The music is
/// presented as instrumentation — a live equalizer glyph, the track set in
/// the app's own UI font, and mono timecodes — precisely so it doesn't
/// compete with the screen's hero number for attention. Three densities:
///
/// * [SpotifyStrip.full] — Today: two rows, with the scrub line and timecodes.
/// * [SpotifyStrip.inline] — Active Set: one row, title + artist + remaining.
/// * [SpotifyStrip.rest] — Rest: one row with prev / play-pause / next.
enum SpotifyStripDensity { full, inline, rest }

class SpotifyStrip extends StatelessWidget {
  const SpotifyStrip({
    required this.controller,
    required this.playing,
    required this.density,
    this.onOpen,
    super.key,
  });

  const SpotifyStrip.full({
    required MusicController controller,
    required NowPlaying playing,
    VoidCallback? onOpen,
    Key? key,
  }) : this(
         controller: controller,
         playing: playing,
         density: SpotifyStripDensity.full,
         onOpen: onOpen,
         key: key,
       );

  const SpotifyStrip.inline({
    required MusicController controller,
    required NowPlaying playing,
    VoidCallback? onOpen,
    Key? key,
  }) : this(
         controller: controller,
         playing: playing,
         density: SpotifyStripDensity.inline,
         onOpen: onOpen,
         key: key,
       );

  const SpotifyStrip.rest({
    required MusicController controller,
    required NowPlaying playing,
    VoidCallback? onOpen,
    Key? key,
  }) : this(
         controller: controller,
         playing: playing,
         density: SpotifyStripDensity.rest,
         onOpen: onOpen,
         key: key,
       );

  final MusicController controller;
  final NowPlaying playing;
  final SpotifyStripDensity density;

  /// Opens the full player. Null makes the strip's body inert (the transport
  /// controls still work).
  final VoidCallback? onOpen;

  bool get _isFull => density == SpotifyStripDensity.full;

  @override
  Widget build(BuildContext context) {
    final body = TickingPlayhead(
      key: ValueKey(playing.trackId),
      position: playing.position,
      duration: playing.duration,
      isPaused: playing.isPaused,
      builder: (context, position, fraction) => switch (density) {
        SpotifyStripDensity.full => _full(context, position, fraction),
        SpotifyStripDensity.inline => _inline(context, position),
        SpotifyStripDensity.rest => _rest(context, position),
      },
    );

    return PressableScale(
      scale: 0.99,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_isFull ? 20 : 16),
          onTap: onOpen,
          child: Container(
            padding: _isFull
                ? const EdgeInsets.fromLTRB(15, 13, 15, 12)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: _isFull ? TrainColors.glass : const Color(0x08FFFFFF),
              borderRadius: BorderRadius.circular(_isFull ? 20 : 16),
              border: Border.all(
                color: _isFull
                    ? TrainColors.hairline
                    : const Color(0x0FFFFFFF),
              ),
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  // ---- Today ---------------------------------------------------------------

  Widget _full(BuildContext context, Duration position, double fraction) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            EqualizerGlyph(
              bars: 4,
              width: 20,
              height: 19,
              playing: !playing.isPaused,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Title(playing.title, size: 13),
                  const SizedBox(height: 3),
                  _Artist(playing.artist, size: 10.5),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _TransportButton(
              enabled: playing.hasControl,
              semanticLabel: playing.isPaused ? 'Play' : 'Pause',
              onTap: () =>
                  playing.isPaused ? controller.play() : controller.pause(),
              child: playing.isPaused
                  ? const TrainPlayGlyph(
                      color: TrainColors.inkPlain,
                      size: 15,
                    )
                  : const TrainPauseGlyph(
                      color: TrainColors.inkPlain,
                      size: 15,
                    ),
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
                  valueColor: const AlwaysStoppedAnimation(TrainColors.green),
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
                color: TrainColors.green.withValues(alpha: 0.6),
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
        EqualizerGlyph(playing: !playing.isPaused),
        const SizedBox(width: 11),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(child: _Title(playing.title, size: 12)),
              const SizedBox(width: 8),
              Flexible(child: _Artist(playing.artist, size: 10)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '-${_mmss(playing.duration - position)}',
          style: TrainType.mono(size: 9, color: const Color(0x59F4F4F0)),
        ),
        const SizedBox(width: 10),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: 'Next track',
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
        EqualizerGlyph(playing: !playing.isPaused),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
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
        const SizedBox(width: 8),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: 'Previous track',
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
          onTap: () =>
              playing.isPaused ? controller.play() : controller.pause(),
          child: playing.isPaused
              ? const TrainPlayGlyph(color: TrainColors.green, size: 13)
              : const TrainPauseGlyph(color: TrainColors.green, size: 13),
        ),
        _TransportButton(
          enabled: playing.hasControl,
          semanticLabel: 'Next track',
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

/// A transport glyph with a real 40px tap target around it. Disabled (dimmed,
/// inert) when another Spotify Connect device owns playback — visible but not
/// drivable, which is Spotify's normal multi-device model, not an error.
class _TransportButton extends StatelessWidget {
  const _TransportButton({
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
          radius: 22,
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
              : null,
          child: SizedBox(
            width: 40,
            height: 40,
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
