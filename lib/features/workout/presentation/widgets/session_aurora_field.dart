import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/train_tokens.dart';
import 'session_ambience.dart';

/// The reactive workout-session background — a soft, screen-blended mesh of
/// album-light that blooms at the screen's edges around a guaranteed-dark
/// readable core. This is the "the music controls the atmosphere" surface.
///
/// It paints, back to front:
///  1. an opaque [TrainColors.base] ground (so a no-music screen and every test
///     stay pixel-identical — see below);
///  2. up to five ultra-soft radial "light blobs", one per hue in the current
///     [SessionField], screen-blended so a blue-and-orange cover glows blue AND
///     orange (with a magenta bloom where they overlap), each pushed to an
///     edge/corner so the most-saturated overlaps sit in the periphery;
///  3. a content-anchored dark **well** that pulls the optical centre back to
///     near-black (the primary legibility guarantee, widened for a loud cover);
///  4. top and bottom scrims so the header and the docked Spotify strip always
///     have crisp dark backing.
///
/// ## Why it is cheap on the GPU (the whole point of this design)
/// The mesh is **rendered once per track into a cached [ui.Image]**, then shown
/// as a plain image — a single texture blit, which composites for ~free at any
/// refresh rate. There is **no per-frame repaint**: a running/resting session is
/// a static composite, exactly as it was before the music feature existed. The
/// only motion is on a **track change**, where the outgoing image cross-fades
/// into the incoming one over [_kFadeDuration] (two alpha-blended blits — no
/// gradient re-evaluation), so the room's colour still visibly EVOLVES as the
/// song changes. This replaced an earlier version that re-rasterised the whole
/// screen-blended mesh every frame on a perpetual ticker, which pinned the
/// raster thread on Samsung; the colour reactivity is identical, the continuous
/// GPU cost is gone.
///
/// ## Why it's inert without music (and in tests)
/// With no live [field] this is a plain [ColoredBox] over [TrainColors.base]
/// with no image, no controller and no ticker — the background then comes
/// entirely from the phase tint above it, exactly as before, and a widget test
/// that never connects music never spins up an animation (so `pumpAndSettle`
/// terminates). Under reduced motion a track change swaps the image instantly
/// rather than cross-fading — the mesh still reads as "this song's colours",
/// only the transition is dropped. Where synchronous GPU rasterisation isn't
/// available (some test environments), it falls back to painting the static
/// scene directly — still correct and still ticker-free, just not image-cached.
class SessionAuroraField extends StatefulWidget {
  const SessionAuroraField({
    required this.field,
    required this.reduced,
    super.key,
  });

  /// The current track's wide colour field (`SessionAmbience.fieldOf`), or null
  /// when there's no live artwork — in which case this paints only the ground.
  final SessionField? field;

  /// When true (`MediaQuery.disableAnimations`), a track change swaps the mesh
  /// instantly instead of cross-fading.
  final bool reduced;

  @override
  State<SessionAuroraField> createState() => _SessionAuroraFieldState();
}

