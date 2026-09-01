import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/env/app_environment.dart';
import '../core/firebase/uid_source.dart';
import '../core/l10n/locale_controller.dart';
import '../core/media/data/device_gallery_target.dart';
import '../core/media/data/firestore_media_preferences_repository.dart';
import '../core/media/data/firestore_media_registry.dart';
import '../core/media/data/google_drive_backup_client.dart';
import '../core/media/data/in_memory_media_preferences_repository.dart';
import '../core/media/data/in_memory_media_registry.dart';
import '../core/media/data/local_media_store.dart';
import '../core/media/domain/media_backup_provider.dart';
import '../core/media/domain/media_registry.dart';
import '../core/media/domain/media_storage_preferences.dart';
import '../core/media/domain/media_store.dart';
import '../core/media/media_service.dart';
import '../core/scope/app_scope.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/zivo_scroll_behavior.dart';
import '../l10n/app_localizations.dart';
import '../features/ai/data/audio_recorder.dart';
import '../features/ai/data/fake_ai_repository.dart';
import '../features/ai/data/firebase_ai_repository.dart';
import '../features/ai/domain/ai_repository.dart';
import '../features/auth/data/firebase_auth_repository.dart';
import '../features/auth/data/firestore_auth_activity_repository.dart';
import '../features/auth/data/firestore_profile_repository.dart';
import '../features/auth/data/noop_auth_activity_repository.dart';
import '../features/auth/domain/auth_activity_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/domain/profile_repository.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/diet/data/firestore_diet_repository.dart';
import '../features/diet/data/in_memory_diet_repository.dart';
import '../features/diet/data/bundled_food_database.dart';
import '../features/diet/domain/diet_repository.dart';
import '../features/diet/domain/nutrition/composite_food_resolver.dart';
import '../features/diet/domain/nutrition/food_resolver.dart';
import '../features/device/steps/step_counter.dart';
import '../features/expenses/data/firestore_category_repository.dart';
import '../features/expenses/data/firestore_expense_repository.dart';
import '../features/expenses/data/firestore_wallet_repository.dart';
import '../features/expenses/data/in_memory_category_repository.dart';
import '../features/expenses/data/in_memory_expense_repository.dart';
import '../features/expenses/data/in_memory_wallet_repository.dart';
import '../features/expenses/domain/category_repository.dart';
import '../features/expenses/domain/expense_repository.dart';
import '../features/expenses/domain/wallet_repository.dart';
import '../features/moments/data/firestore_moment_repository.dart';
import '../features/moments/data/in_memory_moment_repository.dart';
import '../features/moments/domain/moment_repository.dart';
import '../features/music/data/fake_music_controller.dart';
import '../features/music/data/spotify_music_controller.dart';
import '../features/music/domain/music_controller.dart';
import '../features/music/music_config.dart';
import '../features/workout/data/dev_analysis_seed.dart';
import '../features/workout/data/firestore_body_weight_repository.dart';
import '../features/workout/data/firestore_workout_plan_repository.dart';
import '../features/workout/data/firestore_workout_repository.dart';
import '../features/workout/data/firestore_workout_session_repository.dart';
import '../features/workout/data/in_memory_body_weight_repository.dart';
import '../features/workout/data/in_memory_workout_plan_repository.dart';
import '../features/workout/data/in_memory_workout_repository.dart';
import '../features/workout/data/in_memory_workout_session_repository.dart';
import '../features/workout/domain/body_weight_repository.dart';
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
/// and the feature repositories (expenses, moments, workouts, diet) are
/// Firebase-backed. [ai] is Firebase-backed too (Firestore reads + the
/// `aiChat` callable).
///
/// Repositories are injectable (defaulting to the real implementations) so
/// tests can supply fakes — e.g. a pre-authenticated auth repo to exercise the
/// app shell without touching Firebase.
class ZivoApp extends StatefulWidget {
  const ZivoApp({
    this.auth,
    this.profiles,
    this.activity,
    this.expenses,
    this.stepCounter,
    this.wallet,
    this.expenseCategories,
    this.moments,
    this.workouts,
    this.workoutPlans,
    this.workoutSessions,
    this.bodyWeight,
    this.diet,
    this.foods,
    this.ai,
    this.recorder,
    this.media,
    this.mediaPreferences,
    this.music,
    this.locale,
    super.key,
  });

  final AuthRepository? auth;
  final ProfileRepository? profiles;
  final AuthActivityRepository? activity;
  final ExpenseRepository? expenses;
  final WalletRepository? wallet;
  final CategoryRepository? expenseCategories;
  final MomentRepository? moments;
  final WorkoutRepository? workouts;
  final WorkoutPlanRepository? workoutPlans;
  final WorkoutSessionRepository? workoutSessions;
  final BodyWeightRepository? bodyWeight;
  final DietRepository? diet;

