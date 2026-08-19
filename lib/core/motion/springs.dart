import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Apple-style springs — specified as **damping ratio** + **response**
/// (settle time), the two designer-friendly parameters WWDC 2018's
/// "Designing Fluid Interfaces" uses in place of raw mass/stiffness/damping.
///
/// - [damping] `1.0` = critically damped (reaches the target with no
///   overshoot); `< 1.0` overshoots and oscillates — reserve that for
///   momentum-driven interactions (a flick, a completion pop), never a
///   passive fade-in.
/// - [response] is *not* a duration — a spring has no fixed duration, its
///   settle time emerges from the parameters — but it's the closest analogue:
///   roughly how quickly it reaches the target, in seconds. Lower = snappier.
SpringDescription appleSpring({double damping = 1.0, double response = 0.35, double mass = 1.0}) {
  final omega = 2 * math.pi / response;
  return SpringDescription(mass: mass, stiffness: mass * omega * omega, damping: 2 * mass * damping * omega);
}

/// House spring presets, reused across the workout feature's motion so every
/// screen shares one physical "material."
abstract final class AppSprings {
  /// The default for anything that just needs to settle gracefully — phase
  /// transitions, progress/state changes retargeting mid-flight.
  static final standard = appleSpring(damping: 1.0, response: 0.35);

  /// Fast and critically damped — press-down/press-up feedback, ~100ms feel.
  static final press = appleSpring(damping: 1.0, response: 0.15);

  /// The only place overshoot belongs: a momentum moment the gesture itself
  /// earned (a set chip completing, the completion checkmark landing).
  static final bounce = appleSpring(damping: 0.8, response: 0.35);
}

/// Whether the platform/user has asked for reduced motion — springs and
/// slides should fall back to a plain cross-fade or an instant snap rather
/// than animating with overshoot or a visible slide/scale.
bool reducedMotion(BuildContext context) => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Drives a single double value with an interruptible spring: retargeting
/// mid-flight always continues from the animation's current live value (and,
/// where supplied, its current velocity) — never the value it was *told* to
/// be — so nothing visibly jumps when a target changes while still settling.
extension SpringAnimation on AnimationController {
  void springTo(double target, {SpringDescription? spring, double velocity = 0}) {
    animateWith(SpringSimulation(spring ?? AppSprings.standard, value, target, velocity));
  }
}
