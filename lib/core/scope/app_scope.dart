import 'package:flutter/widgets.dart';

import '../l10n/locale_controller.dart';
import '../theme/theme_controller.dart';
import '../media/media_service.dart';
import '../../features/ai/data/audio_recorder.dart';
import '../../features/ai/domain/ai_repository.dart';
import '../../features/auth/data/device_session_guard.dart';
import '../../features/auth/domain/auth_activity_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/profile/domain/profile_repository.dart';
import '../../features/reminders/domain/notification_scheduler.dart';
import '../../features/reminders/domain/reminders_repository.dart';
import '../../features/sleep/domain/sleep_repository.dart';
import '../../features/sleep/domain/sleep_service.dart';
import '../../features/diet/domain/diet_repository.dart';
import '../../features/diet/domain/nutrition/food_resolver.dart';
import '../../features/device/steps/step_counter.dart';
import '../../features/expenses/domain/category_repository.dart';
import '../../features/expenses/domain/expense_repository.dart';
import '../../features/expenses/domain/expenses_service.dart';
import '../../features/expenses/domain/wallet_repository.dart';
import '../../features/moments/domain/moment_repository.dart';
import '../../features/music/domain/music_controller.dart';
import '../../features/workout/domain/body_weight_repository.dart';
import '../../features/workout/domain/session_maintenance.dart';
import '../../features/workout/domain/training_day_mark_repository.dart';
import '../../features/workout/domain/workout_plan_repository.dart';
import '../../features/workout/domain/workout_repository.dart';
import '../../features/workout/domain/workout_session_repository.dart';
import '../../features/workout/domain/workout_settings.dart';
import '../../features/workout/domain/workout_settings_repository.dart';

