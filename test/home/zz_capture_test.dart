import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/theme/zivo_palette.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/home/presentation/pages/today_page.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/inert_music_controller.dart';

void main() {
  testWidgets('capture pull', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    Future<void> load(String family, String path) async {
      final bytes = File(path).readAsBytesSync();
      await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
    }
    for (final w in ['regular', '100', '200', '300', '500', '600', '700', '800', '900']) {
      await load('AzeretMono_$w', '/System/Library/Fonts/SFNSMono.ttf');
      await load('Manrope_$w', '/System/Library/Fonts/SFNS.ttf');
    }
    final prior = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed') || m.contains('font') || m.contains('Plugin')) return;
      prior?.call(d);
    };
    addTearDown(() => FlutterError.onError = prior);
    tester.view.physicalSize = const Size(780, 1000);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 118);
    addTearDown(tester.view.reset);
    ZivoTheme.use(Brightness.dark);
    await tester.pumpWidget(AppScope(
      auth: FakeAuthRepository(initial: const Authenticated(AuthUser(uid: 'test-uid'))),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      diet: InMemoryDietRepository(),
      ai: FakeAiRepository(),
      music: InertMusicController(),
      child: const MaterialApp(home: Scaffold(body: TodayPage())),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byType(TodayPage), matchesGoldenFile('_cap/rest.png'));
    final g = await tester.startGesture(const Offset(200, 200));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await expectLater(find.byType(TodayPage), matchesGoldenFile('_cap/drag.png'));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await expectLater(find.byType(TodayPage), matchesGoldenFile('_cap/refresh.png'));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byType(TodayPage), matchesGoldenFile('_cap/after.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