class _SessionAuroraFieldState extends State<SessionAuroraField>
    with SingleTickerProviderStateMixin {
  /// Fraction of the DEVICE resolution the cached mesh image is rasterised at.
  /// Soft, blurred blobs upscale invisibly, so this halves each dimension (a
  /// quarter of the pixels, a quarter of the memory — a few MB per image) with
  /// no visible loss. Only paid once per track.
  static const double _kRenderScale = 0.5;

  /// The track-change cross-fade length. The only time this widget animates.
  static const Duration _kFadeDuration = Duration(milliseconds: 600);

  /// The current track's rendered mesh, and — only while a cross-fade is
  /// running — the outgoing one shown underneath it.
  ui.Image? _image;
  ui.Image? _previous;

  /// Drives the cross-fade, created lazily on the first track change under
  /// motion and reused thereafter. Null until then (and unused under reduced
  /// motion), so a session that never changes track never spins up a ticker.
  AnimationController? _fade;

  /// What the cached [_image] was rendered from — so we only re-render when the
  /// track, the screen size, or the pixel ratio actually changes.
  SessionField? _renderedField;
  Size? _renderedSize;
  double _renderedDpr = 0;

  /// Set when a synchronous rasterise wasn't available; the build then paints
  /// the static scene directly instead of blitting a cached image.
  bool _renderFailed = false;

  bool get _hasField => widget.field != null && widget.field!.stops.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Covers the first render and any MediaQuery change (rotation / resize).
    _sync(fieldChanged: false);
  }

  @override
  void didUpdateWidget(covariant SessionAuroraField old) {
    super.didUpdateWidget(old);
    if (old.field != widget.field || old.reduced != widget.reduced) {
      _sync(fieldChanged: old.field != widget.field);
    }
  }

  /// Reconciles the cached image with the incoming [field] / screen metrics —
  /// the single place the mesh is rendered and the cross-fade is armed.
  void _sync({required bool fieldChanged}) {
    if (!_hasField) {
      _disposeImages();
      _renderedField = null;
      _renderedSize = null;
      _renderFailed = false;
      return;
    }

    final media = MediaQuery.maybeOf(context);
    // The aurora is full-screen (Positioned.fill), so the screen size is a fine
    // render target — a soft background tolerates a sub-pixel size mismatch with
    // the actual paint box completely.
    final size = media?.size ?? _renderedSize;
    final dpr = media?.devicePixelRatio ??
        (_renderedDpr == 0 ? 1.0 : _renderedDpr);
    if (size == null || size.isEmpty) return;

    final needsRender = fieldChanged ||
        widget.field != _renderedField ||
        size != _renderedSize ||
        dpr != _renderedDpr ||
        (_image == null && !_renderFailed);
    if (!needsRender) return;

    final model = _FieldModel.from(widget.field!);
    ui.Image? next;
    try {
      next = _renderToImage(model, size, dpr);
    } catch (_) {
      next = null;
    }

    _renderedField = widget.field;
    _renderedSize = size;
    _renderedDpr = dpr;

    if (next == null) {
      // No synchronous rasterise here — fall back to painting the scene live
      // (still static, still ticker-free).
      _disposeImages();
      _renderFailed = true;
      if (mounted) setState(() {});
      return;
    }
    _renderFailed = false;

    // Cross-fade only for a genuine track change under motion; the first render
    // and a reduced-motion swap land instantly.
    final crossFade = fieldChanged && _image != null && !widget.reduced;
    if (crossFade) {
      _previous?.dispose();
      _previous = _image;
      _image = next;
      (_fade ??= AnimationController(vsync: this, duration: _kFadeDuration)
            ..addStatusListener(_onFadeStatus))
          .forward(from: 0);
    } else {
      _previous?.dispose();
      _previous = null;
      _image?.dispose();
      _image = next;
    }
    if (mounted) setState(() {});
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _previous?.dispose();
      _previous = null;
      if (mounted) setState(() {});
    }
  }

  /// Rasterises the mesh once, at [_kRenderScale] of the device resolution,
  /// into a [ui.Image]. Kept synchronous ([ui.Picture.toImageSync]) so the new
  /// colour is ready on the very next frame with no flash of the old one.
  ui.Image _renderToImage(_FieldModel model, Size size, double dpr) {
    final w = size.width;
    final h = size.height;
    final pxW = math.max(1, (w * dpr * _kRenderScale).round());
    final pxH = math.max(1, (h * dpr * _kRenderScale).round());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pxW / w, pxH / h);
    _paintAuroraScene(canvas, size, model);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(pxW, pxH);
    picture.dispose();
    return image;
  }

  void _disposeImages() {
    _image?.dispose();
    _image = null;
    _previous?.dispose();
    _previous = null;
  }

  @override
  void dispose() {
    _fade?.dispose();
    _disposeImages();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasField) {
      // No live artwork — the phase tint above paints the whole background, so
      // this is just the ground (and never a ticking widget).
      return ColoredBox(color: TrainColors.base);
    }

    // Fallback: a cached image wasn't available (e.g. no synchronous rasterise
    // in a test). Paint the static scene directly — once, then cached by the
    // enclosing RepaintBoundary, with no ticker.
    final image = _image;
    if (image == null) {
      return CustomPaint(
        size: Size.infinite,
        isComplex: true,
        willChange: false,
        painter: _AuroraScenePainter(_FieldModel.from(widget.field!)),
      );
    }

    final fade = _fade;
    final fading = _previous != null && fade != null;
    if (!fading) {
      // Steady state — a single static image blit, cached and repaint-free.
      return CustomPaint(
        size: Size.infinite,
        isComplex: true,
        willChange: false,
        painter: _AuroraImagePainter(image: image),
      );
    }

    // Track change — cross-fade the outgoing image out under the incoming one.
    // The only time this widget ticks, and only for [_kFadeDuration].
    return AnimatedBuilder(
      animation: fade,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        isComplex: true,
        willChange: true,
        painter: _AuroraImagePainter(
          image: image,
          previous: _previous,
          fade: Curves.easeInOut.transform(fade.value.clamp(0, 1)),
        ),
      ),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