  /// Overridable so tests can inject a stub catalog instead of parsing the
  /// real 1 MB asset.
  final FoodResolver? foods;
  final AiRepository? ai;
  final AudioRecorderService? recorder;
  final StepCounterService? stepCounter;
  final MediaService? media;
  final MediaPreferencesRepository? mediaPreferences;
  final MusicController? music;

  /// Overridable so a test can pin the app to a locale instead of the
  /// device's.
  final LocaleController? locale;

  @override
  State<ZivoApp> createState() => _ZivoAppState();
}

class _ZivoAppState extends State<ZivoApp> {
  late final AuthRepository _auth =
      widget.auth ?? FirebaseAuthRepository(activityRepository: _activity);
  late final ProfileRepository _profiles =
      widget.profiles ?? FirestoreProfileRepository();
  // Auth bookkeeping (account metadata + event log) follows the Firestore
  // flag: a real recorder against the live backend, a silent no-op offline.
  late final AuthActivityRepository _activity = widget.activity ??
      (_useFirestore
          ? FirestoreAuthActivityRepository()
          : const NoopAuthActivityRepository());
  late final ExpenseRepository _expenses =
      widget.expenses ?? _defaultExpenses();
  late final WalletRepository _wallet = widget.wallet ?? _defaultWallet();
  late final CategoryRepository _categories =
      widget.expenseCategories ?? _defaultCategories();
  late final MomentRepository _moments = widget.moments ?? _defaultMoments();
  late final WorkoutRepository _workouts =
      widget.workouts ?? _defaultWorkouts();
  late final WorkoutPlanRepository _workoutPlans =
      widget.workoutPlans ?? _defaultWorkoutPlans();
  late final WorkoutSessionRepository _workoutSessions =
      widget.workoutSessions ?? _defaultWorkoutSessions();
  late final BodyWeightRepository _bodyWeight =
      widget.bodyWeight ?? _defaultBodyWeight();
  late final DietRepository _diet = widget.diet ?? _defaultDiet();

  /// The nutrition catalog: the user's own foods layered over the bundled USDA
  /// reference set, so a food they defined always beats a loose USDA match.
  ///
  /// Constructed eagerly but LOADED lazily — the bundled asset is ~1 MB and is
  /// only parsed the first time something actually looks a food up, so a
  /// session that never opens food search never pays for it.
  late final FoodResolver _foods =
      widget.foods ??
      CompositeFoodResolver(
        catalog: BundledFoodDatabase(),
        customFoods: () => _diet.listCustomFoods(),
      );
  late final AiRepository _ai = widget.ai ?? _defaultAi();
  late final AudioRecorderService _recorder =
      widget.recorder ?? RecordAudioRecorderService();

  /// The device step counter — only where a step sensor exists (iOS /
  /// Android). Desktop and web hosts get null and Today simply hides its
  /// Move ring; no error, no dead UI.
  late final StepCounterService? _stepCounter =
      widget.stepCounter ??
      (deviceHasStepSensor ? PedometerStepCounterService() : null);

  // Media is local-first: the byte store is always the on-device documents
  // directory, independent of the Firestore flag. Only the *metadata* registry
  // and per-account preferences follow [_useFirestore].
  late final MediaStore _mediaStore = LocalMediaStore();
  late final MediaPreferencesRepository _mediaPreferences =
      widget.mediaPreferences ?? _defaultMediaPreferences();
  late final MediaService _media = widget.media ?? _defaultMedia();

  // Always bound, independent of `kMusicEnabled` — that flag only gates the
  // UI's mounting (see `home_shell.dart`); the controller itself is cheap
  // to construct and harmless to leave running unused.
  late final MusicController _music = widget.music ?? _defaultMusic();

  /// The app language. Constructed on "match the phone" and then asked to
  /// restore the stored choice in [initState] — reading preferences is async,
  /// and blocking first paint on it would trade a correct first frame for a
  /// blank one.
  late final LocaleController _locale = widget.locale ?? LocaleController();

  /// Watches the signed-in account and clears the device-local backup
  /// connection when it changes away from a signed-in account (sign-out or
  /// account switch), so account A's backup connection can never leak into
  /// account B. The initial session restore (prev == null) is deliberately not
  /// treated as a change, so a valid connection survives app launch.
  StreamSubscription<AuthState>? _authSub;
  String? _prevUid;

