import 'dart:async';

import '../domain/media_storage_preferences.dart';

/// In-memory [MediaPreferencesRepository] for offline/dev runs and tests.
class InMemoryMediaPreferencesRepository implements MediaPreferencesRepository {
  InMemoryMediaPreferencesRepository([
    this._prefs = MediaStoragePreferences.defaults,
  ]);

  MediaStoragePreferences _prefs;
  final StreamController<MediaStoragePreferences> _controller =
      StreamController<MediaStoragePreferences>.broadcast();

  @override
  Stream<MediaStoragePreferences> watch() async* {
    yield _prefs;
    yield* _controller.stream;
  }

  @override
  Future<MediaStoragePreferences> read() async => _prefs;

  @override
  Future<void> save(MediaStoragePreferences preferences) async {
    _prefs = preferences;
    _controller.add(_prefs);
  }

  void dispose() => _controller.close();
}