/// Provides shared repositories to the widget tree. A deliberately tiny
/// seam for now; it will be replaced by a proper DI container (get_it) when
/// the foundation phase lands. Kept above the app's Navigator so pushed
/// routes can resolve it.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.auth,
    this.deviceSession,
    required this.profiles,
    this.activity,
    required this.expenses,
    this.wallet,
    this.expenseCategories,
    required this.moments,
    required this.workouts,
    required this.workoutPlans,
    required this.workoutSessions,
    this.workoutSettings,
    this.trainingDayMarks,
    this.sessionMaintenance,
    this.bodyWeight,
    required this.diet,
    this.foods,
    required this.ai,
    this.recorder,
    this.stepCounter,
    this.sleep,
    this.sleepService,
    this.reminders,
    this.notifications,
    this.media,
    this.music,
    this.locale,
    this.theme,
    required super.child,
    super.key,
  });

  /// The authentication backend. Its signed-in `uid` is the app's canonical
  /// identity (and the future Firestore ownership key).
  final AuthRepository auth;

  /// Enforces one-account-one-active-device: it raises
  /// [DeviceSessionGuard.signedOutElsewhere] when this device was signed out
  /// because the account was claimed on another. Optional so the many widget
  /// tests that never authenticate can omit it; production always wires one.
  /// The login page reads it to explain the forced sign-out.
  final DeviceSessionGuard? deviceSession;

  /// Persists the signed-in user's [UserProfile] (`users/{uid}` in Firestore).
  final ProfileRepository profiles;

  /// Records authentication activity (account metadata + the event log) for
  /// each successful sign-in/out. Optional so widget tests that never touch
  /// auth bookkeeping can omit it; production always provides one.
  final AuthActivityRepository? activity;
  final ExpenseRepository expenses;

  /// The wallet balance, and the user's custom expense categories on top of
  /// the app's built-in set. Optional for the same reason [media] is: many
  /// widget tests build a scope without touching Expenses. Production and
  /// the Expenses-page tests always provide both — read them through
  /// [requireWallet] / [requireCategories], or via [expensesService].
  final WalletRepository? wallet;
  final CategoryRepository? expenseCategories;

  final MomentRepository moments;
  final WorkoutRepository workouts;
  final WorkoutPlanRepository workoutPlans;
  final WorkoutSessionRepository workoutSessions;

  /// The account's training preferences — currently the maximum session
  /// length that decides when a still-running session is one the user forgot
  /// to close.
  ///
  /// Optional for the same reason [bodyWeight] is: the many widget tests that
  /// never reach a duration keep constructing a scope without it. Read it
  /// through [requireWorkoutSettings], or fall back to the defaults.
  final WorkoutSettingsRepository? workoutSettings;

  /// Per-calendar-day training marks: missed-day reasons and spent streak
  /// restores. Optional, same rationale.
  final TrainingDayMarkRepository? trainingDayMarks;

  /// Closes sessions that were left open. Exposed so the live session screen
  /// can register itself as the owner of the session it has open — see
  /// [SessionMaintenance.openSessionId].
  final SessionMaintenance? sessionMaintenance;

  /// Logged bodyweight entries — the Workout Dashboard's weight-over-time
  /// track, independent of any single training session.
  ///
  /// Optional so the many widget tests that don't exercise the dashboard can
  /// keep constructing a scope without it; production and dashboard tests
  /// always provide one. Read it through [requireBodyWeight].
  final BodyWeightRepository? bodyWeight;
  final DietRepository diet;

  /// The nutrition catalog — the ONLY way a calorie or macro figure may enter
  /// ZIVO (see `docs/DIET_COACH_AUDIT.md`). Backed by the bundled USDA subset
  /// in production.
  ///
  /// Optional for the same reason [bodyWeight] is: most widget tests never
  /// touch food lookup, and forcing every scope to parse a 1 MB catalog would
  /// be a real cost for no benefit. Read it through [requireFoods].
  final FoodResolver? foods;

  /// The AI assistant ("Ask") seam. Today's default is a pure in-memory
  /// `FakeAiRepository`; the real Firestore + `aiChat` gateway impl arrives
  /// once the server half is built and deployed.
  final AiRepository ai;

  /// The composer's voice-note recorder — `record`-backed in production.
  ///
  /// Optional so the many widget tests that don't exercise the mic button can
  /// keep constructing a scope without it; production and Ask-page mic tests
  /// always provide one. Read it through [requireRecorder].
  final AudioRecorderService? recorder;

  /// The device step counter (Today's Move ring / activity insight) —
  /// `pedometer`-backed in production on iOS/Android, null on hosts without
  /// a step sensor. Optional for the same reason [recorder] is: tests that
  /// don't exercise the dashboard shouldn't need one.
  final StepCounterService? stepCounter;

  /// Sleep nights + targets. Optional for the same reason [bodyWeight] is:
  /// most widget tests never open Sleep. Read it through [requireSleep].
  final SleepRepository? sleep;

  /// The sleep ingest pipeline (platform read → sessionize → resolve → store)
  /// and manual logging. Paired with [sleep] — production wires both or
  /// neither. Read it through [requireSleepService].
  final SleepService? sleepService;

  /// The account's local reminders (meal/workout/activity notifications the
  /// user set up). Optional for the same reason [workoutSettings] is: the many
  /// widget tests that never open the Reminders page keep constructing a scope
  /// without it. Production always wires one.
  final RemindersRepository? reminders;

  /// The local-notification scheduler behind the reminders feature — the seam
  /// the Reminders page asks to request OS notification permission. Optional
  /// for the same reason [reminders] is; production always wires one (a no-op
  /// off Firestore).
  final NotificationScheduler? notifications;

  /// The sleep repository, asserting it was provided. Use from the Sleep page
  /// and Today's sleep glance — production always wires it.
  SleepRepository get requireSleep {
    assert(sleep != null, 'AppScope.sleep was not provided to this scope');
    return sleep!;
  }

  /// The sleep service, asserting it was provided.
  SleepService get requireSleepService {
    assert(
      sleepService != null,
      'AppScope.sleepService was not provided to this scope',
    );
    return sleepService!;
  }

  /// The composer's voice-note recorder, asserting it was provided. Use from
  /// the Ask page's mic button — production always wires it.
  AudioRecorderService get requireRecorder {
    assert(
      recorder != null,
      'AppScope.recorder was not provided to this scope',
    );
    return recorder!;
  }

  /// The media pipeline: durable local storage of captured photos, per-account
  /// backup fan-out (Photos now, Drive next), read-side resolution, and — via
  /// [MediaService.preferences] — the account's storage choices surfaced in
  /// Settings. Every feature that captures or displays media goes through this
  /// instead of touching files or Firebase Storage directly.
  ///
  /// Optional so the many widget tests that don't exercise media can keep
  /// constructing a scope without it; production and media-page tests always
  /// provide one. Read it through [requireMedia] from media-bearing pages.
  final MediaService? media;

  /// The media pipeline, asserting it was provided. Use from pages that capture
  /// or display media (Moments, Profile, Settings) — production always wires it.
  MediaService get requireMedia {
    assert(media != null, 'AppScope.media was not provided to this scope');
    return media!;
  }

  /// The music/now-playing seam — a `FakeMusicController` by default, a real
  /// `SpotifyMusicController` only once `music_config.dart`'s
  /// `kMusicEnabled`/`spotifyClientId` are set (see `app.dart`). Bound
  /// unconditionally in production, independent of `kMusicEnabled` — that
  /// flag only gates whether the music UI *mounts* (see `home_shell.dart`),
  /// not whether the controller exists.
  ///
  /// Optional for the same reason [media]/[bodyWeight] are: many widget
  /// tests never touch music and shouldn't have to construct a scope with
  /// one. Read it through [requireMusic] from music-bearing widgets.
  final MusicController? music;

  /// The music controller, asserting it was provided. Use from
  /// `NowPlayingLozenge`/`MusicPlayerPage` — production always wires it.
  MusicController get requireMusic {
    assert(music != null, 'AppScope.music was not provided to this scope');
    return music!;
  }

  /// The app language (Arabic · English · match the phone). Optional for the
  /// same reason [media] is: a widget test pumping one page reads its strings
  /// through `l(context)`'s English fallback and never needs a controller.
  /// Production always wires one. Read it through [requireLocale] from the
  /// language picker.
  final LocaleController? locale;

  /// The language controller, asserting it was provided. Use from Settings'
  /// language picker — production always wires it.
  LocaleController get requireLocale {
    assert(locale != null, 'AppScope.locale was not provided to this scope');
    return locale!;
  }

  /// The app skin (dark · light · match the phone). Optional for the same
  /// reason [locale] is: a widget test pumping one page renders on whatever
  /// palette is active and never needs a controller. Production always wires
  /// one. Read it through [requireTheme] from the theme picker.
  final ThemeController? theme;

  /// The theme controller, asserting it was provided. Use from Settings'
  /// theme picker — production always wires it.
  ThemeController get requireTheme {
    assert(theme != null, 'AppScope.theme was not provided to this scope');
    return theme!;
  }

  WalletRepository get requireWallet {
    assert(wallet != null, 'AppScope.wallet was not provided to this scope');
    return wallet!;
  }

  CategoryRepository get requireCategories {
    assert(
      expenseCategories != null,
      'AppScope.expenseCategories was not provided to this scope',
    );
    return expenseCategories!;
  }

  /// The Expenses feature's composed seam (log + wallet + categories). Built
  /// on demand — cheap, since it holds no state of its own.
  ExpensesService get expensesService => ExpensesService(
    expenses: expenses,
    wallet: requireWallet,
    categories: requireCategories,
  );

  /// The bodyweight repository, asserting it was provided. Use from the
  /// Workout Dashboard — production always wires it.
  /// The maximum session length to reason with — the account's own setting
  /// where there is one, the default otherwise.
  ///
  /// Unlike the `require*` getters this never asserts: a screen asking "is
  /// this duration plausible" must always get an answer, and a scope without
  /// the repository (a widget test) should behave like a fresh account rather
  /// than crash.
  Duration get maxSessionDuration =>
      (workoutSettings?.current ?? WorkoutSettings.defaults).maxSessionDuration;

  BodyWeightRepository get requireBodyWeight {
    assert(
      bodyWeight != null,
      'AppScope.bodyWeight was not provided to this scope',
    );
    return bodyWeight!;
  }

  /// The nutrition catalog, asserting it was provided. Any surface that turns
  /// a food into calories goes through this — production always wires it.
  FoodResolver get requireFoods {
    assert(foods != null, 'AppScope.foods was not provided to this scope');
    return foods!;
  }

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  /// The scope if there is one, null otherwise — for a screen that is meant to
  /// render standalone from data it was handed, and reaches for the scope only
  /// to sharpen what it shows (a user threshold, a preference). Such a screen
  /// must degrade to a sensible default rather than assert, or it stops being
  /// standalone. Anything that genuinely needs a repository uses [of].
  static AppScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>();

  /// [maxSessionDuration] read through [maybeOf] — the account's own setting
  /// where there is a scope with one, the default otherwise.
  static Duration maxSessionDurationOf(BuildContext context) =>
      maybeOf(context)?.maxSessionDuration ??
      WorkoutSettings.defaults.maxSessionDuration;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      auth != oldWidget.auth ||
      deviceSession != oldWidget.deviceSession ||
      profiles != oldWidget.profiles ||
      activity != oldWidget.activity ||
      expenses != oldWidget.expenses ||
      wallet != oldWidget.wallet ||
      expenseCategories != oldWidget.expenseCategories ||
      moments != oldWidget.moments ||
      workouts != oldWidget.workouts ||
      workoutPlans != oldWidget.workoutPlans ||
      workoutSessions != oldWidget.workoutSessions ||
      workoutSettings != oldWidget.workoutSettings ||
      trainingDayMarks != oldWidget.trainingDayMarks ||
      sessionMaintenance != oldWidget.sessionMaintenance ||
      bodyWeight != oldWidget.bodyWeight ||
      diet != oldWidget.diet ||
      foods != oldWidget.foods ||
      ai != oldWidget.ai ||
      recorder != oldWidget.recorder ||
      stepCounter != oldWidget.stepCounter ||
      sleep != oldWidget.sleep ||
      sleepService != oldWidget.sleepService ||
      reminders != oldWidget.reminders ||
      notifications != oldWidget.notifications ||
      media != oldWidget.media ||
      music != oldWidget.music ||
      locale != oldWidget.locale ||
      theme != oldWidget.theme;
}
