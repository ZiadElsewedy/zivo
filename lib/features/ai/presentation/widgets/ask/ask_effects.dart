import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';

/// The message list's once-only entrance: rises into place the FIRST time a
/// display key is seen, then never again. The ledger ([played]) is consulted
/// exactly once per mount — so a rebuild never re-decides and never disposes
/// a running animation — while a later REMOUNT of the same identity (scrolled
/// out and back) reads "already played" and appears settled instantly. This
/// is what keeps scrolling through history solid: no bubble ever re-entrances
/// under the thumb. Honors reduce motion.
class RiseOnce extends StatefulWidget {
  const RiseOnce({
    required this.ledgerKey,
    required this.played,
    required this.child,
    super.key,
  });

  final String ledgerKey;
  final Set<String> played;
  final Widget child;

  @override
  State<RiseOnce> createState() => _RiseOnceState();
}

class _RiseOnceState extends State<RiseOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.enter,
  );

  /// Whether this identity should render settled: its entrance already
  /// played, or it was waived as history, or the user reduces motion.
  bool? _settled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decided exactly once, on first dependencies — never re-decided by a
    // rebuild, so an in-flight entrance is never torn down mid-flight.
    if (_settled == null) {
      final fresh = widget.played.add(widget.ledgerKey);
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      _settled = !fresh || reduceMotion;
      if (_settled!) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_settled ?? false) {
      return widget.child;
    }
    final curved = CurvedAnimation(parent: _c, curve: AppMotion.ease);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(-9 * (1 - t), 14 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
