/// Where a sleep number came from, and how much of it we are entitled to
/// claim. The whole feature hangs off this file.
///
/// ZIVO's rule for sleep is that a number we cannot source is a number we do
/// not show (`docs/SLEEP_SYSTEM.md` §1). That is only enforceable if every
/// session carries, from the moment it is ingested, an honest record of *how
/// it was produced*. Guessing later is not possible: by the time a session
/// reaches a widget, an Apple Watch measurement and a time somebody typed into
/// the Health app by hand look identical.
///
/// Two axes, deliberately kept apart:
///
/// * [SleepMethod] — **how** the value was produced. Objective, read from
///   platform metadata at ingest, never recomputed.
/// * [SleepConfidence] — **how much we trust this particular record**, a
///   deterministic function of method + coverage + stage richness.
///
/// A wearable night with 40% sample coverage is `measuredWearable` *and*
/// `low`. Collapsing the two into one field would force a lie either way.
library;

/// How a sleep record was produced, ordered best-first. The index **is** the
/// priority used by the resolver, so the declaration order is load-bearing.
///
/// Persisted by `name` into Firestore, so this is an **id**: it carries no
/// copy. Reader-facing wording lives in
/// `presentation/sleep_labels.dart` (the `domain/` enum → `presentation/`
/// labels split every ZIVO feature follows).
enum SleepMethod {
  /// A body-worn sensor: Apple Watch, Galaxy Watch, Oura, Whoop, a band.
  /// Accelerometer + PPG on skin — the best signal a consumer device gives.
  measuredWearable,

  /// A real sensor that is not worn: an under-mattress mat (Eight Sleep,
  /// Withings), or a sonar/microphone app. Genuine measurement, weaker at
  /// staging than something on the wrist.
  measuredNearable,

  /// A genuine platform record we could not attribute to a sensor class —
  /// unknown writing app, no device metadata, `asleepUnspecified` only.
  /// Real data of unknown fidelity, which is exactly what this tier says.
  platformDerived,

  /// The user told us: ZIVO's own "I'm going to sleep" / "I'm awake" marks, an
  /// edit to a night, **or** a platform record flagged as hand-entered.
  ///
  /// That last clause is the one that matters. A typed entry synced through
  /// Apple Health is still typed — the transport is not the method — and
  /// ranking by provider instead of method would quietly promote somebody's
  /// rough guess above their own honest tap in ZIVO.
  userReported,

  /// An inference from device behaviour: an Android Sleep API segment, or
  /// anything ZIVO estimates itself. Never a measurement, however confident
  /// the underlying algorithm sounds.
  deviceEstimated;

  /// Whether a sensor — rather than a person or an algorithm — produced this.
  /// Drives the verb the UI is allowed to use (`sleep_labels.dart`).
  bool get isMeasured =>
      this == SleepMethod.measuredWearable ||
      this == SleepMethod.measuredNearable;

  /// Whether times from this method may be shown to the minute.
  ///
  /// An estimate rendered as "1:47 AM" is false precision even when the
  /// sentence around it hedges: the minute digit asserts a resolution the
  /// method does not have. Estimates round to the quarter hour instead.
  bool get supportsExactMinute => this != SleepMethod.deviceEstimated;
}

/// How much we trust one specific record. Derived by [confidenceFor] — never
/// set by hand at a call site, because a confidence somebody typed is just
/// another unsourced number.
enum SleepConfidence { high, medium, low }

/// What kind of hardware produced a record. Used for tiering (a watch beats a
/// phone) and for the source chip's wording.
///
/// Persisted by `name`; an id, not copy.
enum SleepDeviceKind { watch, ring, band, phone, mat, unknown }

