import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
/// whenever a track with artwork is live, derives — once per track, off the
/// main thread — three things from the cover and publishes them down the tree:
///
///  * [SessionAmbience.of] — a deep, near-neutral [_ambientWash] (calmest
///    swatch, saturation hard-capped) for the legacy whole-screen whisper tint.
///  * [SessionAmbience.vividOf] — a clamped-legible foreground accent (vibrant
///    swatch, held to a tasteful ceiling) for marks drawn ON the ground (the
///    rest-ring sweep, transport controls).
///  * [SessionAmbience.vivid2Of] — a SECOND legible accent, the cover's most
///    hue-distinct other colour, so the rest-ring can sweep a two-tone gradient
///    of the song's palette instead of one flat accent (null for mono covers).
///  * [SessionAmbience.fieldOf] — a **wide, population-weighted, luminance-
///    ceilinged [SessionField]**: 1–5 distinct hues pulled from across the whole
///    cover (so a blue-and-orange album really glows blue *and* orange), plus a
///    derived `energy`/`warmth`/`loudness` so the animated aurora background
///    ([SessionAuroraField]) can move, glow and evolve with the song.
///
/// The first two are computed **exactly** as before — this widget's older
/// consumers see byte-identical values. The field is the new, colourful one: it
/// deliberately retires the old ≤0.16-saturation charcoal cap *as the source of
/// visible colour* (the cap is why every song used to wash the screen the same
/// muted pink), keeping the hue and instead capping luminance × alpha and
/// pushing the colour to the periphery (see [SessionAuroraField]).
///
/// With no music connected (or nothing loaded) every value is null and each
/// consumer falls back to its existing neutral styling — pixel-identical to the
/// pre-music look, and, because the field is null, the aurora never spins up a
/// perpetual animation (so tests that never connect music stay static and
/// `pumpAndSettle`-safe). Extraction is cached per track key (`title|artist`),
/// so skipping back and forth doesn't re-run the palette.
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
  /// ground (a ring sweep, a transport glyph, a label) use [vividOf] instead;
  /// for the animated, wide-palette background use [fieldOf].
  static Color? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AmbienceScope>()?.data.accent;

  /// The same track accent, normalised for use as a **foreground** color on
  /// the session's near-black ground — saturation and lightness clamped into
  /// a band that stays legible whatever the album art happens to be (a
  /// near-black cover would otherwise hand the transport controls a color
  /// indistinguishable from the background, and a white one would blow out).
  static Color? vividOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AmbienceScope>()?.data.vivid;

  /// A SECOND, hue-distinct foreground accent pulled from the wide field — the
  /// cover's other prominent colour, normalised to the same legible band as
  /// [vividOf]. Lets a surface sweep through TWO of the song's colours (the
  /// timer ring) instead of a single flat one, so the timer reacts as richly to
  /// the artwork as the background does. Null when the cover has no second hue
  /// far enough from [vividOf] to read as distinct (a monochrome / single-hue
  /// cover), so the ring cleanly stays one colour rather than faking variety.
  static Color? vivid2Of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AmbienceScope>()?.data.vivid2;

  /// The current track's **wide, animated colour field** — 1–5 distinct hues
  /// from across the cover plus the derived energy/mood, or null when there is
  /// no live artwork. Consumed by [SessionAuroraField] to paint the reactive
  /// background. Unlike [of], this keeps the cover's real colours (blues, reds,
  /// oranges, greens…) rather than reducing them to a single deep tint.
  static SessionField? fieldOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AmbienceScope>()?.data.field;

  /// The current song's derived visual **energy** in `0..1` (arousal from the
  /// artwork's colourfulness/spread/contrast — no audio features exist), or a
  /// calm `0.35` baseline when nothing is playing, so a consumer can key motion
  /// intensity off it without a null check.
  static double energyOf(BuildContext context) =>
      fieldOf(context)?.energy ?? 0.35;

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
  Color? _vivid2;
  SessionField? _field;

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
      if (_accent != cached.ambient ||
          _vivid2 != cached.vivid2 ||
          _field != cached.field) {
        _apply(cached);
      }
      return;
    }
    unawaited(_runExtraction(bytes, key));
  }

  Future<void> _runExtraction(Uint8List bytes, String key) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(96, 96),
        // Was 16. A richer quantization gives the wide extraction below more
        // distinct hues to work with (the legacy ambient/vivid derivations are
        // unaffected — they read named swatches, not the raw list).
        maximumColorCount: 20,
      );
      final fallback = palette.colors.isEmpty ? null : palette.colors.first;
      // The two LEGACY jobs pull from DIFFERENT named swatches on purpose and
      // are unchanged. The whole-screen ambient wash starts from the cover's
      // *calmest* swatch (muted before vibrant); the small foreground mark
      // starts from the *vibrant* swatch.
      final ambientRaw =
          palette.darkMutedColor?.color ??
          palette.mutedColor?.color ??
          palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          fallback;
      final vividRaw =
          palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.dominantColor?.color ??
          ambientRaw;
      if (ambientRaw == null || !mounted) return;
      // The NEW wide, colourful field — the reactive background's source of
      // colour. Built from the raw population-weighted swatch list, not the
      // named ones, so it can span the whole cover.
      final field = buildSessionField(palette.paletteColors);
      final vivid = _legible(vividRaw ?? ambientRaw);
      final accent = (
        ambient: _ambientWash(ambientRaw),
        vivid: vivid,
        vivid2: _secondaryVivid(field, vivid),
        field: field,
      );
      _accentCache[key] = accent;
      _apply(accent);
    } catch (_) {
      // Artwork failed to decode — neutral fallback is fine.
    }
  }

  void _apply(_Accent accent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_accent == accent.ambient &&
          _vivid == accent.vivid &&
          _vivid2 == accent.vivid2 &&
          _field == accent.field) {
        return;
      }
      setState(() {
        _accent = accent.ambient;
        _vivid = accent.vivid;
        _vivid2 = accent.vivid2;
        _field = accent.field;
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
  /// This feeds the LEGACY [SessionAmbience.of] consumers only (the whisper
  /// tint blended into the phase gradient). The visible, colourful background
  /// now comes from [buildSessionField] instead — this cap is no longer the
  /// source of the on-screen colour, so it no longer washes every song the same.
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

  /// The cover's SECOND foreground colour: the wide field's stop whose hue sits
  /// farthest from [primary] (the main [vivid]), normalised into the same
  /// legible band via [_legible]. Returns null when nothing is at least 40°
  /// away — a monochrome or single-hue cover has no honest second colour, and a
  /// near-duplicate would make the ring's two-tone sweep read as a flat colour
  /// anyway. Feeds [SessionAmbience.vivid2Of].
  static Color? _secondaryVivid(SessionField? field, Color primary) {
    if (field == null || field.stops.length < 2) return null;
    final primaryHue = HSLColor.fromColor(primary).hue;
    Color? best;
    var bestDist = 0.0;
    for (final stop in field.stops) {
      final d = _hueDist(HSLColor.fromColor(stop).hue, primaryHue);
      if (d > bestDist) {
        bestDist = d;
        best = stop;
      }
    }
    if (best == null || bestDist < 40) return null;
    return _legible(best);
  }

  /// Per-track extraction cache — shared across phase rebuilds so a track's
  /// palette runs exactly once per process.
  static final Map<String, _Accent> _accentCache = {};

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) {
      return _AmbienceScope(
        data: const _AmbienceData(
          accent: null,
          vivid: null,
          vivid2: null,
          field: null,
          trackKey: null,
        ),
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
              vivid2: null,
              field: null,
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
            // A track swap invalidates immediately (the new values land when
            // extraction finishes); nothing loaded clears to neutral.
            final cached = playing == null
                ? null
                : _accentCache[_keyOf(playing)];
            final accentForTrack = playing == null
                ? null
                : (cached?.ambient ?? _accent);
            final vividForTrack = playing == null
                ? null
                : (cached?.vivid ?? _vivid);
            final vivid2ForTrack = playing == null
                ? null
                : (cached?.vivid2 ?? _vivid2);
            final fieldForTrack = playing == null
                ? null
                : (cached?.field ?? _field);
            if (playing != null) _extractAccent(playing);
            return _AmbienceScope(
              data: _AmbienceData(
                accent: accentForTrack,
                vivid: vividForTrack,
                vivid2: vivid2ForTrack,
                field: fieldForTrack,
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

// ---- Wide field extraction ------------------------------------------------
//
// The colourful half. Consumes the raw, population-weighted swatch list
// (`palette.paletteColors`) — never the six named getters, each of which
// collapses the cover to ONE swatch (the root cause of the old mono-hue wash).
// Kept a pure top-level function (no image I/O) so the whole colour-maths
// pipeline is unit-testable by constructing [PaletteColor]s directly.

/// Builds the wide, colourful [SessionField] from a cover's population-weighted
/// [swatches] (`PaletteGenerator.paletteColors`) — the reactive background's
/// source of colour. Picks up to five distinct hues from across the cover,
/// tone-maps each to keep its hue but cap its luminance, and derives the
/// energy/mood scalars the aurora reacts to. Returns null for an empty or
/// degenerate palette (the background then stays static).
SessionField? buildSessionField(List<PaletteColor> swatches) {
  if (swatches.isEmpty) return null;
  var total = 0;
  for (final pc in swatches) {
    total += pc.population;
  }
  if (total <= 0) return null;

  // Score every swatch by PRESENCE = area × colourfulness, so a small but
  // vivid splash (a neon logo) can out-rank a large dull background, while
  // area still dominates overall.
  final cands = <_HueCand>[];
  for (final pc in swatches) {
    final hsl = HSLColor.fromColor(pc.color);
    final pop = pc.population / total;
    final chroma = (hsl.saturation * (1 - (hsl.lightness - 0.5).abs() * 2))
        .clamp(0.0, 1.0);
    cands.add(_HueCand(hsl, pop * (0.35 + 0.65 * chroma)));
  }

  // Hue-bucket dedupe: 12 buckets of 30°; keep the single best-weight swatch
  // per bucket. Near-grey swatches (sat < 0.12) collapse into one shared
  // neutral bucket, kept only as a fallback.
  const neutralKey = -1;
  final buckets = <int, _HueCand>{};
  for (final c in cands) {
    final key = c.hsl.saturation < 0.12 ? neutralKey : (c.hsl.hue ~/ 30) % 12;
    final existing = buckets[key];
    if (existing == null || c.weight > existing.weight) buckets[key] = c;
  }

  final chromatic =
      buckets.entries
          .where((e) => e.key != neutralKey)
          .map((e) => e.value)
          .toList()
        ..sort((a, b) => b.weight.compareTo(a.weight));

  // Grayscale / monochrome cover — no chromatic bucket survived. Stay alive but
  // honest: one quiet slate stop (or the cover's single faint hue plus an
  // analogous companion), never invented colour.
  if (chromatic.isEmpty) {
    final neutral = buckets[neutralKey];
    final hue = neutral?.hsl.hue ?? 212.0;
    final stop = HSLColor.fromAHSL(1, hue, 0.12, 0.34).toColor();
    final companion = HSLColor.fromAHSL(
      1,
      (hue + 22) % 360,
      0.10,
      0.30,
    ).toColor();
    return SessionField(
      stops: [stop, companion],
      weights: const [0.62, 0.38],
      energy: 0.18,
      warmth: 0,
      loudness: 0.2,
      luminosity: 0.12,
      fieldGain: 1,
    );
  }

  final chosen = <_HueCand>[...chromatic.take(5)];

  // FORCE SPREAD — the move that makes colourful covers show MULTIPLE hues. If
  // everything chosen huddles within 40° of the leader, pull in the
  // highest-weight bucket more than 60° away (dropping the weakest if full), so
  // a blue-and-orange cover can't render as blue-only.
  final leaderHue = chosen.first.hsl.hue;
  final hasSpread = chosen.any((c) => _hueDist(c.hsl.hue, leaderHue) > 60);
  if (!hasSpread) {
    for (final c in chromatic) {
      if (_hueDist(c.hsl.hue, leaderHue) > 60 && !chosen.contains(c)) {
        if (chosen.length >= 5) chosen.removeLast();
        chosen.add(c);
        break;
      }
    }
  }

  // Tone-map each chosen hue for the aurora: KEEP the hue, discipline S/L so it
  // is saturated (unlike the old ≤0.16 cap) but luminance-ceilinged (L ≤ 0.50)
  // — a screen-blend at low alpha over near-black then stays dark enough to
  // keep white text readable.
  final stops = <Color>[];
  for (final c in chosen) {
    stops.add(
      HSLColor.fromAHSL(
        1,
        c.hsl.hue,
        c.hsl.saturation.clamp(0.45, 0.85),
        c.hsl.lightness.clamp(0.32, 0.50),
      ).toColor(),
    );
  }

  final wsum = chosen.fold<double>(0, (s, c) => s + c.weight);
  final weights = [
    for (final c in chosen) wsum > 0 ? c.weight / wsum : 1 / chosen.length,
  ];

  // ---- Energy & mood (derived from the field's own colour statistics) ----
  var sat = 0.0;
  var x = 0.0, y = 0.0, wv = 0.0;
  var lMin = 1.0, lMax = 0.0;
  var warmNum = 0.0, warmDen = 0.0;
  var luminosity = 0.0;
  var maxSat = 0.0, maxLight = 0.0;
  for (var i = 0; i < chosen.length; i++) {
    final hsl = chosen[i].hsl;
    final w = weights[i];
    sat += w * hsl.saturation;
    // circular hue variance, weighted by presence × saturation × the
    // chroma-visibility parabola (near-black/near-white swatches don't vote).
    final vis = 1 - math.pow(2 * hsl.lightness - 1, 2).toDouble();
    final ww = w * hsl.saturation * vis;
    final hr = hsl.hue * math.pi / 180;
    x += ww * math.cos(hr);
    y += ww * math.sin(hr);
    wv += ww;
    // luminance punch over significant swatches only.
    if (w >= 0.04) {
      final lum = hsl.toColor().computeLuminance();
      if (lum < lMin) lMin = lum;
      if (lum > lMax) lMax = lum;
    }
    // warmth: +1 ≈ orange (40°), −1 ≈ azure (220°); greys barely vote.
    final ws = w * hsl.saturation;
    warmNum += ws * math.cos((hsl.hue - 40) * math.pi / 180);
    warmDen += ws;
    luminosity += w * hsl.toColor().computeLuminance();
    if (hsl.saturation > maxSat) maxSat = hsl.saturation;
    if (hsl.lightness > maxLight) maxLight = hsl.lightness;
  }
  final spread = wv > 0
      ? (1 - math.sqrt(x * x + y * y) / wv).clamp(0.0, 1.0)
      : 0.0;
  final contrast = (lMax - lMin).clamp(0.0, 1.0);
  final energyRaw = 0.45 * sat + 0.35 * spread + 0.20 * contrast;
  // smoothstep pushes extremes apart; the band [0.10, 0.95] is never frozen,
  // never frantic.
  final energy = (0.10 + 0.85 * _smoothstep(0.12, 0.88, energyRaw)).clamp(
    0.10,
    0.95,
  );
  final warmth = warmDen > 0 ? (warmNum / warmDen).clamp(-1.0, 1.0) : 0.0;
  // loudness — how hard the cover shouts — drives the legibility caps, NOT
  // motion, so a moody-but-punchy cover can be energetic without being loud.
  final loudness = (maxSat * maxLight).clamp(0.0, 1.0);

  // Belt-and-braces legibility guard for pale/high-key covers: dim the whole
  // field until the predicted composited core clears WCAG-AA against ink.
  var fieldGain = 1.0;
  while (_predictedCoreContrast(stops, weights, loudness, fieldGain) < 4.5 &&
      fieldGain > 0.4) {
    fieldGain -= 0.1;
  }

  return SessionField(
    stops: stops,
    weights: weights,
    energy: energy,
    warmth: warmth,
    loudness: loudness,
    luminosity: luminosity.clamp(0.0, 1.0),
    fieldGain: fieldGain.clamp(0.0, 1.0),
  );
}

/// Shortest circular distance between two hues, in degrees (0..180).
double _hueDist(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

double _smoothstep(double a, double b, double x) {
  if (b <= a) return x >= b ? 1 : 0;
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Predicts the composited luminance-contrast at the readable core under the
/// field + well and returns its ratio against near-white ink. The blobs are
/// anchored at the edges, so only a fraction of their peak reaches the core;
/// the well then pulls it back toward base. Mirrors the music player's own
/// contrast-guard discipline.
double _predictedCoreContrast(
  List<Color> stops,
  List<double> weights,
  double loudness,
  double fieldGain,
) {
  final base = TrainColors.base;
  var r = base.r, g = base.g, b = base.b;
  // Screen-blend each stop's peripheral spill into the core.
  for (var i = 0; i < stops.length; i++) {
    // peak alpha (matches the painter's ~0.22 base), weight-scaled; only ~35%
    // of it reaches the content core from the edge-anchored blobs.
    final a = (0.22 * (0.55 + 0.45 * weights[i])) * 0.35 * fieldGain;
    final s = stops[i];
    r = _screenChannel(r, s.r, a);
    g = _screenChannel(g, s.g, a);
    b = _screenChannel(b, s.b, a);
  }
  // The well darkens the core back toward base.
  final wellAlpha = 0.72 + 0.20 * loudness;
  r = r + (base.r - r) * wellAlpha;
  g = g + (base.g - g) * wellAlpha;
  b = b + (base.b - b) * wellAlpha;
  final core = Color.from(alpha: 1, red: r, green: g, blue: b);
  final lCore = core.computeLuminance();
  final lInk = TrainColors.ink.computeLuminance();
  final hi = lInk > lCore ? lInk : lCore;
  final lo = lInk > lCore ? lCore : lInk;
  return (hi + 0.05) / (lo + 0.05);
}

/// One channel of a screen blend of [src] over [dst] at opacity [alpha], all in
/// 0..1 sRGB (good enough for the contrast prediction).
double _screenChannel(double dst, double src, double alpha) {
  final screen = 1 - (1 - dst) * (1 - src);
  return dst + (screen - dst) * alpha;
}

/// A wide, animated colour field derived from the current track's album cover —
/// the source of colour for the reactive session background ([SessionAuroraField]).
///
/// Unlike the single deep [SessionAmbience.of] tint, this keeps the cover's
/// real, varied hues: [stops] holds 1–5 tone-mapped colours spanning the whole
/// cover (dominant first), each luminance-ceilinged so it can glow at the
/// screen edges without breaking legibility. The scalars describe the song's
/// visual mood, all derived from the artwork (no audio features exist):
///
///  * [energy] `0..1` — arousal (colourfulness + hue spread + tonal punch),
///    driving MOTION speed / amplitude / pulse.
///  * [warmth] `-1..1` — hue temperature (+ warm, − cool), biasing composition.
///  * [loudness] `0..1` — how hard the cover shouts, driving the legibility
///    caps (a neon cover gets a darker, wider well) — kept separate from
///    [energy] so a moody-but-punchy cover can move without going garish.
///  * [luminosity] `0..1` — perceptual brightness, pulling the glow back on
///    bright covers.
///  * [fieldGain] `0..1` — a once-per-track legibility scalar from the
///    contrast guard; dims the whole field for a pale/high-key cover.
@immutable
class SessionField {
  const SessionField({
    required this.stops,
    required this.weights,
    required this.energy,
    required this.warmth,
    required this.loudness,
    required this.luminosity,
    required this.fieldGain,
  });

  final List<Color> stops;
  final List<double> weights;
  final double energy;
  final double warmth;
  final double loudness;
  final double luminosity;
  final double fieldGain;

  @override
  bool operator ==(Object other) =>
      other is SessionField &&
      listEquals(other.stops, stops) &&
      other.energy == energy &&
      other.warmth == warmth &&
      other.loudness == loudness &&
      other.fieldGain == fieldGain;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(stops), energy, warmth, loudness, fieldGain);
}

/// One scored candidate hue during field extraction.
class _HueCand {
  const _HueCand(this.hsl, this.weight);

  final HSLColor hsl;
  final double weight;
}

/// The three derivations of one track's artwork — see [SessionAmbience.of]
/// (ambient), [SessionAmbience.vividOf] (vivid) and [SessionAmbience.fieldOf]
/// (the wide field).
typedef _Accent = ({
  Color ambient,
  Color vivid,
  Color? vivid2,
  SessionField? field,
});

class _AmbienceData {
  const _AmbienceData({
    required this.accent,
    required this.vivid,
    required this.vivid2,
    required this.field,
    required this.trackKey,
  });

  final Color? accent;
  final Color? vivid;
  final Color? vivid2;
  final SessionField? field;
  final String? trackKey;
}

class _AmbienceScope extends InheritedWidget {
  const _AmbienceScope({required this.data, required super.child});

  final _AmbienceData data;

  @override
  bool updateShouldNotify(_AmbienceScope oldWidget) =>
      oldWidget.data.accent != data.accent ||
      oldWidget.data.vivid != data.vivid ||
      oldWidget.data.vivid2 != data.vivid2 ||
      oldWidget.data.field != data.field ||
      oldWidget.data.trackKey != data.trackKey;
}
