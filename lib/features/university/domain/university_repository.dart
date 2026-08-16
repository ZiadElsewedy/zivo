import 'university_item.dart';

/// The seam between the app and university item storage (in-memory demo for
/// now, Firestore-backed later).
abstract interface class UniversityRepository {
  List<UniversityItem> get current;
  Stream<List<UniversityItem>> watchAll();
  Future<void> add(UniversityItem item);
  Future<void> update(UniversityItem item);
  Future<void> setDone(String id, bool done);
  Future<void> remove(String id);
}