/// The platform's own "was this measured or typed" flag, preserved verbatim.
///
/// Android hands this to us as `Metadata.recordingMethod` and it is
/// authoritative. iOS has no equivalent field; the closest is the optional
/// `HKMetadataKeyWasUserEntered`, which maps to [manual] when present and
/// leaves [unknown] when absent. Kept raw and separate from [SleepMethod] so a
/// later change to our tiering rules can be re-derived from what the platform
/// actually said, rather than from what we concluded at the time.
enum SleepRecordingMethod { automatic, active, manual, unknown }

/// The full provenance of one [SleepSession].
class SleepProvenance {
  const SleepProvenance({
    required this.method,
    required this.providerId,
    required this.providerName,
    required this.deviceKind,
    required this.recordingMethod,
    required this.confidence,
    required this.completeness,
    required this.rawRefs,
    required this.ingestedAt,
  });

  /// How it was produced. Set at ingest; never revised by presentation.
  final SleepMethod method;

  /// The writing app's stable id — an iOS bundle identifier, an Android
  /// package name, or `zivo.manual` for ZIVO's own marks.
  final String providerId;

  /// The writing app's display name as the platform gave it ("Apple Health",
  /// "Oura"), or the localized "You" for ZIVO's own marks. Text we did not
  /// write, so presentation isolates it for bidi.
  final String providerName;

  final SleepDeviceKind deviceKind;

  /// The platform's raw flag, kept for re-derivation. See
  /// [SleepRecordingMethod].
  final SleepRecordingMethod recordingMethod;

  /// Deterministic — see [confidenceFor].
  final SleepConfidence confidence;

  /// Share of `[startAt, endAt]` actually backed by samples, `0..1`.
  ///
  /// This is what stops a sparse cloud of samples from presenting as a fully
  /// measured night: half-hour samples every seventy-five minutes stitch into
  /// one five-and-a-half-hour session, under half of which is actually backed
  /// by a sample. Android sessions arrive as one span and are complete by
  /// construction; iOS sessions are stitched from fragments and frequently
  /// are not.
  final double completeness;

  /// Upstream record ids (HealthKit uuids, Health Connect record ids) that
  /// went into this session. The dedup key on re-sync and the join key when a
  /// record is deleted upstream and has to be withdrawn here.
  final List<String> rawRefs;

  final DateTime ingestedAt;

  /// ZIVO's own manual mark — always [SleepMethod.userReported], never
  /// dressed up as anything else.
  factory SleepProvenance.manual({
    required DateTime ingestedAt,
    required String providerName,
    List<String> rawRefs = const [],
  }) => SleepProvenance(
    method: SleepMethod.userReported,
    providerId: manualProviderId,
    providerName: providerName,
    deviceKind: SleepDeviceKind.phone,
    recordingMethod: SleepRecordingMethod.manual,
    confidence: SleepConfidence.low,
    completeness: 1,
    rawRefs: rawRefs,
    ingestedAt: ingestedAt,
  );

  /// The [providerId] ZIVO writes on its own manual entries.
  static const String manualProviderId = 'zivo.manual';

  SleepProvenance copyWith({
    SleepMethod? method,
    SleepConfidence? confidence,
    double? completeness,
    List<String>? rawRefs,
  }) => SleepProvenance(
    method: method ?? this.method,
    providerId: providerId,
    providerName: providerName,
    deviceKind: deviceKind,
    recordingMethod: recordingMethod,
    confidence: confidence ?? this.confidence,
    completeness: completeness ?? this.completeness,
    rawRefs: rawRefs ?? this.rawRefs,
    ingestedAt: ingestedAt,
  );
}

