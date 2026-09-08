import 'dart:async';

import '../domain/workout_settings.dart';
import '../domain/workout_settings_repository.dart';

/// The offline/test [WorkoutSettingsRepository] — the same contract without
/// Firestore.
class InMemoryWorkoutSettingsRepository implements WorkoutSettingsRepository {
  InMemoryWorkoutSettingsRepository({WorkoutSettings? initial})
    : _settings = initial ?? WorkoutSettings.defaults;

  WorkoutSettings _settings;
  final _controller = StreamController<WorkoutSettings>.broadcast();

  @override
  WorkoutSettings get current => _settings;

  @override
  Stream<WorkoutSettings> watch() async* {
    yield _settings;
    yield* _controller.stream;
  }

  @override
  Future<void> save(WorkoutSettings settings) async {
    _settings = settings;
    _controller.add(settings);
  }

  void dispose() => _controller.close();
}
