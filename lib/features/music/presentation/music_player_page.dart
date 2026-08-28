import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/train_tokens.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/rise_in.dart';
import '../../../core/widgets/train_chrome.dart';
import '../domain/audio_output.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'artwork_palette_service.dart';
import 'equalizer_glyph.dart';
import 'music_artwork.dart';
import 'music_scrubber.dart';

/// The full-screen **Now Playing** player — pushed from [NowPlayingBar] as a
/// fullscreen-dialog route (the platform's own symmetric slide-up/down; nothing
/// bespoke is added here).
///
/// ## A deliberate, owner-signed divergence from the handoff
///
/// The workout-tracking `IDENTITY.md` bans album art ("text over imagery") and
/// makes the strips text-first. This screen is the **one place** that departs
/// from that, on the owner's call: the player is *immersive* — the cover is the
/// hero, and the whole screen's neon glow, scrub line and accents are pulled
/// live from the artwork and animate smoothly as the track changes (see
/// [ArtworkPalette] / [ArtworkColors]). Everywhere else the text-first rule
/// still holds; this is the cover-adaptive moment users expect from a player,
/// dressed in ZIVO's own glow language rather than Spotify's.
///
/// It still obeys the rest of the system: dark handoff ground, Manrope +
/// Azeret Mono, ember reserved for the single committing action (play/pause),
/// green for "playing / Spotify", one soft glow, mono timecodes.
class MusicPlayerPage extends StatelessWidget {
  const MusicPlayerPage({required this.controller, super.key});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    // Outer subscription drives ONLY the artwork-derived colours (a
    // presentation concern) — the connection/now-playing logic below keeps its
    // own subscriptions untouched. The colours stay inside this builder; they
    // are never passed out of the music UI.
    return StreamBuilder<NowPlaying?>(
      stream: controller.nowPlaying,
      initialData: controller.currentNowPlaying,
      builder: (context, paletteSnap) {
        final track = paletteSnap.data;
        return ArtworkPalette(
          trackId: track?.trackId,
          artworkBytes: track?.artworkBytes,
          builder: (context, colours) => Scaffold(
            backgroundColor: colours.background,
            body: Stack(
              children: [
                // The one soft radial glow this screen is allowed — pulled from
                // the cover and breathing slowly behind everything.
                Positioned.fill(child: _AmbientGlow(accent: colours.accent)),
                // Positioned.fill (not a loose Stack child) so the scroll view
                // fills the height instead of shrink-wrapping to its content.
                // That gives BouncingScrollPhysics room to overscroll even when
                // the player fits the screen — which is what pull-to-dismiss
                // rides. It hands down tight constraints WITHOUT querying child
                // intrinsics, so it's safe past MusicScrubber's LayoutBuilder
                // (unlike IntrinsicHeight / SliverFillRemaining — see §4).
                Positioned.fill(
                  child: SafeArea(
                    child: StreamBuilder<MusicConnection>(
                      stream: controller.connection,
                      initialData: controller.currentConnection,
                      builder: (context, connSnap) {
                        final state =
                            connSnap.data ?? MusicConnection.disconnected;
                        if (state != MusicConnection.connected) {
                          return _ConnectionState(
                            state: state,
                            onConnect: controller.connect,
                          );
                        }
                        return StreamBuilder<NowPlaying?>(
                          stream: controller.nowPlaying,
                          initialData: controller.currentNowPlaying,
                          builder: (context, snap) {
                            final playing = snap.data;
                            if (playing == null) return const _NothingPlaying();
                            return _ImmersivePlayer(
                              controller: controller,
                              playing: playing,
                              colours: colours,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A large, soft, breathing radial bloom in the track's neon accent — the
/// depth-from-light the handoff calls for, here made to react to the song.
/// Sits under all content; never interactive.
class _AmbientGlow extends StatefulWidget {
  const _AmbientGlow({required this.accent});

  final Color accent;

  @override
  State<_AmbientGlow> createState() => _AmbientGlowState();
}

class _AmbientGlowState extends State<_AmbientGlow>
    with SingleTickerProviderStateMixin {
  // 6s breathe, matching the handoff's screen-glow motion (opacity .55 → .9).
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) {
      return _GlowPaint(accent: widget.accent, breath: 0.75);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) =>
          _GlowPaint(accent: widget.accent, breath: 0.55 + 0.35 * _c.value),
    );
  }
}

class _GlowPaint extends StatelessWidget {
  const _GlowPaint({required this.accent, required this.breath});

  final Color accent;
  final double breath;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            // Centred on where the artwork sits (upper third).
            center: const Alignment(0, -0.5),
            radius: 1.15,
            colors: [
              accent.withValues(alpha: 0.26 * breath),
              accent.withValues(alpha: 0.06 * breath),
              Colors.transparent,
            ],
            stops: const [0.0, 0.42, 0.82],
          ),
        ),
      ),
    );
  }
}

/// The connected player: one animated scroll from the collapse chevron down to
/// the transport, so nothing reads as a detached component. On tall screens the
/// groups distribute top / centre / bottom; on short ones the whole thing
/// scrolls as a unit.
class _ImmersivePlayer extends StatefulWidget {
  const _ImmersivePlayer({
    required this.controller,
    required this.playing,
    required this.colours,
  });

  final MusicController controller;
  final NowPlaying playing;
  final ArtworkColors colours;

  @override
  State<_ImmersivePlayer> createState() => _ImmersivePlayerState();
}

/// Adds **pull-down-to-dismiss** on top of the single scroll. It rides the
/// scroll view's own `BouncingScrollPhysics` overscroll rather than a competing
/// gesture, so normal vertical scrolling is never intercepted: only once the
/// content is at the top and the finger keeps pulling down does the surface
/// follow it — that downward travel is the physics' own rubber-band, which we
/// simply fade and gently recede as it grows — and releasing past a threshold
/// pops the route. Released short, the physics springs it back and the fade
/// follows it home, no bespoke animation. The finger-up decision comes from a
/// passive [Listener] (which never joins the gesture arena, so it can't disturb
/// the scroll), not `ScrollEndNotification` — that one is delayed until the
/// bounce fully settles, by which point the pull distance is already gone.
class _ImmersivePlayerState extends State<_ImmersivePlayer> {
  /// Live overscroll distance (px past the top). Drives the dismiss transform;
  /// a [ValueNotifier] so only the thin transform wrapper rebuilds each frame of
  /// a pull — never the whole scroll subtree underneath it.
  final ValueNotifier<double> _pull = ValueNotifier<double>(0);

  /// Owned so the scroll position SURVIVES rebuilds. The player rebuilds on
  /// every `nowPlaying` emission (position ticks, pause, artwork arriving); a
  /// controller-less scroll view would spin up a fresh `ScrollPosition` at 0 on
  /// each one — resetting any scroll mid-interaction and, worse, detaching an
  /// in-progress pull-to-dismiss drag from under the finger.
  final ScrollController _scroll = ScrollController();

  /// Releasing past this many px of pull dismisses; below it springs back.
  static const double _dismissThreshold = 116;

  /// Pull at which the fade/scale reach full — a little beyond the threshold, so
  /// the surface reads as clearly "leaving" by the time it commits.
  static const double _pullRange = 260;

  bool _dismissing = false;

  bool _onScroll(ScrollNotification notification) {
    if (_dismissing) return false;
    final pixels = notification.metrics.pixels;
    // BouncingScrollPhysics lets pixels dip below minScrollExtent (0) at the top
    // — that negative amount IS the downward pull. Reading it here tracks both
    // the finger drag and the ballistic spring-back, so the transform trails the
    // surface all the way home on a short release for free.
    final pull = pixels < 0 ? -pixels : 0.0;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // The spring-back can correct the position DURING layout/paint; poking the
      // notifier now would "schedule a build during frame". Apply it right after
      // this frame instead — one frame of lag on the fade is imperceptible.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_dismissing) _pull.value = pull;
      });
    } else {
      _pull.value = pull;
    }
    return false;
  }

  void _onPointerUp() {
    if (_dismissing) return;
    if (_pull.value >= _dismissThreshold) {
      // Freeze the transform where it was released and let the route's own
      // slide-down carry it the rest of the way (see _onScroll's early-out).
      _dismissing = true;
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _pull.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final playing = widget.playing;
    final accent = widget.colours.accent;
    final artworkSide = (MediaQuery.of(context).size.width * 0.66).clamp(
      200.0,
      320.0,
    );

    // One cohesive top-to-bottom scroll — not distributed with `spaceBetween`,
    // because a fill-to-viewport wrapper (`IntrinsicHeight` /
    // `SliverFillRemaining`) queries child intrinsics, which crashes against
    // `MusicScrubber`'s internal `LayoutBuilder`. The generous, tuned gaps do
    // the balancing instead, and the whole thing scrolls as a unit on short
    // screens / large text.
    final scroll = SingleChildScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiseIn(child: _TopBar(onClose: () => Navigator.of(context).pop())),
          const SizedBox(height: 22),
          RiseIn(
            delay: const Duration(milliseconds: 80),
            child: Column(
              children: [
                _SpotifyBrand(accent: accent, isPlaying: !playing.isPaused),
                const SizedBox(height: 26),
                _ArtworkHero(
                  bytes: playing.artworkBytes,
                  url: playing.artworkUrl,
                  accent: accent,
                  side: artworkSide,
                ),
                const SizedBox(height: 32),
                _TrackMeta(playing: playing),
              ],
            ),
          ),
          const SizedBox(height: 42),
          RiseIn(
            delay: const Duration(milliseconds: 150),
            child: Column(
              children: [
                MusicScrubber(
                  controller: controller,
                  trackId: playing.trackId,
                  duration: playing.duration,
                  position: playing.position,
                  isPaused: playing.isPaused,
                  accentColor: accent,
                ),
                if (!playing.hasControl) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Playing on another device — controls are read-only here.',
                    textAlign: TextAlign.center,
                    style: TrainType.caption(
                      size: 10,
                      tracking: 0.04,
                      color: TrainColors.ink3,
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                _Controls(
                  controller: controller,
                  playing: playing,
                  accent: accent,
                ),
                // The output-device row — shown ONLY when the route is known,
                // so it reclaims its own space rather than sitting empty
                // (handoff: nothing shifts when a module is absent). Its own
                // stream so a route change (unplug headphones) updates it live.
                StreamBuilder<AudioOutput?>(
                  stream: controller.output,
                  initialData: controller.currentOutput,
                  builder: (context, snap) {
                    final out = snap.data;
                    if (out == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: _OutputRow(output: out),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final reduce = reducedMotion(context);
    return Listener(
      // Passive — a Listener never enters the gesture arena, so it reads the
      // finger-up without stealing anything from the scroll view.
      onPointerUp: (_) => _onPointerUp(),
      onPointerCancel: (_) => _onPointerUp(),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ValueListenableBuilder<double>(
          valueListenable: _pull,
          child: scroll,
          builder: (context, pull, child) {
            // Structurally stable on purpose: Opacity + Transform are ALWAYS in
            // the tree (identity at rest), so the scroll view's render object
            // never reparents when the pull starts — reparenting it mid-drag
            // cancels the very gesture doing the pulling. The downward
            // finger-follow is the scroll's own BouncingScrollPhysics overscroll
            // (adding a Transform.translate here both double-moved it and broke
            // the drag); we only fade and gently recede the surface as it goes,
            // and Transform keeps `transformHitTests: false` so it can't perturb
            // the live pointer either.
            final t = (pull / _pullRange).clamp(0.0, 1.0);
            return Opacity(
              opacity: 1 - 0.4 * t,
              child: Transform.scale(
                scale: reduce ? 1.0 : 1 - 0.04 * t,
                alignment: Alignment.topCenter,
                transformHitTests: false,
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Collapse chevron on the left, a centred caption, and a balancing gap on the
/// right so the caption stays optically centred.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TrainCircleButton(
          semanticLabel: 'Close player',
          onTap: onClose,
          child: const Icon(
            AppIcons.chevronDown,
            size: 20,
            color: TrainColors.ink2,
          ),
        ),
        const Expanded(
          child: Center(child: TrainCaption('NOW PLAYING', tracking: 0.22)),
        ),
        // Balances the chevron's tap target so the caption is truly centred.
        const SizedBox(width: TrainCircleButton.target),
      ],
    );
  }
}

/// The Spotify source badge — the real logo asset (never recoloured, per the
/// trademark note in the feature map) + a live equalizer so it reads as
/// *playing from Spotify*, not just a static label.
class _SpotifyBrand extends StatelessWidget {
  const _SpotifyBrand({required this.accent, required this.isPlaying});

  final Color accent;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/spotify/spotify-icon.png',
          width: 16,
          height: 16,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(width: 8),
        Text(
          'SPOTIFY',
          style: TrainType.caption(
            size: 9.5,
            tracking: 0.2,
            color: TrainColors.green,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        EqualizerGlyph(
          bars: 4,
          width: 16,
          height: 12,
          color: accent,
          playing: isPlaying,
        ),
      ],
    );
  }
}

/// The album cover as the hero, floating on a black depth shadow plus a soft
/// glow in the track's own accent — the artwork literally lights the room in
/// its colour.
class _ArtworkHero extends StatelessWidget {
  const _ArtworkHero({
    required this.bytes,
    required this.url,
    required this.accent,
    required this.side,
  });

  final Uint8List? bytes;
  final String? url;
  final Color accent;
  final double side;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            // Quiet physical depth.
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 40,
              spreadRadius: -12,
              offset: const Offset(0, 20),
            ),
            // The neon halo — the artwork's own colour, wide and soft.
            BoxShadow(
              color: accent.withValues(alpha: 0.34),
              blurRadius: 60,
              spreadRadius: -18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: MusicArtwork(
          bytes: bytes,
          url: url,
          size: side,
          iconSize: 66,
          borderRadius: 24,
        ),
      ),
    );
  }
}

/// Title (the screen's one large element — type, not a number) + artist. One
/// line each; the title truncates, never wraps.
class _TrackMeta extends StatelessWidget {
  const _TrackMeta({required this.playing});

  final NowPlaying playing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          playing.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TrainType.ui(
            size: 26,
            weight: FontWeight.w800,
            tracking: -0.03,
            color: TrainColors.ink,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          playing.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TrainType.mono(
            size: 13,
            tracking: 0.02,
            color: TrainColors.ink2,
          ),
        ),
      ],
    );
  }
}

/// The transport row: shuffle · prev · the one ember action · next · repeat.
///
/// Shuffle and repeat render live from the observed [NowPlaying] (never a local
/// toggle) and request the change through the controller; the new state flows
/// back on `nowPlaying`, exactly like play/pause. Repeat derives its own
/// `off → all → one → off` cycle from the current mode. Both are disabled — but
/// still show their state — when another device owns playback ([hasControl]
/// false), consistent with prev/next.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.playing,
    required this.accent,
  });

  final MusicController controller;
  final NowPlaying playing;
  final Color accent;

  static MusicRepeatMode _nextRepeat(MusicRepeatMode mode) => switch (mode) {
    MusicRepeatMode.off => MusicRepeatMode.all,
    MusicRepeatMode.all => MusicRepeatMode.one,
    MusicRepeatMode.one => MusicRepeatMode.off,
  };

  @override
  Widget build(BuildContext context) {
    final enabled = playing.hasControl;
    final repeat = playing.repeatMode;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _IconControl(
          icon: AppIcons.shuffle,
          semanticLabel: playing.isShuffling ? 'Shuffle on' : 'Shuffle off',
          active: playing.isShuffling,
          activeColor: accent,
          enabled: enabled,
          onTap: () {
            HapticFeedback.selectionClick();
            controller.setShuffle(!playing.isShuffling);
          },
        ),
        _IconControl(
          glyph: const TrainPlayGlyph(
            color: TrainColors.ink,
            size: 18,
            bar: true,
          ),
          flip: true,
          semanticLabel: 'Previous track',
          enabled: enabled,
          onTap: () {
            HapticFeedback.lightImpact();
            controller.previous();
          },
        ),
        _BigPlayButton(controller: controller, playing: playing),
        _IconControl(
          glyph: const TrainPlayGlyph(
            color: TrainColors.ink,
            size: 18,
            bar: true,
          ),
          semanticLabel: 'Next track',
          enabled: enabled,
          onTap: () {
            HapticFeedback.lightImpact();
            controller.next();
          },
        ),
        _IconControl(
          icon: repeat == MusicRepeatMode.one
              ? AppIcons.repeatOne
              : AppIcons.repeat,
          semanticLabel: switch (repeat) {
            MusicRepeatMode.off => 'Repeat off',
            MusicRepeatMode.all => 'Repeat all',
            MusicRepeatMode.one => 'Repeat one',
          },
          active: repeat != MusicRepeatMode.off,
          activeColor: accent,
          enabled: enabled,
          onTap: () {
            HapticFeedback.selectionClick();
            controller.setRepeat(_nextRepeat(repeat));
          },
        ),
      ],
    );
  }
}

/// A 52px tap target holding either a Lucide [icon] (shuffle/repeat) or a
/// filled [glyph] (prev/next). [active] tints it with the track accent;
/// [enabled] false dims and inerts it (another device owns playback).
class _IconControl extends StatelessWidget {
  const _IconControl({
    this.icon,
    this.glyph,
    required this.semanticLabel,
    required this.onTap,
    this.active = false,
    this.enabled = true,
    this.flip = false,
    this.activeColor = TrainColors.green,
  });

