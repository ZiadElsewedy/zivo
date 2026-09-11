/// The local, offline copy a **motivational** workout reminder shows instead of
/// the day's exercise list.
///
/// A workout-synced reminder can be flipped to "motivational" (see
/// [WorkoutSync.motivational]): rather than listing what's on the next-up day,
/// the notification names the day and adds one short line of encouragement. That
/// line is drawn from here — plain local data, no network, no backend, in
/// keeping with the whole feature (ADR-013).
///
/// The two lists are **index-aligned** — `kWorkoutMotivationsEn[i]` and
/// `kWorkoutMotivationsAr[i]` say the same thing — so a single seed picks the
/// same idea in whichever language the app is set to.
library;

/// English motivational lines. Short, punchy, and safe under any workout day.
const List<String> kWorkoutMotivationsEn = [
  "Keep going — you've got this.",
  'Show up for yourself today.',
  "Don't skip it. Future you is watching.",
  'One session closer to your goal.',
  'Strong is built one rep at a time.',
  "Don't skip leg day.",
  'Go ahead — make today count.',
  'The only bad workout is the one you skipped.',
  'Progress, not perfection. Just start.',
  "You're one workout away from a better mood.",
  "Discipline beats motivation. Let's move.",
  'Every rep is a promise kept.',
];

/// Arabic motivational lines, index-aligned with [kWorkoutMotivationsEn].
const List<String> kWorkoutMotivationsAr = [
  'واصل، أنت قادر على ذلك.',
  'اليوم من أجلك، لا تتأخر.',
  'لا تتخطَّ التمرين، مستقبلك يراقبك.',
  'خطوة أقرب إلى هدفك.',
  'القوة تُبنى تكرارًا بعد تكرار.',
  'لا تتغيّب عن يوم الأرجل.',
  'تقدّم، اجعل يومك مميزًا.',
  'التمرين الوحيد السيّئ هو الذي فوّتّه.',
  'تقدّم لا كمال، فقط ابدأ.',
  'تمرين واحد يفصلك عن مزاج رائع.',
  'الانضباط يتفوّق على الحماس، هيا بنا.',
  'كل تكرار وعد تحافظ عليه.',
];

/// Picks a motivational line for the given [languageCode] (Arabic when it starts
/// with `ar`, English otherwise).
///
/// Deterministic in [seed]: the same seed always yields the same line, which is
/// what lets the app root pick one phrase per day (see `app.dart`) without the
/// choice churning the notification schedule on every reschedule. The modulo is
/// written to stay in range for a negative seed (a hash code can be negative).
String pickWorkoutMotivation({required int seed, String languageCode = 'en'}) {
  final list = languageCode.startsWith('ar')
      ? kWorkoutMotivationsAr
      : kWorkoutMotivationsEn;
  if (list.isEmpty) return '';
  final index = (seed % list.length + list.length) % list.length;
  return list[index];
}
