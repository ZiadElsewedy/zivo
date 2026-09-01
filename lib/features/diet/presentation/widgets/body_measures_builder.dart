import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../workout/domain/body_weight_entry.dart';
import '../../domain/analysis/maintenance_calibration.dart';
import '../../domain/body_measures.dart';
import '../../domain/body_profile.dart';

/// Assembles the user's body data from the three places its parts live, and
/// rebuilds [builder] whenever any of them changes.
///
/// **The one place a screen gets [BodyMeasuresResolution] from.** The parts
/// come from three repositories — the body profile (diet), the weigh-in log
/// (workout) and the date of birth (account profile) — and a screen that
/// wires them up for itself is how two surfaces end up quoting two different
/// maintenance figures for the same person. `resolveBodyMeasures` owns the
/// rules; this owns the plumbing.
///
/// It also runs the **maintenance calibration** — the measurement of what this
/// person actually burns, from their own weigh-ins and food log
/// (`analysis/maintenance_calibration.dart`). That belongs here rather than in
/// each screen for the same reason the rest does: it reads three repositories
/// and it must produce one answer, not one per surface. [CalibrationResult] is
/// handed to the builder alongside the measures, so a screen can say *why*
/// there is no measurement yet instead of silently falling back to the
/// equation.
///
/// Missing data is a normal outcome, not an error: [builder] is handed a
/// resolution that names what's absent, and the screen asks for exactly that.
class BodyMeasuresBuilder extends StatefulWidget {
  const BodyMeasuresBuilder({required this.builder, this.now, super.key});

  final Widget Function(
    BuildContext context,
    BodyMeasuresResolution measures,
    CalibrationResult calibration,
  )
  builder;

  /// Injected for tests; defaults to the wall clock. Only used to turn a date
  /// of birth into an age.
  final DateTime? now;

  @override
  State<BodyMeasuresBuilder> createState() => _BodyMeasuresBuilderState();
}

class _BodyMeasuresBuilderState extends State<BodyMeasuresBuilder> {
  BodyProfile? _profile;
  BodyWeightEntry? _latestWeighIn;
  DateTime? _dateOfBirth;

  StreamSubscription<BodyProfile?>? _profileSub;
  StreamSubscription<List<BodyWeightEntry>>? _weighInSub;
  bool _wired = false;

  /// The measurement, or what it's short of. Starts as "needs weigh-ins" —
  /// the honest state before anything has been read.
  CalibrationResult _calibration = const CalibrationResult.needs(
    CalibrationGap.needsWeighIns,
  );
  List<BodyWeightEntry> _weighIns = const [];
  List<DailyIntake> _intake = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;

    final scope = AppScope.of(context);
    _profile = scope.diet.currentBodyProfile;
    _profileSub = scope.diet.watchBodyProfile().listen((profile) {
      if (mounted) setState(() => _profile = profile);
    });

    // Optional in [AppScope] (many widget tests never provide one), so its
    // absence is just "no weigh-in", handled by the resolution like any other
    // missing piece.
    final log = scope.bodyWeight;
    if (log != null) {
      _weighIns = log.current;
      _latestWeighIn = log.current.isEmpty ? null : log.current.first;
      _weighInSub = log.watchAll().listen((entries) {
        if (!mounted) return;
        setState(() {
          _weighIns = entries;
          _latestWeighIn = entries.isEmpty ? null : entries.first;
        });
        _recalibrate();
      });
    }

    // The intake history behind the calibration. One range read, not a
    // subscription: this is a measurement over weeks, and nothing about it
    // needs to change when the user logs lunch.
    final now = widget.now ?? DateTime.now();
    scope.diet
        .dailyIntake(
          from: now.subtract(const Duration(days: kCalibrationWindowDays)),
          to: now,
        )
        .then((intake) {
          if (!mounted) return;
          setState(() => _intake = intake);
          _recalibrate();
        })
        .catchError((_) {});

    // Read once, best-effort. A failure here means no verdict — never a
    // guessed age.
    final uid = scope.auth.currentUser?.uid;
    if (uid != null) {
      scope.profiles
          .fetchProfile(uid)
          .then((profile) {
            if (mounted && profile != null) {
              setState(() => _dateOfBirth = profile.dateOfBirth);
            }
          })
          .catchError((_) {});
    }
  }

  void _recalibrate() {
    if (!mounted) return;
    final result = calibrateMaintenance(
      weighIns: _weighIns,
      intake: _intake,
      now: widget.now ?? DateTime.now(),
    );
    setState(() => _calibration = result);
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _weighInSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    resolveBodyMeasures(
      profile: _profile,
      latestWeightKg: _latestWeighIn?.weightKg,
      weighedAt: _latestWeighIn?.loggedAt,
      dateOfBirth: _dateOfBirth,
      now: widget.now ?? DateTime.now(),
      measuredMaintenanceKcal: _calibration.measured?.maintenanceKcal,
    ),
    _calibration,
  );
}

/// How far back the calibration looks for logged intake.
///
/// Eight weeks. Long enough that a user who logs most days clears the coverage
/// bar comfortably, short enough that a metabolism, an activity level and a
/// body from two months ago are still recognisably this person's.
const int kCalibrationWindowDays = 56;
