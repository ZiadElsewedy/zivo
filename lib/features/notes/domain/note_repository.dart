import 'note.dart';

/// The seam between the app and note storage (in-memory demo for now).
abstract interface class NoteRepository {
  List<Note> get current;
  Stream<List<Note>> watchAll();
  Future<void> add(Note note);
  Future<void> update(Note note);
  Future<void> remove(String id);
}
