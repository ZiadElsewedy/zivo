/// The local, offline copy a **motivational** workout reminder shows instead of
/// the day's exercise list.
///
/// A workout-synced reminder can be flipped to "motivational" (see
/// [WorkoutSync.motivational]): rather than listing what's on the next-up day,
/// the notification names the day and adds one short line of encouragement,
/// drawn from here — plain local data, no network, no backend (ADR-013).
///
/// The line comes in three [MotivationTone]s so the nudge matches the user: a
/// kind [MotivationTone.gentle], a blunt [MotivationTone.toughLove], or an
/// energetic [MotivationTone.hype]. Within a tone the English and Arabic lists
/// are **index-aligned** — `_gentleEn[i]` and `_gentleAr[i]` say the same
/// thing — so one seed picks the same idea in whichever language the app is set
/// to. Alignment across tones is not needed.
library;

/// The voice a motivational workout reminder speaks in. A persisted id with no
/// copy of its own (labels live in `presentation/reminder_labels.dart`, the same
/// rule [ReminderKind] follows).
enum MotivationTone {
  gentle,
  toughLove,
  hype;

  /// Decodes a stored tone, falling back to [gentle] for anything missing or
  /// unrecognised — a value written by a newer build must never leave an old
  /// one unable to read its reminders.
  static MotivationTone fromName(Object? raw) {
    for (final tone in MotivationTone.values) {
      if (tone.name == raw) return tone;
    }
    return MotivationTone.gentle;
  }
}

const List<String> _gentleEn = [
  "Keep going — you've got this.",
  'Show up for yourself today.',
  'One session closer to your goal.',
  'A little today beats nothing. Just start.',
  'Be proud you showed up.',
  'Progress, not perfection.',
  'Your future self says thank you.',
  'Small steps still move you forward.',
  "You're stronger than you think.",
  'Every day you show up counts.',
  "Trust the process — it's working.",
  "Rest when you need, but don't quit.",
  "You don't have to be perfect, just present.",
  'One rep at a time.',
  'Your body can do this; your mind just needs to catch up.',
  'Kindness to yourself is part of the plan.',
  "You've come further than you realise.",
  'Today is a gift to your future self.',
  'Just breathe and begin.',
  "You're allowed to be proud of small wins.",
  'Consistency beats intensity.',
  "Showing up is half the battle — and you're here.",
  'Gentle effort still counts.',
  "You're building something that lasts.",
  'Be patient with your progress.',
  'Every step forward matters.',
  "You're doing better than you feel.",
  'A calm mind lifts a strong body.',
  'Give today your honest best.',
  'You planted this goal; keep watering it.',
  'Slow progress is still progress.',
  'You deserve to feel strong.',
  'Take it one breath, one rep, one day.',
  "You showed up — that's what counts.",
];

const List<String> _gentleAr = [
  'واصل، أنت قادر على ذلك.',
  'اليوم من أجلك.',
  'خطوة أقرب إلى هدفك.',
  'القليل اليوم خير من لا شيء، فقط ابدأ.',
  'افخر بأنك حضرت.',
  'تقدّم لا كمال.',
  'مستقبلك يشكرك.',
  'الخطوات الصغيرة تُقدّمك أيضًا.',
  'أنت أقوى مما تظن.',
  'كل يوم تحضر فيه له قيمة.',
  'ثِق بالمسار، فهو يؤتي ثماره.',
  'استرح عند الحاجة، لكن لا تستسلم.',
  'لست مضطرًا للكمال، يكفي أن تحضر.',
  'تكرار واحد في كل مرة.',
  'جسدك قادر، وعقلك سيلحق به.',
  'الرفق بنفسك جزء من الخطة.',
  'قطعت شوطًا أبعد مما تتصوّر.',
  'اليوم هدية لنفسك في المستقبل.',
  'تنفّس فقط وابدأ.',
  'من حقك أن تفخر بالإنجازات الصغيرة.',
  'الاستمرار أهم من الشدّة.',
  'الحضور نصف المعركة، وأنت هنا.',
  'الجهد الهادئ له قيمة أيضًا.',
  'أنت تبني شيئًا يدوم.',
  'كن صبورًا مع تقدّمك.',
  'كل خطوة للأمام لها معنى.',
  'أداؤك أفضل مما تشعر.',
  'العقل الهادئ يرفع جسدًا قويًا.',
  'امنح اليوم أفضل ما لديك بصدق.',
  'أنت زرعت هذا الهدف، فاستمر في سقايته.',
  'التقدّم البطيء يبقى تقدّمًا.',
  'أنت تستحق أن تشعر بالقوة.',
  'خُذها نَفَسًا نَفَسًا، وتكرارًا تكرارًا، ويومًا يومًا.',
  'لقد حضرت، وهذا هو المهم.',
];

