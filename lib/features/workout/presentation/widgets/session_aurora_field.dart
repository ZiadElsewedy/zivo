import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/train_tokens.dart';
import 'session_ambience.dart';

/// The reactive workout-session background — a slow, screen-blended mesh of
/// album-light that blooms at the screen's edges around a guaranteed-dark
/// readable core. This is the "the music controls the atmosphere" surface.
///
/// It paints, back to front:
///  1. an opaque [TrainColors.base] ground (so a no-music screen and every test
///     stay pixel-identical — see below);
///  2. up to five ultra-soft radial "light blobs", one per hue in the current
///     [SessionField], screen-blended so a blue-and-orange cover glows blue AND
///     orange (with a magenta bloom where they overlap) — drifting on
///     incommensurate orbits and breathing, faster/wider/harder for a
///     high-[SessionField.energy] cover and barely stirring for a calm one;
///  3. a content-anchored dark **well** that pulls the optical centre back to
///     near-black (the primary legibility guarantee, widened for a loud cover);
///  4. top and bottom scrims so the header and the docked Spotify strip always
///     have crisp dark backing.
///
/// On a **track change** it doesn't cut: every blob morphs by the shortest
/// hue-arc toward its counterpart in the new cover over 1.4s while it keeps
/// drifting, so the room's colour visibly EVOLVES, with a brief "lighting
/// board" dip-and-swell as the cover swaps.
///
/// ## Why it's inert without music (and in tests)
/// The perpetual drift only runs when there is a live [field] with colours AND
/// motion is allowed. With no music the field is null, so this widget is a
/// plain [ColoredBox] over [TrainColors.base] with NO ticker — the background
/// then comes entirely from the phase tint above it, exactly as before, and a
/// widget test that never connects music never spins up an animation (so
/// `pumpAndSettle` terminates). Under reduced motion it paints a single, still,
/// full-colour frame — the mesh still reads as "this song's colours", only the
/// movement is dropped.
class SessionAuroraField extends StatefulWidget {
  const SessionAuroraField({
    required this.field,
    required this.reduced,
    super.key,
  });

  /// The current track's wide colour field (`SessionAmbience.fieldOf`), or null
  /// when there's no live artwork — in which case this paints only the ground.
  final SessionField? field;

  /// When true (`MediaQuery.disableAnimations`), no controllers are created and
  /// a single still frame is painted.
  final bool reduced;

  @override
  State<SessionAuroraField> createState() => _SessionAuroraFieldState();
}

