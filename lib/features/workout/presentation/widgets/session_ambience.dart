import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../music/domain/music_connection.dart';
import '../../../music/domain/music_controller.dart';
import '../../../music/domain/now_playing.dart';
import '../../../../core/theme/train_tokens.dart';

/// The whole-session music ambience — the workout player's answer to "the
/// screen should feel the music, not just the Spotify card".
///
/// It listens to the [MusicController]'s connection + now-playing streams and,
/// whenever a track with artwork is live, derives two chroma-disciplined
/// colours from the cover once per track: a deep, near-neutral [_ambientWash]
/// for the whole-screen tint (calmest swatch, saturation hard-capped) and a
/// clamped-legible foreground accent (vibrant swatch, held to a tasteful
/// ceiling). The pair is published down the tree via [SessionAmbience.of] so
/// every layer
/// of the session — background wash, progress bar, rest ring, card glows —
/// can pick it up and the whole surface reads as one cohesive, reactive
/// visual instead of a single tinted widget floating over a static screen.
///
/// With no music connected (or nothing loaded) the accent is null and every
/// consumer falls back to its existing neutral/pulse styling — pixel-identical
/// to the pre-music look. Extraction is cached per track key
/// (`title|artist`), so skipping back and forth doesn't re-run the palette.
class SessionAmbience extends StatefulWidget {
  const SessionAmbience({
    required this.controller,
    required this.child,
    super.key,
  });

  final MusicController? controller;
  final Widget child;

  /// The current track's accent color for the nearest [SessionAmbience]
  /// above [context], or null when there is none (no music / no artwork yet).
  /// Subscribing: an accent change (track change, artwork resolved) rebuilds.
  ///
  /// This is the **ambient** accent — a chroma-capped deep tint (see
  /// [_ambientWash]), so it can wash a whole background without glare and can
  /// never go garish however loud the cover is. For anything drawn ON that
  /// ground (a ring sweep, a transport glyph, a label) use [vividOf] instead:
  /// this one is deliberately too close to the background to read as a
  /// foreground mark.
  static Color? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AmbienceScope>()?.data.accent;

  /// The same track accent, normalised for use as a **foreground** color on
  /// the session's near-black ground — saturation and lightness clamped into
  /// a band that stays legible whatever the album art happens to be (a
  /// near-black cover would otherwise hand the transport controls a color
  /// indistinguishable from the background, and a white one would blow out).
  static Color? vividOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AmbienceScope>()?.data.vivid;

  /// The identity of whatever is playing right now — changes exactly when
  /// the track does. Consumers key their track-change motion off this so a
  /// mere artwork/position update doesn't re-trigger it.
  static String? trackKeyOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_AmbienceScope>()
      ?.data
      .trackKey;

  @override
  State<SessionAmbience> createState() => _SessionAmbienceState();
}