const List<String> _toughEn = [
  "Don't skip leg day.",
  'No excuses. Get it done.',
  "The workout won't do itself.",
  "You don't want it if you skip it.",
  'Discipline over motivation. Move.',
  'Comfort builds nothing.',
  'Earn it today.',
  'Stop scrolling. Start lifting.',
  "Nobody's coming to do it for you.",
  "Excuses don't build muscle.",
  'You said you wanted this. Prove it.',
  "Tired isn't a reason. It's an excuse.",
  "Winners train when they don't feel like it.",
  'The couch will still be there after.',
  'Do the work you promised yourself.',
  'Sweat now or regret later.',
  "Your goals don't care about your mood.",
  'Show up or shut up.',
  "Get uncomfortable. That's where it grows.",
  "You've skipped enough. Not today.",
  'Pain is temporary. Quitting lasts.',
  'Stop negotiating with yourself. Go.',
  'Weak is a choice. Choose better.',
  "The gym doesn't care about your excuses.",
  'Talk less. Lift more.',
  "Future you is watching. Don't disappoint.",
  'You know what to do. Do it.',
  'Motivation is for beginners. Move anyway.',
  'Half-effort gets half-results.',
  'Nobody built a body on maybes.',
  'Prove the doubters wrong — starting with yourself.',
  "You're one skipped day from a habit of skipping.",
  'Hard now, easy later.',
  'Quit making it optional.',
];

const List<String> _toughAr = [
  'لا تتغيّب عن يوم الأرجل.',
  'لا أعذار، أنجزها.',
  'التمرين لن يؤدّي نفسه.',
  'إن تخطّيته فأنت لا تريده حقًا.',
  'الانضباط قبل الحماس، تحرّك.',
  'الراحة لا تبني شيئًا.',
  'استحقّه اليوم.',
  'توقّف عن التصفّح وابدأ التمرين.',
  'لن يأتي أحد ليؤدّيه عنك.',
  'الأعذار لا تبني عضلات.',
  'قلت إنك تريد هذا، فأثبته.',
  'التعب ليس سببًا، بل عذرًا.',
  'الناجحون يتمرّنون حتى دون رغبة.',
  'الأريكة ستبقى مكانها بعد التمرين.',
  'نفّذ العمل الذي وعدت به نفسك.',
  'تعرّق الآن أو تندم لاحقًا.',
  'أهدافك لا تكترث لمزاجك.',
  'اِعمل أو اصمت.',
  'اخرج من منطقة راحتك، هناك ينمو التقدّم.',
  'تغيّبت بما يكفي، ليس اليوم.',
  'الألم مؤقت، أما الاستسلام فيدوم.',
  'توقّف عن مجادلة نفسك، انطلق.',
  'الضعف اختيار، فاختر الأفضل.',
  'النادي لا يكترث لأعذارك.',
  'كلامًا أقل، وتمرينًا أكثر.',
  'مستقبلك يراقبك، فلا تخذله.',
  'تعرف ما عليك فعله، فافعله.',
  'الحماس للمبتدئين، تحرّك رغم كل شيء.',
  'نصف الجهد يعطي نصف النتيجة.',
  'لم يبنِ أحد جسدًا بـ«ربما».',
  'أثبت خطأ المشكّكين، بدءًا من نفسك.',
  'يومٌ واحد تتخطّاه يقودك إلى عادة التخطّي.',
  'اِشقَ الآن لترتاح لاحقًا.',
  'توقّف عن جعله خيارًا.',
];