  final IconData? icon;
  final Widget? glyph;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  /// Mirrors the glyph horizontally — turns the "next" triangle into "prev".
  final bool flip;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    Widget child =
        glyph ??
        Icon(icon, size: 21, color: active ? activeColor : TrainColors.ink2);
    if (flip) {
      child = Transform.flip(flipX: true, child: child);
    }
    return PressableScale(
      enabled: enabled,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: InkResponse(
          radius: 26,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Center(
              child: Opacity(opacity: enabled ? 1 : 0.4, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// The single committing action — a 76px ember disc under its own coloured
/// bloom (the only shadow the system allows). Falls back to a flat glass disc
/// when another device owns playback.
class _BigPlayButton extends StatelessWidget {
  const _BigPlayButton({required this.controller, required this.playing});

  final MusicController controller;
  final NowPlaying playing;

  @override
  Widget build(BuildContext context) {
    final enabled = playing.hasControl;
    final paused = playing.isPaused;
    return PressableScale(
      scale: 0.96,
      enabled: enabled,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: enabled ? TrainColors.actionGlow(TrainColors.ember) : null,
        ),
        child: Material(
          color: enabled ? TrainColors.ember : TrainColors.glassStrong,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: !enabled
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    paused ? controller.play() : controller.pause();
                  },
            child: SizedBox(
              width: 76,
              height: 76,
              child: Center(
                child: paused
                    ? TrainPlayGlyph(
                        color: enabled ? Colors.white : TrainColors.ink3,
                        size: 28,
                      )
                    : TrainPauseGlyph(
                        color: enabled ? Colors.white : TrainColors.ink3,
                        size: 26,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The current audio route — "AirPods Pro · 72%" in the design. Informational
/// (no chevron): ZIVO can't drive the OS route picker, so it reports where
/// sound is going rather than pretending to switch it. Green reads as an active
/// output. Only built when a device is actually known (see the caller).
class _OutputRow extends StatelessWidget {
  const _OutputRow({required this.output});

  final AudioOutput output;

  IconData get _icon => switch (output.kind) {
    AudioOutputKind.bluetooth => AppIcons.bluetooth,
    AudioOutputKind.headphones => AppIcons.headphones,
    AudioOutputKind.speaker => AppIcons.speaker,
    AudioOutputKind.phone => AppIcons.speaker,
    AudioOutputKind.unknown => AppIcons.headphones,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 18, color: TrainColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              output.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TrainType.ui(
                size: 13,
                weight: FontWeight.w600,
                color: TrainColors.inkPlain,
                height: 1,
              ),
            ),
          ),
          if (output.batteryPercent != null) ...[
            const SizedBox(width: 10),
            Text(
              '${output.batteryPercent}%',
              style: TrainType.mono(
                size: 12,
                tracking: 0.02,
                color: TrainColors.ink2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The non-`connected` states — each with copy specific to what's actually
/// wrong, rather than one generic "can't connect" message. This is the music
/// feature's only always-reachable surface (the Profile tab's Music row opens
/// straight here regardless of connection state — see `profile_page.dart`), so
/// it has to carry every state on its own.
class _ConnectionState extends StatelessWidget {
  const _ConnectionState({required this.state, required this.onConnect});

  final MusicConnection state;
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    final (icon, message, connectLabel) = switch (state) {
      // Generic and non-misleading on purpose — see MusicConnection.authFailed's
      // doc comment for why this doesn't name a specific cause.
      MusicConnection.authFailed => (
        Icons.error_outline_rounded,
        "Couldn't connect to Spotify. Make sure the Spotify app is open "
            "and you're signed in, then try again.",
        'Try again',
      ),
      MusicConnection.needsPremium => (
        Icons.workspace_premium_outlined,
        'Spotify Premium is required to control playback here.',
        null,
      ),
      MusicConnection.noSpotifyApp => (
        Icons.error_outline_rounded,
        'Install Spotify to connect.',
        null,
      ),
      MusicConnection.connecting => (Icons.sync_rounded, 'Connecting…', null),
      MusicConnection.disconnected || MusicConnection.connected => (
        Icons.music_note_rounded,
        "Connect Spotify to see what's playing.",
        'Connect Spotify',
      ),
    };
    return Column(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 0, 0),
            child: TrainCircleButton(
              semanticLabel: 'Close player',
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(
                AppIcons.chevronDown,
                size: 20,
                color: TrainColors.ink2,
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 30, color: TrainColors.ink3),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TrainType.ui(
                      size: 14,
                      weight: FontWeight.w500,
                      color: TrainColors.ink2,
                      height: 1.5,
                    ),
                  ),
                  if (connectLabel != null) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 220,
                      child: TrainPrimaryButton(
                        label: connectLabel,
                        color: TrainColors.green,
                        labelColor: const Color(0xFF04140D),
                        onTap: onConnect,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Nothing playing right now.',
        style: TrainType.ui(
          size: 14,
          weight: FontWeight.w500,
          color: TrainColors.ink2,
        ),
      ),
    );
  }
}
