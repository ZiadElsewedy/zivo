import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/train_tokens.dart';

/// The two colours the music UI paints itself with, both derived from the
/// current track's album artwork:
///
/// * [background] — a dark, readable wash (WCAG-AA behind body text) that
///   grounds the immersive player.
/// * [accent] — a vivid, saturated *neon* pulled from the cover, used for the
///   breathing glow, the scrub line and small artwork-tinted echoes. It is a
///   glow colour, not a text colour, so it is deliberately pushed bright and
///   saturated rather than kept readable.
///
/// This pairing is what powers the "colours react to the song" behaviour:
/// [ArtworkPalette] tweens both smoothly whenever the track changes.
@immutable
class ArtworkColors {
  const ArtworkColors({required this.background, required this.accent});

  final Color background;
  final Color accent;

  /// The neutral fallback — the workout-tracking ground tone plus the app's
  /// own "playing / connected" green as a calm default neon. Returned whenever
  /// there's no artwork, extraction fails, or nothing usable survives, so the
  /// UI is never left unpainted and a no-cover track still looks intentional.
  static const ArtworkColors fallback = ArtworkColors(
    background: TrainColors.base,
    accent: TrainColors.green,
  );

  @override
  bool operator ==(Object other) =>
      other is ArtworkColors &&
      other.background == background &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(background, accent);
}

/// Derives an [ArtworkColors] pair from the current track's album artwork —
/// the music UI's answer to Spotify's cover-adaptive player, extended here
/// with a neon accent for ZIVO's glow language.
///
/// This is a PURE PRESENTATION concern and lives entirely in the music
/// presentation layer: it never touches the [NowPlaying] domain model or the
/// `MusicController` port (which carry no colour), so the domain stays ignorant
/// of how the UI happens to paint itself. The extracted colours are consumed by
/// exactly two widgets (the immersive player + the mini-bar echo) via
/// [ArtworkPalette] below,
/// and reach nothing else (not `SessionAmbience`, not the workout screens, not
/// the global theme).
///
/// Extraction runs off the critical path (async, via `palette_generator`),
/// results are cached per track, and a `_disposed` guard drops any in-flight
/// work whose owner has gone away — the same lifecycle discipline the Spotify
/// controller follows.
class ArtworkPaletteService {
  ArtworkPaletteService();

  /// Minimum contrast ratio the chosen background must clear against the
  /// app's near-white body text ([TrainColors.ink]) — WCAG AA for normal text.
  static const double _minInkContrast = 4.5;

  /// Per-track cache, shared across every [ArtworkPaletteService] instance so
  /// a cover's palette is computed at most once per process — skipping back to
  /// a recent track is instant. Keyed by track id.
  static final Map<String, ArtworkColors> _cache = <String, ArtworkColors>{};

  bool _disposed = false;

  /// Synchronous cache lookup — lets a consumer paint the right colours on the
  /// very first frame (no async gap, no flash of the fallback) when the track
  /// has been seen before.
  ArtworkColors? cachedFor(String trackId) => _cache[trackId];

  /// Resolves the [ArtworkColors] for [trackId]'s [bytes], off the main
  /// thread. Returns [ArtworkColors.fallback] on any miss (no bytes,
  /// decode/extract failure, or no sufficiently-dark readable swatch) rather
  /// than throwing — a palette failure must never break playback or the
  /// surrounding UI.
  Future<ArtworkColors> coloursFor({
    required String trackId,
    required Uint8List? bytes,
  }) async {
    final cached = _cache[trackId];
    if (cached != null) return cached;
    if (bytes == null || bytes.isEmpty) return ArtworkColors.fallback;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(96, 96),
        maximumColorCount: 16,
      );
      // The extraction future can outlive its owner; don't publish or cache a
      // result nobody's waiting for.
      if (_disposed) return ArtworkColors.fallback;
      final colours = _toColours(palette);
      _cache[trackId] = colours;
      return colours;
    } catch (_) {
      // Corrupt bytes, unsupported format, decode failure — neutral fallback.
      return ArtworkColors.fallback;
    }
  }

  ArtworkColors _toColours(PaletteGenerator palette) {
    final background = _toReadableDarkBackground(palette);
    final accent = _toNeonAccent(palette);
    return ArtworkColors(background: background, accent: accent);
  }

  /// Picks a dark, muted swatch (never just the first colour) and forces it
  /// into a readable dark-background range: pulled toward the app's ground
  /// tone so it reads as ambient light rather than glare, then darkened
  /// further until near-white text clears [_minInkContrast]. Falls back to
  /// the fallback ground if nothing usable survives.
  Color _toReadableDarkBackground(PaletteGenerator palette) {
    // Preference order: dark-muted first (calmest, most background-like),
    // then dark-vibrant, then the generic dominant/muted/vibrant swatches.
    final swatch = palette.darkMutedColor ??
        palette.darkVibrantColor ??
        palette.dominantColor ??
        palette.mutedColor ??
        palette.vibrantColor;
    final base = swatch?.color;
    if (base == null) return ArtworkColors.fallback.background;

    // Keep a hint of the cover's hue but land firmly in the app's dark range.
    var bg = Color.lerp(base, ArtworkColors.fallback.background, 0.55)!;

    // Contrast guard: keep pulling toward ground until body text is
    // comfortably readable on top. Bounded so it always terminates.
    var guard = 0;
    while (_contrastWithInk(bg) < _minInkContrast && guard < 6) {
      bg = Color.lerp(bg, ArtworkColors.fallback.background, 0.2)!;
      guard++;
    }
    // Still unreadable (a pathological near-white cover) → neutral fallback.
    if (_contrastWithInk(bg) < _minInkContrast) {
      return ArtworkColors.fallback.background;
    }
    return bg;
  }

  /// Pulls the cover's most vivid swatch and pushes it into a bright, saturated
  /// *glow* colour. Unlike the background this is NOT held to a contrast rule —
  /// it's light, never text — so a dull cover still yields a usable neon by
  /// clamping saturation and lightness up. Falls back to the app's green.
  Color _toNeonAccent(PaletteGenerator palette) {
    final swatch = palette.vibrantColor ??
        palette.lightVibrantColor ??
        palette.dominantColor ??
        palette.lightMutedColor ??
        palette.mutedColor;
    final base = swatch?.color;
    if (base == null) return ArtworkColors.fallback.accent;

    final hsl = HSLColor.fromColor(base);
    // A grey/near-desaturated swatch can't glow — give it a floor of colour;
    // an already-vivid one keeps (most of) its own saturation.
    final saturation = hsl.saturation < 0.35
        ? 0.6
        : hsl.saturation.clamp(0.5, 0.95);
    // Land in the bright band so the glow actually reads on the dark ground.
    final lightness = hsl.lightness.clamp(0.55, 0.72);
    return HSLColor.fromAHSL(1, hsl.hue, saturation, lightness).toColor();
  }

  static double _contrastWithInk(Color background) {
    final lInk = TrainColors.ink.computeLuminance();
    final lBg = background.computeLuminance();
    final hi = lInk > lBg ? lInk : lBg;
    final lo = lInk > lBg ? lBg : lInk;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// After this, any in-flight [coloursFor] resolves to the fallback and
  /// caches nothing. The static cache is intentionally NOT cleared — it's a
  /// process-lifetime memo shared by every instance.
  void dispose() => _disposed = true;
}