  @override
  void initState() {
    super.initState();
    if (widget.locale == null) _locale.load();
    _authSub = _auth.watchAuthState().listen((_) {
      final uid = _auth.currentUser?.uid;
      if (_prevUid != null && _prevUid != uid) {
        _media.disconnectBackup();
      }
      _prevUid = uid;
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    // Only when we own it (the default) — a caller-supplied controller
    // (a test passing its own fake) stays theirs to dispose.
    if (widget.music == null) _music.dispose();
    if (widget.locale == null) _locale.dispose();
    super.dispose();
  }

  MediaPreferencesRepository _defaultMediaPreferences() => _useFirestore
      ? FirestoreMediaPreferencesRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryMediaPreferencesRepository();

  MediaRegistry _defaultMediaRegistry() => _useFirestore
      ? FirestoreMediaRegistry(uidSource: UidSource.firebaseAuth())
      : InMemoryMediaRegistry();

  MediaService _defaultMedia() => MediaService(
    store: _mediaStore,
    registry: _defaultMediaRegistry(),
    preferences: _mediaPreferences,
    galleryTarget: DeviceGalleryTarget(store: _mediaStore),
    backup: _defaultBackupProvider(),
    currentAccountId: () => _auth.currentUser?.uid,
  );

  /// Real Google Drive backup provider when running against the real backend;
  /// null in offline/dev runs (no OAuth), where cloud backup is simply absent.
  /// Swapping providers is a one-line change here — nothing else moves.
  MediaBackupProvider? _defaultBackupProvider() =>
      _useFirestore ? GoogleDriveBackupClient() : null;

  ExpenseRepository _defaultExpenses() => _useFirestore
      ? FirestoreExpenseRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryExpenseRepository();

  WalletRepository _defaultWallet() => _useFirestore
      ? FirestoreWalletRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryWalletRepository();

  CategoryRepository _defaultCategories() => _useFirestore
      ? FirestoreCategoryRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryCategoryRepository();

  MomentRepository _defaultMoments() => _useFirestore
      ? FirestoreMomentRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryMomentRepository();

  WorkoutRepository _defaultWorkouts() => _useFirestore
      ? FirestoreWorkoutRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryWorkoutRepository();

  WorkoutPlanRepository _defaultWorkoutPlans() => _useFirestore
      ? FirestoreWorkoutPlanRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryWorkoutPlanRepository();

  // Dev-only: seeds a few completed sessions for the active plan's first day
  // so the Analysis page (Phase 2) has real week-over-week data on an
  // in-memory/offline run. Never reaches Firestore-backed (real user) data.
  WorkoutSessionRepository _defaultWorkoutSessions() => _useFirestore
      ? FirestoreWorkoutSessionRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryWorkoutSessionRepository(
          seed: _workoutPlans.activePlan == null
              ? const []
              : devAnalysisSeedSessions(_workoutPlans.activePlan!),
        );

  BodyWeightRepository _defaultBodyWeight() => _useFirestore
      ? FirestoreBodyWeightRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryBodyWeightRepository();

  DietRepository _defaultDiet() => _useFirestore
      ? FirestoreDietRepository(uidSource: UidSource.firebaseAuth())
      : InMemoryDietRepository();

  AiRepository _defaultAi() => _useFirestore
      ? FirebaseAiRepository(uidSource: UidSource.firebaseAuth())
      : FakeAiRepository();

  MusicController _defaultMusic() =>
      (kMusicEnabled && spotifyClientId.isNotEmpty)
      ? SpotifyMusicController()
      : FakeMusicController();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: _auth,
      profiles: _profiles,
      activity: _activity,
      expenses: _expenses,
      wallet: _wallet,
      expenseCategories: _categories,
      moments: _moments,
      workouts: _workouts,
      workoutPlans: _workoutPlans,
      workoutSessions: _workoutSessions,
      bodyWeight: _bodyWeight,
      diet: _diet,
      foods: _foods,
      ai: _ai,
      recorder: _recorder,
      stepCounter: _stepCounter,
      media: _media,
      music: _music,
      locale: _locale,
      // Rebuilds the whole MaterialApp on a language change, which is what
      // swaps both the strings and the text direction: `locale: null` means
      // "resolve against the device", so RTL follows from the locale itself
      // rather than from anything the screens do.
      child: ValueListenableBuilder<Locale?>(
        valueListenable: _locale.locale,
        builder: (context, locale, _) => MaterialApp(
          title: 'ZIVO',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const ZivoScrollBehavior(),
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const AuthGate(),
        ),
      ),
    );
  }
}
