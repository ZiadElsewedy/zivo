import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../workout/domain/body_weight_entry.dart';
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
/// Missing data is a normal outcome, not an error: [builder] is handed a
/// resolution that names what's absent, and the screen asks for exactly that.
class BodyMeasuresBuilder extends StatefulWidget {
  const BodyMeasuresBuilder({required this.builder, this.now, super.key});

  final Widget Function(BuildContext context, BodyMeasuresResolution measures)
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
      _latestWeighIn = log.current.isEmpty ? null : log.current.first;
      _weighInSub = log.watchAll().listen((entries) {
        if (mounted) {
          setState(
            () => _latestWeighIn = entries.isEmpty ? null : entries.first,
          );
        }
      });
    }

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
    ),
  );
}