class _SessionAmbienceState extends State<SessionAmbience> {
  Color? _accent;
  Color? _vivid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final controller = widget.controller;
    if (controller == null) return;
    if (controller.currentConnection != MusicConnection.connected) return;
    final playing = controller.currentNowPlaying;
    if (playing != null) _extractAccent(playing);
  }

  String _keyOf(NowPlaying p) => '${p.title}|${p.artist}';

  /// Never calls [setState] synchronously — callers invoke it from `build`,
  /// so both the cached fast path and the extraction completion land through
  /// a post-frame callback.
  void _extractAccent(NowPlaying playing) {
    if (!mounted) return;
    final bytes = playing.artworkBytes;
    final key = _keyOf(playing);
    if (bytes == null || bytes.isEmpty) return;
    final cached = _accentCache[key];
    if (cached != null) {
      if (_accent != cached.ambient) _apply(cached);
      return;
    }
    unawaited(_runExtraction(bytes, key));
  }

  Future<void> _runExtraction(Uint8List bytes, String key) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(96, 96),
      );
      final fallback = palette.colors.isEmpty ? null : palette.colors.first;
      // The two jobs pull from DIFFERENT swatches on purpose. The whole-screen
      // ambient wash starts from the cover's *calmest* swatch (muted before
      // vibrant), so the background is grounded in the quiet hue rather than
      // the neon one. The small foreground mark starts from the *vibrant*
      // swatch — once it's clamped legible it can afford to carry the cover's
      // actual colour.
      final ambientRaw = palette.darkMutedColor?.color ??
          palette.mutedColor?.color ??
          palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          fallback;
      final vividRaw = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.dominantColor?.color ??
          ambientRaw;
      if (ambientRaw == null || !mounted) return;
      // Ambient: chroma-disciplined deep tint (see [_ambientWash]). Vivid:
      // clamped into a legible band (see [SessionAmbience.vividOf]) for marks
      // drawn on top of that ground.
      final accent = (
        ambient: _ambientWash(ambientRaw),
        vivid: _legible(vividRaw ?? ambientRaw),
      );
      _accentCache[key] = accent;
      _apply(accent);
    } catch (_) {
      // Artwork failed to decode — neutral fallback is fine.
    }
  }

  void _apply(_Accent accent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _accent == accent.ambient) return;
      setState(() {
        _accent = accent.ambient;
        _vivid = accent.vivid;
      });
    });
  }

  /// The whole-screen ambient wash. Reduces an album swatch to a deep,
  /// near-neutral tint: the cover's hue survives as a *hint*, but saturation
  /// is hard-capped (≤0.16) and lightness pulled into a narrow dark band. A
  /// neon-pink cover lands as a warm charcoal, a blue one as deep slate — the
  /// wash reads as premium ambient light in the room, never a sampled
  /// billboard.
  ///
  /// This replaced a straight lerp toward the ground tone, which darkened the
  /// swatch but *kept* its chroma, so loud covers still washed the whole
  /// screen pink/purple.
  static Color _ambientWash(Color raw) {
    final hsl = HSLColor.fromColor(raw);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.0, 0.16))
        .withLightness(hsl.lightness.clamp(0.10, 0.14))
        .toColor();
  }

  /// Clamps an album swatch into the saturation/lightness band that stays a
  /// tasteful foreground on [TrainColors.base]. The ceiling is deliberately
  /// low (0.55, not near-1.0) so the rest-ring sweep and transport controls
  /// read as a refined accent, never neon. Hue — the part that actually
  /// carries the track's identity — is left untouched.
  static Color _legible(Color raw) {
    final hsl = HSLColor.fromColor(raw);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.30, 0.55))
        .withLightness(hsl.lightness.clamp(0.60, 0.70))
        .toColor();
  }

  /// Per-track extraction cache — shared across phase rebuilds so a track's
  /// palette runs exactly once per process.
  static final Map<String, _Accent> _accentCache = {};

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) {
      return _AmbienceScope(
        data: const _AmbienceData(accent: null, vivid: null, trackKey: null),
        child: widget.child,
      );
    }
    return StreamBuilder<MusicConnection>(
      stream: controller.connection,
      initialData: controller.currentConnection,
      builder: (context, connSnap) {
        if (connSnap.data != MusicConnection.connected) {
          return _AmbienceScope(
            data: const _AmbienceData(
              accent: null,
              vivid: null,
              trackKey: null,
            ),
            child: widget.child,
          );
        }
        return StreamBuilder<NowPlaying?>(
          stream: controller.nowPlaying,
          initialData: controller.currentNowPlaying,
          builder: (context, nowSnap) {
            final playing = nowSnap.data;
            // A track swap invalidates immediately (the new accent lands
            // when extraction finishes); nothing loaded clears to neutral.
            final cached = playing == null
                ? null
                : _accentCache[_keyOf(playing)];
            final accentForTrack = playing == null
                ? null
                : (cached?.ambient ?? _accent);
            final vividForTrack = playing == null
                ? null
                : (cached?.vivid ?? _vivid);
            if (playing != null) _extractAccent(playing);
            return _AmbienceScope(
              data: _AmbienceData(
                accent: accentForTrack,
                vivid: vividForTrack,
                trackKey: playing?.trackId,
              ),
              child: widget.child,
            );
          },
        );
      },
    );
  }
}

/// The two derivations of one album-art swatch — see
/// [SessionAmbience.of] (ambient) and [SessionAmbience.vividOf] (vivid).
typedef _Accent = ({Color ambient, Color vivid});

class _AmbienceData {
  const _AmbienceData({
    required this.accent,
    required this.vivid,
    required this.trackKey,
  });

  final Color? accent;
  final Color? vivid;
  final String? trackKey;
}

class _AmbienceScope extends InheritedWidget {
  const _AmbienceScope({required this.data, required super.child});

  final _AmbienceData data;

  @override
  bool updateShouldNotify(_AmbienceScope oldWidget) =>
      oldWidget.data.accent != data.accent ||
      oldWidget.data.vivid != data.vivid ||
      oldWidget.data.trackKey != data.trackKey;
}
