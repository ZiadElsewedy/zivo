import 'dart:async';

import '../domain/note.dart';
import '../domain/note_repository.dart';

/// Demo store for notes, newest first. Seeded with a couple of notes.
class InMemoryNoteRepository implements NoteRepository {
  InMemoryNoteRepository() {
    _seed();
  }

  final List<Note> _items = [];
  final StreamController<List<Note>> _controller =
      StreamController<List<Note>>.broadcast();

  void _seed() {
    final now = DateTime.now();
    _items.addAll([
      Note(
        id: 'seed-n1',
        body: 'Visa appointment — bring passport, photos, and the bank letter.',
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
      Note(
        id: 'seed-n2',
        title: 'Project ideas',
        body: 'A tiny CLI that summarises my week from the app data.',
        updatedAt: now.subtract(const Duration(days: 5)),
      ),
    ]);
  }

  @override
  List<Note> get current => List.unmodifiable(_items);

  @override
  Stream<List<Note>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> add(Note note) async {
    _items.insert(0, note);
    _controller.add(current);
  }

  @override
  Future<void> update(Note note) async {
    final index = _items.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
    _items[index] = note;
    _controller.add(current);
  }

  @override
  Future<void> remove(String id) async {
    _items.removeWhere((n) => n.id == id);
    _controller.add(current);
  }

  void dispose() => _controller.close();
}
