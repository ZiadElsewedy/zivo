/// The hourly line under Today's greeting — a short push, in the voice of a
/// training partner rather than a poster.
///
/// Changes on the hour, and every device shows the same line in the same
/// hour. Walking the list with a stride of 7 (coprime with its 24 entries)
/// makes consecutive hours jump around rather than read top to bottom, while
/// still showing all 24 before any repeats — so a day never sees the same
/// line twice.
String motivationFor(DateTime now, String languageCode) {
  final lines = languageCode == 'ar' ? _ar : _en;
  final hour =
      DateTime(now.year, now.month, now.day, now.hour).millisecondsSinceEpoch ~/
      Duration.millisecondsPerHour;
  return lines[(hour * 7) % lines.length];
}

/// When the line next changes: the top of the next hour.
DateTime nextMotivationChange(DateTime now) => DateTime(
  now.year,
  now.month,
  now.day,
  now.hour,
).add(const Duration(hours: 1));

// Both lists must stay at 24 entries — the stride above relies on it.
const _en = [
  'Light weight. Heavy intent.',
  'Nobody is coming. Go get it.',
  'Earn the rest day.',
  'Discipline outlasts motivation.',
  'Show up on the off days too.',
  "The bar doesn't care how you feel.",
  'One more rep is how it gets built.',
  'Tired is a feeling, not a fact.',
  'You vs. yesterday. Win it.',
  'Small plates add up.',
  'Hard now, easy later.',
  'Chase the feeling after the last set.',
  'Consistency is the cheat code.',
  'Make the warm-up count.',
  'Stay hungry. Stay stubborn.',
  'Your future self is watching.',
  'Doubt less. Lift more.',
  'Strong is built on boring days.',
  'Quiet work. Loud results.',
  'Be the reason the bar bends.',
  'Sweat now. Flex later.',
  'Fall in love with the grind.',
  "Every set is a vote for who you're becoming.",
  'Ignite. Lift. Repeat.',
];

const _ar = [
  'وزن خفيف، ونية ثقيلة.',
  'لن يأتي أحد. انهض وخذها بنفسك.',
  'استحق يوم راحتك.',
  'الانضباط يبقى حين يرحل الحماس.',
  'احضر حتى في الأيام الصعبة.',
  'البار لا يهتم بمزاجك.',
  'تكرار إضافي واحد هو ما يبني الفرق.',
  'التعب شعور، وليس حقيقة.',
  'أنت ضد نفسك بالأمس. انتصر.',
  'الأوزان الصغيرة تتراكم.',
  'صعب الآن، سهل لاحقًا.',
  'طارد الشعور بعد آخر مجموعة.',
  'الاستمرارية هي السر.',
  'اجعل الإحماء يستحق.',
  'ابقَ جائعًا. ابقَ عنيدًا.',
  'نسختك القادمة تراقبك.',
  'شكّ أقل، ارفع أكثر.',
  'القوة تُبنى في الأيام العادية.',
  'عمل هادئ، ونتائج صاخبة.',
  'كن سبب انحناء البار.',
  'اعرق الآن، واستعرض لاحقًا.',
  'أحبّ التعب في الطريق.',
  'كل مجموعة تصويت لمن تصبح.',
  'اشتعل. ارفع. كرّر.',
];