const List<String> _hypeEn = [
  "Let's go — time to train!",
  "Today's the day. Bring it!",
  'Beast mode: on.',
  'Go make it count!',
  'One workout away from a better mood!',
  'Show up and show out!',
  "Every rep counts — let's move!",
  'Crush it today!',
  "Let's get after it!",
  'Time to make gains!',
  'You were built for this!',
  'Light it up today!',
  'Turn it up — full send!',
  "Let's chase greatness!",
  'Energy up, excuses out!',
  "This is your moment — seize it!",
  'Go hard or go home!',
  'Feel that fire? Use it!',
  'Today you level up!',
  'Bring the heat!',
  "Let's make today legendary!",
  "Power through — you're unstoppable!",
  'Rise and grind!',
  "Give it everything you've got!",
  'Champions train today!',
  "Let's break some records!",
  'Full power — no limits!',
  'Own the gym today!',
  'Unleash it!',
  'Make your muscles remember this one!',
  'Big energy, bigger results!',
  "Let's write a new PR today!",
  'Attack the day!',
  'You vs. you — go win!',
];

const List<String> _hypeAr = [
  'هيا بنا، وقت التمرين!',
  'اليوم هو يومك، انطلق!',
  'وضع الوحش: مُفعّل.',
  'اجعل اليوم يستحق!',
  'تمرين واحد يفصلك عن مزاج أفضل!',
  'احضر وتألّق!',
  'كل تكرار مهم، هيا نتحرّك!',
  'حطّم أرقامك اليوم!',
  'هيا ننقضّ عليه!',
  'حان وقت المكاسب!',
  'خُلقت لهذا!',
  'أشعِلها اليوم!',
  'ارفع الإيقاع، بأقصى قوة!',
  'لنطارد العظمة!',
  'الطاقة عالية، والأعذار خارجًا!',
  'هذه لحظتك، اغتنمها!',
  'بكل قوة أو لا شيء!',
  'أتشعر بتلك النار؟ استخدمها!',
  'اليوم ترتقي مستوى!',
  'أطلق حماسك!',
  'لنجعل اليوم أسطوريًا!',
  'تابع بقوة، لا شيء يوقفك!',
  'انهض وثابر!',
  'اِبذل كل ما لديك!',
  'الأبطال يتمرّنون اليوم!',
  'لنحطّم بعض الأرقام!',
  'قوة كاملة، بلا حدود!',
  'تسيّد النادي اليوم!',
  'أطلق العنان!',
  'اجعل عضلاتك تتذكّر هذا التمرين!',
  'طاقة كبيرة، ونتائج أكبر!',
  'لنسجّل رقمًا قياسيًا جديدًا اليوم!',
  'هاجم يومك!',
  'أنت ضد نفسك، فانتصر!',
];

/// The phrase list for a [tone] and [languageCode] (Arabic when it starts with
/// `ar`, English otherwise). Exposed for tests that assert index alignment.
List<String> workoutMotivationsFor(MotivationTone tone, String languageCode) {
  final arabic = languageCode.startsWith('ar');
  return switch (tone) {
    MotivationTone.gentle => arabic ? _gentleAr : _gentleEn,
    MotivationTone.toughLove => arabic ? _toughAr : _toughEn,
    MotivationTone.hype => arabic ? _hypeAr : _hypeEn,
  };
}

/// Picks a motivational line for the given [tone] and [languageCode].
///
/// Deterministic in [seed]: the same seed always yields the same line, which is
/// what lets the app root pick one phrase per day (see `app.dart`) without the
/// choice churning the notification schedule on every reschedule. The modulo is
/// written to stay in range for a negative seed (a hash code can be negative).
String pickWorkoutMotivation({
  required int seed,
  String languageCode = 'en',
  MotivationTone tone = MotivationTone.gentle,
}) {
  final list = workoutMotivationsFor(tone, languageCode);
  if (list.isEmpty) return '';
  final index = (seed % list.length + list.length) % list.length;
  return list[index];
}
