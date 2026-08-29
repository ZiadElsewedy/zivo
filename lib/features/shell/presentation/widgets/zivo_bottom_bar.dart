import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../music/presentation/now_playing_lozenge.dart'
    show kNowPlayingLozengeHeight;

/// Shared sizing so callers needing clearance above [ZivoBottomBar] (e.g. a
/// page's scroll padding, or the floating now-playing orb) can derive it
/// exactly instead of guessing a magic number — keeps that clearance from
/// drifting out of sync with the bar's actual layout.
abstract final class ZivoBottomBarMetrics {
  /// The floating island's own device-independent height: vertical padding
  /// (11 + 11) + icon (24) + icon-label gap (4) + label line height (~13 at
  /// 9.5sp). The island floats, so its rendered footprint also includes the
  /// bottom margin below it — see [height].
  static const double islandHeight = 63;

  /// Horizontal inset of the floating island from the screen edges.
  static const double sideMargin = 16;

  /// The gap between the island's bottom edge and the safe area (or the
  /// screen bottom on devices without a home indicator).
  static double _bottomMargin(double bottomInset) =>
      bottomInset > 0 ? bottomInset : 14;

  /// The now-playing strip fused to the island's top edge, when music is on
  /// screen. Re-exported from the strip itself so there is exactly one
  /// definition of how tall it is.
  static const double lozengeHeight = kNowPlayingLozengeHeight;

  /// Total rendered footprint of [ZivoBottomBar] for the current context —
  /// the floating island, the fused now-playing strip when [music] is on
  /// screen, and the margin beneath them — so page content clears the whole
  /// thing.
  ///
  /// Callers inside the shell should read [BottomChrome.of] rather than
  /// calling this directly: it resolves [music] from the live player state
  /// and rebuilds them when it changes. This is the raw computation behind
  /// it, and the fallback for a page mounted outside the shell.
  static double height(BuildContext context, {bool music = false}) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return islandHeight +
        (music ? lozengeHeight : 0) +
        _bottomMargin(bottomInset) +
        6;
  }
}

/// The four-tab command bar: Today · Hub · Ask · You (decision D-1).
///
/// A floating, blurred "island" rather than an edge-to-edge strip: it reads
/// as a physical object lifted off the content. Its signature is a single
/// ember capsule that **spring-glides** between destinations on the app's
/// house physics, while every tab's icon and label continuously interpolate
/// their colour and scale from the capsule's live position — so a tab
/// doesn't just switch on, it warms up as the capsule arrives.
class ZivoBottomBar extends StatefulWidget {
  const ZivoBottomBar({
    required this.currentIndex,
    required this.onTap,
    this.fused,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// An optional slim strip fused to the island's **top edge** — today, the
  /// now-playing lozenge. It is rendered inside the island's own clip and
  /// blur, so music reads as part of this one object rather than a second
  /// slab floating above it. Must be exactly
  /// [ZivoBottomBarMetrics.lozengeHeight] tall, or page clearance drifts.
  final Widget? fused;

  @override
  State<ZivoBottomBar> createState() => _ZivoBottomBarState();
}

class _ZivoBottomBarState extends State<ZivoBottomBar>
    with SingleTickerProviderStateMixin {
  static const _tabs = <_TabSpec>[
    _TabSpec('Today', AppIcons.today),
    _TabSpec('Hub', AppIcons.hub),
    _TabSpec('Ask', AppIcons.ask),
    _TabSpec('You', AppIcons.you),
  ];

  /// The live, fractional position of the ember capsule along the tab row
  /// (0 = Today … 3 = You). It's a continuous value — not the integer index
  /// — precisely so it can spring *between* slots and drive the smooth
  /// colour/scale falloff on either side as it travels.
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
    value: widget.currentIndex.toDouble(),
  );

  @override
  void didUpdateWidget(covariant ZivoBottomBar old) {
    super.didUpdateWidget(old);
    if (widget.currentIndex != old.currentIndex) {
      final target = widget.currentIndex.toDouble();
      if (reducedMotion(context)) {
        _pos.value = target;
      } else {
        // The capsule is a physical object the tap flicked toward its new
        // home — a touch of overshoot as it settles is the life of the bar.
        _pos.springTo(target, spring: AppSprings.bounce);
      }
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: ZivoBottomBarMetrics.sideMargin,
        right: ZivoBottomBarMetrics.sideMargin,
        bottom: ZivoBottomBarMetrics._bottomMargin(bottomInset),
      ),
      child: DecoratedBox(
        // A soft, warm lift so the island floats above whatever scrolls
        // behind it — depth from shadow, not a hard border.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.38),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                // Cool, not the old warm charcoal: this island is on screen
                // over every surface in the app, so it was the single biggest
                // source of "two palettes on one screen".
                color: TrainColors.raised,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: TrainColors.hairlineStrong),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.fused != null) widget.fused!,
                  SizedBox(
                    height: ZivoBottomBarMetrics.islandHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final slot = constraints.maxWidth / _tabs.length;
                          return AnimatedBuilder(
                            animation: _pos,
                            builder: (context, _) {
                              final pos = _pos.value.clamp(
                                0.0,
                                _tabs.length - 1.0,
                              );
                              return Stack(
                                children: [
                                  _Capsule(left: pos * slot, width: slot),
                                  Row(
                                    children: [
                                      for (var i = 0; i < _tabs.length; i++)
                                        Expanded(
                                          child: _Tab(
                                            spec: _tabs[i],
                                            // Warmth falls off with distance from the
                                            // capsule: 1 at its centre, 0 a slot away.
                                            t: (1 - (pos - i).abs()).clamp(
                                              0.0,
                                              1.0,
                                            ),
                                            onTap: () => widget.onTap(i),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
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
          ),
        ),
      ),
    );
  }
}

/// The ember highlight that glides beneath the active tab.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.left, required this.width});

  final double left;
  final double width;

  @override
  Widget build(BuildContext context) {
    // Inset within its slot so the capsule reads as a pill, not a full cell.
    const inset = 8.0;
    return Positioned(
      left: left + inset,
      top: 8,
      bottom: 8,
      width: width - inset * 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TrainColors.emberWash,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: TrainColors.ember.withValues(alpha: 0.28)),
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _Tab extends StatelessWidget {
  const _Tab({required this.spec, required this.t, required this.onTap});

  final _TabSpec spec;

  /// 0 = fully inactive, 1 = fully active — the live warmth of this tab,
  /// interpolated from the capsule's position so it eases in and out as the
  /// capsule passes rather than snapping.
  final double t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(TrainColors.tabInactive, TrainColors.ember, t)!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 1.0 + 0.12 * t,
            child: Icon(spec.icon, size: 24, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            spec.label.toUpperCase(),
            style: AppText.tabLabel.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
