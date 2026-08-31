// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'ZIVO';

  @override
  String get actionSave => 'حفظ';

  @override
  String get actionCancel => 'إلغاء';

  @override
  String get actionDone => 'تم';

  @override
  String get actionDelete => 'حذف';

  @override
  String get actionEdit => 'تعديل';

  @override
  String get actionAdd => 'إضافة';

  @override
  String get actionRemove => 'إزالة';

  @override
  String get actionNext => 'التالي';

  @override
  String get actionRetry => 'حاول مرة أخرى';

  @override
  String get tabToday => 'اليوم';

  @override
  String get tabHub => 'الأقسام';

  @override
  String get tabAsk => 'اسأل';

  @override
  String get tabYou => 'حسابي';

  @override
  String get dietTitle => 'التغذية';

  @override
  String dietMealNumber(int number) {
    return 'الوجبة $number';
  }

  @override
  String dietKcalLeft(int kcal) {
    return 'باقي $kcal سعرة';
  }

  @override
  String dietKcalOver(int kcal) {
    return 'زيادة $kcal سعرة';
  }

  @override
  String get dietEatenToday => 'أكلت اليوم';

  @override
  String get dietLogSomething => 'أضف شيئًا أكلته';

  @override
  String get dietSupplements => 'المكملات';

  @override
  String get dietNoPlanToday => 'لا توجد وجبات اليوم';

  @override
  String get dietNoPlan => 'لا يوجد نظام غذائي بعد';

  @override
  String get dietAddPlan => 'أضف نظامًا غذائيًا';

  @override
  String get dietYourPlans => 'أنظمتك الغذائية';

  @override
  String get dietPlanDetails => 'تفاصيل النظام';

  @override
  String get bodyTitle => 'عنك';

  @override
  String get bodyHeightQuestion => 'كم طولك؟';

  @override
  String get bodyWeightQuestion => 'كم وزنك؟';

  @override
  String get bodySexQuestion => 'الجنس';

  @override
  String get bodyActivityQuestion => 'ما مستوى نشاطك؟';

  @override
  String get bodySexMale => 'ذكر';

  @override
  String get bodySexFemale => 'أنثى';

  @override
  String get unitCm => 'سم';

  @override
  String get unitKg => 'كجم';

  @override
  String get unitKcal => 'سعرة';

  @override
  String get unitGrams => 'جم';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageArabic => 'العربية';

  @override
  String get settingsLanguageSystem => 'حسب إعدادات الهاتف';

  @override
  String get prefsLikes => 'أكلات تحبها';

  @override
  String get prefsLikesNote => 'زيفو يبني الخطة حولها.';

  @override
  String get prefsAvoid => 'أكلات لا تأكلها';

  @override
  String get prefsAvoidNote => 'لن تدخل الخطة.';

  @override
  String get prefsAllergies => 'الحساسية';

  @override
  String get prefsAllergiesNote =>
      'زيفو يرفض أي خطة تحتوي عليها. راجع الخطة بنفسك أيضًا.';

  @override
  String get prefsNotes => 'أي شيء آخر';

  @override
  String get prefsNotesHint => 'أتمرن الساعة ٦ صباحًا وآكل بعدها مباشرة';

  @override
  String get prefsOther => 'غير ذلك…';

  @override
  String get prefsAddYourOwn => 'أضف ما تريد';

  @override
  String get foodChicken => 'دجاج';

  @override
  String get foodBeef => 'لحم بقري';

  @override
  String get foodFish => 'سمك';

  @override
  String get foodTuna => 'تونة';

  @override
  String get foodEggs => 'بيض';

  @override
  String get foodRice => 'أرز';

  @override
  String get foodPasta => 'مكرونة';

  @override
  String get foodBread => 'خبز';

  @override
  String get foodPotato => 'بطاطس';

  @override
  String get foodOats => 'شوفان';

  @override
  String get foodYoghurt => 'زبادي';

  @override
  String get foodCheese => 'جبن';

  @override
  String get foodBeans => 'بقوليات وعدس';

  @override
  String get foodVegetables => 'خضار';

  @override
  String get foodFruit => 'فاكهة';

  @override
  String get foodNuts => 'مكسرات';

  @override
  String get allergenPeanuts => 'فول سوداني';

  @override
  String get allergenTreeNuts => 'مكسرات شجرية';

  @override
  String get allergenMilk => 'حليب';

  @override
  String get allergenEggs => 'بيض';

  @override
  String get allergenFish => 'سمك';

  @override
  String get allergenShellfish => 'محار وقشريات';

  @override
  String get allergenSoy => 'صويا';

  @override
  String get allergenGluten => 'جلوتين';

  @override
  String get allergenSesame => 'سمسم';

  @override
  String get bodyIntro => 'زيفو يحتاجها ليعرف تأثير نظامك الغذائي على وزنك.';

  @override
  String get bodyWeighInNote => 'يُحفظ في سجل أوزانك.';

  @override
  String bodyLastWeighIn(String ago) {
    return 'آخر قياس $ago. غيّر الرقم لتسجيل وزن جديد.';
  }

  @override
  String get bodyHeightRange => 'الطول بالسنتيمتر، وليس بالمتر.';

  @override
  String get bodyKnowMaintenance => 'أعرف عدد سعراتي اليومية';

  @override
  String get bodyMaintenanceNote =>
      'من تحليل، أو مدرب، أو متابعتك الشخصية. سيستخدمه زيفو بدلًا من تقديره.';

  @override
  String get bodyMaintenanceRange => 'يبدو أن هناك خطأ في الرقم.';

  @override
  String get bodySaved => 'تم الحفظ';

  @override
  String greetingMorningNamed(String name) {
    return 'صباح الخير يا $name';
  }

  @override
  String greetingAfternoonNamed(String name) {
    return 'مساء الخير يا $name';
  }

  @override
  String greetingEveningNamed(String name) {
    return 'مساء الخير يا $name';
  }

  @override
  String get greetingMorning => 'صباح الخير';

  @override
  String get greetingAfternoon => 'مساء الخير';

  @override
  String get greetingEvening => 'مساء الخير';

  @override
  String get hubWorkout => 'التمرين';

  @override
  String get hubDiet => 'التغذية';

  @override
  String get hubExpenses => 'المصروفات';

  @override
  String get hubMoments => 'اللحظات';

  @override
  String get hubRecent => 'الأخيرة';

  @override
  String get hubNoPlanYet => 'لا توجد خطة بعد';

  @override
  String get hubNoMomentsYet => 'لا توجد لحظات بعد';

  @override
  String get comingNext => 'قريبًا.';

  @override
  String get errorCheckConnection => 'تحقق من اتصالك وحاول مرة أخرى بعد قليل.';

  @override
  String get actionBack => 'رجوع';

  @override
  String get todayQuickLogVoice => 'تسجيل سريع بالصوت';

  @override
  String get todayDaytime => 'نهار';

  @override
  String get todayEvening => 'مساء';

  @override
  String get todayNight => 'ليل';

  @override
  String get todayNextSession => 'التمرين القادم';

  @override
  String todayPlanPosition(int week, int day) {
    return 'الأسبوع $week · اليوم $day';
  }

  @override
  String get todayNoPlanTitle => 'لا توجد خطة تمرين بعد';

  @override
  String get todayNoPlanBody =>
      'استورد جدولك من ملف PDF أو صورة ويحوّله زيفو إلى خطة متكررة حقيقية — أو ابنِ واحدة بنفسك.';

  @override
  String get todayImportPlan => 'استورد خطة';

  @override
  String get todayBuildManually => 'أو ابنِها بنفسك';

  @override
  String get todayEmptySplitBody =>
      'أضف أيام التمرين والتمارين إلى هذا الجدول وسيظهر هنا جاهزًا للبدء.';

  @override
  String get todayEditSplit => 'تعديل الجدول';

  @override
  String get todayGetStarted => 'لنبدأ';

  @override
  String get todayImportWorkoutPlan => 'استورد\nخطة تمرين';

  @override
  String get todayAddExpense => 'أضف\nمصروفًا';

  @override
  String get pulseToday => 'اليوم';

  @override
  String get pulseNotYetToday => 'لم يحدث اليوم بعد';

  @override
  String get pulseTrained => 'تمرنت';

  @override
  String get pulseSteps => 'الخطوات';

  @override
  String pulseOfGoal(String goal) {
    return 'من $goal';
  }

  @override
  String get pulseNoSensor => 'لا يوجد حساس';

  @override
  String get pulseVolume => 'الحِمل';

  @override
  String get pulseNoSetsYet => 'لا توجد مجموعات بعد';

  @override
  String get pulseFirstWeek => 'الأسبوع الأول';

  @override
  String get pulseMomentum => 'الاندفاع';

  @override
  String get pulseNoStreakYet => 'لا توجد سلسلة بعد';

  @override
  String get pulseNoSessionsYet => 'لا توجد جلسات بعد';

  @override
  String get pulseWorthKnowing => 'يستحق المعرفة';
}
