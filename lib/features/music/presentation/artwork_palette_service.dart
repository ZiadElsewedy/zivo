import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/app_colors.dart';

/// Derives a readable, dark background wash from the current track's album
/// artwork — the music UI's answer to Spotify's cover-adaptive player.
///
/// This is a PURE PRESENTATION concern and lives entirely in the music
/// presentation layer: it never touches the [NowPlaying] domain model or the
/// `MusicController` port (which carry no color), so the domain stays ignorant
/// of how the UI happens to paint itself. The extracted color is consumed by
/// exactly two widgets — `MusicPlayerPage` and `NowPlayingBar` — via
/// [ArtworkPalette] below, and reaches nothing else (not `SessionAmbience`,
/// not the workout screens, not the global theme).
///
/// Extraction runs off the critical path (async, via `palette_generator`),
/// results are cached per track, and a `_disposed` guard drops any in-flight
/// work whose owner has gone away — the same lifecycle discipline the Spotify
/// controller follows.
class ArtworkPaletteService {
  ArtworkPaletteService();

  /// The neutral fallback — the app's own screen ground. Returned whenever
  /// there's no artwork, extraction fails, or no swatch clears the contrast
  /// bar, so the UI is never left unreadable and looks pixel-identical to the
  /// pre-feature player when a track has no cover.
  static const Color defaultBackground = AppColors.ground;

  /// Minimum contrast ratio the chosen background must clear against the
  /// app's near-white body text ([AppColors.ink]) — WCAG AA for normal text.
  static const double _minInkContrast = 4.5;

  /// Per-track cache, shared across every [ArtworkPaletteService] instance so
  /// a cover's palette is computed at most once per process — the player page
  /// and the mini bar reuse each other's result, and skipping back to a
  /// recent track is instant. Keyed by track id.
  static final Map<String, Color> _cache = <String, Color>{};

  bool _disposed = false;

  /// Synchronous cache lookup — lets a consumer paint the right color on the
  /// very first frame (no async gap, no flash of the fallback) when the track
  /// has been seen before.
  Color? cachedFor(String trackId) => _cache[trackId];

  /// Resolves the background color for [trackId]'s [bytes], off the main
  /// thread. Returns [defaultBackground] on any miss (no bytes, decode/extract
  /// failure, or no sufficiently-dark readable swatch) rather than throwing —
  /// a palette failure must never break playback or the surrounding UI.
  Future<Color> backgroundFor({
    required String trackId,
    required Uint8List? bytes,
  }) async {
    final cached = _cache[trackId];
    if (cached != null) return cached;
    if (bytes == null || bytes.isEmpty) return defaultBackground;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(96, 96),
        maximumColorCount: 16,
      );
      // The extraction future can outlive its owner; don't publish or cache a
      // result nobody's waiting for.
      if (_disposed) return defaultBackground;
      final color = _toReadableDarkBackground(palette);
      _cache[trackId] = color;
      return color;
    } catch (_) {
      // Corrupt bytes, unsupported format, decode failure — neutral fallback.
      return defaultBackground;
    }
  }

  /// Picks a dark, muted swatch (never just the first color) and forces it
  /// into a readable dark-background range: pulled toward the app's ground
  /// tone so it reads as ambient light rather than glare, then darkened
  /// further until near-white text clears [_minInkContrast]. Falls back to
  /// [defaultBackground] if nothing usable survives.
  Color _toReadableDarkBackground(PaletteGenerator palette) {
    // Preference order: dark-muted first (calmest, most background-like),
    // then dark-vibrant, then the generic dominant/muted/vibrant swatches.
    final swatch = palette.darkMutedColor ??
        palette.darkVibrantColor ??
        palette.dominantColor ??
        palette.mutedColor ??
        palette.vibrantColor;
    final base = swatch?.color;
    if (base == null) return defaultBackground;

    // Keep a hint of the cover's hue but land firmly in the app's dark range.
    var bg = Color.lerp(base, defaultBackground, 0.55)!;

    // Contrast guard: keep pulling toward ground until body text is
    // comfortably readable on top. Bounded so it always terminates.
    var guard = 0;
    while (_contrastWithInk(bg) < _minInkContrast && guard < 6) {
      bg = Color.lerp(bg, defaultBackground, 0.2)!;
      guard++;
    }
    // Still unreadable (a pathological near-white cover) → neutral fallback.
    if (_contrastWithInk(bg) < _minInkContrast) return defaultBackground;
    return bg;
  }

  static double _contrastWithInk(Color background) {
    final lInk = AppColors.ink.computeLuminance();
    final lBg = background.computeLuminance();
    final hi = lInk > lBg ? lInk : lBg;
    final lo = lInk > lBg ? lBg : lInk;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// After this, any in-flight [backgroundFor] resolves to the fallback and
  /// caches nothing. The static cache is intentionally NOT cleared — it's a
  /// process-lifetime memo shared by every instance.
  void dispose() => _disposed = true;
}

/// Drives an animated, artwork-derived background color for a slice of the
/// music UI. Owns an [ArtworkPaletteService], resolves the color for the
/// current track off the main thread, discards stale results when the track
/// changes mid-extraction, and hands the (smoothly tweened) color to [builder].
///
/// Confined to the music UI by construction — only `MusicPlayerPage` and
/// `NowPlayingBar` build one. The color it produces is passed to [builder] and
/// nowhere else; it never crosses into `SessionAmbience` or the workout tree.
class ArtworkPalette extends StatefulWidget {
  const ArtworkPalette({
    required this.trackId,
    required this.artworkBytes,
    required this.builder,
    this.duration = const Duration(milliseconds: 600),
    super.key,
  });

  /// The current track's id — a change triggers re-resolution. Null (nothing
  /// playing) resolves straight to the fallback.
  final String? trackId;

  /// The current track's raw cover bytes, as populated by
  /// `SpotifyMusicController`. Null falls back cleanly.
  final Uint8List? artworkBytes;

  /// Receives the resolved, animated background color to paint with.
  final Widget Function(BuildContext context, Color background) builder;

  /// Cross-fade duration between one track's color and the next.
  final Duration duration;

  @override
  State<ArtworkPalette> createState() => _ArtworkPaletteState();
}

class _ArtworkPaletteState extends State<ArtworkPalette> {
  final ArtworkPaletteService _service = ArtworkPaletteService();
  Color _background = ArtworkPaletteService.defaultBackground;

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
      _set(ArtworkPaletteService.defaultBackground);
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
        .backgroundFor(trackId: trackId, bytes: widget.artworkBytes)
        .then((color) {
      if (!mounted) return;
      if (widget.trackId != trackId) return; // stale: track changed meanwhile
      _set(color);
    });
  }

  void _set(Color color) {
    if (!mounted || _background == color) return;
    setState(() => _background = color);
  }

  @override
  void dispose() {
    // Drops any extraction still running for this instance.
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      duration: reducedMotion(context) ? Duration.zero : widget.duration,
      curve: Curves.easeOut,
      tween: ColorTween(end: _background),
      builder: (context, color, _) =>
          widget.builder(context, color ?? _background),
    );
  }
}
