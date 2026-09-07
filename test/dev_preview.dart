// THROWAWAY preview entrypoint — for a UI/UX visual walkthrough only.
// Boots ZIVO straight into the signed-in shell with fake auth + a complete
// profile and in-memory (empty) feature data, so we can see the real
// first-run Today / Hub / Ask / You without a backend or credentials.
//
// Run with:
//   flutter run -t test/dev_preview.dart --dart-define=USE_FIRESTORE=false -d <sim>
//
// Delete when the walkthrough is done. Not part of the app or the test suite.
import 'package:flutter/material.dart';
import 'package:zivo/app/app.dart';
import 'package:zivo/features/sleep/data/health_sleep_source.dart';
import 'package:zivo/features/sleep/data/in_memory_sleep_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/music/data/fake_music_controller.dart';

import 'package:zivo/features/sleep/domain/sleep_night.dart';
import 'package:zivo/features/sleep/domain/sleep_provenance.dart';
import 'package:zivo/features/sleep/domain/sleep_session.dart';
import 'package:zivo/features/sleep/domain/sleep_targets.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';

void main() {
  const user = AuthUser(
    uid: 'fake-uid',
    email: 'you@zivo.app',
    displayName: 'Ziad',
    isEmailVerified: true,
    providerIds: <String>['google.com'],
  );
  final auth = FakeAuthRepository(initial: const Authenticated(user));
  // Force the fake music player in the preview: the real spotifyClientId is
  // present, so _defaultMusic() would otherwise pick SpotifyMusicController,
  // which can't connect in the simulator (no Spotify app).
  runApp(ZivoApp(
    // Sleep, like every other repository here, is injected rather than
    // left to ZivoApp's default — which is Firestore-backed and resolves
    // the signed-in uid through FirebaseAuth at construction, so booting
    // the real app root without it reaches Firebase in a test that has
    // none.
    sleep: _previewSleep(),
    sleepSource: HealthSleepSource(),
    auth: auth,
    profiles: FakeProfileRepository(),
    music: FakeMusicController(),
  ));
}

/// PREVIEW DATA — fabricated, reachable only from this throwaway entrypoint.
InMemorySleepRepository _previewSleep() {
  final repo = InMemorySleepRepository();
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);

  SleepSession s({
    required int daysAgo,
    required int bedHour,
    required int bedMinute,
    required int wakeHour,
    required int wakeMinute,
    required SleepMethod method,
    required String provider,
    bool staged = false,
  }) {
    final wake = DateTime(day.year, day.month, day.day - daysAgo,
        wakeHour, wakeMinute);
    final bed = DateTime(
        day.year, day.month, day.day - daysAgo - (bedHour >= 12 ? 1 : 0),
        bedHour, bedMinute);
    final off = bed.timeZoneOffset.inMinutes;
    return SleepSession(
      id: 'preview-$daysAgo',
      startAt: bed.toUtc(),
      endAt: wake.toUtc(),
      startOffsetMinutes: off,
      endOffsetMinutes: off,
      inBedStartAt:
          staged ? bed.subtract(const Duration(minutes: 22)).toUtc() : null,
      inBedEndAt: staged ? wake.toUtc() : null,
      stages: staged
          ? [
              SleepStageSegment(startAt: bed.toUtc(),
                  endAt: bed.add(const Duration(hours: 2)).toUtc(),
                  stage: SleepStage.light),
              SleepStageSegment(
                  startAt: bed.add(const Duration(hours: 2)).toUtc(),
                  endAt: bed.add(const Duration(hours: 3, minutes: 20)).toUtc(),
                  stage: SleepStage.deep),
            ]
          : const [],
      provenance: SleepProvenance(
        method: method,
        providerId: method == SleepMethod.userReported
            ? SleepProvenance.manualProviderId
            : 'com.apple.health',
        providerName: provider,
        deviceKind: method == SleepMethod.measuredWearable
            ? SleepDeviceKind.watch
            : SleepDeviceKind.unknown,
        recordingMethod: method == SleepMethod.userReported
            ? SleepRecordingMethod.manual
            : SleepRecordingMethod.automatic,
        confidence: confidenceFor(method: method, hasStages: staged,
            completeness: 1, sourceCount: 1),
        completeness: 1,
        rawRefs: const [],
        ingestedAt: DateTime.now(),
      ),
    );
  }

  SleepNight n(int daysAgo, SleepSession? main) => SleepNight(
    sleepDay: DateTime(day.year, day.month, day.day - daysAgo),
    main: main,
    resolution:
        main == null ? SleepResolution.none : SleepResolution.soleSource,
    targets: SleepTargets.defaults,
  );

  repo.upsertNights([
    n(0, s(daysAgo: 0, bedHour: 23, bedMinute: 47, wakeHour: 6, wakeMinute: 59,
        method: SleepMethod.measuredWearable, provider: 'Apple Watch',
        staged: true)),
    n(1, s(daysAgo: 1, bedHour: 0, bedMinute: 34, wakeHour: 7, wakeMinute: 12,
        method: SleepMethod.measuredWearable, provider: 'Apple Watch',
        staged: true)),
    n(2, s(daysAgo: 2, bedHour: 23, bedMinute: 10, wakeHour: 6, wakeMinute: 40,
        method: SleepMethod.platformDerived, provider: 'Pillow')),
    n(3, null),
    n(4, s(daysAgo: 4, bedHour: 1, bedMinute: 5, wakeHour: 8, wakeMinute: 20,
        method: SleepMethod.userReported, provider: 'You')),
    n(5, s(daysAgo: 5, bedHour: 22, bedMinute: 50, wakeHour: 6, wakeMinute: 30,
        method: SleepMethod.measuredWearable, provider: 'Apple Watch',
        staged: true)),
    n(6, null),
  ]);
  repo.saveTargets(SleepTargets.defaults);
  return repo;
}
