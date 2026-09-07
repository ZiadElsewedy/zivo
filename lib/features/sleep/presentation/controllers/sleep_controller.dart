import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/sleep_insight.dart';
import '../../domain/sleep_metrics.dart';
import '../../domain/sleep_night.dart';
import '../../domain/sleep_repository.dart';
import '../../domain/sleep_service.dart';
import '../../domain/sleep_source.dart';
import '../../domain/sleep_targets.dart';

/// The Sleep screens' document ([ADR-008](../../../../../docs/DECISIONS/ADR-008-presentation-controllers.md)).
///
/// It exists for one reason above the others: **the window arithmetic**. The
/// daily view, the weekly raster, the week-over-week comparison and the AI
/// fact sheet all read the same night list through four different windows, and
/// every one of them has to apply the gates in `SleepGates` before a figure is
/// allowed on screen. Spread across `build` methods that logic would be
/// re-derived per widget and the gates would drift apart — the exact way a
/// "trend" over three nights ends up rendered.
///
/// Holds no `BuildContext` and never navigates.
class SleepController extends ChangeNotifier {
  SleepController({
    required this.repository,
    required this.service,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    // Seeded synchronously before subscribing: every repository exposes a
    // `current` for exactly this reason, and reading it here means the first
    // frame is never a lie about what we have.
    _nights = repository.current;
    _targets = repository.currentTargets;
    _openMark = repository.currentOpenMark;

    _subscribe();
    service.syncState.addListener(_onSyncState);
  }

  final SleepRepository repository;
  final SleepService service;
  final DateTime Function() _now;

  StreamSubscription<List<SleepNight>>? _nightsSub;
  StreamSubscription<SleepTargets?>? _targetsSub;
  StreamSubscription<SleepMark?>? _markSub;

  List<SleepNight> _nights = const [];
  SleepTargets? _targets;
  SleepMark? _openMark;
  bool _hasLoaded = false;
  bool _loadFailed = false;

  List<SleepNight> get nights => _nights;
  SleepTargets? get targets => _targets;
  SleepMark? get openMark => _openMark;

  /// How long the open session has been running, or null when none is open.
  ///
  /// Computed on read rather than ticked. A periodic timer would buy a live
  /// second hand and cost the page a frame every tick forever — for a figure
  /// whose smallest unit is a minute, on a screen whose whole point is that
  /// nothing is being measured while it is open.
  Duration? get openMarkElapsed {
    final mark = _openMark;
    if (mark == null) return null;
    final elapsed = _now().toUtc().difference(mark.atUtc);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }
  SleepSyncState get syncState => service.syncState.value;

  /// Whether the first snapshot has arrived. Distinguishes "still loading"
  /// from "loaded and empty", which must render as two different screens —
  /// a spinner and an honest empty state are not interchangeable.
  bool get hasLoaded => _hasLoaded;

  /// The nights stream ended in an error — storage refused the read, or the
  /// snapshot could not be decoded.
  ///
  /// It has its own flag because the alternative is what this screen used to
  /// do: nothing. [_onNights] was the only thing that ever set [_hasLoaded],
  /// and the subscription carried no `onError`, so a refused read left the
  /// page rendering its not-yet-loaded placeholder **forever** — a silent
  /// 120px void where the headline belongs, with the week and the insights
  /// below it looking perfectly healthy. A screen may say it is loading, and
  /// it may say it failed; it may not sit between the two with no way out.
  bool get loadFailed => _loadFailed;

  /// Last night's record, or null when there is none.
  ///
  /// "Last night" is the most recent night **that has data**, not simply the
  /// newest row: a night with nothing in it is stored so the week can show a
  /// gap, and surfacing it as the headline would put an empty state on a
  /// screen that has perfectly good data from the night before.
  SleepNight? get lastNight {
    for (final night in _nights) {
      if (night.hasData) return night;
    }
    return null;
  }

  /// The seven sleep-days ending today, oldest first, with missing days filled
  /// in as empty nights.
  ///
  /// The fill is what lets the raster draw a gap. Dropping absent days would
  /// close the week up and hide exactly the thing the chart exists to show.
  List<SleepNight> get week => _window(7);

  /// The seven days before [week] — the comparison half.
  List<SleepNight> get previousWeek => _window(7, offsetDays: 7);

  SleepWindowMetrics get weekMetrics =>
      SleepMetrics.forWindow(week, windowNights: 7, targets: _targets);

  SleepWindowMetrics get previousWeekMetrics =>
      SleepMetrics.forWindow(previousWeek, windowNights: 7, targets: _targets);

  SleepComparison get comparison => SleepMetrics.compare(
    current: weekMetrics,
    previous: previousWeekMetrics,
  );

  SleepTrend get trend => SleepMetrics.trend(_window(28));

  /// The typed input the AI layer is allowed to see — computed figures only,
  /// plus the explicit list of what failed its gate and must not be discussed.
  SleepFactSheet get factSheet => buildFactSheet(
    current: weekMetrics,
    previous: previousWeekMetrics,
    comparison: comparison,
    trend: trend,
    nights: week,
    targets: _targets,
  );

  /// Whether the empty state may say "no sleep recorded".
  ///
  /// It may not when the platform will not confirm we were allowed to read —
  /// the iOS case, where a refusal is indistinguishable from an empty store.
  /// Asserting emptiness there would be a claim with nothing behind it, so the
  /// screen says "not visible to ZIVO" instead.
  bool get canAssertNoData =>
      !syncState.nothingVisible &&
      syncState.authorization != SleepAuthorization.unknown;

  Future<void> refresh({int? days}) => service.sync(days: days);

  /// Re-open the repository streams after [loadFailed], and re-read the
  /// platform store.
  ///
  /// Re-subscribing is what makes the button worth showing: a Firestore
  /// snapshot listener that errors is *finished*, so re-reading the health
  /// store alone would leave the screen exactly as broken as it was.
  Future<void> retryLoad() async {
    _loadFailed = false;
    _subscribe();
    notifyListeners();
    await service.sync();
  }

  Future<void> requestAccess() async {
    await service.source.requestAuthorization();
    await service.sync(days: SleepService.backfillDays);
  }

  Future<void> markGoingToSleep() => service.markGoingToSleep();

  Future<bool> markAwake({required String providerName}) =>
      service.markAwake(providerName: providerName);

  Future<void> cancelOpenMark() => repository.clearOpenMark();

  Future<void> saveTargets(SleepTargets targets) =>
      service.saveTargets(targets);

  Future<void> editNight({
    required DateTime sleepDay,
    required DateTime startAtUtc,
    required DateTime endAtUtc,
    required String providerName,
  }) => service.editNight(
    sleepDay: sleepDay,
    startAtUtc: startAtUtc,
    endAtUtc: endAtUtc,
    providerName: providerName,
  );

  @override
  void dispose() {
    _nightsSub?.cancel();
    _targetsSub?.cancel();
    _markSub?.cancel();
    service.syncState.removeListener(_onSyncState);
    super.dispose();
  }

  void _subscribe() {
    _nightsSub?.cancel();
    _targetsSub?.cancel();
    _markSub?.cancel();
    // Every one of these carries an `onError`. A repository stream that fails
    // is a state this screen has to be able to render, and an unhandled
    // stream error is not one — it goes to the zone, where in a release build
    // nobody sees it and the UI is left waiting on an event that will never
    // come.
    _nightsSub = repository.watchNights().listen(_onNights, onError: _onError);
    _targetsSub = repository.watchTargets().listen(
      _onTargets,
      onError: _onError,
    );
    _markSub = repository.watchOpenMark().listen(_onMark, onError: _onError);
  }

  /// [count] consecutive sleep-days ending [offsetDays] before today, oldest
  /// first, with absent days present as empty nights.
  List<SleepNight> _window(int count, {int offsetDays = 0}) {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final byDay = {
      for (final night in _nights) _dayKey(night.sleepDay): night,
    };

    return [
      for (var i = count - 1; i >= 0; i--)
        () {
          final day = today.subtract(Duration(days: i + offsetDays));
          return byDay[_dayKey(day)] ??
              SleepNight.empty(day, targets: _targets);
        }(),
    ];
  }

  static String _dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

  void _onNights(List<SleepNight> nights) {
    _nights = nights;
    _hasLoaded = true;
    notifyListeners();
  }

  void _onTargets(SleepTargets? targets) {
    _targets = targets;
    notifyListeners();
  }

  void _onMark(SleepMark? mark) {
    _openMark = mark;
    notifyListeners();
  }

  void _onError(Object error, StackTrace stackTrace) {
    // Loaded, and the answer is "we could not read it" — which is a screen,
    // where "not loaded yet" is a spinner that never stops.
    _hasLoaded = true;
    _loadFailed = true;
    notifyListeners();
  }

  void _onSyncState() => notifyListeners();
}
