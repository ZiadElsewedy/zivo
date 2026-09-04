import 'dart:io';

import 'package:flutter/material.dart';
import 'package:zivo/l10n/l10n.dart';
import 'package:zivo/core/media/data/in_memory_media_preferences_repository.dart';
import 'package:zivo/core/media/data/in_memory_media_registry.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/media_service.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_repository.dart';
import 'package:zivo/features/profile/domain/profile_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/moments/domain/moment_repository.dart';
import 'package:zivo/features/music/domain/music_controller.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import 'fake_auth_repository.dart';
import 'fake_profile_repository.dart';
import 'inert_music_controller.dart';

/// Wraps [child] in an [AppScope] (fake auth + fresh in-memory repos) and a
/// [MaterialApp], for widget tests that need the full DI seam.
/// An in-memory [MediaService] backed by a throwaway temp directory, so media
/// pages render in tests without the `path_provider` platform channel.
MediaService testMediaService() {
  final root = Directory.systemTemp.createTempSync('zivo_media_test');
  return MediaService(
    store: LocalMediaStore(rootOverride: root),
    registry: InMemoryMediaRegistry(),
    preferences: InMemoryMediaPreferencesRepository(),
  );
}

/// Pass [locale] to install the real localization delegates and render the
/// page in that language. Left null (the default), the [MaterialApp] carries no
/// delegates and `l(context)` falls back to English — which is what the ~120
/// existing widget tests rely on, so they are unaffected.
Widget wrapWithScope(
  Widget child, {
  AuthRepository? auth,
  ProfileRepository? profiles,
  MediaService? media,
  MusicController? music,
  MomentRepository? moments,
  Locale? locale,
}) {
  return AppScope(
    media: media ?? testMediaService(),
    auth: auth ?? FakeAuthRepository(),
    profiles: profiles ?? FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    moments: moments ?? InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    music: music ?? InertMusicController(),
    child: locale == null
        ? MaterialApp(home: child)
        : MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: child,
          ),
  );
}