/// Drives animated, artwork-derived colours for a slice of the music UI. Owns
/// an [ArtworkPaletteService], resolves the colours for the current track off
/// the main thread, discards stale results when the track changes
/// mid-extraction, and hands the (smoothly tweened) [ArtworkColors] to
/// [builder].
///
/// Confined to the music UI by construction — only `MusicPlayerPage` (full
/// background) and `NowPlayingBar` (subtle mini-bar echo) build one. The colours
/// it produces are passed to [builder] and nowhere else; they never cross into
/// `SessionAmbience` or the workout tree.
class ArtworkPalette extends StatefulWidget {
  const ArtworkPalette({
    required this.trackId,
    required this.artworkBytes,
    required this.builder,
    this.duration = const Duration(milliseconds: 700),
    super.key,
  });

  /// The current track's id — a change triggers re-resolution. Null (nothing
  /// playing) resolves straight to the fallback.
  final String? trackId;

  /// The current track's raw cover bytes, as populated by
  /// `SpotifyMusicController`. Null falls back cleanly.
  final Uint8List? artworkBytes;

  /// Receives the resolved, animated colours to paint with.
  final Widget Function(BuildContext context, ArtworkColors colours) builder;

  /// Cross-fade duration between one track's colours and the next.
  final Duration duration;

  @override
  State<ArtworkPalette> createState() => _ArtworkPaletteState();
}

class _ArtworkPaletteState extends State<ArtworkPalette> {
  final ArtworkPaletteService _service = ArtworkPaletteService();
  ArtworkColors _colours = ArtworkColors.fallback;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ArtworkPalette old) {
    super.didUpdateWidget(old);
    if (old.trackId != widget.trackId ||
        old.artworkBytes != widget.artworkBytes) {
      _resolve();
    }
  }

  void _resolve() {
    final trackId = widget.trackId;
    if (trackId == null) {
      _set(ArtworkColors.fallback);
      return;
    }
    // Synchronous cache hit → paint immediately, no async gap or flicker.
    final cached = _service.cachedFor(trackId);
    if (cached != null) {
      _set(cached);
      return;
    }
    // Off the main thread. On completion, discard the result if the track has
    // moved on (rapid skips) or this widget is gone — the stale-result guard.
    _service
        .coloursFor(trackId: trackId, bytes: widget.artworkBytes)
        .then((colours) {
      if (!mounted) return;
      if (widget.trackId != trackId) return; // stale: track changed meanwhile
      _set(colours);
    });
  }

  void _set(ArtworkColors colours) {
    if (!mounted || _colours == colours) return;
    setState(() => _colours = colours);
  }

  @override
  void dispose() {
    // Drops any extraction still running for this instance.
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = reducedMotion(context) ? Duration.zero : widget.duration;
    // Two nested tweens so the background and the accent glide independently
    // but on the same curve — one implicit animation each, no controller.
    return TweenAnimationBuilder<Color?>(
      duration: duration,
      curve: Curves.easeOut,
      tween: ColorTween(end: _colours.background),
      builder: (context, background, _) {
        return TweenAnimationBuilder<Color?>(
          duration: duration,
          curve: Curves.easeOut,
          tween: ColorTween(end: _colours.accent),
          builder: (context, accent, _) => widget.builder(
            context,
            ArtworkColors(
              background: background ?? _colours.background,
              accent: accent ?? _colours.accent,
            ),
          ),
        );
      },
    );
  }
}
