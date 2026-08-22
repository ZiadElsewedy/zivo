import 'body_weight_entry.dart';

/// The seam between the app and bodyweight-log storage (in-memory demo for
/// now, Firestore-backed later) — every logged weigh-in, newest first.
abstract interface class BodyWeightRepository {
  List<BodyWeightEntry> get current;
  Stream<List<BodyWeightEntry>> watchAll();

  /// Creates or replaces [entry] by id (idempotent edit).
  Future<void> save(BodyWeightEntry entry);

  Future<void> remove(String id);
}
