# device — feature map

> Thin platform-sensor layer. Today: a pedometer step counter feeding Today's Move ring.

## Start here

- `steps/step_counter.dart` — `StepCounterService` (interface) + `PedometerStepCounterService`
  (real, via the `pedometer` dep) + the `deviceHasStepSensor` capability check.

## Wiring

- Injected in [`app.dart`](../../app/app.dart): a real service **only where a step sensor
  exists** (iOS/Android); desktop/web get `null`. Exposed as `AppScope.stepCounter` (nullable).
- Consumed by Today's Move ring, which simply hides when the service is null — no error, no
  dead UI.

## Gotchas

- Keep device/sensor code behind an interface here so tests and unsupported hosts get a
  null/fake rather than a hard platform dependency.
- Owns its own OS permission prompt (motion/activity).