// Blob anchors in normalised [-1, 1] space, pushed to the edges/corners so the
// most-saturated screen-blend overlaps happen in the periphery, away from the
// optical centre where the hero number sits.
const List<Offset> _anchors = [
  Offset(-0.72, -0.95),
  Offset(0.78, -0.82),
  Offset(0.92, 0.18),
  Offset(-0.82, 0.85),
  Offset(0.10, 1.02),
];
const List<double> _radiusFactor = [0.82, 0.72, 0.78, 0.70, 0.66];

/// Paints the mesh — ground, blobs, well, scrims — in logical coordinates, in
/// its still resting composition (the mesh no longer drifts; a track's identity
/// is carried by its *colours*, not by motion). Called once per track into an
/// offscreen recorder ([_renderToImage]), and directly onto the canvas in the
/// no-image fallback ([_AuroraScenePainter]).
void _paintAuroraScene(Canvas canvas, Size size, _FieldModel model) {
  final base = TrainColors.base;
  final w = size.width;
  final h = size.height;
  if (w <= 0 || h <= 0) return;

  // 1. Opaque ground.
  canvas.drawRect(Offset.zero & size, Paint()..color = base);

  final shortSide = math.min(w, h);
  final diag = math.sqrt(w * w + h * h);
  final e = model.energy;
  final crush = _lerp(0.85, 0.60, e); // higher energy → crisper (smaller) blobs
  final pulse = _lerp(0.06, 0.20, e);
  final warmDrift = -model.warmth * 0.03 * shortSide; // heat rises
  final gain = model.fieldGain;

  // 2. Light blobs (screen-blended so overlaps mix into secondary hues). Placed
  // at their resting anchors — the breathing envelope is at its mid-point.
  for (var j = 0; j < 5; j++) {
    final a = _anchors[j];
    final cx = (a.dx * 0.5 + 0.5) * w;
    final cy = (a.dy * 0.5 + 0.5) * h + warmDrift;
    final radius = _radiusFactor[j] * diag * crush;
    if (radius <= 0) continue;

    const b01 = 0.5; // resting point of the breathing envelope
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

/// Blits the cached mesh image(s) to fill the screen. In steady state it draws
/// just [image] (one texture blit); during a track change it draws [previous]
/// opaque with [image] alpha-blended over it at [fade] — a cross-fade with no
/// gradient re-evaluation, so it stays cheap on the raster thread.
class _AuroraImagePainter extends CustomPainter {
  _AuroraImagePainter({
    required this.image,
    this.previous,
    this.fade = 1.0,
  });

  final ui.Image image;
  final ui.Image? previous;

  /// Opacity of [image] over [previous], 0..1. Ignored when [previous] is null.
  final double fade;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final dst = Offset.zero & size;
    // The ground, in case an image ever has translucent edges — cheap, opaque.
    canvas.drawRect(dst, Paint()..color = TrainColors.base);
    final prev = previous;
    if (prev != null) {
      _blit(canvas, prev, dst, 1.0);
      _blit(canvas, image, dst, fade);
    } else {
      _blit(canvas, image, dst, 1.0);
    }
  }

  void _blit(Canvas canvas, ui.Image img, Rect dst, double opacity) {
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraImagePainter old) =>
      !identical(old.image, image) ||
      !identical(old.previous, previous) ||
      old.fade != fade;
}

/// The no-image fallback: paints the static scene directly. Repaints only when
/// the field (track) changes, so it too is cached and ticker-free.
class _AuroraScenePainter extends CustomPainter {
  _AuroraScenePainter(this.model);

  final _FieldModel model;

  @override
  void paint(Canvas canvas, Size size) => _paintAuroraScene(canvas, size, model);

  @override
  bool shouldRepaint(covariant _AuroraScenePainter old) => old.model != model;
}

/// The paint-ready shape of a [SessionField]: exactly five blob slots (a stable
/// count keeps the render simple), plus the motion/mood scalars. Slots beyond
/// the field's hue count reuse earlier hues at half weight, so a two-tone cover
/// fills the corners cohesively.
class _FieldModel {
  const _FieldModel(
    this.slotColors,
    this.slotPeak,
    this.energy,
    this.warmth,
    this.loudness,
    this.fieldGain,
  );

  /// Per-slot colour and per-slot base peak alpha (before fieldGain), both
  /// length 5.
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
