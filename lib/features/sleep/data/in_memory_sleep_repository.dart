import 'dart:async';

import '../domain/sleep_night.dart';
import '../domain/sleep_repository.dart';
import '../domain/sleep_targets.dart';

/// The offline/test [SleepRepository]. Starts **empty** on purpose.
///
/// Every other in-memory repository in ZIVO seeds demo rows so a screen has
/// something to show; this one must not. A fabricated night is exactly the
/// thing the feature exists to refuse, and a demo night indistinguishable from
/// a measured one would make the empty state — the single most important
/// screen here — impossible to see during development.
class InMemorySleepRepository implements SleepRepository {
  final List<SleepNight> _nights = [];
  SleepTargets? _targets;
  SleepMark? _openMark;

  final StreamController<List<SleepNight>> _nightsController =
      StreamController<List<SleepNight>>.broadcast();
  final StreamController<SleepTargets?> _targetsController =
      StreamController<SleepTargets?>.broadcast();
  final StreamController<SleepMark?> _markController =
      StreamController<SleepMark?>.broadcast();

  @override
  List<SleepNight> get current => List.unmodifiable(_nights);

  @override
  SleepTargets? get currentTargets => _targets;

  @override
  SleepMark? get currentOpenMark => _openMark;

  @override
  Stream<List<SleepNight>> watchNights() async* {
    yield current;
    yield* _nightsController.stream;
  }

  @override
  Stream<SleepTargets?> watchTargets() async* {
    yield _targets;
    yield* _targetsController.stream;
  }

  @override
  Stream<SleepMark?> watchOpenMark() async* {
    yield _openMark;
    yield* _markController.stream;
  }

  @override
  Future<void> saveTargets(SleepTargets targets) async {
    _targets = targets;
    _targetsController.add(targets);
  }

  @override
  Future<void> upsertNights(List<SleepNight> nights) async {
    for (final night in nights) {
      final index = _nights.indexWhere(
        (existing) => _sameDay(existing.sleepDay, night.sleepDay),
      );
      if (index >= 0) {
        _nights[index] = night;
      } else {
        _nights.add(night);
      }
    }
    _nights.sort((a, b) => b.sleepDay.compareTo(a.sleepDay));
    _nightsController.add(current);
  }

  @override
  Future<void> removeNight(DateTime sleepDay) async {
    _nights.removeWhere((night) => _sameDay(night.sleepDay, sleepDay));
    _nightsController.add(current);
  }

  @override
  Future<void> openMark(SleepMark mark) async {
    _openMark = mark;
    _markController.add(mark);
  }

  @override
  Future<void> clearOpenMark() async {
    _openMark = null;
    _markController.add(null);
  }

  void dispose() {
    _nightsController.close();
    _targetsController.close();
    _markController.close();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
