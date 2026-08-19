import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/env/app_environment.dart';
import '../core/env/env_banner.dart';
import '../core/firebase/uid_source.dart';
import '../core/media/data/device_gallery_target.dart';
import '../core/media/data/firestore_media_preferences_repository.dart';
import '../core/media/data/firestore_media_registry.dart';
import '../core/media/data/google_drive_backup_client.dart';
import '../core/media/data/google_drive_target.dart';
import '../core/media/data/in_memory_media_preferences_repository.dart';
import '../core/media/data/in_memory_media_registry.dart';
import '../core/media/data/local_media_store.dart';
import '../core/media/domain/drive_backup_client.dart';
import '../core/media/domain/media_backup_target.dart';
import '../core/media/domain/media_registry.dart';
import '../core/media/domain/media_storage_preferences.dart';
import '../core/media/domain/media_store.dart';
import '../core/media/media_service.dart';
import '../core/scope/app_scope.dart';
import '../core/theme/app_theme.dart';
import '../features/ai/data/fake_ai_repository.dart';
import '../features/ai/data/firebase_ai_repository.dart';
import '../features/ai/domain/ai_repository.dart';
import '../features/auth/data/firebase_auth_repository.dart';
import '../features/auth/data/firestore_profile_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/domain/profile_repository.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/diet/data/firestore_diet_repository.dart';
import '../features/diet/data/in_memory_diet_repository.dart';
import '../features/diet/domain/diet_repository.dart';
import '../features/expenses/data/firestore_expense_repository.dart';
import '../features/expenses/data/in_memory_expense_repository.dart';
import '../features/expenses/domain/expense_repository.dart';
import '../features/moments/data/firestore_moment_repository.dart';
import '../features/moments/data/in_memory_moment_repository.dart';
import '../features/moments/domain/moment_repository.dart';
import '../features/notes/data/firestore_note_repository.dart';
import '../features/notes/data/in_memory_note_repository.dart';
import '../features/notes/domain/note_repository.dart';
import '../features/schedule/data/firestore_schedule_repository.dart';
import '../features/schedule/data/in_memory_schedule_repository.dart';
import '../features/schedule/domain/schedule_repository.dart';
import '../features/tasks/data/firestore_task_repository.dart';
import '../features/tasks/data/in_memory_task_repository.dart';
import '../features/tasks/domain/task_repository.dart';
import '../features/university/data/firestore_university_repository.dart';
import '../features/university/data/in_memory_university_repository.dart';
import '../features/university/domain/university_repository.dart';
import '../features/workout/data/firestore_workout_plan_repository.dart';
import '../features/workout/data/firestore_workout_repository.dart';
import '../features/workout/data/firestore_workout_session_repository.dart';
import '../features/workout/data/in_memory_workout_plan_repository.dart';
import '../features/workout/data/in_memory_workout_repository.dart';
import '../features/workout/data/in_memory_workout_session_repository.dart';
import '../features/workout/domain/workout_plan_repository.dart';
import '../features/workout/domain/workout_repository.dart';
import '../features/workout/domain/workout_session_repository.dart';

/// Firestore persistence for a feature is opt-out via `--dart-define
/// USE_FIRESTORE=false` (e.g. for offline/dev runs); it defaults to on.
/// The flag itself lives in [AppEnvironment]; aliased here for the repository
/// wiring below.
const bool _useFirestore = AppEnvironment.useFirestore;

/// The ZIVO application root. Owns shared repositories and exposes them via
/// [AppScope]. [auth] and [profiles] are backed by Firebase Auth/Firestore,
/// and all eight feature repositories (expenses, tasks, schedule, notes,
/// moments, workouts, university, diet) are Firebase-backed. [ai] is
/// Firebase-backed too (Firestore reads + the `aiChat` callable).
///
/// Repositories are injectable (defaulting to the real implementations) so
/// tests can supply fakes — e.g. a pre-authenticated auth repo to exercise the
/// app shell without touching Firebase.
class ZivoApp extends StatefulWidget {
  const ZivoApp({
    this.auth,
    this.profiles,
    this.expenses,
    this.tasks,
    this.schedule,
    this.notes,
    this.moments,
    this.workouts,
    this.workoutPlans,
    this.workoutSessions,
    this.university,
    this.diet,
    this.ai,
    this.media,
    this.mediaPreferences,
    super.key,
  });

  final AuthRepository? auth;
  final ProfileRepository? profiles;
  final ExpenseRepository? expenses;
  final TaskRepository? tasks;
  final ScheduleRepository? schedule;
  final NoteRepository? notes;
  final MomentRepository? moments;
  final WorkoutRepository? workouts;
  final WorkoutPlanRepository? workoutPlans;
  final WorkoutSessionRepository? workoutSessions;
  final UniversityRepository? university;
  final DietRepository? diet;
  final AiRepository? ai;
  final MediaService? media;
  final MediaPreferencesRepository? mediaPreferences;

  @override
  State<ZivoApp> createState() => _ZivoAppState();
}

