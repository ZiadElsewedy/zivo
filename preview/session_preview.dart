// TEMPORARY visual harness for reviewing the live-session redesign on a
// simulator. Not part of the app; delete once the pass is signed off.
//
//   flutter run -t preview/session_preview.dart
//
// It boots straight into LiveSessionPage on in-memory repos, with a music
// controller that serves REAL artwork bytes (generated at runtime, one strong
// colour per track) so the artwork tile, the palette extraction and every
// accent that hangs off it are all actually exercised.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/theme/app_theme.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/music/domain/audio_output.dart';
import 'package:zivo/features/music/domain/music_connection.dart';
import 'package:zivo/features/music/domain/music_controller.dart';
import 'package:zivo/features/music/domain/now_playing.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/presentation/pages/live_session_page.dart';

import '../test/support/fake_auth_repository.dart';
import '../test/support/fake_profile_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final music = PreviewMusicController();
  await music.warmUp();
  runApp(_PreviewApp(music: music));
}

final _plan = WorkoutPlan(
  id: 'p1',
  name: 'Preview Split',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 0,
  days: const [
    WorkoutDay(
      id: 'a',
      slot: 'A',
      label: 'Pull',
      order: 0,
      exercises: [
        PlannedExercise(
          id: 'ex1',
          name: 'Lat Pulldown',
          order: 0,
          muscleGroup: 'Back',
          defaultRestSeconds: 90,
          sets: [
            PlannedSet(
              order: 0,
              repTarget: RepTarget.fixed(9),
              restSeconds: 90,
              targetWeightKg: 30,
              type: SetType.working,
            ),
            PlannedSet(
              order: 1,
              repTarget: RepTarget.fixed(9),
              restSeconds: 90,
              targetWeightKg: 30,
              type: SetType.working,
            ),
            PlannedSet(
              order: 2,
              repTarget: RepTarget.fixed(9),
              restSeconds: 90,
              targetWeightKg: 30,
              type: SetType.working,
            ),
          ],
        ),
        PlannedExercise(
          id: 'ex2',
          name: 'Seated Row',
          order: 1,
          muscleGroup: 'Back',
          defaultRestSeconds: 90,
          sets: [
            PlannedSet(
              order: 0,
              repTarget: RepTarget.fixed(10),
              restSeconds: 90,
              targetWeightKg: 45,
              type: SetType.working,
            ),
          ],
        ),
      ],
    ),
  ],
);

class _PreviewApp extends StatelessWidget {
  const _PreviewApp({required this.music});

  final MusicController music;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      diet: InMemoryDietRepository(),
      ai: FakeAiRepository(),
      music: music,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: LiveSessionPage(day: _plan.days.first, plan: _plan),
      ),
    );
  }
}

/// A [MusicController] that behaves like a connected player and, crucially,
/// hands out real PNG artwork — the palette extraction in `SessionAmbience`
/// is what drives every accent in this pass, and it needs actual pixels.
class PreviewMusicController implements MusicController {
  final _now = StreamController<NowPlaying?>.broadcast();
  final _conn = StreamController<MusicConnection>.broadcast();
  final _out = StreamController<AudioOutput?>.broadcast();

  static const _tracks = [
    ('Neon Hours', 'Vault Signal', Color(0xFF1DB954)),
    ('Iron Cadence', 'Northbound', Color(0xFFE8402A)),
    ('Slow Burn', 'Marrow Club', Color(0xFF4C6BFF)),
    ('Gold Static', 'Halcyon Fields', Color(0xFFE8B93C)),
  ];

  final List<Uint8List> _artwork = [];
  int _index = 0;
  bool _paused = false;
  Timer? _ticker;
  Duration _position = Duration.zero;

  Future<void> warmUp() async {
    for (final track in _tracks) {
      _artwork.add(await _cover(track.$3));
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_paused) return;
      _position += const Duration(milliseconds: 500);
      _emit();
    });
    _conn.add(MusicConnection.connected);
    _emit();
  }

  /// A 240×240 two-tone cover, vivid enough that `PaletteGenerator` returns a
  /// decisive vibrant swatch rather than mud.
  Future<Uint8List> _cover(Color color) async {
    const size = 240.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, size, size),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(size, size),
          [color, Color.lerp(color, Colors.black, 0.65)!],
        ),
    );
    canvas.drawCircle(
      const Offset(size * 0.66, size * 0.34),
      size * 0.2,
      Paint()..color = Color.lerp(color, Colors.white, 0.55)!,
    );
    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  void _emit() {
    if (_artwork.isEmpty) return;
    final track = _tracks[_index];
    _current = NowPlaying(
      trackId: 'track-$_index',
      title: track.$1,
      artist: track.$2,
      artworkBytes: _artwork[_index],
      duration: const Duration(minutes: 3, seconds: 24),
      position: _position,
      isPaused: _paused,
      hasControl: true,
    );
    _now.add(_current);
  }

  NowPlaying? _current;

  @override
  Stream<NowPlaying?> get nowPlaying => _now.stream;
  @override
  Stream<MusicConnection> get connection => _conn.stream;
  @override
  Stream<AudioOutput?> get output => _out.stream;
  @override
  NowPlaying? get currentNowPlaying => _current;
  @override
  MusicConnection get currentConnection => MusicConnection.connected;
  @override
  AudioOutput? get currentOutput => null;

  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> play() async {
    _paused = false;
    _emit();
  }

  @override
  Future<void> pause() async {
    _paused = true;
    _emit();
  }

  @override
  Future<void> next() async {
    _index = (_index + 1) % _tracks.length;
    _position = Duration.zero;
    _emit();
  }

  @override
  Future<void> previous() async {
    _index = (_index - 1 + _tracks.length) % _tracks.length;
    _position = Duration.zero;
    _emit();
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _emit();
  }

  @override
  Future<void> replay() => seek(Duration.zero);
  @override
  Future<void> setShuffle(bool shuffle) async {}
  @override
  Future<void> setRepeat(MusicRepeatMode mode) async {}

  @override
  void dispose() {
    _ticker?.cancel();
    _now.close();
    _conn.close();
    _out.close();
  }
}