class _SessionAuroraFieldState extends State<SessionAuroraField>
    with TickerProviderStateMixin {
  /// The one perpetual time accumulator. A long period so the composite of the
  /// blobs' incommensurate orbits never visibly loops across a workout; all
  /// motion is `sin`/`cos` of the elapsed seconds it yields.
  static const double _masterSeconds = 120;

  /// The mesh advances a 120-second drift, so sampling it at the display's
  /// 60–120Hz only burns the GPU on motion the eye can't resolve at that speed.
  /// Both animation clocks are snapped to this cadence before they reach the
  /// painter; [_AuroraPainter.shouldRepaint] then sees an unchanged value
  /// between beats and skips the full-screen re-raster entirely, so the layer
  /// re-rasters ~15×/s. At a 120s period the motion is visually identical.
  static const int _auroraFps = 15;

  /// Fraction of the DEVICE resolution the full-screen screen-blended mesh is
  /// rasterised at before being bilinear-upscaled to fill the screen. Soft,
  /// blurred blobs upscale invisibly, so the look is preserved while the
  /// expensive gradient fill costs ~a quarter as much. See [_AuroraPainter].
  static const double _auroraRenderScale = 0.5;

  /// The track-change morph length — shared between the controller that drives
  /// it and the snap that throttles it.
  static const Duration _morphDuration = Duration(milliseconds: 1400);

  AnimationController? _master;
  AnimationController? _morph;

  /// The model currently being painted-from and the model being morphed-to.
  /// Equal except during the 1.4s track-change morph.
  _FieldModel? _from;
  _FieldModel? _to;

  bool get _hasField => widget.field != null && widget.field!.stops.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _sync(null);
  }

  @override
  void didUpdateWidget(covariant SessionAuroraField old) {
    super.didUpdateWidget(old);
    if (old.field != widget.field || old.reduced != widget.reduced) {
      _sync(old.field);
    }
  }

  /// Reconciles the controllers + morph state with the incoming [field] /
  /// [reduced]. The single place tickers are created or torn down.
  void _sync(SessionField? oldField) {
    if (!_hasField) {
      _teardown();
      _from = _to = null;
      return;
    }
    final model = _FieldModel.from(widget.field!);

    // Reduced motion: no controllers at all, recolour instantly.
    if (widget.reduced) {
      _teardown();
      _from = _to = model;
      return;
    }

    _master ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();

    if (_to == null) {
      // First field for this screen — arrive already lit, no morph.
      _from = _to = model;
    } else if (oldField == null || oldField != widget.field) {
      // Track change — morph from whatever is on screen right now.
      _from = _displayedModel();
      _to = model;
      (_morph ??= AnimationController(
        vsync: this,
        duration: _morphDuration,
      )..addStatusListener(_onMorphStatus)).forward(from: 0);
    }
  }

  void _onMorphStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _from = _to;
  }

  /// The model as it is painted THIS instant — the morph source when a new
  /// track lands mid-morph, so an interrupted morph continues from the live
  /// colour instead of snapping.
  _FieldModel _displayedModel() {
    final from = _from, to = _to;
    if (from == null) return to!;
    if (to == null) return from;
    final m = _morph;
    if (m != null && m.isAnimating) {
      return _FieldModel.lerp(from, to, _easeInOutCubic(m.value));
    }
    return to;
  }

  void _teardown() {
    _master?.dispose();
    _morph?.dispose();
    _master = null;
    _morph = null;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasField || _to == null) {
      // No live artwork — the phase tint above paints the whole background, so
      // this is just the ground (and never a ticking widget).
      return ColoredBox(color: TrainColors.base);
    }

    // Reduced motion, or controllers not (yet) built: one still, full-colour
    // frame at t=0.
    if (widget.reduced || _master == null) {
      return CustomPaint(
        size: Size.infinite,
        isComplex: true,
        willChange: false,
        painter: _AuroraPainter(model: _to!, time: 0),
      );
    }

    final master = _master!;
    final morph = _morph;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return AnimatedBuilder(
      animation: morph == null ? master : Listenable.merge([master, morph]),
      builder: (context, _) {
        // Throttle: snap both clocks to [_auroraFps] before they reach the
        // painter, so shouldRepaint sees an unchanged value between beats and
        // the full-screen mesh re-rasters ~15×/s instead of every display
        // frame. AnimatedBuilder still ticks (cheap UI-thread work); the
        // expensive raster is what the snap gates away.
        final time = _snapSeconds(master.value * _masterSeconds, _auroraFps);
        final morphing = morph != null && morph.isAnimating;
        final morphT = morphing
            ? _snapUnit(morph.value, _morphDuration, _auroraFps)
            : 1.0;
        final model = morphing
            ? _FieldModel.lerp(_from!, _to!, _easeInOutCubic(morphT))
            : _to!;
        final flourish = morphing ? _flourish(morphT) : 1.0;
        return CustomPaint(
          size: Size.infinite,
          isComplex: true,
          willChange: true,
          painter: _AuroraPainter(
            model: model,
            time: time,
            flourish: flourish,
            devicePixelRatio: dpr,
            renderScale: _auroraRenderScale,
          ),
        );
      },
    );
  }
}

double _easeInOutCubic(double t) =>
    Curves.easeInOutCubic.transform(t.clamp(0, 1));

