import '../../diet/domain/body_profile.dart';
import '../../diet/domain/diet_repository.dart';
import '../../workout/domain/body_weight_entry.dart';
import '../../workout/domain/body_weight_repository.dart';
import '../domain/body_data_writer.dart';

/// The real [BodyDataWriter]: persists Ask-form values through the same
/// user-owned repositories the app's own capture screens use — weight as a
/// weigh-in in [BodyWeightRepository] (the app's single weight time series),
/// height merged into the diet feature's [BodyProfile]. No new storage, no
/// second copy of a number, and nothing the manual forms don't already write.
class RepositoryBodyDataWriter implements BodyDataWriter {
  RepositoryBodyDataWriter({
    required DietRepository diet,
    required BodyWeightRepository? bodyWeight,
    DateTime Function() now = DateTime.now,
  }) : // Public params to private fields — an initializing formal can't be
       // named with a leading underscore, so these stay plain assignments.
       // ignore: prefer_initializing_formals
       _diet = diet,
       // ignore: prefer_initializing_formals
       _bodyWeight = bodyWeight,
       // ignore: prefer_initializing_formals
       _now = now;

  final DietRepository _diet;

  /// Nullable because some scopes (a few widget tests) omit it; without it a
  /// weight simply isn't remembered — it still reaches the coach as context.
  final BodyWeightRepository? _bodyWeight;
  final DateTime Function() _now;

  @override
  Future<void> saveWeightKg(double weightKg) async {
    if (!_weightIsPlausible(weightKg)) return;
    final log = _bodyWeight;
    if (log == null) return;
    final at = _now();
    await log.save(
      BodyWeightEntry(
        // Same id scheme the manual weigh-in forms use.
        id: at.microsecondsSinceEpoch.toString(),
        weightKg: weightKg,
        loggedAt: at,
      ),
    );
  }

  @override
  Future<bool> saveHeightCm(double heightCm) async {
    if (!heightIsPlausible(heightCm)) return false;
    // Height alone can't construct a BodyProfile (sex + activity are required),
    // so it can only be MERGED into one that already exists. When none does,
    // report false and let the value flow on to the coach unremembered.
    //
    // A one-shot fetch, NOT the sync `currentBodyProfile` cache: that cache is
    // only warm once a screen has subscribed to the profile stream this
    // session, so from Ask (where none has) it reads null even when a profile
    // exists — and height would silently never be remembered (audit F2).
    final existing = await _diet.fetchBodyProfile();
    if (existing == null) return false;
    if (existing.heightCm == heightCm) return true; // already set — no-op write
    await _diet.saveBodyProfile(
      existing.copyWith(heightCm: heightCm, updatedAt: _now()),
    );
    return true;
  }

  /// A believable bodyweight in kg — a wide typo guard mirroring the spirit of
  /// [heightIsPlausible], not a judgement about any person.
  static bool _weightIsPlausible(double kg) => kg >= 20 && kg <= 400;
}
