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
/// whenever a track with artwork is live, extracts that artwork's accent
/// color (vibrant swatch, falling back to dominant) once per track. The
/// accent is published down the tree via [SessionAmbience.of] so every layer
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
  static Color? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AmbienceScope>()?.data.accent;

  @override
  State<SessionAmbience> createState() => _SessionAmbienceState();
}

class _SessionAmbienceState extends State<SessionAmbience> {
  Color? _accent;

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
      if (_accent != cached) _apply(cached);
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
      Color? chosen =
          palette.vibrantColor?.color ?? palette.dominantColor?.color;
      chosen ??= palette.colors.isEmpty ? null : palette.colors.first;
      if (chosen == null || !mounted) return;
      // Pull most of the way toward the session's own ground tone so the
      // accent reads as ambient light, never glare — text on any surface
      // stays readable.
      final tinted = Color.lerp(chosen, TrainColors.base, 0.55)!;
      _accentCache[key] = tinted;
      _apply(tinted);
    } catch (_) {
      // Artwork failed to decode — neutral fallback is fine.
    }
  }

  void _apply(Color accent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _accent != accent) setState(() => _accent = accent);
    });
  }

  /// Per-track extraction cache — shared across phase rebuilds so a track's
  /// palette runs exactly once per process.
  static final Map<String, Color> _accentCache = {};

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) {
      return _AmbienceScope(
        data: _AmbienceData(accent: null),
        child: widget.child,
      );
    }
    return StreamBuilder<MusicConnection>(
      stream: controller.connection,
      initialData: controller.currentConnection,
      builder: (context, connSnap) {
        if (connSnap.data != MusicConnection.connected) {
          return _AmbienceScope(
            data: _AmbienceData(accent: null),
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
            final accentForTrack = playing == null
                ? null
                : (_accentCache[_keyOf(playing)] ?? _accent);
            if (playing != null) _extractAccent(playing);
            return _AmbienceScope(
              data: _AmbienceData(accent: accentForTrack),
              child: widget.child,
            );
          },
        );
      },
    );
  }
}

class _AmbienceData {
  const _AmbienceData({required this.accent});

  final Color? accent;
}

class _AmbienceScope extends InheritedWidget {
  const _AmbienceScope({required this.data, required super.child});

  final _AmbienceData data;

  @override
  bool updateShouldNotify(_AmbienceScope oldWidget) =>
      oldWidget.data.accent != data.accent;
}
