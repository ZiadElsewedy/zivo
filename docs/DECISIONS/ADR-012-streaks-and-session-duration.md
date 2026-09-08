# ADR-012 — What a streak means, and why a session's duration is measured rather than capped

**Status:** accepted · 2026-09-08
**Context:** [`lib/features/workout/`](../../lib/features/workout/FEATURE.md) ·
[`docs/WORKOUT_SYSTEM.md`](../WORKOUT_SYSTEM.md) ·
supersedes nothing; extends [ADR-010](ADR-010-sleep-provenance.md)'s posture to training

## Context

Two problems in the workout feature, with one root in common: the app was
reporting numbers it had not measured.

**The streak was two engines that disagreed.** `training_dashboard_stats.dart`
bucketed sessions by `startedAt`; `home/domain/today_pulse.dart` bucketed by
`completedAt ?? startedAt`. A session finishing at 12:20am landed on different
days on the Workout hub and on Today, and the same history produced two
numbers. Both walked the calendar with `Duration(days: 1)` — 24 absolute hours,
which is not a calendar day on the two days a year a zone shifts. Verified in
`Africa/Cairo`: stepping back from `2026-04-25 00:00` lands on
`2026-04-23 23:00`, skipping 24 April entirely and matching nothing in a set
keyed by local midnights. **The day streak zeroed itself twice a year.**

The rule was also the wrong rule: consecutive calendar days with a completed
session, so one missed day reset it to zero. An app built around a coach should
not tell you that resting broke your consistency, and a rest day was not even
representable — `WorkoutPlan` is an order-based rotation, and
`ziad_workout_plan.dart` says outright that rest days are not modelled.

**Session duration was wall-clock time with no floor under it.** `elapsed` was
`completedAt - startedAt - pausedAccum`, `completedAt` was stamped when the last
set resolved, nothing auto-paused on backgrounding, and there was **no way to
end a session early** — Finish existed only once every set was resolved. So the
normal shape of a cut-short workout was: leave it, and it stays `active`
forever, contributing nothing to the streak while hijacking "up next"
indefinitely; or come back the next day, tap the last set, and log a
nineteen-hour session into the average.

Meanwhile a completed session could be freely, permanently deleted from two
places. The state was exactly backwards: you could erase a good session because
you disliked the number, and you could not fix a broken one.

## Decision

**1. One streak engine, and the rule is a gap, not a calendar run.**
`workout/domain/training_streak.dart` is the only implementation; Today
delegates to it. A streak day is a day with at least one **completed working
set** — the same bar `plan_adherence.dart` sets, so warming up and leaving is
not a trained day. The streak survives a gap of up to `kStreakMaxGapDays` (3)
calendar days and breaks only on a longer one. Two sessions in a day are one
day. A partly-logged session counts in full, and counts whether or not Finish
was ever tapped, so forgetting to close a session cannot cost a day that was
genuinely trained.

**2. Calendar arithmetic never uses `Duration`.** `core/util/calendar.dart`
owns day/week stepping and differencing, built on the `DateTime(y, m, d + n)`
constructor and a UTC ordinal. `test/core/calendar_test.dart` discovers the
ambient zone's real DST transitions and asserts across them, so the regression
is caught in any DST zone rather than only in a hard-coded one.

**3. A missed-day reason is context; a restore is the only thing that touches
the number.** Both live on one `TrainingDayMark` per calendar day
(`users/{uid}/trainingDayMarks/{yyyy-MM-dd}`). A reason explains a gap and
changes nothing — a system where typing "travel" repairs your consistency
produces numbers worth nothing. A restore bridges a gap, is rationed (one per
30 days, reaching back at most 7, never today), **adds no trained day to the
count**, and is excluded from the all-time best.

**Restores are a separate collection, not synthetic sessions.** That is the
whole safety argument: a restore stored as a `LiveSession` would have to be
filtered out of roughly fifteen call sites and every one written afterwards.
Kept in its own collection, "a restore is not a workout" is a fact about where
the bytes live rather than a convention someone must remember.

**4. Duration is measured, and the measurement is per-set.** `LoggedSet` now
carries `resolvedAt`, stamped when Done or Skip is tapped and cleared by undo.
The last one in a session is `lastActivityAt` — the last moment there is
evidence anyone was training.

**5. A left-open session is closed at its last logged set. It is never
capped.** `LiveSession.autoClose` ends the session at `lastActivityAt`, so a
workout whose last set landed at 7:14pm gets its real 62 minutes. A capped
duration would be a fabricated number wearing a measured one's clothes, and it
would still land in the average — the exact thing being protected against.
Where there is no evidence to close at, the duration is `unknown` and is
withheld, never guessed. Staleness requires **both** running past the maximum
**and** `kStaleInactivityGrace` (30 min) of silence, so a genuinely long workout
still being logged is never closed under someone mid-set.

**6. The maximum is a user setting, not a constant.** `WorkoutSettings`
(`users/{uid}/settings/workout`), default 3 hours, clamped to 30 min–12 h.
Someone doing 40-minute sessions and someone doing three-hour strongman days do
not share a threshold.

**7. Implausible durations are excluded and flagged, never silently averaged.**
`hasUsableDuration(max)` gates every average and sparkline; the drill-down says
"over 23 of 24" rather than presenting a partial average as a total one. A
correction is an **amendment** — `correctedDurationMinutes` +
`DurationSource`, with `startedAt`/`completedAt` kept exactly as recorded.

**8. Finish Now.** A session can be ended with sets outstanding. Pending sets
stay pending — not done, not skipped, no reps, no load — which every counter
downstream already ignores. Nothing is invented; the only thing written is the
ending.

**9. A session that recorded work is voided, never deleted.**
`SessionStatus.voided` + a `VoidReason`. It keeps its place in History showing
exactly what was lifted, and stops counting everywhere. Hard delete survives
only for a session with nothing logged in it, which is indistinguishable from
one never started. **The asymmetry is the point: obviously-wrong data can be
corrected, but history cannot be curated.**

## Consequences we accepted

- **Two engines' worth of public API changed.** `currentStreakTrainedDays` and
  `bestStreakDays` are gone; `TrainingDashboardStats` exposes a
  `TrainingStreak` instead of a bare int, and its counts/averages now bucket by
  `completedAt ?? startedAt` like everything else in the codebase.
- **`markSetDone`/`markSetSkipped` take a required `now`.** The model still
  never reads the wall clock; the caller supplies it, as everywhere else here.
- **Sessions logged before this have no `resolvedAt`.** They cannot be closed
  at a last set, so a stale one among them closes as `unknown` and is held out
  of the averages until corrected. History is deliberately **not** rewritten at
  upgrade time — inventing timestamps for past sessions would be the same
  mistake in a different place.
- **The backend mirrors the gate.** `functions/ai/tools.js` honours the
  correction and withholds an implausible or unknown duration, because a coach
  quoting a nineteen-hour workout the app is already disowning is worse than
  one that says nothing about duration.
- **Two new collections' worth of rules** (`trainingDayMarks`, plus `voided`
  and the corrected-duration bounds on `workoutSessions`), each with emulator
  tests, per the standing rule.
- **`kStreakMaxGapDays` is a product decision, in one constant.** Moving it
  from 3 changes the rule everywhere, by design.