/// The confidence rules, in one place, as pure arithmetic.
///
/// ```
/// high   : measuredWearable ∧ has stages ∧ completeness ≥ .90 ∧ one source
/// medium : measuredWearable without stages, or measuredNearable,
///          or platformDerived with completeness ≥ .80
/// low    : userReported, deviceEstimated, or completeness < .80
/// ```
///
/// Deliberately a free function rather than a method on [SleepProvenance]:
/// confidence is computed *while* provenance is being assembled, from facts
/// (stage presence, source count) that live on the session rather than on the
/// provenance itself.
SleepConfidence confidenceFor({
  required SleepMethod method,
  required bool hasStages,
  required double completeness,
  required int sourceCount,
}) {
  if (method == SleepMethod.userReported ||
      method == SleepMethod.deviceEstimated) {
    return SleepConfidence.low;
  }
  if (completeness < 0.80) return SleepConfidence.low;
  if (method == SleepMethod.measuredWearable &&
      hasStages &&
      completeness >= 0.90 &&
      sourceCount == 1) {
    return SleepConfidence.high;
  }
  return SleepConfidence.medium;
}

/// Apps known to write sleep from a **worn** sensor. Matched as a prefix so
/// `com.ouraring.oura.watchapp` resolves like `com.ouraring.oura`.
///
/// This table only ever *promotes* a record whose device metadata is missing,
/// and only after [SleepRecordingMethod.manual] has been ruled out — so a
/// hand-typed Oura entry still lands in [SleepMethod.userReported] where it
/// belongs. Unlisted apps are not demoted; they fall to
/// [SleepMethod.platformDerived], which is the honest tier for "real record,
/// unknown sensor".
const List<String> kWearableProviderPrefixes = [
  'com.ouraring.oura',
  'com.whoop.',
  'com.fitbit.',
  'com.garmin.connect',
  'com.withings.',
  'com.polar.',
  'com.samsung.android.app.shealth',
  'com.sec.android.app.shealth',
  'com.ultrahuman.',
];

/// Apps known to measure sleep with a real sensor that is **not worn** — an
/// under-mattress mat, or sonar/microphone sensing from the nightstand.
const List<String> kNearableProviderPrefixes = [
  'com.eightsleep.',
  'com.withings.sleep',
  'com.northcube.sleepcycle',
  'se.northcube.sleepcycle',
  'com.sleepscore.',
];

/// Apple's own Health app. Sleep reaching us under this id came from an Apple
/// Watch, another app that wrote into Health, or a person typing — the id
/// alone cannot tell us which, which is why [SleepRecordingMethod] and the
/// device metadata decide and this constant is only ever a naming fallback.
const String kAppleHealthProviderId = 'com.apple.health';

/// [SleepMethod] for one record, from platform metadata alone.
///
/// The order of the checks is the whole point (`docs/SLEEP_SYSTEM.md` §8).
/// **Manual is tested first**, before any device or provider signal, because a
/// typed entry synced out of Apple Health arrives carrying an Apple Watch's
/// device metadata and would otherwise be promoted to a measurement. Tier 4
/// routinely turns up dressed as tier 1, and this is the twenty lines that
/// stop it.
SleepMethod methodFor({
  required String providerId,
  required SleepDeviceKind deviceKind,
  required SleepRecordingMethod recordingMethod,
}) {
  if (recordingMethod == SleepRecordingMethod.manual) {
    return SleepMethod.userReported;
  }
  if (providerId == SleepProvenance.manualProviderId) {
    return SleepMethod.userReported;
  }

  switch (deviceKind) {
    case SleepDeviceKind.watch:
    case SleepDeviceKind.ring:
    case SleepDeviceKind.band:
      return SleepMethod.measuredWearable;
    case SleepDeviceKind.mat:
      return SleepMethod.measuredNearable;
    case SleepDeviceKind.phone:
    case SleepDeviceKind.unknown:
      break;
  }

  final id = providerId.toLowerCase();
  if (kWearableProviderPrefixes.any(id.startsWith)) {
    return SleepMethod.measuredWearable;
  }
  if (kNearableProviderPrefixes.any(id.startsWith)) {
    return SleepMethod.measuredNearable;
  }

  // A real record from an unidentified writer. Not demoted to an estimate —
  // it *is* platform data — but not credited to a sensor class we cannot see.
  return SleepMethod.platformDerived;
}