/// Snaps [seconds] down to the nearest `1/fps` step, so every value inside the
/// same frame bucket is bit-identical — which is what lets the painter's
/// shouldRepaint gate the full-screen re-raster away between beats.
double _snapSeconds(double seconds, int fps) {
  final step = 1 / fps;
  return (seconds / step).floorToDouble() * step;
}

/// Snaps a 0..1 controller [value] to `fps` even steps across [span] — the
/// morph's counterpart to [_snapSeconds], so a track change also updates at the
/// throttled cadence rather than every display frame.
double _snapUnit(double value, Duration span, int fps) {
  final steps = span.inMilliseconds / 1000 * fps;
  if (steps <= 0) return value;
  return (value * steps).floorToDouble() / steps;
}

/// A short "lighting board dips then swells as it swaps gels" envelope over the
/// track-change morph — restrained (≤1.08), back to 1.0 by ~⅔ of the way, so
/// the song change reads as deliberate and premium rather than a flash.
double _flourish(double m) {
  if (m >= 0.66) return 1;
  if (m < 0.16) return _lerp(1.0, 0.80, m / 0.16);
  if (m < 0.50) {
    return _lerp(0.80, 1.06, Curves.easeOut.transform((m - 0.16) / 0.34));
  }
  return _lerp(1.06, 1.0, (m - 0.50) / 0.16);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _smoothstep(double a, double b, double x) {
  if (b <= a) return x >= b ? 1 : 0;
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// The paint-ready shape of a [SessionField]: exactly five blob slots (a stable
/// count makes the track morph a straight per-slot lerp), plus the motion/mood
/// scalars. Slots beyond the field's hue count reuse earlier hues at half
/// weight, so a two-tone cover fills the corners cohesively.
class _FieldModel {
  const _FieldModel(
    this.slotColors,
    this.slotPeak,
    this.energy,
    this.warmth,
    this.loudness,
    this.fieldGain,
  );

  /// Per-slot colour and per-slot base peak alpha (before fieldGain/flourish),
  /// both length 5.
  final List<Color> slotColors;
  final List<double> slotPeak;
  final double energy;
  final double warmth;
  final double loudness;
  final double fieldGain;

  factory _FieldModel.from(SessionField f) {
    final stops = f.stops;
    final n = stops.length;
    final maxW = f.weights.isEmpty
        ? 1.0
        : f.weights.reduce((a, b) => a > b ? a : b);
    final colors = <Color>[];
    final peaks = <double>[];
    for (var j = 0; j < 5; j++) {
      final src = j % n;
      final filler = j >= n;
      final w = f.weights.isEmpty ? 1.0 : f.weights[src];
      final rel = maxW > 0 ? (w / maxW).clamp(0.0, 1.0) : 1.0;
      // Dominant hue brightest. Peak alpha sits at the bold end of the
      // legibility headroom (the well still holds the core well past the 4.5:1
      // floor), so the periphery reads as genuinely, vividly colourful rather
      // than a faint wash — the whole point of the feature.
      var peak = 0.22 * (0.6 + 0.4 * rel);
      if (filler) peak *= 0.6;
      colors.add(stops[src]);
      peaks.add(peak);
    }
    return _FieldModel(
      colors,
      peaks,
      f.energy,
      f.warmth,
      f.loudness,
      f.fieldGain,
    );
  }

  static _FieldModel lerp(_FieldModel a, _FieldModel b, double t) {
    if (t >= 1) return b;
    if (t <= 0) return a;
    return _FieldModel(
      [
        for (var i = 0; i < 5; i++)
          _lerpHueArc(a.slotColors[i], b.slotColors[i], t),
      ],
      [for (var i = 0; i < 5; i++) _lerp(a.slotPeak[i], b.slotPeak[i], t)],
      _lerp(a.energy, b.energy, t),
      _lerp(a.warmth, b.warmth, t),
      _lerp(a.loudness, b.loudness, t),
      _lerp(a.fieldGain, b.fieldGain, t),
    );
  }

  /// Lerp two colours through HSL along the SHORTEST hue arc — blue→new-blue,
  /// orange→new-orange — never `Color.lerp`'s swing through grey.
  static Color _lerpHueArc(Color a, Color b, double t) {
    final ha = HSLColor.fromColor(a);
    final hb = HSLColor.fromColor(b);
    var dh = hb.hue - ha.hue;
    if (dh > 180) {
      dh -= 360;
    } else if (dh < -180) {
      dh += 360;
    }
    final hue = (ha.hue + dh * t) % 360;
    return HSLColor.fromAHSL(
      1,
      (hue + 360) % 360,
      _lerp(ha.saturation, hb.saturation, t),
      _lerp(ha.lightness, hb.lightness, t),
    ).toColor();
  }

  @override
  bool operator ==(Object other) =>
      other is _FieldModel &&
      other.energy == energy &&
      other.warmth == warmth &&
      other.loudness == loudness &&
      other.fieldGain == fieldGain &&
      _listEq(other.slotColors, slotColors) &&
      _listEq(other.slotPeak, slotPeak);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(slotColors),
    Object.hashAll(slotPeak),
    energy,
    warmth,
    loudness,
    fieldGain,
  );

  static bool _listEq(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.model,
    required this.time,
    this.flourish = 1.0,
    this.devicePixelRatio = 1.0,
    this.renderScale = 1.0,
  });

  final _FieldModel model;

  /// Elapsed seconds from the master accumulator (0 when static).
  final double time;

  /// Track-change dip-and-swell multiplier (1.0 at rest).
  final double flourish;

  /// The screen's device-pixel ratio, so [renderScale] measures against real
  /// device pixels rather than logical ones.
  final double devicePixelRatio;

  /// Fraction of the DEVICE resolution the full-screen mesh is rasterised at
  /// before being bilinear-upscaled to fill the screen. 1.0 paints directly at
  /// full resolution (the single static / reduced-motion frame); the animated
  /// path passes a smaller value so the expensive screen-blended gradient fill
  /// runs over ~renderScale² of the pixels. Soft, blurred blobs upscale
  /// invisibly, so the look is preserved.
  final double renderScale;

  // Blob anchors in normalised [-1, 1] space, pushed to the edges/corners so
  // the most-saturated screen-blend overlaps happen in the periphery, away
  // from the optical centre where the hero number sits.
  static const List<Offset> _anchors = [
    Offset(-0.72, -0.95),
    Offset(0.78, -0.82),
    Offset(0.92, 0.18),
    Offset(-0.82, 0.85),
    Offset(0.10, 1.02),
  ];
  // Pairwise-incommensurate drift periods (seconds) so no single beat dominates
  // and the composite never visibly repeats.
  static const List<double> _px = [23, 31, 37, 41, 43];
  static const List<double> _py = [29, 47, 53, 59, 61];
  static const List<double> _radiusFactor = [0.82, 0.72, 0.78, 0.70, 0.66];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Full-resolution path — the single static / reduced-motion frame.
    if (renderScale >= 1.0) {
      _paintScene(canvas, size);
      return;
    }

    // Downscaled path: rasterise the whole mesh into a low-resolution offscreen
    // and bilinear-upscale it to fill the screen. The costly gradient +
    // screen-blend fill then runs over ~renderScale² of the pixels, and the
    // upscale is a single cheap blit. Falls back to a direct full-res paint if
    // the synchronous rasterise isn't available here (e.g. some test
    // environments) — still correct, just not downscaled.
    final lowW = math.max(1, (w * devicePixelRatio * renderScale).round());
    final lowH = math.max(1, (h * devicePixelRatio * renderScale).round());
    try {
      final recorder = ui.PictureRecorder();
      final lowCanvas = Canvas(recorder)..scale(lowW / w, lowH / h);
      _paintScene(lowCanvas, size);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(lowW, lowH);
      picture.dispose();
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, lowW.toDouble(), lowH.toDouble()),
        Offset.zero & size,
        Paint()
          ..filterQuality = FilterQuality.low
          ..isAntiAlias = true,
      );
      image.dispose();
    } catch (_) {
      _paintScene(canvas, size);
    }
  }

  /// Paints the mesh — ground, blobs, well, scrims — in logical coordinates.
  /// Called either straight onto the screen canvas (full-res / fallback) or
  /// into a scaled-down offscreen recorder (the downscaled animated path).
  void _paintScene(Canvas canvas, Size size) {
    final base = TrainColors.base;
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // 1. Opaque ground.
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final shortSide = math.min(w, h);
    final diag = math.sqrt(w * w + h * h);
    final e = model.energy;
    final amp = _lerp(0.03, 0.10, e) * shortSide;
    final speed = _lerp(
      1.9,
      0.75,
      e,
    ); // higher energy → shorter effective period
    final crush = _lerp(
      0.85,
      0.60,
      e,
    ); // higher energy → crisper (smaller) blobs
    final pulse = _lerp(0.06, 0.20, e);
    final breathBase = _lerp(7.5, 2.8, e);
    final warmDrift = -model.warmth * 0.03 * shortSide; // heat rises
    final gain = model.fieldGain * flourish;
    final percMix = _smoothstep(0.55, 0.90, e); // sharper attack on hot covers

    // 2. Light blobs (screen-blended so overlaps mix into secondary hues).
    for (var j = 0; j < 5; j++) {
      final a = _anchors[j];
      final cx =
          (a.dx * 0.5 + 0.5) * w +
          amp * math.sin(2 * math.pi * time / (_px[j] * speed));
      final cy =
          (a.dy * 0.5 + 0.5) * h +
          amp * math.sin(2 * math.pi * time / (_py[j] * speed)) +
          warmDrift;
      final breath = math.sin(2 * math.pi * time / (breathBase + j * 0.7));
      final radius = _radiusFactor[j] * diag * crush * (1 + 0.10 * breath);
      if (radius <= 0) continue;

      var b01 = 0.5 + 0.5 * breath; // 0..1 breathing envelope
      if (percMix > 0) {
        b01 = b01 * (1 - percMix) + math.pow(b01, 2).toDouble() * percMix;
      }
      final alpha = (model.slotPeak[j] * (1 - pulse + 2 * pulse * b01) * gain)
          .clamp(0.0, 0.28);
      if (alpha <= 0.003) continue;

      final color = model.slotColors[j];
      final center = Offset(cx, cy);
      final paint = Paint()
        ..blendMode = BlendMode.screen
        ..shader = ui.Gradient.radial(center, radius, [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ]);
      canvas.drawCircle(center, radius, paint);
    }

    // 3. The well — the readable core. A base-coloured radial anchored a touch
    // above centre (where the hero number lives), wider and darker for a louder
    // cover, holding the centre near-black however loud the field is.
    final wellCenter = Offset(0.5 * w, 0.45 * h);
    final wellAlpha = _lerp(0.72, 0.92, model.loudness);
    final wellRadius = _lerp(0.62, 0.80, model.loudness) * shortSide;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          wellCenter,
          wellRadius,
          [
            base.withValues(alpha: wellAlpha),
            base.withValues(alpha: wellAlpha * 0.4),
            base.withValues(alpha: 0),
          ],
          [0.0, 0.55, 1.0],
        ),
    );

    // 4. Edge scrims — crisp dark backing for the header and the docked strip.
    final topH = 0.12 * h;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, topH),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, topH), [
          base.withValues(alpha: 0.5),
          base.withValues(alpha: 0),
        ]),
    );
    final botH = 0.18 * h;
    canvas.drawRect(
      Rect.fromLTWH(0, h - botH, w, botH),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, h), Offset(0, h - botH), [
          base.withValues(alpha: 0.5),
          base.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) =>
      old.time != time ||
      old.flourish != flourish ||
      old.renderScale != renderScale ||
      old.devicePixelRatio != devicePixelRatio ||
      old.model != model;
}
