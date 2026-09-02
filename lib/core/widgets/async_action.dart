import 'package:flutter/widgets.dart';

/// One-at-a-time guard for the actions a screen *commits* — anything that
/// writes, uploads, deletes, or navigates away as a result.
///
/// Every capture screen in this app had grown its own `bool _busy` for the
/// same reason: these handlers are `async`, so between the first tap and the
/// `pop()` at the end of them the button is still live, and a second tap runs
/// the whole thing again. On a NEW entity that is not a harmless repeat — the
/// id is minted from `microsecondsSinceEpoch` per call, so the second tap
/// writes a *second* row instead of overwriting the first, and its `pop` then
/// pops the route underneath. This mixin is that flag, written once:
///
/// ```dart
/// class _FooPageState extends State<FooPage> with AsyncAction<FooPage> {
///   void _save() => runAction(#save, () async { ... });
///
///   Widget build(...) => PillButton(
///     enabled: _canSave && !actionInFlight,
///     busy: isRunning(#save),
///     onTap: _save,
///   );
/// }
/// ```
///
/// **One flight at a time, screen-wide** — not one per tag. Save racing
/// Delete on the same entity is the same bug as Save racing Save; the tag
/// exists only so the button that was actually pressed can show the spinner
/// while its siblings merely disable. A re-entrant call is *dropped*, never
/// queued: the user asked for one save, and a tap that lands during a save is
/// a duplicate of it, not a second intention.
///
/// The guard is about **duplicate submission**, not about waiting. Actions
/// that persist should still hand their durable write to
/// `core/util/deferred_write.dart` and return, so the flight this guards is
/// measured in frames rather than in network round-trips — see that file.
mixin AsyncAction<T extends StatefulWidget> on State<T> {
  Object? _running;
  bool _spent = false;

  /// Whether any guarded action on this screen is in flight, or a `once`
  /// action has already committed. Controls should read this (not
  /// [isRunning]) for their *enabled* state, so a second control can't start
  /// a racing write and a committed screen can't commit again.
  bool get actionInFlight => _running != null || _spent;

  /// Whether the action registered under [tag] is the one in flight — the
  /// spinner predicate for the specific control that was pressed.
  bool isRunning(Object tag) => _running == tag;

  /// Runs [action] unless something else already is. [tag] names it for
  /// [isRunning]; use a symbol or a short const string (`#save`, `#delete`).
  ///
  /// Set [once] for an action that **commits and leaves** — a save, a delete,
  /// anything that ends with a `pop`. In-flight alone is not enough of a
  /// guard for those any more: a local-first save hands its write to
  /// `deferWrite` and returns within the same frame, so the flight is over
  /// before a second tap of an impatient double-tap even lands. What actually
  /// makes a second tap harmless in the running app is the route being torn
  /// down — and depending on the timing of a pop animation for correctness is
  /// how the duplicate-row bug comes back. `once` retires the screen's
  /// actions outright: it has committed, and there is no second commit to be
  /// had.
  ///
  /// Rebuilds on entry and exit so the button reflects the flight. Both
  /// rebuilds are `mounted`-guarded because the overwhelmingly common shape
  /// is "write, then pop": by the time [action] returns, this State is
  /// usually gone.
  Future<void> runAction(
    Object tag,
    Future<void> Function() action, {
    bool once = false,
  }) async {
    if (_running != null || _spent) return;
    _running = tag;
    if (mounted) setState(() {});
    try {
      await action();
      if (once) _spent = true;
    } finally {
      _running = null;
      if (mounted) setState(() {});
    }
  }
}
