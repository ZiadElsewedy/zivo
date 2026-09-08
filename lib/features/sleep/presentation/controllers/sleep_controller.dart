import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/sleep_insight.dart';
import '../../domain/sleep_metrics.dart';
import '../../domain/sleep_night.dart';
import '../../domain/sleep_repository.dart';
import '../../domain/sleep_service.dart';
import '../../domain/sleep_source.dart';
import '../../domain/sleep_stage_breakdown.dart';
import '../../domain/sleep_targets.dart';
import '../../domain/sleep_window.dart';

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

  /// Today's sleep-day — the date the user woke up on this morning.
  ///
  /// The anchor every window here is measured from. Named because the
  /// noon-to-noon rule in `sleep_resolver.dart` makes "today" mean something
  /// specific and non-obvious: the night of the 8th is the sleep you woke up
  /// from on the 8th, so today's row is last night's sleep.
  DateTime get today => SleepWindow.dayOf(_now());

  /// The most recent night **that has data**, or null when there is none.
  ///
  /// Not simply the newest row: an empty night is stored so the week can draw
  /// its gap, and surfacing one as the headline would put an empty state on a
  /// screen with perfectly good data from the night before.
  ///
  /// Deliberately *not* called `lastNight`. It is only last night when
  /// [latestNightAgeDays] is 0 or 1 — see [isLatestNightStale].
  SleepNight? get latestNight => SleepWindow.latestWithData(_nights);

  /// Whole days between [latestNight] and today; null when there is no night.
  ///
  /// `0` is the night we woke from this morning, `1` is the night before.
  int? get latestNightAgeDays {
    final night = latestNight;
    if (night == null) return null;
    return SleepWindow.ageInDays(night, _now());
  }

  /// Whether [latestNight] is old enough that calling it "last night" would be
  /// false.
  ///
  /// The screen used to headline the newest night it could find with the words
  /// "Last night" and no date, so a user who had not worn their watch for five
  /// days was shown a five-day-old figure as though it were this morning's.
  /// That is the single most misleading thing this feature could do — a real
  /// number, correctly computed, attached to the wrong night — and it is
  /// indistinguishable from the app simply not updating.
  bool get isLatestNightStale => (latestNightAgeDays ?? 0) > 1;

  /// The stage composition of [latestNight], or null when the source did not
  /// stage it. See [SleepStageBreakdown] for what "did not stage it" covers.
  SleepStageBreakdown? get latestNightStages {
    final session = latestNight?.main;
    if (session == null) return null;
    return SleepStageBreakdown.forSession(session);
  }

  /// The seven sleep-days ending today, oldest first, with missing days filled
  /// in as empty nights.
  ///
  /// The fill is what lets the raster draw a gap. Dropping absent days would
  /// close the week up and hide exactly the thing the chart exists to show.
  List<SleepNight> get week => weekEndingOn(today);

  /// The seven days before [week] — the comparison half.
  List<SleepNight> get previousWeek =>
      weekEndingOn(today.subtract(const Duration(days: 7)));

  /// The seven sleep-days ending on [lastDay], oldest first.
  ///
  /// Public because the weekly page pages backwards through history with it,
  /// and doing that arithmetic there would fork the definition of a week
  /// between two screens. `SleepWindow` is the one implementation.
  List<SleepNight> weekEndingOn(DateTime lastDay) => SleepWindow.daysEndingOn(
    _nights,
    lastDay: lastDay,
    count: 7,
    targets: _targets,
  );

  /// Metrics for any window — the weekly page's historical weeks included.
  SleepWindowMetrics metricsFor(List<SleepNight> nights) =>
      SleepMetrics.forWindow(
        nights,
        windowNights: nights.length,
        targets: _targets,
      );

  SleepWindowMetrics get weekMetrics => metricsFor(week);

  /// The fortnight **before** [latestNight] — the baseline the headline night
  /// is compared against.
  ///
  /// Excluding the night itself is the whole point. A night compared to an
  /// average it is a member of pulls that average toward itself and shrinks
  /// the difference, worst on exactly the sparse weeks where the reader has
  /// least ability to notice: one night against a "week" of one night reports
  /// a difference of zero, forever, and reads as a bug.
  SleepWindowMetrics get baselineMetrics {
    final night = latestNight;
    if (night == null) {
      return const SleepWindowMetrics(nightCount: 0, windowNights: 0);
    }
    return metricsFor(
      SleepWindow.daysEndingOn(
        _nights,
        lastDay: SleepWindow.dayOf(
          night.sleepDay,
        ).subtract(const Duration(days: 1)),
        count: baselineNights,
        targets: _targets,
      ),
    );
  }

  /// How far back the headline's baseline reaches. A fortnight: long enough
  /// that a couple of missing nights still clears
  /// `SleepGates.minNightsForAverage`, short enough that it describes the
  /// user's current sleep rather than their year.
  static const int baselineNights = 14;

  SleepWindowMetrics get previousWeekMetrics => metricsFor(previousWeek);

  /// Mean stage composition across [nights], or null when too few are staged.
  SleepStageAverages? stageAveragesFor(List<SleepNight> nights) =>
      SleepStageAverages.forWindow(nights);

  SleepComparison get comparison =>
      SleepMetrics.compare(current: weekMetrics, previous: previousWeekMetrics);

  SleepTrend get trend => SleepMetrics.trend(
    SleepWindow.daysEndingOn(
      _nights,
      lastDay: today,
      count: trendWindowNights,
      targets: _targets,
    ),
  );

  /// The run a trend is read over. Four weeks, which is the shortest window
  /// that can satisfy `SleepGates.minDaysSpanForTrend` at all.
  static const int trendWindowNights = 28;

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

  /// The refresh the page runs when it opens and when the app comes forward.
  ///
  /// Throttled in the service rather than here, so the Sleep page, Today and
  /// the Hub share one budget instead of three. A user who wakes up, opens
  /// ZIVO, sees Today, then taps into Sleep should trigger **one** read of the
  /// health store, not two.
  Future<void> refreshIfStale() => service.syncIfStale();

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