class _ZivoAppState extends State<ZivoApp> {
  late final AuthRepository _auth = widget.auth ?? FirebaseAuthRepository();
  late final ProfileRepository _profiles =
      widget.profiles ?? FirestoreProfileRepository();
  late final ExpenseRepository _expenses =
      widget.expenses ?? _defaultExpenses();
  late final TaskRepository _tasks = widget.tasks ?? _defaultTasks();
  late final ScheduleRepository _schedule =
      widget.schedule ?? _defaultSchedule();
  late final NoteRepository _notes = widget.notes ?? _defaultNotes();
  late final MomentRepository _moments = widget.moments ?? _defaultMoments();
  late final WorkoutRepository _workouts =
      widget.workouts ?? _defaultWorkouts();
  late final WorkoutPlanRepository _workoutPlans =
      widget.workoutPlans ?? _defaultWorkoutPlans();
  late final WorkoutSessionRepository _workoutSessions =
      widget.workoutSessions ?? _defaultWorkoutSessions();
  late final UniversityRepository _university =
      widget.university ?? _defaultUniversity();
  late final DietRepository _diet = widget.diet ?? _defaultDiet();
  late final AiRepository _ai = widget.ai ?? _defaultAi();

  // Media is local-first: the byte store is always the on-device documents
  // directory, independent of the Firestore flag. Only the *metadata* registry
  // and per-account preferences follow [_useFirestore].
  late final MediaStore _mediaStore = LocalMediaStore();
  late final MediaPreferencesRepository _mediaPreferences =
      widget.mediaPreferences ?? _defaultMediaPreferences();
  late final MediaService _media = widget.media ?? _defaultMedia();

  MediaPreferencesRepository _defaultMediaPreferences() => _useFirestore
      ? FirestoreMediaPreferencesRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryMediaPreferencesRepository();

  MediaRegistry _defaultMediaRegistry() => _useFirestore
      ? FirestoreMediaRegistry(uidSource: UidSource.firebaseAuth())
      : InMemoryMediaRegistry();

  MediaService _defaultMedia() {
    final driveClient = _defaultDriveClient();
    return MediaService(
      store: _mediaStore,
      registry: _defaultMediaRegistry(),
      preferences: _mediaPreferences,
      driveClient: driveClient,
      isUnmetered: _isUnmetered,
      targets: <BackupTargetId, MediaBackupTarget>{
        BackupTargetId.gallery: DeviceGalleryTarget(store: _mediaStore),
        if (driveClient != null)
          BackupTargetId.drive:
              GoogleDriveTarget(client: driveClient, store: _mediaStore),
      },
    );
  }

  /// True when the active connection is unmetered (wifi/ethernet) — gates the
  /// "Wi-Fi only" automatic-backup preference.
  Future<bool> _isUnmetered() async {
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

  /// Real Google Drive backup client when running against the real backend;
  /// null in offline/dev runs (no OAuth), where Drive backup is simply absent.
  DriveBackupClient? _defaultDriveClient() =>
      _useFirestore ? GoogleDriveBackupClient() : null;

  TaskRepository _defaultTasks() => _useFirestore
      ? FirestoreTaskRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryTaskRepository();

  ExpenseRepository _defaultExpenses() => _useFirestore
      ? FirestoreExpenseRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryExpenseRepository();

  ScheduleRepository _defaultSchedule() => _useFirestore
      ? FirestoreScheduleRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryScheduleRepository();

  NoteRepository _defaultNotes() => _useFirestore
      ? FirestoreNoteRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryNoteRepository();

  MomentRepository _defaultMoments() => _useFirestore
      ? FirestoreMomentRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryMomentRepository();

  WorkoutRepository _defaultWorkouts() => _useFirestore
      ? FirestoreWorkoutRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryWorkoutRepository();

  WorkoutPlanRepository _defaultWorkoutPlans() => _useFirestore
      ? FirestoreWorkoutPlanRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryWorkoutPlanRepository();

  WorkoutSessionRepository _defaultWorkoutSessions() => _useFirestore
      ? FirestoreWorkoutSessionRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryWorkoutSessionRepository();

  UniversityRepository _defaultUniversity() => _useFirestore
      ? FirestoreUniversityRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryUniversityRepository();

  DietRepository _defaultDiet() => _useFirestore
      ? FirestoreDietRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryDietRepository();

  AiRepository _defaultAi() => _useFirestore
      ? FirebaseAiRepository(uidSource: UidSource.firebaseAuth())
      : FakeAiRepository();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: _auth,
      profiles: _profiles,
      expenses: _expenses,
      tasks: _tasks,
      schedule: _schedule,
      notes: _notes,
      moments: _moments,
      workouts: _workouts,
      workoutPlans: _workoutPlans,
      workoutSessions: _workoutSessions,
      university: _university,
      diet: _diet,
      ai: _ai,
      media: _media,
      child: MaterialApp(
        title: 'ZIVO',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        // Names the active build configuration in Development/Profile; compiled
        // out of Release so production UX is untouched.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: EnvBanner(child: child ?? const SizedBox.shrink()),
        ),
        home: const AuthGate(),
      ),
    );
  }
}
