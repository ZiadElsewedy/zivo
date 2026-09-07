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
  String get hubNoPlanYet => 'لا توجد خطة بعد';

  @override
  String get hubNoMomentsYet => 'لا توجد لحظات بعد';

  @override
  String get pulseWeekOverWeek => 'أسبوعيًا';

  @override
  String get hubTitle => 'الأقسام';

  @override
  String get hubConnected => 'المتصل';

  @override
  String hubWorkoutResume(String day) {
    return '$day · استئناف';
  }

  @override
  String hubWorkoutUpNext(String day) {
    return '$day · التالي';
  }

  @override
  String hubDietStat(int eaten, int total, String kcal) {
    return '$eaten من $total · $kcal سعرة';
  }

  @override
  String hubExpensesStat(String amount) {
    return '$amount هذا الأسبوع';
  }

  @override
  String hubMomentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count لحظة',
      many: '$count لحظة',
      few: '$count لحظات',
      two: 'لحظتان',
      one: 'لحظة واحدة',
      zero: 'لا لحظات',
    );
    return '$_temp0';
  }

  @override
  String get connectedBackingUp => 'يتم النسخ الاحتياطي';

  @override
  String get connectedNotConnected => 'غير متصل';

  @override
  String get connectedConnected => 'متصل';

  @override
  String get connectedPlaying => 'قيد التشغيل';

  @override
  String get connectedPaused => 'متوقف مؤقتًا';

  @override
  String get connectedConnecting => 'جارٍ الاتصال…';

  @override
  String get connectedCouldntConnect => 'تعذّر الاتصال';

  @override
  String get connectedPremiumRequired => 'يتطلب Premium';

  @override
  String get connectedInstallSpotify => 'ثبّت Spotify';

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

  @override
  String insightStreakTitle(int days) {
    return 'سلسلة تمرين $days أيام';
  }

  @override
  String get insightStreakBody => 'الاندفاع حقيقي الآن — احمِه بتمرين اليوم.';

  @override
  String insightRestTitle(int days) {
    return 'امتدت الراحة إلى $days أيام';
  }

  @override
  String get insightRestBody =>
      'لا تلم نفسك — فقط ابدأ تمرينًا صغيرًا وقتما تكون جاهزًا.';

  @override
  String get insightEveningTitle => 'مراجعة المساء';

  @override
  String get insightMealsLeftOne =>
      'ما زالت هناك وجبة واحدة اليوم — يستحق إنهاؤها.';

  @override
  String insightMealsLeftOneKcal(int kcal) {
    return 'ما زالت هناك وجبة واحدة اليوم (~$kcal سعرة) — يستحق إنهاؤها.';
  }

  @override
  String insightMealsLeftMany(int count) {
    return 'ما زالت هناك $count وجبات اليوم.';
  }

  @override
  String insightMealsLeftManyKcal(int count, int kcal) {
    return 'ما زالت هناك $count وجبات اليوم (باقي ~$kcal سعرة).';
  }

  @override
  String insightSpendTitle(int percent) {
    return 'إنفاقك أعلى بنحو $percent%';
  }

  @override
  String get insightSpendBody =>
      'هذا الأسبوع مقارنة بالفترة نفسها الأسبوع الماضي — يستحق نظرة.';

  @override
  String get insightStepsTitle => 'خطواتك متأخرة اليوم';

  @override
  String insightStepsClose(int steps) {
    return 'باقي $steps خطوة فقط للهدف — مشية قصيرة تكفي.';
  }

  @override
  String insightStepsFar(int steps) {
    return 'باقي $steps خطوة — حتى عشر دقائق تساعد.';
  }

  @override
  String insightWeightDownTitle(String kg, int days) {
    return 'نزل وزنك $kg كجم خلال $days يومًا';
  }

  @override
  String insightWeightUpTitle(String kg, int days) {
    return 'زاد وزنك $kg كجم خلال $days يومًا';
  }

  @override
  String get insightWeightDownBody =>
      'تقدم ثابت — استمر في الأكل الكافي لتتمرن بقوة.';

  @override
  String get insightWeightUpBody =>
      'لا شيء مقلق — تابع الاتجاه العام، لا يومًا بعينه.';

  @override
  String get workoutTitle => 'التمرين';

  @override
  String get workoutProgress => 'التقدم';

  @override
  String get workoutTraining => 'التدريب';

  @override
  String get workoutBodyweight => 'وزن الجسم';

  @override
  String get workoutSplits => 'الجداول';

  @override
  String get workoutAnalysis => 'التحليل';

  @override
  String get workoutHistory => 'السجل';

  @override
  String get workoutCreatePlan => 'إنشاء خطة';

  @override
  String get workoutEditPlan => 'تعديل الخطة';

  @override
  String get workoutNoPlanYet => 'لا توجد خطة تمرين بعد';

  @override
  String get workoutNoDayUpNext => 'لا يوجد يوم تالٍ.';

  @override
  String get workoutFullCycle => 'الدورة كاملة';

  @override
  String get workoutAnyDayNote =>
      'يوم اليوم مُعلَّم — لكن أي يوم متاح. الحياة لا تتبع الدورة دائمًا.';

  @override
  String get workoutUpNext => 'التالي';

  @override
  String get workoutNextUp => 'التالي';

  @override
  String get workoutInProgress => 'جارٍ الآن';

  @override
  String get workoutInProgressCaps => 'جارٍ الآن';

  @override
  String get workoutStart => 'ابدأ التمرين';

  @override
  String get workoutResume => 'أكمل التمرين';

  @override
  String get workoutPause => 'إيقاف مؤقت';

  @override
  String get workoutStartThisDay => 'ابدأ هذا اليوم';

  @override
  String get workoutChange => 'تغيير';

  @override
  String get workoutChangeWorkout => 'تغيير التمرين';

  @override
  String get workoutChangeSwap => 'تبديل';

  @override
  String get workoutChangeSkip => 'تخطّي';

  @override
  String workoutChangeSwapNote(String day) {
    return '$day يأخذ مكان اليوم الذي تختاره — تبقى الدورة كاملة.';
  }

  @override
  String workoutChangeSkipNote(String day) {
    return 'سيُتخطّى $day في هذه الدورة.';
  }

  @override
  String workoutDayLabel(String slot, String label) {
    return 'اليوم $slot · $label';
  }

  @override
  String workoutDaySlot(String slot) {
    return 'اليوم $slot';
  }

  @override
  String get workoutExercises => 'تمارين';

  @override
  String get workoutSets => 'مجموعات';

  @override
  String get workoutMinutes => 'دقيقة';

  @override
  String workoutReadyToStart(String day) {
    return 'جاهز لبدء $day؟';
  }

  @override
  String get workoutReadyToResume => 'جاهز للعودة؟';

  @override
  String get actionResume => 'أكمل';

  @override
  String get actionStart => 'ابدأ';

  @override
  String weighInLast(String kg) {
    return 'آخر قياس: $kg كجم';
  }

  @override
  String get weighInLog => 'سجّل وزنك';

  @override
  String get weighInNone => 'لا توجد قياسات بعد';

  @override
  String get weighInStartTrend => 'سجّل واحدًا لتبدأ المتابعة.';

  @override
  String weighInLoggedAgo(String ago) {
    return 'سُجّل منذ $ago';
  }

  @override
  String get statTotal => 'الإجمالي';

  @override
  String get statSessions => 'الجلسات';

  @override
  String get statDays => 'يوم';

  @override
  String get statStreak => 'السلسلة';

  @override
  String get statMinAvg => 'متوسط الدقائق';

  @override
  String get statDuration => 'المدة';

  @override
  String get statUsualStart => 'وقت البدء المعتاد';

  @override
  String get commonToday => 'اليوم';

  @override
  String weighInOneMore(String ago) {
    return 'سُجّل منذ $ago · قياس آخر يرسم الاتجاه.';
  }

  @override
  String get liveDiscardTitle => 'تجاهل هذا التمرين؟';

  @override
  String get liveDiscardBody => 'ستفقد تقدم هذه الجلسة ولن تتقدم الخطة.';

  @override
  String get liveKeepGoing => 'أكمل';

  @override
  String get liveDiscard => 'تجاهل';

  @override
  String get liveDiscardWorkout => 'تجاهل التمرين';

  @override
  String get liveNoExercises => 'لا توجد تمارين';

  @override
  String get liveNothingToDo => 'لا يوجد ما تفعله.';

  @override
  String get liveSetLogged => 'سُجّلت المجموعة';

  @override
  String liveSetLoggedDetail(String detail) {
    return 'سُجّلت المجموعة · $detail';
  }

  @override
  String liveSetsLogged(String count) {
    return '$count مجموعات مسجلة';
  }

  @override
  String get liveReps => 'التكرارات';

  @override
  String get liveWeightKg => 'الوزن · كجم';

  @override
  String get liveRepsField => 'التكرارات';

  @override
  String get liveWeightField => 'الوزن (كجم)';

  @override
  String get liveNow => 'الآن';

  @override
  String get livePaused => 'متوقف';

  @override
  String get livePausedCaps => 'متوقف';

  @override
  String get livePausedTapResume => 'متوقف · اضغط للمتابعة';

  @override
  String get livePreWorkout => 'قبل التمرين';

  @override
  String get liveFirstUp => 'الأول';

  @override
  String get liveSkipWarmUp => 'تخطَّ الإحماء';

  @override
  String get liveRest => 'راحة';

  @override
  String get liveSkipRest => 'تخطَّ الراحة';

  @override
  String liveRestPlanned(String total) {
    return 'من $total مخططة';
  }

  @override
  String get liveWorkoutComplete => 'اكتمل التمرين';

  @override
  String get liveFinish => 'إنهاء';

  @override
  String get livePrsTitle => 'أرقام شخصية جديدة';

  @override
  String get liveMatchingPrevious => 'مطابق لمجموعتك السابقة';

  @override
  String get liveFirstTime => 'المرة الأولى';

  @override
  String get liveMatchingLast => 'مطابق للمرة السابقة';

  @override
  String liveSetNumber(int position) {
    return 'المجموعة $position';
  }

  @override
  String liveSetNumberCaps(int number) {
    return 'المجموعة $number';
  }

  @override
  String liveSetNumberKg(int number) {
    return 'المجموعة $number · كجم';
  }

  @override
  String get liveSkipped => 'تم تخطيها';

  @override
  String get liveSkippedCaps => 'تم تخطيها';

  @override
  String get liveSkip => 'تخطَّ';

  @override
  String get liveLogSet => 'سجّل المجموعة';

  @override
  String get liveMarkDone => 'علّمها كمنجزة';

  @override
  String get liveCorrectSkipped => 'أدخل ما فعلته بالفعل لتعليمها كمنجزة.';

  @override
  String get liveCorrectLogged => 'صحّح التكرارات أو الوزن المسجل.';

  @override
  String get liveGoal => 'الهدف';

  @override
  String get liveLastTime => 'المرة السابقة';

  @override
  String get liveTargetRange => 'النطاق المستهدف';

  @override
  String get liveWeightUp => 'زاد الوزن — أكملت تكراراتك آخر مرة';

  @override
  String get liveWeightEased => 'خُفّف الوزن — أعد البناء بتكرارات نظيفة';

  @override
  String get liveSameLoadMoreRep => 'نفس الوزن، تكرار إضافي';

  @override
  String liveSameWeight(String kg) {
    return 'نفسه · $kg كجم';
  }

  @override
  String get liveConnectMusic => 'اربط الموسيقى';

  @override
  String get actionClose => 'إغلاق';

  @override
  String get actionBackCaps => 'رجوع';

  @override
  String liveDeltaWeight(String delta) {
    return '$delta كجم عن مجموعتك السابقة';
  }

  @override
  String liveDeltaReps(String delta) {
    return '$delta تكرار عن مجموعتك السابقة';
  }

  @override
  String liveRepsValue(int reps) {
    return '$reps تكرار';
  }

  @override
  String liveWeightValue(String kg) {
    return '$kg كجم';
  }

  @override
  String liveRepsByWeight(int reps, String kg) {
    return '$reps × $kg كجم';
  }

  @override
  String get categoryFood => 'طعام';

  @override
  String get categoryCoffee => 'قهوة';

  @override
  String get categoryTransport => 'مواصلات';

  @override
  String get categoryGroceries => 'بقالة';

  @override
  String get categoryShopping => 'تسوق';

  @override
  String get categoryOther => 'أخرى';

  @override
  String get expensesTitle => 'المصروفات';

  @override
  String get expensesEmpty => 'لا يوجد إنفاق بعد — بداية هادئة.';

  @override
  String get expenseNew => 'مصروف جديد';

  @override
  String get expenseEdit => 'تعديل المصروف';

  @override
  String get expenseDelete => 'حذف المصروف';

  @override
  String get expenseNote => 'ملاحظة';

  @override
  String get expenseNoteHint => 'على ماذا كان؟';

  @override
  String get expenseAddNote => 'أضف ملاحظة';

  @override
  String expenseSaveAmount(String amount) {
    return 'حفظ · $amount';
  }

  @override
  String get walletCaps => 'المحفظة';

  @override
  String get walletSetUp => 'أعدّ محفظتك';

  @override
  String get walletHowMuchNow => 'كم معك الآن؟';

  @override
  String get walletDeductNote => 'كل مصروف تسجله يُخصم منها تلقائيًا.';

  @override
  String get walletSetStarting => 'حدد الرصيد المبدئي';

  @override
  String get walletTopUp => 'إضافة رصيد';

  @override
  String get walletTopUpTitle => 'إضافة رصيد للمحفظة';

  @override
  String get walletSetBalanceTitle => 'تحديد رصيد المحفظة';

  @override
  String get walletHowMuchAdding => 'كم ستضيف؟';

  @override
  String get walletSaveBalance => 'حفظ الرصيد';

  @override
  String get walletAddFunds => 'إضافة الرصيد';

  @override
  String get expensesThisWeek => 'هذا الأسبوع';

  @override
  String get categoryNew => 'فئة جديدة';

  @override
  String get categoryNewHint => 'مثال: الاشتراكات';

  @override
  String get categoryIconCaps => 'الأيقونة';

  @override
  String get categoryAdd => 'إضافة فئة';

  @override
  String get captureTitle => 'تسجيل سريع';

  @override
  String get captureExpense => 'مصروف';

  @override
  String get captureExpenseDetail => 'المبلغ والفئة — في ثوانٍ';

  @override
  String get captureMoment => 'لحظة';

  @override
  String get captureMomentDetail => 'صورة + سطر';

  @override
  String get captureWorkout => 'تمرين';

  @override
  String get captureWorkoutDetail => 'سجّل جلسة تدريب';

  @override
  String get dateToday => 'اليوم';

  @override
  String get dateYesterday => 'أمس';

  @override
  String get nutritionCalories => 'السعرات';

  @override
  String get nutritionProtein => 'البروتين (جم)';

  @override
  String get nutritionCarbs => 'الكربوهيدرات (جم)';

  @override
  String get nutritionFat => 'الدهون (جم)';

  @override
  String get nutritionCaloriesPer100g => 'السعرات / ١٠٠ جم';

  @override
  String get targetsSave => 'حفظ الهدف';

  @override
  String get targetsNoneSet => 'لم يُحدد هدف يومي';

  @override
  String get targetsZivoWillUse => 'سيستخدم زيفو';

  @override
  String get targetsFillFields => 'املأ الحقول';

  @override
  String get targetsChangeBodyData => 'تعديل بيانات جسمي';

  @override
  String get targetsFromBodyData => 'احسبه من بيانات جسمي';

  @override
  String get bodyWeightLabel => 'الوزن';

  @override
  String get bodyHeightLabel => 'الطول';

  @override
  String get bodyAgeLabel => 'العمر';

  @override
  String get bodyActivityLabel => 'النشاط';

  @override
  String get planDeleteTitle => 'حذف هذه الخطة؟';

  @override
  String get planEditTitle => 'تعديل الخطة الغذائية';

  @override
  String get planDelete => 'حذف الخطة';

  @override
  String get planNameHint => 'اسم الخطة';

  @override
  String get planSave => 'حفظ الخطة';

  @override
  String get planNoDays => 'لا توجد أيام بعد.';

  @override
  String get planDaySlot => 'الرمز';

  @override
  String get planDaySlotHint => 'A';

  @override
  String get planDayLabel => 'الاسم';

  @override
  String get planDayLabelHint => 'اسم اليوم (اختياري)';

  @override
  String get planDayNotesOptional => 'ملاحظات (اختياري)';

  @override
  String get workoutShortestSession => 'الأقصر';

  @override
  String get workoutLongestSession => 'الأطول';

  @override
  String get planAddDay => 'أضف يومًا';

  @override
  String get planAddMeal => 'أضف وجبة';

  @override
  String get planAddItem => 'أضف صنفًا';

  @override
  String get planAddFoodItem => 'أضف صنف طعام';

  @override
  String get planEveryDay => 'كل يوم';

  @override
  String get planMealNameHint => 'اسم الوجبة';

  @override
  String get planFoodNameHint => 'اسم الطعام';

  @override
  String get planQty => 'الكمية';

  @override
  String get plansTitle => 'خططك';

  @override
  String get plansFollow => 'اتبع هذه الخطة';

  @override
  String get plansStopFollowing => 'إيقاف المتابعة';

  @override
  String get prefsBuildTitle => 'ابنِ لي خطة';

  @override
  String get prefsBuild => 'ابنِ خطتي';

  @override
  String get dictateHint => 'الإفطار هو…';

  @override
  String get dictateTurnIntoPlan => 'حوّل هذا إلى خطة';

  @override
  String get dictateDoneTalking => 'انتهيت';

  @override
  String get logWhatDidYouEat => 'ماذا أكلت؟';

  @override
  String get logBackToSearch => 'العودة للبحث';

  @override
  String get logIt => 'سجّلها';

  @override
  String logAddOwnFood(String query) {
    return 'أضف \"$query\" كطعام خاص بي';
  }

  @override
  String get logYourOwnFood => 'طعامك الخاص';

  @override
  String get logFoodName => 'الاسم';

  @override
  String get logSaveFood => 'حفظ الطعام';

  @override
  String get dietBasisLogged => 'سجّلتها بنفسك';

  @override
  String get dietBasisTicked => 'من وجبات مؤشَّرة، غير موزونة';

  @override
  String get dietBasisNothing => 'لم يُسجَّل شيء بعد';

  @override
  String get dietFindingObservation => 'ملاحظة';

  @override
  String get dietFindingAnalysis => 'تحليل';

  @override
  String get dietFindingSuggestion => 'اقتراح';

  @override
  String get dietFindingWarning => 'تنبيه';

  @override
  String get dietFindingGoingWell => 'يسير على ما يرام';

  @override
  String get dietFindingWorthKnowing => 'جدير بالمعرفة';

  @override
  String get dietEaten => 'أُكلت';

  @override
  String get dietNotEaten => 'لم تُؤكل';

  @override
  String get adoptSaveAsTarget => 'احفظه كهدفي';

  @override
  String get addDietPdfOrPhoto => 'ملف أو صورة';

  @override
  String get addDietPdfOrPhotoDetail => 'خطة أخصائي التغذية، أو صورة لها.';

  @override
  String get addDietDictate => 'قلها بصوتك';

  @override
  String get addDietDictateDetail => 'صف وجباتك؛ وزيفو يكتبها.';

  @override
  String get addDietType => 'اكتبها';

  @override
  String get addDietTypeDetail => 'اكتب وجباتك بكلماتك.';

  @override
  String get addDietGenerate => 'ابنِها لي';

  @override
  String get addDietGenerateDetail => 'أخبر زيفو بما تأكله؛ وهو يصمم الخطة.';

  @override
  String get addDietManual => 'ابنِها وجبة بوجبة';

  @override
  String get addDietManualDetail => 'المحرر الكامل، دون استخراج تلقائي.';

  @override
  String get addDietIntro =>
      'مهما وصلت إلى زيفو، ستراجع كل وجبة وكل رقم قبل الحفظ.';

  @override
  String get momentDeleteTitle => 'حذف اللحظة؟';

  @override
  String get momentDeleteBody =>
      'سيؤدي هذا إلى إزالتها من لحظاتك. كما ستُحذف الصورة من جهازك.';

  @override
  String dietPlanDeleteBody(String name) {
    return 'سيؤدي هذا إلى حذف \"$name\" وكل أيامها ووجباتها. لا يمكن التراجع عن هذا.';
  }

  @override
  String dietPlanArchiveHint(String name) {
    return 'سيؤدي هذا إلى حذف $name نهائيًا. الأرشفة تحتفظ بها وتزيلها من شاشة التغذية بالمثل.';
  }

  @override
  String get sessionDeleteTitle => 'حذف هذه الجلسة؟';

  @override
  String sessionDeleteBody(String day) {
    return 'سيؤدي هذا إلى حذف جلسة \"$day\" وكل ما سُجّل فيها نهائيًا. لا يمكن التراجع عن هذا.';
  }

  @override
  String splitDeleteTitle(String name) {
    return 'حذف \"$name\"؟';
  }

  @override
  String get splitDeleteBody =>
      'سيؤدي هذا إلى حذف التقسيمة وكل أيامها وتمارينها. يبقى السجل المُسجَّل لها محفوظًا، لكن لا يمكن تعديله من هنا. لا يمكن التراجع عن هذا.';

  @override
  String get workoutPlanDeleteTitle => 'حذف هذه الخطة؟';

  @override
  String workoutPlanDeleteBody(String name) {
    return 'سيؤدي هذا إلى حذف \"$name\" وكل أيامها وتمارينها. لا يمكن التراجع عن هذا.';
  }

  @override
  String get splitDeleteTitlePlain => 'حذف هذه التقسيمة؟';

  @override
  String get expenseSaveFailed => 'تعذّر حفظ هذا المصروف.';

  @override
  String get expenseDeleteFailed => 'تعذّر حذف هذا المصروف.';

  @override
  String get dietLogFailed => 'تعذّر تسجيل هذا الطعام.';

  @override
  String get musicConnect => 'ربط Spotify';

  @override
  String get musicReconnect => 'إعادة ربط Spotify';

  @override
  String get musicConnecting => 'جارٍ الربط…';

  @override
  String get musicInstallSpotify => 'ثبّت Spotify للتشغيل';

  @override
  String get musicNothingPlaying => 'لا يوجد تشغيل';

  @override
  String get musicPrevious => 'المقطع السابق';

  @override
  String get musicNext => 'المقطع التالي';

  @override
  String get musicPlay => 'تشغيل';

  @override
  String get musicPause => 'إيقاف مؤقت';

  @override
  String get musicDisconnect => 'فصل Spotify';

  @override
  String get errorCouldntLoad => 'تعذّر تحميل هذا.';

  @override
  String get workoutStatusProgressing => 'يتقدّم';

  @override
  String get workoutStatusHolding => 'ثابت';

  @override
  String get workoutStatusPlateaued => 'متوقّف';

  @override
  String get workoutStatusTrendingDown => 'في تراجع';

  @override
  String get workoutStatusBuilding => 'قيد التكوين';

  @override
  String get workoutToneImproved => 'تحسّنت';

  @override
  String get workoutToneMatched => 'مماثلة';

  @override
  String get workoutToneMixed => 'متفاوتة';

  @override
  String get workoutToneDown => 'أقل';

  @override
  String get workoutBodyweightLoadError => 'تعذّر تحميل القياسات.';

  @override
  String workoutWeighInsLogged(int count) {
    return '$count قياس مسجّل';
  }

  @override
  String get workoutUnitKg => 'كجم';

  @override
  String workoutBodyweightChange30d(String change) {
    return '$change كجم · ٣٠ يوم';
  }

  @override
  String get workoutBodyweightEmpty => 'سجّل أول قياس لك لتبدأ متابعة التغيّر.';

  @override
  String get workoutThisWeekCaps => 'هذا الأسبوع';

  @override
  String get workoutLastWeekCaps => 'الأسبوع الماضي';

  @override
  String get workoutSessionsLabel => 'الجلسات';

  @override
  String get workoutTrained => 'وقت التدريب';

  @override
  String get workoutThisWeek => 'هذا الأسبوع';

  @override
  String get workoutSessionCompleted => 'مكتملة';

  @override
  String get workoutSessionInProgress => 'قيد التنفيذ';

  @override
  String get workoutSessionNotCompleted => 'غير مكتملة';

  @override
  String workoutExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تمرين',
      many: '$count تمرينًا',
      few: '$count تمارين',
      two: 'تمرينان',
      one: 'تمرين واحد',
      zero: 'لا تمارين',
    );
    return '$_temp0';
  }

  @override
  String workoutSetsOfTotal(int done, int total) {
    return '$done/$total مجموعات';
  }

  @override
  String get workoutNoSessionsTitle => 'لا توجد جلسات مسجّلة بعد.';

  @override
  String get workoutNoSessionsBody => 'أنهِ تمرينًا وسيظهر هنا.';

  @override
  String get workoutSessionsLoadError => 'تعذّر تحميل الجلسات.';

  @override
  String get workoutNoCompletedWorkouts => 'لا توجد تمارين مكتملة بعد.';

  @override
  String workoutCompletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تمرين مكتمل',
      many: '$count تمرينًا مكتملًا',
      few: '$count تمارين مكتملة',
      two: 'تمرينان مكتملان',
      one: 'تمرين مكتمل واحد',
      zero: 'لا تمارين مكتملة',
    );
    return '$_temp0';
  }

  @override
  String workoutNoCompletedWithEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'لا تمارين مكتملة · $count مدخل',
      many: 'لا تمارين مكتملة · $count مدخلًا',
      few: 'لا تمارين مكتملة · $count مدخلات',
      two: 'لا تمارين مكتملة · مدخلان',
      one: 'لا تمارين مكتملة · مدخل واحد',
      zero: 'لا تمارين مكتملة',
    );
    return '$_temp0';
  }

  @override
  String workoutCompletedAndNotCompleted(String completed, int notCompleted) {
    return '$completed · $notCompleted غير مكتملة';
  }

  @override
  String get workoutSessionsEmpty =>
      'لا شيء هنا بعد — التمارين المنتهية تظهر هنا.';

  @override
  String get workoutSessionEndedEarly => 'انتهت مبكرًا';

  @override
  String workoutSetsCaps(int done, int total) {
    return '$done/$total مجموعات';
  }

  @override
  String get workoutDayStreak => 'أيام متتالية';

  @override
  String get workoutNoActiveStreak =>
      'لا سلسلة نشطة — أكمل تمرينًا لتبدأ واحدة.';

  @override
  String workoutStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أيام في سلسلتك الحالية',
      two: 'يومان في سلسلتك الحالية',
      one: 'يوم في سلسلتك الحالية',
    );
    return '$_temp0';
  }

  @override
  String get workoutBestStreak => 'أطول سلسلة أيام';

  @override
  String get workoutStreakEmpty => 'تدرّب اليوم وتبدأ السلسلة من الآن.';

  @override
  String workoutSessionsCountCaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جلسة',
      many: '$count جلسة',
      few: '$count جلسات',
      two: 'جلستان',
      one: 'جلسة واحدة',
      zero: 'لا جلسات',
    );
    return '$_temp0';
  }

  @override
  String get workoutSessionLength => 'مدة الجلسة';

  @override
  String get workoutNoAverageYet => 'أكمل تمرينًا لترى متوسطك.';

  @override
  String get workoutAverageSession => 'متوسط الجلسة المكتملة';

  @override
  String get workoutDurationsEmpty => 'تظهر المدد بعد أن تنهي تمارين.';

  @override
  String get workoutStartTimes => 'أوقات البدء';

  @override
  String get workoutNoStartTimeYet => 'أكمل تمرينًا لترى وقت بدئك المعتاد.';

  @override
  String get workoutUsualStartTime => 'وقت بدئك المعتاد للتدريب';

  @override
  String get workoutStartTimesEmpty => 'ستظهر أوقات بدئك هنا.';

  @override
  String get workoutToday => 'اليوم';

  @override
  String workoutAgo(String value) {
    return 'منذ $value';
  }

  @override
  String get workoutCurrentSplit => 'الجدول الحالي';

  @override
  String get workoutRecentActivity => 'النشاط الأخير';

  @override
  String get workoutNoSessionYet => 'لم تسجّل أي جلسة بعد.';

  @override
  String get workoutGoDeeper => 'تعمّق أكثر';

  @override
  String get workoutFullAnalysis => 'التحليل الكامل';

  @override
  String get workoutFullAnalysisDetail => 'تمرينًا بتمرين، لكل يوم تدريب';

  @override
  String get workoutAllHistory => 'كل السجل';

  @override
  String get workoutAllHistoryDetail => 'كل جلسة سجّلتها';

  @override
  String get workoutSplitsDetail => 'بدّل جداول تدريبك أو عدّلها';

  @override
  String get workoutTotalSessions => 'إجمالي الجلسات';

  @override
  String get workoutAvgLength => 'متوسط المدة';

  @override
  String get workoutSeeFullAnalysisCaps => 'عرض التحليل الكامل';

  @override
  String get workoutSeeAllCaps => 'عرض الكل';

  @override
  String workoutPrCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count رقم قياسي',
      many: '$count رقمًا قياسيًا',
      few: '$count أرقام قياسية',
      two: 'رقمان قياسيان',
      one: 'رقم قياسي',
      zero: 'لا أرقام قياسية',
    );
    return '$_temp0';
  }

  @override
  String workoutSessionsCompletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جلسة مكتملة',
      many: '$count جلسة مكتملة',
      few: '$count جلسات مكتملة',
      two: 'جلستان مكتملتان',
      one: 'جلسة واحدة مكتملة',
      zero: 'لا جلسات مكتملة',
    );
    return '$_temp0';
  }

  @override
  String get workoutPlanShort => 'الخطة';

  @override
  String workoutAgoWithDuration(String value, String duration) {
    return 'منذ $value · $duration';
  }

  @override
  String get workoutRecentPrs => 'أرقام قياسية حديثة';

  @override
  String get workoutGoingWell => 'ما يسير على ما يرام';

  @override
  String workoutImprovingCount(int count) {
    return '$count في تحسّن';
  }

  @override
  String get workoutGettingWorse => 'ما يتراجع';

  @override
  String workoutDecliningCount(int count) {
    return '$count في تراجع';
  }

  @override
  String get workoutStalled => 'متوقّف — يحتاج تغييرًا';

  @override
  String workoutFlatCount(int count) {
    return '$count ثابت';
  }

  @override
  String get workoutBeingSkipped => 'ما يتم تخطّيه';

  @override
  String workoutSkippedOfPlanned(int skipped, int planned) {
    return '$skipped من $planned';
  }

  @override
  String get workoutFocusNext => 'ركّز على التالي';

  @override
  String get workoutTrainingVolume => 'حجم التدريب';

  @override
  String get workoutAllExercises => 'كل التمارين';

  @override
  String get workoutTapToDrillIn => 'اضغط للتفاصيل';

  @override
  String get workoutOverallCaps => 'الإجمالي';

  @override
  String get workoutPrHeaviest => 'الأثقل';

  @override
  String get workoutPrMostReps => 'أكثر تكرارات';

  @override
  String get workoutPrBestStrength => 'أفضل قوة';

  @override
  String workoutRepsOnly(int reps) {
    return '$reps تكرار';
  }

  @override
  String workoutWeightByReps(String weight, int reps) {
    return '$weight كجم × $reps';
  }

  @override
  String workoutStatusWithStrength(String status, String change) {
    return '$status · $change قوة';
  }

  @override
  String get workoutNeverTrained => 'مخطّط لكن لم يُدرَّب أبدًا';

  @override
  String workoutStaleSince(int days, String day) {
    return '$days يومًا منذ آخر مرة — في $day';
  }

  @override
  String get workoutNoPriorWeek => 'لا يوجد أسبوع سابق للمقارنة';

  @override
  String workoutVsLastWeek(String change) {
    return '$change مقارنة بالأسبوع الماضي';
  }

  @override
  String get workoutSameAsLastWeek => 'كما الأسبوع الماضي';

  @override
  String get workoutThisWeekWorkingSets =>
      'هذا الأسبوع · المجموعات الفعّالة فقط';

  @override
  String get workoutAnalysisEmptyTitle => 'أكمل بضع جلسات لتبدأ متابعة تقدّمك.';

  @override
  String get workoutAnalysisEmptyBody =>
      'بعد أن تسجّل التمرين نفسه بضع مرات، سيعرض ZIVO تطوّر قوتك وأرقامك القياسية وما يجب التركيز عليه.';

  @override
  String get workoutStrengthTrend => 'تطوّر القوة';

  @override
  String get workoutVolumeTrend => 'تطوّر الحجم';

  @override
  String get workoutAtAGlance => 'نظرة سريعة';

  @override
  String get workoutPersonalRecords => 'الأرقام القياسية';

  @override
  String get workoutSessionHistory => 'سجل الجلسات';

  @override
  String workoutSessionsLogged(int count) {
    return '$count مسجّلة';
  }

  @override
  String workoutEstStrengthChange(String change) {
    return '$change قوة تقديرية';
  }

  @override
  String get workoutEst1rmCaps => 'أقصى تكرار تقديري';

  @override
  String get workoutWhatHappenedCaps => 'ما الذي حدث';

  @override
  String get workoutWhyItMattersCaps => 'لماذا يهم';

  @override
  String get workoutDoThisCaps => 'افعل هذا';

  @override
  String get workoutEst1rmUnitCaps => 'أقصى تكرار تقديري (كجم)';

  @override
  String get workoutVolumeUnitCaps => 'الحجم (كجم)';

  @override
  String get workoutOldest => 'الأقدم';

  @override
  String get workoutLatest => 'الأحدث';

  @override
  String get workoutBestEst1rm => 'أفضل أقصى تكرار تقديري';

  @override
  String get workoutTotalVolume => 'إجمالي الحجم';

  @override
  String get workoutFrequency => 'التكرار';

  @override
  String get workoutPerWeek => '/أسبوع';

  @override
  String get workoutLastTrained => 'آخر تدريب';

  @override
  String get workoutDaysAgo => 'يومًا مضت';

  @override
  String get workoutPrHeaviestLoad => 'أثقل حمل';

  @override
  String workoutKgValue(String value) {
    return '$value كجم';
  }

  @override
  String workoutSessionNumberCaps(int index) {
    return 'الجلسة $index';
  }

  @override
  String get workoutSetsShort => 'المجموعات';

  @override
  String get workoutTopSet => 'أفضل مجموعة';

  @override
  String get workoutVolumeShort => 'الحجم';

  @override
  String get workoutEst1rmShort => 'أقصى تكرار تقديري';

  @override
  String get workoutVsPreviousSessionCaps => 'مقارنة بالجلسة السابقة';

  @override
  String get workoutSetDropsetShort => 'D';

  @override
  String workoutRepsSpec(String reps) {
    return '$reps تكرار';
  }

  @override
  String workoutSetCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مجموعة',
      many: '$count مجموعة',
      few: '$count مجموعات',
      two: 'مجموعتان',
      one: 'مجموعة واحدة',
      zero: 'لا مجموعات',
    );
    return '$_temp0';
  }

  @override
  String get workoutToFailure => 'حتى الفشل';

  @override
  String get planDefaultRest => 'الراحة الافتراضية';

  @override
  String planDefaultRestValue(String time) {
    return 'الراحة الافتراضية · $time';
  }

  @override
  String get planDefaultRestNote =>
      'يضبط راحة كل تمرين في هذه الخطة على هذه القيمة. وتعديل تمرين واحد بعدها يظل يتجاوزها على حدة.';

  @override
  String get planSetAll => 'ضبط الكل';

  @override
  String workoutRestFor(String time) {
    return 'راحة $time';
  }

  @override
  String workoutSetsBy(int count, String reps) {
    return '$count × $reps';
  }

  @override
  String workoutPlanDayMeta(String plan, String exercises) {
    return '$plan · $exercises';
  }

  @override
  String workoutExerciseMeta(String sets, String muscleGroup) {
    return '$sets · $muscleGroup';
  }

  @override
  String get workoutSetFailureShort => 'F';

  @override
  String get workoutPbCaps => 'رقم قياسي';

  @override
  String get workoutExerciseEmptyTitle =>
      'لا توجد جلسات مكتملة بهذا التمرين بعد.';

  @override
  String get workoutExerciseEmptyBody =>
      'سجّله في جلسة وسيظهر هنا سجلّه الكامل وتطوّره ومقارنة كل جلسة بالتي قبلها.';

  @override
  String get workoutNewPb => 'رقم قياسي جديد';

  @override
  String workoutDeltaE1rm(String change) {
    return 'أقصى تكرار تقديري $change';
  }

  @override
  String workoutDeltaLoad(String change) {
    return 'الحمل $change';
  }

  @override
  String workoutDeltaReps(String change) {
    return 'التكرارات $change';
  }

  @override
  String workoutDeltaVolume(String change) {
    return 'الحجم $change';
  }

  @override
  String get workoutNoMeaningfulChange => 'لا تغيّر يُذكر';

  @override
  String workoutDurationHm(int hours, int minutes) {
    return '$hoursس $minutesد';
  }

  @override
  String workoutDurationM(int minutes) {
    return '$minutesد';
  }

  @override
  String workoutDurationH(String hours) {
    return '$hoursس';
  }

  @override
  String get askTitle => 'اسأل';

  @override
  String get askNewChat => 'محادثة جديدة';

  @override
  String get askChatHistory => 'سجل المحادثات';

  @override
  String get askReplyStyle => 'أسلوب الرد';

  @override
  String get timeAgoNow => 'الآن';

  @override
  String timeAgoMinutes(int minutes) {
    return '$minutes د';
  }

  @override
  String timeAgoHours(int hours) {
    return '$hours س';
  }

  @override
  String timeAgoDays(int days) {
    return '$days ي';
  }

  @override
  String get askReplyStyleConcise => 'موجز';

  @override
  String get askReplyStyleBalanced => 'متوازن';

  @override
  String get askReplyStyleDetailed => 'مفصّل';

  @override
  String get askChats => 'المحادثات';

  @override
  String get askNoChats => 'لا توجد محادثات بعد.';

  @override
  String get askNameItHint =>
      'سمِّها لتجدها لاحقًا — أو اتركها فارغة وستأخذ اسمها من أول رسالة.';

  @override
  String get askNamePlaceholder => 'مثال: تعديلات التمرين';

  @override
  String get askStartChatting => 'ابدأ المحادثة';

  @override
  String get askDeleteChatTitle => 'حذف هذه المحادثة؟';

  @override
  String askDeleteChatBody(String title) {
    return 'سيؤدي هذا إلى حذف \"$title\" وكل ما فيها نهائيًا. لا يمكن التراجع.';
  }

  @override
  String get askDeleteChatConfirm => 'حذف المحادثة';

  @override
  String get askGreeting => 'أهلًا، أنا ZIVO.';

  @override
  String get askIntro =>
      'التدريب والتغذية والمصروفات. اسألني أي شيء — أو دعني أسجّله لك.';

  @override
  String get askSuggestSpend => 'كم أنفقت هذا الأسبوع؟';

  @override
  String get askSuggestTraining => 'كيف يسير تدريبي؟';

  @override
  String get askSuggestDiet => 'ماذا تبقّى في نظامي الغذائي اليوم؟';

  @override
  String get askSuggestWeek => 'لخّص أسبوعي';

  @override
  String get askUnreachableTitle => 'تعذّر الوصول إلى ZIVO';

  @override
  String get askUnreachableBody => 'لم تُرسل رسالتك.';

  @override
  String get askRetry => 'إعادة المحاولة';

  @override
  String get askSaveFailed => 'تعذّر الحفظ — حاول مرة أخرى.';

  @override
  String get askActionFailed => 'تعذّر تنفيذ ذلك الآن. حاول مرة أخرى.';

  @override
  String get askThinking => 'يفكّر…';

  @override
  String get askUnderstanding => 'يفهم طلبك…';

  @override
  String get askWorking => 'يعمل…';

  @override
  String get askPreparingChange => 'يجهّز التعديل…';

  @override
  String get askStillWorking => 'ما زال يعمل على هذه…';

  @override
  String get askReadingDay => 'يقرأ يومك…';

  @override
  String get askReadingDiet => 'يقرأ نظامك الغذائي اليوم…';

  @override
  String get askReadingTraining => 'يقرأ تدريبك…';

  @override
  String get askReadingSpending => 'يقرأ مصروفاتك…';

  @override
  String get askSummarisingWeek => 'يلخّص أسبوعك…';

  @override
  String get askLookingUpFood => 'يبحث عن هذا الطعام…';

  @override
  String get askCalculating => 'يحسب الأرقام…';

  @override
  String get askProposalConfirmed => 'تم التأكيد';

  @override
  String get askProposalCancelled => 'أُلغيت';

  @override
  String get askProposalExpired => 'انتهت صلاحيتها';

  @override
  String get askProposalConfirm => 'تأكيد';

  @override
  String get askActionNewExpense => 'مصروف جديد';

  @override
  String get askActionEditExpense => 'تعديل مصروف';

  @override
  String get askActionDeleteExpense => 'حذف مصروف';

  @override
  String get askActionDietPlan => 'خطة التغذية';

  @override
  String get askActionLogFood => 'تسجيل طعام';

  @override
  String get askActionSuggestion => 'اقتراح';

  @override
  String askFoodCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count طعام',
      many: '$count طعامًا',
      few: '$count أطعمة',
      two: 'طعامان',
      one: 'طعام واحد',
      zero: 'لا أطعمة',
    );
    return '$_temp0';
  }

  @override
  String askKcalTotal(String total) {
    return '$total سعرة';
  }

  @override
  String get askVoiceUnavailable => 'الإدخال الصوتي غير متاح حاليًا.';

  @override
  String get askMicPermission => 'فعّل إذن الميكروفون لاستخدام الإدخال الصوتي.';

  @override
  String get askMicStartFailed => 'تعذّر تشغيل الميكروفون — حاول مرة أخرى.';

  @override
  String get askDidntCatchThat => 'لم أسمع ذلك — أعد التسجيل.';

  @override
  String get askTranscribeFailed =>
      'تعذّر تحويل الصوت إلى نص — تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get askTranscribeTimeout =>
      'استغرق ذلك وقتًا طويلًا — تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get askNothingCameThrough => 'لم يصل شيء — حاول مرة أخرى.';

  @override
  String get askTranscribing => 'يحوّل الصوت إلى نص…';

  @override
  String get askDiscardRecording => 'تجاهل التسجيل';

  @override
  String get askDiscardVoiceNote => 'تجاهل الملاحظة الصوتية';

  @override
  String get askTryAgain => 'حاول مرة أخرى';

  @override
  String askSecondsElapsed(int seconds) {
    return ' · $seconds ث';
  }

  @override
  String get askComposerHint => 'اسأل ZIVO…';

  @override
  String get askRecordVoiceNote => 'سجّل ملاحظة صوتية';

  @override
  String get askSilenceHint => 'لا أسمعك بعد — اقترب من الميكروفون.';

  @override
  String get askVoiceLog => 'تسجيل صوتي';

  @override
  String get askVoiceLogSubtitle =>
      'قلها مرة واحدة — ستصل إلى \"اسأل\" جاهزة للإرسال.';

  @override
  String get askTapAndSpeak => 'اضغط وتحدّث';

  @override
  String get askVoiceExamples =>
      '\"سجّل ٤٠ جنيه موقف سيارات\" · \"أنهيت تمرين الصدر\"';

  @override
  String get profileName => 'الاسم';

  @override
  String get profileDateOfBirth => 'تاريخ الميلاد';

  @override
  String get profileEmail => 'البريد الإلكتروني';

  @override
  String get profileCompleteTitle => 'أكمل ملفك';

  @override
  String get profileCompleteSubtitle => 'تفصيلان بسيطان لتخصيص ZIVO.';

  @override
  String get profileSaveFailed => 'تعذّر حفظ ملفك. حاول مرة أخرى.';

  @override
  String get profileUseAnotherAccount => 'استخدم حسابًا آخر';

  @override
  String get actionContinue => 'متابعة';

  @override
  String get profileSettings => 'الإعدادات';

  @override
  String get profileAccountCaps => 'الحساب';

  @override
  String get profileSignInCaps => 'تسجيل الدخول';

  @override
  String get profileEditName => 'تعديل الاسم';

  @override
  String get profileYourName => 'اسمك';

  @override
  String get profileSignedIn => 'مسجّل الدخول';

  @override
  String get profileVerifiedCaps => 'موثّق';

  @override
  String get profileUnverifiedCaps => 'غير موثّق';

  @override
  String get profileConnectedCaps => 'مرتبط';

  @override
  String get profileEmailAndPassword => 'البريد وكلمة المرور';

  @override
  String profileDobWithAge(String date, int age) {
    return '$date · $age';
  }

  @override
  String get profileStatSessions => 'الجلسات';

  @override
  String get profileStatMonthsIn => 'أشهر معنا';

  @override
  String get profileStatLifetime => 'الإجمالي';

  @override
  String get profileAbout => 'نبذة';

  @override
  String get profileAboutEmpty => 'أضف بضع كلمات عن نفسك.';

  @override
  String get profileAboutHint => 'بضع كلمات عن نفسك…';

  @override
  String profileCharCount(int used, int max) {
    return '$used / $max';
  }

  @override
  String get profilePhotoTitle => 'صورة الملف';

  @override
  String get profileChoosePhoto => 'اختر صورة';

  @override
  String get profileRemovePhoto => 'إزالة الصورة';

  @override
  String get profileCropTitle => 'حرّك وكبّر';

  @override
  String get profileCropDone => 'اختيار';

  @override
  String get profileEditPhoto => 'تعديل الصورة';

  @override
  String get dietGoalFatLoss => 'خسارة دهون';

  @override
  String get dietGoalMaintain => 'الحفاظ على الوزن';

  @override
  String get dietGoalMuscleGain => 'بناء عضل';

  @override
  String get dietGoalRecomp => 'إعادة تكوين';

  @override
  String get dietGoalFatLossDetail =>
      'تناول أقل من احتياجك للحفاظ مع بقاء البروتين مرتفعًا لخسارة الدهون.';

  @override
  String get dietGoalMaintainDetail =>
      'حافظ على وزنك عند سعرات الحفاظ تقريبًا.';

  @override
  String get dietGoalMuscleGainDetail =>
      'تناول أكثر من احتياجك للحفاظ لدعم بناء العضل.';

  @override
  String get dietGoalRecompDetail =>
      'أبقِ السعرات قرب الحفاظ مع بروتين كافٍ للبناء مع خسارة الدهون.';

  @override
  String get dietTargetSourceManual => 'أنت حدّدته';

  @override
  String get dietTargetSourceCalculated => 'محسوب من بيانات جسمك';

  @override
  String get dietTargetSourcePlan => 'مأخوذ من إجمالي خطتك اليومي';

  @override
  String get dietCalibrationNeedsWeighIns => 'قياسَي وزن';

  @override
  String dietCalibrationNeedsLongerWindow(int days) {
    return 'قياسَي وزن بينهما $days يومًا على الأقل';
  }

  @override
  String get dietCalibrationNeedsMoreDays => 'أيامًا أكثر من تسجيل الطعام';

  @override
  String get dietMacroProtein => 'بروتين';

  @override
  String get dietMacroCarbs => 'كربوهيدرات';

  @override
  String get dietMacroFat => 'دهون';

  @override
  String get dietTodaySoFar => 'اليوم حتى الآن';

  @override
  String dietKcalEaten(String kcal) {
    return '$kcal سعرة مأكولة';
  }

  @override
  String get dietYourTarget => 'هدفك';

  @override
  String get dietMacrosToday => 'الماكروز اليوم';

  @override
  String get dietWhatPlanDoes => 'ماذا تفعل هذه الخطة';

  @override
  String get dietTodaysRead => 'قراءة اليوم';

  @override
  String get dietFullPlan => 'الخطة كاملة';

  @override
  String dietDayCountCaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يومًا',
      few: '$count أيام',
      two: 'يومان',
      one: 'يوم واحد',
    );
    return '$_temp0';
  }

  @override
  String get dietNoTargetBody =>
      'حدّد هدفًا وتتحوّل الأرقام أعلاه إلى تقدّم نحوه — ويصبح بإمكان مدرّبك أن يخبرك أين أنت.';

  @override
  String dietUseThisPlanKcal(String kcal) {
    return 'استخدم $kcal سعرة من هذه الخطة';
  }

  @override
  String dietGoalKcalPerDayCaps(String goal, int kcal) {
    return '$goal · $kcal سعرة/يوم';
  }

  @override
  String dietBelowSafeFloor(String source, int kcal) {
    return '$source · أقل من $kcal سعرة — يُستحسن مراجعة مختص';
  }

  @override
  String get dietGainOrLose => 'هل تزيدك هذه الخطة وزنًا أم تنقصك؟';

  @override
  String dietNeedsToWorkOut(String missing) {
    return 'يحتاج ZIVO إلى $missing ليحسبها.';
  }

  @override
  String dietListTwo(String first, String second) {
    return '$first و$second';
  }

  @override
  String dietListMany(String leading, String last) {
    return '$leading و$last';
  }

  @override
  String get dietThisPlanCaps => 'هذه الخطة';

  @override
  String get dietBodyDataCaps => 'بيانات الجسم';

  @override
  String dietAveragedOver(int counted, int missing) {
    String _temp0 = intl.Intl.pluralLogic(
      counted,
      locale: localeName,
      other: '$counted يومًا',
      few: '$counted أيام',
      two: 'يومين',
      one: 'يوم واحد',
    );
    String _temp1 = intl.Intl.pluralLogic(
      missing,
      locale: localeName,
      other: '$missing يومًا بلا',
      few: '$missing أيام بلا',
      two: 'يومان بلا',
      one: 'يوم واحد بلا',
    );
    return 'بمتوسط $_temp0؛ $_temp1 أرقام سعرات.';
  }

  @override
  String dietProteinPerKg(String grams) {
    return 'البروتين $grams جم لكل كجم من وزن الجسم.';
  }

  @override
  String dietStaleWeighIn(int days) {
    return 'آخر قياس لوزنك عمره $days يومًا — الوزن يحدّد هذا الرقم، لذا يستحق التحديث.';
  }

  @override
  String dietUnderSafeFloor(int kcal) {
    return 'هذه الخطة أقل من $kcal سعرة يوميًا. الاستمرار عند هذا الحد شأن طبيب، لا تطبيق.';
  }

  @override
  String dietCalibrationPrompt(String missing) {
    return 'سجّل $missing ليقيس ZIVO ما تحرقه فعلًا بدل تقديره.';
  }

  @override
  String dietMeasuredDisagrees(int days, int measured, int used) {
    return 'آخر $days يومًا تقول إنك تحرق نحو $measured — لا $used أعلاه. يستحق التحديث.';
  }

  @override
  String dietMeasuredFrom(int days, int intake, String change) {
    return 'مقيس من آخر $days يومًا: $intake سعرة يوميًا، $change.';
  }

  @override
  String get dietWeightSteady => 'الوزن ثابت';

  @override
  String dietWeightUp(String kg) {
    return 'الوزن زاد $kg كجم';
  }

  @override
  String dietWeightDown(String kg) {
    return 'الوزن نقص $kg كجم';
  }

  @override
  String dietMacroProgress(String eaten, String target) {
    return '$eaten/$target جم';
  }

  @override
  String dietDayKcal(String kcal) {
    return '$kcal سعرة';
  }

  @override
  String get dietMissingWeight => 'وزنك الحالي';

  @override
  String get dietMissingHeight => 'طولك';

  @override
  String get dietMissingSex => 'معادلة الأيض التي يستخدمها ZIVO';

  @override
  String get dietMissingActivity => 'مدى نشاط أسبوعك';

  @override
  String get dietMissingDateOfBirth => 'تاريخ ميلادك';

  @override
  String get dietSourceUsda => 'USDA FoodData Central';

  @override
  String get dietSourceUserCustom => 'طعامك المخصّص';

  @override
  String get dietSourcePlan => 'خطتك الغذائية';

  @override
  String get dietNoPlanYetHeadline => 'لا توجد خطة غذائية بعد.';

  @override
  String get dietNotFollowingHeadline => 'أنت لا تتبع أي خطة.';

  @override
  String get dietNoPlanYetBody =>
      'استورد مستندًا أو صورة، أو قلها بصوتك، أو اكتبها، أو ابنِ واحدة يدويًا — وسأكمل السعرات والماكروز.';

  @override
  String dietArchivedPlans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count خطة مؤرشفة — أعِد واحدة أو أضف غيرها.',
      few: '$count خطط مؤرشفة — أعِد واحدة أو أضف غيرها.',
      two: 'خطتان مؤرشفتان — أعِد واحدة أو أضف غيرها.',
      one: 'خطة واحدة مؤرشفة — أعِد واحدة أو أضف غيرها.',
    );
    return '$_temp0';
  }

  @override
  String get dietSeeYourPlans => 'اعرض خططك';

  @override
  String get dietFromYourPlan => 'من خطتك';

  @override
  String dietQuantityUnit(String quantity, String unit) {
    return '$quantity $unit';
  }

  @override
  String dietKcalLeftOfTarget(String kcal) {
    return 'بقي $kcal سعرة من هدفك';
  }

  @override
  String dietKcalLeftOfPlan(String kcal) {
    return 'بقي $kcal سعرة من الخطة';
  }

  @override
  String dietKcalOverTarget(String kcal) {
    return 'تجاوزت هدفك بـ $kcal سعرة';
  }

  @override
  String dietMealsEaten(int eaten, int total) {
    return '$eaten من $total وجبات مأكولة';
  }

  @override
  String get dietNoCalorieDataCaps => 'لا بيانات سعرات بعد';

  @override
  String get dietKcalOverCaps => 'سعرة زائدة';

  @override
  String get dietKcalLeftCaps => 'سعرة متبقية';

  @override
  String get dietKcalLeftOfPlanCaps => 'سعرة متبقية من الخطة';

  @override
  String get dietEstPrefixCaps => 'تقديري ';

  @override
  String dietItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
    );
    return '$_temp0';
  }

  @override
  String get dietViewDetails => 'عرض التفاصيل';

  @override
  String get dietActivitySedentary => 'قليل الحركة';

  @override
  String get dietActivityLight => 'خفيف';

  @override
  String get dietActivityModerate => 'متوسط';

  @override
  String get dietActivityHigh => 'عالٍ';

  @override
  String get dietActivityAthlete => 'عالٍ جدًا';

  @override
  String get dietActivitySedentaryDetail =>
      'عمل مكتبي، وقليل من التمرين المقصود';

  @override
  String get dietActivityLightDetail => 'تدريب ١–٣ أيام أسبوعيًا';

  @override
  String get dietActivityModerateDetail => 'تدريب ٣–٥ أيام أسبوعيًا';

  @override
  String get dietActivityHighDetail => 'تدريب ٦–٧ أيام أسبوعيًا';

  @override
  String get dietActivityAthleteDetail => 'تدريب شاق يوميًا، أو عمل بدني فوقه';

  @override
  String dietTargetBasisSummary(
    String weight,
    String activity,
    int maintenance,
  ) {
    return '$weight كجم · $activity · $maintenance سعرة للحفاظ';
  }

  @override
  String get dietSetYourTarget => 'حدّد هدفك';

  @override
  String get dietDailyTarget => 'الهدف اليومي';

  @override
  String get dietTargetsIntro =>
      'يعتمد مدرّبك على هذه الأرقام في كل ما يقوله. وحتى تُضبط، يمكنه وصف خطتك لا تقييم أدائك عليها.';

  @override
  String get dietGoal => 'الهدف';

  @override
  String get dietDailyNumbers => 'الأرقام اليومية';

  @override
  String get dietCalculatedCaps => 'محسوب';

  @override
  String get dietOnlyCaloriesRequired =>
      'السعرات وحدها مطلوبة. اترك أي ماكرو فارغًا إن كنت لا تتابعه — الفراغ يعني غير متابَع، لا صفرًا.';

  @override
  String get dietFillFieldsHint =>
      'يملأ الحقول بنقطة بداية يمكنك تعديلها. لا يُحفظ شيء حتى تضغط حفظ.';

  @override
  String dietBelowSafeWarning(int calories, int floor) {
    return '$calories سعرة أقل من $floor، وهو دون ما ينبغي أن يدرّب عليه ZIVO. يمكنك الحفظ، لكن الأكل عند هذا الحد يستحق مناقشته مع طبيب أو أخصائي تغذية أولًا.';
  }

  @override
  String dietCalculatedFrom(
    String weight,
    String activity,
    int bmr,
    int maintenance,
    String goal,
  ) {
    return 'من $weight كجم عند نشاط $activity: $bmr سعرة في الراحة، و$maintenance سعرة للحفاظ، معدّلة لـ$goal. هذه تقديرات لمتوسط الناس — عدّلها بحسب ما يقوله الميزان فعلًا.';
  }

  @override
  String get dietSexMale => 'ذكر';

  @override
  String get dietSexFemale => 'أنثى';

  @override
  String dietStaleWeighInPrompt(int days) {
    return 'آخر قياس لوزنك كان قبل $days يومًا. يُستحسن تسجيل واحد جديد أولًا.';
  }

  @override
  String dietKgValue(String value) {
    return '$value كجم';
  }

  @override
  String dietCmValue(int value) {
    return '$value سم';
  }

  @override
  String dietSearching(String source) {
    return 'يبحث في $source.';
  }

  @override
  String get dietFoodSearchHint => 'صدر دجاج، أرز، زيت زيتون…';

  @override
  String get dietEnterAmount => 'أدخل كمية.';

  @override
  String get dietEnterAmountAboveZero => 'أدخل كمية أكبر من صفر.';

  @override
  String dietKcalPer100g(int kcal) {
    return '$kcal سعرة / ١٠٠ جم';
  }

  @override
  String dietKcalPer100gTight(int kcal) {
    return '$kcal سعرة/١٠٠ جم';
  }

  @override
  String get dietTypeToSearch => 'اكتب اسم طعام للبحث.';

  @override
  String dietNoCatalogMatch(String query) {
    return 'لا شيء في الفهرس يطابق \"$query\".';
  }

  @override
  String get dietCatalogThinBody =>
      'إنه فهرس USDA، لذا فهو ضعيف في الأطعمة المحلية والمنزلية. بدل التخمين، عرّف ZIVO بهذا الطعام مرة وسيتذكّره.';

  @override
  String dietKcalValue(int kcal) {
    return '$kcal سعرة';
  }

  @override
  String dietMacroLine(String protein, String carbs, String fat, String grams) {
    return 'بروتين $protein جم · كربوهيدرات $carbs جم · دهون $fat جم · $grams جم';
  }

  @override
  String dietWeightOnlyFood(String unit) {
    return 'لا يملك ZIVO هذا الطعام إلا بالوزن — أدخله بالجرامات. تحويل $unit يعني تخمين الكثافة.';
  }

  @override
  String dietNoSuchUnit(String unit, String alternatives) {
    return 'لا يملك ZIVO وحدة $unit لهذا الطعام. استخدم الجرامات، أو: $alternatives';
  }

  @override
  String get dietCustomFoodHint =>
      'لكل ١٠٠ جم، من الملصق أو قياسك الخاص. يحفظها ZIVO باسمك ولا يستبدلها أبدًا.';

  @override
  String get dietMaintenanceCaps => 'سعرات الحفاظ';

  @override
  String dietKcalPerDay(int kcal) {
    return '$kcal سعرة يوميًا';
  }

  @override
  String get dietMaintenanceGiven => 'الرقم الذي أدخلته. يستخدمه ZIVO كما هو.';

  @override
  String get dietMaintenanceEstimated =>
      'مقدّر من هذه الأرقام — متوسط لعموم الناس، لا قياسًا لك أنت.';

  @override
  String dietDaysAgo(int days) {
    return 'قبل $days يومًا';
  }

  @override
  String dietWeeksAgo(int weeks) {
    return 'قبل $weeks أسابيع';
  }

  @override
  String dietMonthsAgo(int months) {
    return 'قبل $months أشهر';
  }

  @override
  String get dietCuisineEgyptian => 'مصري';

  @override
  String get dietCuisineMediterranean => 'متوسطي';

  @override
  String get dietCuisineLevantine => 'شامي';

  @override
  String get dietCuisineIndian => 'هندي';

  @override
  String get dietCuisineAsian => 'آسيوي';

  @override
  String get dietCuisineWestern => 'غربي';

  @override
  String get dietImportOneRun =>
      'كل عملية إما تقرأ مادة أو تصمّم خطة — لا الاثنين معًا.';

  @override
  String get dietGeneratingFoods => 'يختار أطعمة تحبها…';

  @override
  String get dietGeneratingCalories => 'يبحث عن السعرات الحقيقية لكل منها…';

  @override
  String get dietGeneratingPortions => 'يضبط الحصص على هدفك…';

  @override
  String get dietFileReadFailed => 'تعذّر قراءة هذا الملف.';

  @override
  String dietFileTooLarge(int mb) {
    return 'هذا الملف كبير جدًا — اختر واحدًا أقل من $mb ميجابايت.';
  }

  @override
  String get dietImportPlanTitle => 'استيراد خطة';

  @override
  String get dietBuildingYourPlan => 'يبني خطتك';

  @override
  String get dietReadingYourPlan => 'يقرأ خطتك';

  @override
  String get dietSelectYourPlan => 'اختر خطتك الغذائية';

  @override
  String get dietSelectYourPlanBody =>
      'اختر ملف PDF أو صورة لخطتك وسأحوّلها إلى خطة حقيقية قابلة للتعديل — مع تقدير السعرات والماكروز حيثما لا يذكرها المستند.';

  @override
  String get dietCouldntBuildPlan => 'تعذّر على ZIVO بناء تلك الخطة';

  @override
  String get dietNotADietPlan => 'لا يبدو هذا خطة غذائية';

  @override
  String get dietChooseDifferentFile => 'اختر ملفًا آخر';

  @override
  String get dietGoBackAndEdit => 'ارجع وعدّل';

  @override
  String get dietBuildManually => 'ابنِ الخطة يدويًا.';

  @override
  String get dietPreferencesIntro =>
      'يختار ZIVO الأطعمة ويبحث عن سعراتها الحقيقية — لا يخمّنها. أخبره بما تأكل وسيبني يومًا تراجعه قبل حفظ أي شيء.';

  @override
  String get dietMealsADay => 'وجبات يوميًا';

  @override
  String get dietMealsADayNote =>
      'السبب الأكبر في نجاح الخطة خلال أسبوع عمل أو فشلها.';

  @override
  String get dietKitchen => 'المطبخ';

  @override
  String get dietOptionalCaps => 'اختياري';

  @override
  String get dietNothingSavedUntilReview =>
      'لا يُحفظ شيء حتى تراجع الخطة وتضغط حفظ.';

  @override
  String dietSizedToTarget(int kcal) {
    return 'مضبوطة على هدفك — $kcal سعرة يوميًا.';
  }

  @override
  String get dietNoTargetToSizeTo =>
      'سيبني ZIVO الخطة على أي حال، لكن لا يوجد رقم يضبط عليه الحصص. حدّد هدفًا أولًا ليأتي اليوم مفصّلًا عليه.';

  @override
  String get dietOnePlanNote =>
      'خطة واحدة. استورد أو اكتب أخرى وستتمكّن من التبديل بينهما دون فقد أي منهما.';

  @override
  String dietManyPlansNote(int count) {
    return '$count خطط. واحدة فقط سارية في كل وقت — وشاشة التغذية تعرضها دائمًا.';
  }

  @override
  String get dietNoPlansYet => 'لا خطط بعد.';

  @override
  String dietDaysCaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يومًا',
      few: '$count أيام',
      two: 'يومان',
      one: 'يوم واحد',
    );
    return '$_temp0';
  }

  @override
  String dietKcalPerDayCaps(String kcal) {
    return '$kcal سعرة/يوم';
  }

  @override
  String get dietFollowingCaps => 'متبعة';

  @override
  String get dietArchivedCaps => 'مؤرشفة';

  @override
  String get dietDraftCaps => 'مسودة';

  @override
  String get dietWhatsInIt => 'ما بداخلها';

  @override
  String get dietNoItemsListed => 'لا عناصر مدرجة لهذه الوجبة.';

  @override
  String get dietMarkNotEaten => 'وضع علامة غير مأكولة';

  @override
  String get dietMarkEaten => 'تم — وضع علامة مأكولة';

  @override
  String get dietMacroP => 'ب';

  @override
  String get dietMacroC => 'ك';

  @override
  String get dietMacroF => 'د';

  @override
  String dietGramsValue(int grams) {
    return '$grams جم';
  }

  @override
  String get dietUsePlanNumbers => 'استخدم أرقام خطتك';

  @override
  String dietPlanAverageOverDays(String kcal, int days, String plan) {
    return '$kcal سعرة يوميًا، بمتوسط $days أيام من $plan.';
  }

  @override
  String dietPlanFrom(String kcal, String plan) {
    return '$kcal سعرة يوميًا، من $plan.';
  }

  @override
  String dietDaysWithoutCalories(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يومًا بلا أرقام سعرات وغير داخل في المتوسط.',
      few: '$count أيام بلا أرقام سعرات وغير داخلة في المتوسط.',
      two: 'يومان بلا أرقام سعرات وغير داخلين في المتوسط.',
      one: 'يوم واحد بلا أرقام سعرات وغير داخل في المتوسط.',
    );
    return '$_temp0';
  }

  @override
  String get dietWhatIsItFor => 'لأي غرض؟';

  @override
  String get dietWhyGoalMatters =>
      'السعرات نفسها تعني أشياء مختلفة بحسب ما تفعله. يحتاج ZIVO إلى هذا ليقول كيف أداؤك مقابلها.';

  @override
  String dietPlanBelowSafeFloor(int kcal) {
    return 'متوسط هذه الخطة أقل من $kcal سعرة يوميًا. اعتمادها هدفًا يستحق مناقشته مع طبيب أو أخصائي تغذية أولًا.';
  }

  @override
  String get dietEveryDay => 'كل يوم';

  @override
  String get dietRemoveDay => 'إزالة اليوم';

  @override
  String get dietRemoveMeal => 'إزالة الوجبة';

  @override
  String get dietRemoveItem => 'إزالة العنصر';

  @override
  String get dietUnitCaps => 'الوحدة';

  @override
  String get dietDescribeYourDiet => 'صف نظامك الغذائي';

  @override
  String get dietTypeItOut => 'اكتبها';

  @override
  String get dietDictateBody =>
      'قل أو اكتب ما تأكله في يوم — الوجبات والأطعمة والكميات التقريبية. يحوّلها ZIVO إلى خطة تراجعها قبل حفظ أي شيء.';

  @override
  String get dietDictateExample =>
      'مثال: \"الفطور ثلاث بيضات و٦٠ جرام شوفان. الغداء ٢٠٠ جرام دجاج مع أرز وسلطة.\"';

  @override
  String get dietHideCaps => 'إخفاء';

  @override
  String get dietWhyCaps => 'لماذا';

  @override
  String get dietSourceManual => 'مكتوبة يدويًا';

  @override
  String get dietSourcePdf => 'مستوردة من مستند';

  @override
  String get dietSourcePhoto => 'مستوردة من صورة';

  @override
  String get dietSourceDictated => 'مُملاة';

  @override
  String get dietSourceGenerated => 'بناها ZIVO';

  @override
  String get dateTodayLower => 'اليوم';

  @override
  String get dateYesterdayLower => 'أمس';

  @override
  String get mediaCapturedOnAnotherDevice => 'التُقطت على جهاز آخر';

  @override
  String get mediaOnAnotherBackupAccount => 'في حساب Drive آخر';

  @override
  String get storageTitle => 'التخزين والمزامنة';

  @override
  String get storageSectionBackup => 'النسخ والمزامنة';

  @override
  String get storageSectionInstant => 'المزامنة الفورية';

  @override
  String get storageSectionDevicePhotos => 'صور الجهاز';

  @override
  String get storageUploadToDrive => 'الرفع إلى Drive';

  @override
  String get storageSaveToPhotos => 'حفظ في الصور';

  @override
  String get storageAccountNote =>
      'كل حساب ZIVO يحتفظ بصوره في مجلد Drive خاص به، فلا تختلط الحسابات أبدًا — حتى لو استخدمت نفس حساب Google Drive.';

  @override
  String get storageOnThisDevice => 'على هذا الجهاز';

  @override
  String get storageLocalFirst => 'صورك محفوظة هنا أولًا، دائمًا.';

  @override
  String storageSavedHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صورة محفوظة هنا.',
      many: '$count صورة محفوظة هنا.',
      few: '$count صور محفوظة هنا.',
      two: 'صورتان محفوظتان هنا.',
      one: 'صورة واحدة محفوظة هنا.',
      zero: 'لا صور محفوظة هنا.',
    );
    return '$_temp0';
  }

  @override
  String get storageConnectDrive => 'وصّل Google Drive';

  @override
  String get storageBackUpNow => 'انسخ الآن';

  @override
  String get storageSync => 'مزامنة';

  @override
  String get storageDisconnect => 'فصل';

  @override
  String get storageUnavailableInBuild => 'غير متاح في هذه النسخة';

  @override
  String get storageConnectedOnDevice => 'متصل على هذا الجهاز';

  @override
  String get storageNotConnectedOnDevice => 'غير متصل على هذا الجهاز';

  @override
  String get storageConnectFailed => 'تعذّر الاتصال بـ Google Drive.';

  @override
  String get storageConnectedToast => 'تم توصيل Google Drive على هذا الجهاز.';

  @override
  String get storageDisconnectedToast => 'تم فصل Google Drive عن هذا الجهاز.';

  @override
  String get storageAlreadyBackedUp => 'كل شيء منسوخ احتياطيًا بالفعل.';

  @override
  String get storageNothingNew => 'لا جديد للتنزيل.';

  @override
  String storageBackedUpToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم نسخ $count صورة إلى Drive.',
      many: 'تم نسخ $count صورة إلى Drive.',
      few: 'تم نسخ $count صور إلى Drive.',
      two: 'تم نسخ صورتين إلى Drive.',
      one: 'تم نسخ صورة واحدة إلى Drive.',
      zero: 'لم تُنسخ أي صور.',
    );
    return '$_temp0';
  }

  @override
  String storageDownloadedToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تنزيل $count صورة من Drive.',
      many: 'تم تنزيل $count صورة من Drive.',
      few: 'تم تنزيل $count صور من Drive.',
      two: 'تم تنزيل صورتين من Drive.',
      one: 'تم تنزيل صورة واحدة من Drive.',
      zero: 'لم تُنزّل أي صور.',
    );
    return '$_temp0';
  }

  @override
  String storageOtherAccountTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صورة في حساب Google آخر',
      many: '$count صورة في حساب Google آخر',
      few: '$count صور في حساب Google آخر',
      two: 'صورتان في حساب Google آخر',
      one: 'صورة واحدة في حساب Google آخر',
      zero: 'لا صور في حساب Google آخر',
    );
    return '$_temp0';
  }

  @override
  String get storageOtherAccountBody =>
      'نُسخت قبل تبديل الحسابات. «انسخ الآن» ينسخ ما زال موجودًا على هذا الجهاز؛ أما الباقي فأعد توصيل ذلك الحساب.';

  @override
  String get storageBackingUp => 'جارٍ النسخ…';

  @override
  String get storageSyncing => 'جارٍ المزامنة…';

  @override
  String get storageCheckingPhotos => 'جارٍ فحص صورك…';

  @override
  String storageProgressCount(int done, int total) {
    return '$done من $total صورة';
  }

  @override
  String get storageNothingYetTitle => 'لا شيء للنسخ بعد';

  @override
  String get storageNothingYetBody => 'الصور التي تضيفها ستُنسخ هنا.';

  @override
  String get storageAllBackedUpTitle => 'كل شيء منسوخ';

  @override
  String storageAllSafeBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صورة في أمان داخل Google Drive.',
      many: '$count صورة في أمان داخل Google Drive.',
      few: '$count صور في أمان داخل Google Drive.',
      two: 'صورتان في أمان داخل Google Drive.',
      one: 'صورة واحدة في أمان داخل Google Drive.',
      zero: 'لا صور بعد.',
    );
    return '$_temp0';
  }

  @override
  String storagePartialTitle(int backedUp, int total) {
    return '$backedUp من $total منسوخة';
  }

  @override
  String storagePendingBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صورة في انتظار النسخ.',
      many: '$count صورة في انتظار النسخ.',
      few: '$count صور في انتظار النسخ.',
      two: 'صورتان في انتظار النسخ.',
      one: 'صورة واحدة في انتظار النسخ.',
      zero: 'لا صور في الانتظار.',
    );
    return '$_temp0';
  }

  @override
  String get sessionNoExercises => 'لم تُسجَّل أي تمارين.';

  @override
  String get sessionDetailsTitle => 'تفاصيل الجلسة';

  @override
  String get sessionDeleteAction => 'حذف الجلسة';

  @override
  String get sessionStatusCompleted => 'مكتملة';

  @override
  String get sessionStatusActive => 'جارية';

  @override
  String get sessionStatusAbandoned => 'غير مكتملة';

  @override
  String get sessionStatDuration => 'المدة';

  @override
  String get sessionStatTime => 'الوقت';

  @override
  String get sessionStatExercises => 'التمارين';

  @override
  String get sessionStatSetsDone => 'المجموعات المنجزة';

  @override
  String sessionSetNumber(int index) {
    return 'المجموعة $index';
  }

  @override
  String get sessionSetSkipped => 'متخطاة';

  @override
  String sessionSetRpe(String value) {
    return 'RPE $value';
  }

  @override
  String sessionSetWeightByReps(String weight, String reps) {
    return '$weight × $reps';
  }

  @override
  String sessionSetRepsOnly(int reps) {
    String _temp0 = intl.Intl.pluralLogic(
      reps,
      locale: localeName,
      other: '$reps تكرار',
      many: '$reps تكرارًا',
      few: '$reps تكرارات',
      two: 'تكراران',
      one: 'تكرار واحد',
      zero: 'لا تكرارات',
    );
    return '$_temp0';
  }

  @override
  String sessionSetRepsUnknown(String reps) {
    return '$reps تكرار';
  }

  @override
  String sessionTimeRange(String start, String end) {
    return '$start–$end';
  }

  @override
  String get splitsTitle => 'الجداول';

  @override
  String get splitNewAction => 'جدول جديد';

  @override
  String splitCopyName(String name) {
    return 'نسخة من $name';
  }

  @override
  String splitDayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم',
      many: '$count يومًا',
      few: '$count أيام',
      two: 'يومان',
      one: 'يوم واحد',
      zero: 'لا أيام',
    );
    return '$_temp0';
  }

  @override
  String splitMeta(String days, String exercises) {
    return '$days · $exercises';
  }

  @override
  String get splitSetActive => 'اجعله النشط';

  @override
  String get actionDuplicate => 'تكرار';

  @override
  String get splitActiveBadge => 'نشط';

  @override
  String get splitsEmptyTitle => 'لا توجد جداول بعد.';

  @override
  String get splitsEmptyBody => 'اضغط + لبناء أول جدول لك.';

  @override
  String workoutThisWeekCount(int count) {
    return '$count هذا الأسبوع';
  }

  @override
  String get workoutLogTodaysWeight => 'سجّل وزن اليوم';

  @override
  String get workoutWeighInFailed =>
      'تعذّر حفظ الوزن — تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get workoutNoPlanImportHint =>
      'استورد ملف PDF أو صورة وسأحوّلها إلى جدول حقيقي، أو ابنِ واحدًا من الصفر.';

  @override
  String workoutWeightDeltaWindow(String delta) {
    return '$delta كجم · ٣٠ يومًا';
  }

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsSectionApp => 'التطبيق';

  @override
  String get settingsSectionAccount => 'الحساب';

  @override
  String get settingsSectionMusic => 'الموسيقى';

  @override
  String get settingsSectionMedia => 'الوسائط';

  @override
  String get settingsTheme => 'المظهر';

  @override
  String get settingsThemeDark => 'داكن';

  @override
  String get settingsVersion => 'الإصدار';

  @override
  String get settingsBuild => 'النسخة';

  @override
  String get settingsPrivacyPolicy => 'سياسة الخصوصية';

  @override
  String get settingsChangePassword => 'تغيير كلمة المرور';

  @override
  String get settingsDeleteAccount => 'حذف الحساب';

  @override
  String get settingsSignOut => 'تسجيل الخروج';

  @override
  String settingsVersionLine(String version, String build) {
    return 'الإصدار $version ($build)';
  }

  @override
  String settingsVersionValue(String version, String build) {
    return '$version ($build)';
  }

  @override
  String get settingsStorageSync => 'التخزين والمزامنة';

  @override
  String get settingsStorageSyncValue => 'الصور · Drive';

  @override
  String get connectedConnectedPaused => 'متصل · متوقف مؤقتًا';

  @override
  String get connectedConnectedPlaying => 'متصل · قيد التشغيل';

  @override
  String get authEmail => 'البريد الإلكتروني';

  @override
  String get authPassword => 'كلمة المرور';

  @override
  String get authNameOptional => 'الاسم (اختياري)';

  @override
  String get authConfirmPassword => 'تأكيد كلمة المرور';

  @override
  String get authNewPassword => 'كلمة المرور الجديدة';

  @override
  String get authCurrentPassword => 'كلمة المرور الحالية';

  @override
  String get authConfirmNewPassword => 'تأكيد كلمة المرور الجديدة';

  @override
  String get authSignIn => 'تسجيل الدخول';

  @override
  String get authCreateAccount => 'إنشاء حساب';

  @override
  String get authForgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get authHaveAccount => 'لديك حساب بالفعل؟  ';

  @override
  String get authNewToZivo => 'جديد على ZIVO؟  ';

  @override
  String get authTitleSignUp => 'اصنع مساحتك.';

  @override
  String get authTitleSignIn => 'يومك كله، في مكان واحد.';

  @override
  String get authSignInWithApple => 'تسجيل الدخول عبر Apple';

  @override
  String get authContinueWithGoogle => 'المتابعة عبر Google';

  @override
  String get authPasswordUpdated => 'تم تحديث كلمة المرور.';

  @override
  String get authPasswordUpdatedSignIn =>
      'تم تحديث كلمة المرور. سجّل الدخول بكلمة المرور الجديدة.';

  @override
  String authShowField(String label) {
    return 'إظهار $label';
  }

  @override
  String authHideField(String label) {
    return 'إخفاء $label';
  }

  @override
  String authOtpFieldLabel(int length) {
    return 'رمز تحقق من $length أرقام';
  }

  @override
  String authCodeWrongWithAttempts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الرمز غير صحيح. بقيت $count محاولة.',
      many: 'الرمز غير صحيح. بقيت $count محاولة.',
      few: 'الرمز غير صحيح. بقيت $count محاولات.',
      two: 'الرمز غير صحيح. بقيت محاولتان.',
      one: 'الرمز غير صحيح. بقيت محاولة واحدة.',
      zero: 'الرمز غير صحيح. لا محاولات متبقية.',
    );
    return '$_temp0';
  }

  @override
  String get authCodeWrong => 'الرمز غير صحيح.';

  @override
  String get authCodeExpired => 'انتهت صلاحية الرمز. أرسل رمزًا جديدًا.';

  @override
  String get authCodeTooManyAttempts =>
      'محاولات كثيرة جدًا. أرسل رمزًا جديدًا.';

  @override
  String get authCodeSent => 'رمز جديد في الطريق.';

  @override
  String get authSending => 'جارٍ الإرسال…';

  @override
  String authResendIn(int seconds) {
    return 'إعادة الإرسال خلال $seconds ث';
  }

  @override
  String get authResendCode => 'إعادة إرسال الرمز';

  @override
  String get authDidntGetIt => 'لم يصلك؟  ';

  @override
  String get authResetTitle => 'إعادة تعيين كلمة المرور';

  @override
  String get authResetSubtitle => 'أدخل بريد حسابك وسنرسل لك رمزًا من 6 أرقام.';

  @override
  String get authSendCode => 'إرسال الرمز';

  @override
  String get authEnterCode => 'أدخل الرمز';

  @override
  String get authCodeSentTo =>
      'أدخل الرمز المكوّن من 6 أرقام الذي أرسلناه إلى\n';

  @override
  String get authThenChoosePassword => '، ثم اختر كلمة مرور جديدة.';

  @override
  String get authResetPassword => 'إعادة تعيين كلمة المرور';

  @override
  String get authEmailLooksWrong => 'يبدو أن البريد الإلكتروني غير صحيح.';

  @override
  String get authVerifyTitle => 'تأكيد بريدك الإلكتروني';

  @override
  String get authVerify => 'تأكيد';

  @override
  String get authUseAnotherAccount => 'استخدام حساب آخر';

  @override
  String get authChangePasswordSubtitle =>
      'أكّد هويتك، ثم اختر كلمة مرور جديدة.';

  @override
  String get authConfirmItsYou => 'أكّد هويتك';

  @override
  String get authUpdatePassword => 'تحديث كلمة المرور';

  @override
  String get authDeleteAccountBody =>
      'سيؤدي هذا إلى حذف حسابك وكل ما فيه نهائيًا — التمارين والتغذية واللحظات والمصروفات والملف الشخصي. لا يمكن التراجع عن هذا.';

  @override
  String get authDeleteConfirmPassword => 'أدخل كلمة المرور للتأكيد';

  @override
  String get authDeleteMyAccount => 'احذف حسابي';

  @override
  String get authPasswordStrength => 'قوة كلمة المرور';

  @override
  String get authPasswordStrong => 'قوية';

  @override
  String get authPasswordAlmost => 'شبه قوية';

  @override
  String get authPasswordWeak => 'ضعيفة';

  @override
  String get authPasswordsMatch => 'كلمتا المرور متطابقتان';

  @override
  String get authPasswordsDontMatch => 'كلمتا المرور غير متطابقتين';

  @override
  String authRuleState(String rule, String state) {
    return '$rule: $state';
  }

  @override
  String get authRuleMet => 'مستوفاة';

  @override
  String get authRuleNotMet => 'غير مستوفاة';

  @override
  String get authRuleMinLength => '٨ أحرف على الأقل';

  @override
  String get authRuleMinLengthShort => '٨+ أحرف';

  @override
  String get authRuleUppercase => 'حرف كبير واحد';

  @override
  String get authRuleUppercaseShort => 'حرف كبير';

  @override
  String get authRuleLowercase => 'حرف صغير واحد';

  @override
  String get authRuleLowercaseShort => 'حرف صغير';

  @override
  String get authRuleNumber => 'رقم واحد';

  @override
  String get authRuleNumberShort => 'رقم';

  @override
  String get settingsPermanent => 'نهائي';

  @override
  String get momentTakePhoto => 'التقاط صورة';

  @override
  String get momentChooseFromLibrary => 'اختيار من المعرض';

  @override
  String get momentEditPhoto => 'تعديل الصورة';

  @override
  String get momentEditTitle => 'تعديل اللحظة';

  @override
  String get momentNewTitle => 'لحظة جديدة';

  @override
  String get momentDeleteAction => 'حذف اللحظة';

  @override
  String get momentNoteHint => 'قل شيئًا…';

  @override
  String get momentSave => 'حفظ اللحظة';

  @override
  String get momentAdd => 'إضافة لحظة';

  @override
  String get momentAddPhoto => 'أضف صورة';

  @override
  String get momentRetake => 'إعادة الالتقاط';

  @override
  String get momentRemove => 'إزالة';

  @override
  String get momentSaveFailed => 'تعذّر حفظ تلك اللحظة.';

  @override
  String get momentDeleteFailed => 'تعذّر حذف تلك اللحظة.';

  @override
  String get momentsTitle => 'اللحظات';

  @override
  String get momentsFilterAll => 'الكل';

  @override
  String get momentsFilterPhotos => 'الصور';

  @override
  String get momentsFilterNotes => 'الملاحظات';

  @override
  String get momentsFilterCamera => 'الكاميرا';

  @override
  String get momentsFilterLibrary => 'المعرض';

  @override
  String get momentsEmptyTitle => 'لم يُسجَّل شيء بعد';

  @override
  String get momentsEmptyBody =>
      'صوّر تمرينًا أو وجبة أو قراءة ميزان — ترتبط اللحظات بالجلسة التي كنت فيها.';

  @override
  String get momentsEmptyCamera => 'لا صور من الكاميرا بعد.';

  @override
  String get momentsEmptyLibrary => 'لا شيء من معرضك بعد.';

  @override
  String get momentsEmptyPhotos => 'لا صور بعد.';

  @override
  String get momentsEmptyNotes => 'لا ملاحظات بعد.';

  @override
  String get momentsEmptyOther => 'لم يُسجَّل شيء آخر بعد';

  @override
  String get momentUntitled => 'بلا عنوان';

  @override
  String get momentUntitledFull => 'لحظة بلا عنوان';

  @override
  String get momentPhotoInfo => 'معلومات الصورة';

  @override
  String momentPhotoPosition(int index, int total) {
    return '$index من $total';
  }

  @override
  String get metaDate => 'التاريخ';

  @override
  String get metaTime => 'الوقت';

  @override
  String get metaTimeZone => 'المنطقة الزمنية';

  @override
  String get metaCapturedWith => 'التُقطت بواسطة';

  @override
  String get metaDimensions => 'الأبعاد';

  @override
  String get metaFileSize => 'حجم الملف';

  @override
  String get metaType => 'النوع';

  @override
  String get metaLocation => 'الموقع';

  @override
  String get metaBackup => 'النسخ الاحتياطي';

  @override
  String get metaOnThisDevice => 'على هذا الجهاز';

  @override
  String get metaInPhotos => 'الصور';

  @override
  String get metaNotBackedUp => 'لم يُنسخ احتياطيًا بعد';

  @override
  String get metaInDriveTapToDownload => 'في Google Drive — اضغط للتنزيل';

  @override
  String get captureSourceCamera => 'الكاميرا';

  @override
  String get captureSourceLibrary => 'معرض الصور';

  @override
  String get captureSourceUnknown => 'غير معروف';

  @override
  String get musicNowPlaying => 'قيد التشغيل الآن';

  @override
  String get musicClosePlayer => 'إغلاق المشغّل';

  @override
  String get musicReadOnly =>
      'التشغيل على جهاز آخر — عناصر التحكم هنا للعرض فقط.';

  @override
  String get musicPreviousTrack => 'المقطع السابق';

  @override
  String get musicNextTrack => 'المقطع التالي';

  @override
  String get musicShuffleOn => 'التشغيل العشوائي مفعّل';

  @override
  String get musicShuffleOff => 'التشغيل العشوائي متوقف';

  @override
  String get musicRepeatOff => 'التكرار متوقف';

  @override
  String get musicRepeatAll => 'تكرار الكل';

  @override
  String get musicRepeatOne => 'تكرار المقطع';

  @override
  String get musicAuthFailed =>
      'لم يصرّح Spotify بالاتصال. تأكد من تسجيل دخولك إلى Spotify ثم حاول مرة أخرى.';

  @override
  String get musicTryAgain => 'حاول مرة أخرى';

  @override
  String get musicPremiumRequired =>
      'يتطلب التحكم في التشغيل هنا اشتراك Spotify Premium.';

  @override
  String get musicConnectPrompt => 'وصّل Spotify لترى ما يعمل الآن.';

  @override
  String get musicConnectSpotify => 'وصّل Spotify';

  @override
  String musicTimeLeft(String time) {
    return 'بقي $time';
  }

  @override
  String musicStripMeta(String artist, String remaining) {
    return '$artist · $remaining';
  }

  @override
  String musicNowPlayingSemantics(String title, String artist) {
    return 'قيد التشغيل الآن: $title لـ $artist. افتح المشغّل.';
  }

  @override
  String musicBatteryPercent(int percent) {
    return '$percent%';
  }

  @override
  String get importCouldntReadFile => 'تعذّرت قراءة ذلك الملف.';

  @override
  String get importFileTooLarge =>
      'هذا الملف كبير جدًا — اختر ملفًا أصغر من 7 ميجابايت.';

  @override
  String get importSaveFailed =>
      'تعذّر حفظ الجدول — تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get importReviewTitle => 'مراجعة الاستيراد';

  @override
  String get importPlanTitle => 'استيراد جدول';

  @override
  String get importSelectTitle => 'اختر جدول تدريبك';

  @override
  String get importSelectBody =>
      'اختر ملف PDF أو صورة لجدولك وسأحوّله إلى جدول حقيقي قابل للتعديل.';

  @override
  String get importChooseDifferentFile => 'اختر ملفًا آخر';

  @override
  String get importStartOver => 'ابدأ من جديد';

  @override
  String get importNotAPlan => 'لا يبدو هذا كجدول تدريب';

  @override
  String get importGoBackAndEdit => 'ارجع وعدّل';

  @override
  String get importHeresWhatIFound => 'هذا ما وجدته';

  @override
  String get importDoingIt => 'جارٍ الاستيراد…';

  @override
  String get importThisSplit => 'استورد هذا الجدول';

  @override
  String get importEditBefore => 'عدّل قبل الاستيراد';

  @override
  String importDayHeading(String slot, String label) {
    return 'اليوم $slot · $label';
  }

  @override
  String get importNoExercisesForDay => 'لم يُعثر على تمارين لهذا اليوم.';

  @override
  String get importComplete => 'اكتمل الاستيراد';

  @override
  String importSummary(String name, String days, String exercises) {
    return 'تمت إضافة «$name» إلى جداولك — $days، $exercises.';
  }

  @override
  String importPlanShape(String days, String exercises) {
    return '$days · $exercises إجمالًا';
  }

  @override
  String get importBuildManually => 'ابنِ الجدول يدويًا.';

  @override
  String get exerciseEditTitle => 'تعديل التمرين';

  @override
  String get exerciseAddTitle => 'إضافة تمرين';

  @override
  String get exerciseName => 'الاسم';

  @override
  String get exerciseNameHint => 'بنش بريس';

  @override
  String get exerciseMuscleGroup => 'المجموعة العضلية (اختياري)';

  @override
  String get exerciseMuscleGroupHint => 'الصدر';

  @override
  String get exerciseSets => 'المجموعات';

  @override
  String get exerciseRepTarget => 'هدف التكرارات';

  @override
  String get exerciseTargetFixed => 'ثابت';

  @override
  String get exerciseTargetRange => 'نطاق';

  @override
  String get exerciseMinReps => 'أقل تكرارات';

  @override
  String get exerciseMaxReps => 'أكثر تكرارات';

  @override
  String get exerciseReps => 'التكرارات';

  @override
  String get exerciseWeightKg => 'الوزن (كجم)';

  @override
  String get exerciseSaveChanges => 'حفظ التغييرات';

  @override
  String get workoutCaptureSaveFailed => 'تعذّر حفظ ذلك التمرين.';

  @override
  String get workoutCaptureDeleteFailed => 'تعذّر حذف ذلك التمرين.';

  @override
  String get workoutCaptureEditTitle => 'تعديل التمرين';

  @override
  String get workoutCaptureNewTitle => 'تمرين جديد';

  @override
  String get workoutCaptureDelete => 'حذف التمرين';

  @override
  String get workoutCaptureNameHint => 'سمِّ هذه الجلسة';

  @override
  String get workoutCaptureSave => 'حفظ التمرين';

  @override
  String get workoutCaptureNoExercises => 'لا تمارين بعد.';

  @override
  String get workoutCaptureExerciseName => 'اسم التمرين';

  @override
  String get workoutCaptureRemove => 'إزالة';

  @override
  String get importAppCheckDebug =>
      'تعذّر على التطبيق التحقق من نفسه (App Check). سجّل رمز التصحيح لهذه النسخة في وحدة تحكم Firebase ثم حاول مرة أخرى.';

  @override
  String get importAppCheckFailed =>
      'تعذّر التحقق من تثبيت التطبيق. حاول مرة أخرى بعد قليل.';

  @override
  String get importServiceUnavailable =>
      'خدمة الاستيراد غير متاحة الآن — حاول لاحقًا.';

  @override
  String get importNetworkProblem =>
      'مشكلة في الشبكة أثناء الوصول إلى خدمة الاستيراد — تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String importCouldntRead(String manualFallback) {
    return 'تعذّرت قراءة هذا الجدول — جرّب صورة أو ملف PDF أوضح، أو $manualFallback';
  }

  @override
  String importUnsupportedFileType(String extension) {
    return 'نوع ملف غير مدعوم: $extension';
  }

  @override
  String get describeMicNeeded =>
      'يحتاج ZIVO إلى إذن الميكروفون لتدوين هذا. يمكنك الكتابة بدلًا من ذلك.';

  @override
  String get describeRecordFailed =>
      'تعذّر بدء التسجيل. يمكنك الكتابة بدلًا من ذلك.';

  @override
  String get describeNothingRecorded =>
      'لم يُسجَّل شيء. حاول مرة أخرى، أو اكتبه بدلًا من ذلك.';

  @override
  String get describeYourDescription => 'وصفك';

  @override
  String get describeCheckWords =>
      'راجع الكلمات قبل المتابعة — التفصيل الذي يُسمع خطأً يصبح رقمًا لاحقًا.';

  @override
  String get describeSayItInstead => 'قلها بدلًا من ذلك';

  @override
  String get describeAddMoreByVoice => 'أضف المزيد بالصوت';

  @override
  String get describeWritingItDown => 'جارٍ التدوين…';

  @override
  String get describeListening => 'يستمع';

  @override
  String get describeDiscard => 'تجاهل';

  @override
  String get importReadingDocument => 'جارٍ قراءة المستند…';

  @override
  String importFoundNamed(String name) {
    return 'تم العثور على «$name»…';
  }

  @override
  String get importAnalyzing => 'جارٍ تحليل جدولك';

  @override
  String get importBuildManuallyInstead => 'ابنِ يدويًا بدلًا من ذلك';

  @override
  String importSectionItems(String section, String items) {
    return '$section · $items';
  }

  @override
  String importItemCountDay(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم',
      many: '$count يومًا',
      few: '$count أيام',
      two: 'يومان',
      one: 'يوم واحد',
      zero: 'لا أيام',
    );
    return '$_temp0';
  }

  @override
  String importItemCountMeal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count وجبة',
      many: '$count وجبة',
      few: '$count وجبات',
      two: 'وجبتان',
      one: 'وجبة واحدة',
      zero: 'لا وجبات',
    );
    return '$_temp0';
  }

  @override
  String get workoutDescribeTitleVoice => 'صف تدريبك';

  @override
  String get workoutDescribeTitleType => 'اكتبه';

  @override
  String get workoutDescribeBody =>
      'قل أو اكتب جدولك — الأيام والتمارين والمجموعات والتكرارات لكل منها. يحوّله ZIVO إلى جدول حقيقي قابل للتعديل تراجعه قبل أن يُحفظ أي شيء.';

  @override
  String get workoutDescribeExample =>
      'مثال: «اليوم A دفع — بنش بريس 4 مجموعات من 8، بريس مائل بالدمبل 3 في 10، ثم كابل فلاي 3 في 15. اليوم B سحب…»';

  @override
  String get workoutDescribeHint => 'اليوم A دفع…';

  @override
  String get workoutDescribeSubmit => 'حوّل هذا إلى جدول';

  @override
  String get workoutDescribeDoneTalking => 'انتهيت من الكلام';

  @override
  String get addPlanTitle => 'أضف جدول تدريب';

  @override
  String get addPlanBody =>
      'مهما كانت طريقة إدخال جدولك، فإنه يصل إلى المحرر نفسه لمراجعته قبل أن يُحفظ أي شيء.';

  @override
  String get addPlanPdfTitle => 'ملف PDF أو صورة';

  @override
  String get addPlanPdfBody => 'جدول من مدرب، لقطة شاشة، صورة لصفحة';

  @override
  String get addPlanVoiceTitle => 'قلها بصوت عالٍ';

  @override
  String get addPlanVoiceBody => 'صف جدولك وسيدوّنه ZIVO';

  @override
  String get addPlanTypeTitle => 'اكتبه';

  @override
  String get addPlanTypeBody => 'اكتب جدولك في بضعة أسطر';

  @override
  String get addPlanManualTitle => 'ابنِ يدويًا';

  @override
  String get addPlanManualBody => 'أضف الأيام والتمارين بنفسك';

  @override
  String importItemCountExercise(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تمرين',
      many: '$count تمرينًا',
      few: '$count تمارين',
      two: 'تمرينان',
      one: 'تمرين واحد',
      zero: 'لا تمارين',
    );
    return '$_temp0';
  }

  @override
  String importItemCountGeneric(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
      zero: 'لا عناصر',
    );
    return '$_temp0';
  }

  @override
  String pulseTrainedFor(String day, int minutes) {
    return '$day · $minutes دقيقة';
  }

  @override
  String pulseUnderWay(String day) {
    return '$day · جارية';
  }

  @override
  String pulseStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'سلسلة $count يوم',
      many: 'سلسلة $count يومًا',
      few: 'سلسلة $count أيام',
      two: 'سلسلة يومين',
      one: 'سلسلة يوم واحد',
      zero: 'لا سلسلة',
    );
    return '$_temp0';
  }

  @override
  String pulseSessionsLast7(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جلسة · آخر ٧ أيام',
      many: '$count جلسة · آخر ٧ أيام',
      few: '$count جلسات · آخر ٧ أيام',
      two: 'جلستان · آخر ٧ أيام',
      one: 'جلسة واحدة · آخر ٧ أيام',
      zero: 'لا جلسات · آخر ٧ أيام',
    );
    return '$_temp0';
  }

  @override
  String pulseWeightSpan(int days) {
    return 'كجم · $days يوم';
  }

  @override
  String expenseSpentToday(String amount) {
    return '$amount أُنفقت اليوم';
  }

  @override
  String expenseAmountWithCurrency(String amount, String currency) {
    return '$amount $currency';
  }

  @override
  String expenseRowMeta(String time, String category) {
    return '$time · $category';
  }

  @override
  String get planEditSplitTitle => 'تعديل الجدول';

  @override
  String get planEditPlanTitle => 'تعديل خطة التمرين';

  @override
  String get planNewSplitTitle => 'جدول جديد';

  @override
  String get planNewPlanTitle => 'خطة تمرين جديدة';

  @override
  String get planDeleteSplit => 'حذف الجدول';

  @override
  String get planDeletePlan => 'حذف الخطة';

  @override
  String get planName => 'اسم الخطة';

  @override
  String get privacyTitle => 'الخصوصية';

  @override
  String privacyIntro(String date) {
    return 'كيف يتعامل ZIVO مع بياناتك.\nآخر تحديث $date.';
  }

  @override
  String get privacyOverviewLabel => 'نظرة عامة';

  @override
  String get privacyOverviewBody =>
      'ZIVO تطبيق شخصي وخاص لتنظيم أجزاء يومك — اللحظات والتمارين والتغذية والمصروفات وغيرها — في مكان واحد هادئ. توضّح هذه السياسة ما يخزّنه ZIVO، وكيف يُستخدم، والخيارات المتاحة لك.';

  @override
  String get privacyShortLabel => 'النسخة المختصرة';

  @override
  String get privacyShortBullet1 =>
      'محتواك خاص بحسابك ولا يُباع أو يُشارك لأغراض الإعلانات أبدًا.';

  @override
  String get privacyShortBullet2 =>
      'لا يستخدم ZIVO بياناتك أو محتواك لتدريب نماذج تابعة لجهات خارجية.';

  @override
  String get privacyShortBullet3 =>
      'تُحفظ النسخ الاحتياطية في حساب Google Drive الخاص بك، وتحت سيطرتك أنت.';

  @override
  String get privacyShortBullet4 =>
      'يمكنك حذف محتواك في أي وقت، من داخل التطبيق.';

  @override
  String get privacyAccountLabel => 'الحساب وتسجيل الدخول';

  @override
  String get privacyAccountBody =>
      'يستخدم ZIVO خدمة Firebase Authentication لتسجيل دخولك، مع خيارات Apple أو Google أو البريد الإلكتروني وكلمة المرور. وبحسب الطريقة التي تختارها، يتلقّى ZIVO تفاصيل أساسية عن الحساب مثل اسمك وبريدك الإلكتروني ومعرّف حساب فريد. هذا المعرّف هو ما يبقي كل جزء من بياناتك مقصورًا على حسابك وحده.';

  @override
  String get privacyOtpLabel => 'رموز التحقق بالبريد الإلكتروني';

  @override
  String get privacyOtpBody =>
      'إذا سجّلت الدخول بالبريد الإلكتروني، يرسل ZIVO رمز تحقق قصيرًا لتأكيد عنوانك. تُشفَّر الرموز قبل تخزينها، وتنتهي صلاحيتها خلال دقائق، ولا تُستخدم لأي غرض سوى التأكد من أن العنوان يخصّك.';

  @override
  String get privacyContentLabel => 'محتواك';

  @override
  String get privacyContentBody =>
      'كل ما تنشئه في ZIVO — اللحظات وخطط التمارين والجلسات وخطط التغذية وسجلاتها وسجلات المصروفات وقياسات الوزن وتفاصيل الملف الشخصي — يُخزَّن في حسابك ليتمكن التطبيق من عرضه عليك عبر أجهزتك. وهو خاص بك ولا يظهر لمستخدمين آخرين.';

  @override
  String get privacyPhotosLabel => 'الصور والتخزين المحلي';

  @override
  String get privacyPhotosBody =>
      'حيثما تتيح لك ميزة إرفاق صورة (مثل اللحظات أو ملفك الشخصي)، لا يصل ZIVO إلى معرض صورك إلا عندما تختار صورة أو تلتقطها. تُحفظ الوسائط أولًا على جهازك؛ ولا يحدث النسخ الاحتياطي السحابي إلا عبر وجهة النسخ التي تختارها صراحةً.';

  @override
  String get privacyAskLabel => 'المساعد الذكي («اسأل»)';

  @override
  String get privacyAskBody =>
      '«اسأل» مساعد اختياري يمكنه الإجابة عن أسئلة تخص بياناتك أنت — تمارينك ووجباتك ومصروفاتك. عند إرسالك رسالة، يعالج مزوّد النموذج السياق ذا الصلة لغرض الإجابة عليك فقط. تُحفظ المحادثات بشكل خاص في حسابك ليعمل السجل عبر أجهزتك، ولا تُستخدم أبدًا لتدريب نماذج تابعة لجهات خارجية.';

  @override
  String get privacySpotifyLabel => 'SPOTIFY';

  @override
  String get privacySpotifyBody =>
      'تتصل ميزة الموسيقى بحساب Spotify الخاص بك عندما تطلب ذلك. يستخدم ZIVO حزمة تطوير Spotify الرسمية للتحكم في التشغيل ومعرفة ما يعمل حاليًا. ويمكنك فصل الاتصال في أي وقت من الإعدادات.';

  @override
  String get privacyMetadataLabel => 'بيانات الحساب والأمان';

  @override
  String get privacyMetadataBody =>
      'للحفاظ على أمان حسابك وإمكانية دعمه، يحتفظ ZIVO بسجل صغير لأحداث تسجيل الدخول — متى أُنشئ حسابك، ومتى وكيف سجّلت الدخول آخر مرة، ومتى أُرسلت رسائل التحقق. هذه البيانات هي سجلّ أمني لا غير: لا تُباع ولا تُشارك ولا تُستخدم للإعلانات أبدًا.';

  @override
  String get privacyDriveLabel => 'النسخ الاحتياطي على GOOGLE DRIVE';

  @override
  String get privacyDriveBody =>
      'النسخ الاحتياطي اختياري، وإذا فعّلته فإنه يعمل على حساب Google Drive الخاص بك — مستخدمًا نطاق drive.file، وهو أضيق نطاقات Google، والذي يتيح لـ ZIVO رؤية وإدارة الملفات التي أنشأها بنفسه فقط. لا يطلب ZIVO أبدًا صلاحية وصول واسعة إلى Drive، وتبقى ملفاتك هناك تحت سيطرتك.';

  @override
  String get privacySharingLabel => 'مشاركة البيانات';

  @override
  String get privacySharingBody =>
      'لا يبيع ZIVO بياناتك الشخصية ولا يؤجّرها. تُعالَج البيانات فقط بواسطة البنية التحتية اللازمة لتشغيل التطبيق — Google Firebase (تسجيل الدخول وقاعدة البيانات والوظائف) — إضافةً إلى التكاملات التي تفعّلها صراحةً: حساب Google Drive الخاص بك وحساب Spotify الخاص بك.';

  @override
  String get privacyRetentionLabel => 'الاحتفاظ والحذف';

  @override
  String get privacyRetentionBody =>
      'يُحتفظ بمحتواك حتى تحذفه أو تحذف حسابك. تبقى الملفات الموجودة في حساب Google Drive الخاص بك هناك حتى تزيلها، ويمكن إلغاء صلاحية الوصول إلى Drive في أي وقت — من الإعدادات أو من صفحة وصول الجهات الخارجية في حساب Google الخاص بك.';

  @override
  String get privacySecurityLabel => 'الأمان';

  @override
  String get privacySecurityBody =>
      'يُفرَض التحكم في الوصول من طرف إلى طرف: Firebase Authentication للهوية، وقواعد أمان Firestore بحيث لا يستطيع قراءة بياناتك أو الكتابة فيها إلا حسابك بعد تسجيل دخوله. تُخزَّن رموز التحقق على هيئة تجزئات مملّحة فقط. وتُشفَّر البيانات أثناء نقلها.';

  @override
  String get privacyChangesLabel => 'التغييرات على هذه السياسة';

  @override
  String get privacyChangesBody =>
      'قد تُحدَّث هذه السياسة مع تطوّر الميزات. ويعكس تاريخ «آخر تحديث» دائمًا أحدث مراجعة.';

  @override
  String get privacyContactLabel => 'التواصل';

  @override
  String privacyContactBody(String email) {
    return 'يمكن إرسال الأسئلة المتعلقة بالخصوصية أو ببياناتك إلى $email.';
  }

  @override
  String get sleepTitle => 'النوم';

  @override
  String get sleepHubSubtitle => 'الليلة الماضية';

  @override
  String get sleepLastNight => 'الليلة الماضية';

  @override
  String get sleepNoDataTitle => 'لا يوجد نوم مسجَّل';

  @override
  String get sleepNoDataBody =>
      'سجِّل ليلة بنفسك، أو اربط جهازًا يتتبّع النوم.';

  @override
  String get sleepNotVisibleTitle => 'لا تظهر لـ ZIVO أي بيانات نوم';

  @override
  String sleepNotVisibleBody(String provider) {
    return 'لا يوضّح $provider ما إذا كان قد رُفض وصول أحد التطبيقات، لذا قد يعني هذا أن الإذن غير مفعّل لا أنه لا توجد بيانات.';
  }

  @override
  String get sleepPermissionDeniedTitle => 'لا يستطيع ZIVO قراءة نومك';

  @override
  String sleepPermissionDeniedBody(String provider) {
    return 'اسمح بالوصول إلى النوم في $provider لرؤية الليالي التي يقيسها ساعتك أو تطبيق آخر.';
  }

  @override
  String get sleepUnavailableTitle => 'لا يوجد تطبيق صحة على هذا الجهاز';

  @override
  String get sleepUnavailableBody => 'لا يزال بإمكانك تسجيل الليالي بنفسك.';

  @override
  String sleepHistoryUnavailable(String provider) {
    return 'تحتاج الليالي الأقدم إلى إذن السجل في $provider.';
  }

  @override
  String get sleepSyncFailed => 'تعذّرت قراءة النوم الآن.';

  @override
  String sleepConnect(String provider) {
    return 'اربط $provider';
  }

  @override
  String get sleepProviderApple => 'صحة Apple';

  @override
  String get sleepProviderHealthConnect => 'Health Connect';

  @override
  String get sleepProviderYou => 'أنت';

  @override
  String get sleepGoingToSleep => 'سأنام الآن';

  @override
  String get sleepImAwake => 'استيقظت';

  @override
  String sleepMarkOpenSince(String time) {
    return 'نائم منذ $time';
  }

  @override
  String get sleepMarkCancel => 'لم أنم بعد كل شيء';

  @override
  String get sleepEditNight => 'تعديل هذه الليلة';

  @override
  String get sleepEditHint =>
      'يُحفظ تصحيحك باسمك، وتبقى الأوقات المقيسة محفوظة.';

  @override
  String sleepOnsetMeasured(String time) {
    return 'نام $time';
  }

  @override
  String sleepOnsetPlatform(String time) {
    return 'سُجِّل النوم $time';
  }

  @override
  String sleepOnsetReported(String time) {
    return 'سجّلت $time';
  }

  @override
  String sleepOnsetEstimated(String time) {
    return 'غالبًا نام حوالي $time';
  }

  @override
  String sleepWakeMeasured(String time) {
    return 'استيقظ $time';
  }

  @override
  String sleepWakePlatform(String time) {
    return 'سُجِّل الاستيقاظ $time';
  }

  @override
  String sleepWakeReported(String time) {
    return 'سجّلت $time';
  }

  @override
  String sleepWakeEstimated(String time) {
    return 'غالبًا استيقظ حوالي $time';
  }

  @override
  String sleepLastPhoneUse(String time) {
    return 'آخر استخدام للهاتف $time';
  }

  @override
  String get sleepMethodMeasured => 'مقيس';

  @override
  String get sleepMethodRecorded => 'مسجَّل';

  @override
  String get sleepMethodLogged => 'سجّلته بنفسك';

  @override
  String get sleepMethodEstimated => 'تقدير';

  @override
  String get sleepConfidenceHigh => 'ثقة عالية';

  @override
  String get sleepConfidenceMedium => 'ثقة متوسطة';

  @override
  String get sleepConfidenceLow => 'ثقة منخفضة';

  @override
  String sleepSourceChip(String provider, String method) {
    return '$provider · $method';
  }

  @override
  String get sleepDurationLabel => 'مدة النوم';

  @override
  String get sleepTimeInBedLabel => 'في السرير';

  @override
  String get sleepEfficiencyLabel => 'الكفاءة';

  @override
  String get sleepEfficiencyUnknown => 'غير متتبَّع';

  @override
  String sleepInterruptionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count انقطاعًا',
      few: '$count انقطاعات',
      two: 'انقطاعان',
      one: 'انقطاع واحد',
      zero: 'بلا انقطاعات',
    );
    return '$_temp0';
  }

  @override
  String sleepNapCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count قيلولة',
      few: '$count قيلولات',
      two: 'قيلولتان',
      one: 'قيلولة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get sleepSpansDstNote =>
      'عبَرت هذه الليلة تغييرًا في الساعة، لذا تختلف مدتها عن الأوقات المعروضة.';

  @override
  String get sleepTargetsTitle => 'أهدافك';

  @override
  String get sleepTargetBedtime => 'موعد النوم';

  @override
  String get sleepTargetWake => 'موعد الاستيقاظ';

  @override
  String get sleepTargetDuration => 'مدة النوم';

  @override
  String get sleepTargetsHint =>
      'تُستخدم لخط الهدف فقط — لا يمنح ZIVO أي تقييم لليلة.';

  @override
  String get sleepNoTargets => 'حدّد هدفًا لترى كيف تقارَن لياليك.';

  @override
  String sleepDeltaLonger(String amount, String target) {
    return '$amount أكثر من هدفك $target';
  }

  @override
  String sleepDeltaShorter(String amount, String target) {
    return '$amount أقل من هدفك $target';
  }

  @override
  String sleepDeltaOnTarget(String target) {
    return 'مطابق لهدفك $target';
  }

  @override
  String sleepBedtimeLater(String amount) {
    return '$amount بعد موعد نومك المستهدف';
  }

  @override
  String sleepBedtimeEarlier(String amount) {
    return '$amount قبل موعد نومك المستهدف';
  }

  @override
  String get sleepBedtimeOnTarget => 'مطابق لموعد نومك المستهدف';

  @override
  String get sleepWhyTitle => 'لماذا هذا الرقم؟';

  @override
  String get sleepWhySole => 'مصدر واحد فقط سجّل هذه الليلة.';

  @override
  String get sleepWhyMethod => 'اختير لأنه مقيس لا مُدخَل أو مُقدَّر.';

  @override
  String get sleepWhyCoverage =>
      'اختير لأن جزءًا أكبر من الليلة كان مسجَّلًا فعليًا.';

  @override
  String get sleepWhyDetail => 'اختير لأنه تضمّن مراحل النوم.';

  @override
  String get sleepWhyOverride => 'أنت ضبطت هذه الليلة بنفسك.';

  @override
  String sleepDisagreement(String provider, String amount) {
    return 'سجّل $provider وقتًا مختلفًا — بفارق $amount.';
  }

  @override
  String get sleepCoverageLabel => 'التغطية المسجَّلة';

  @override
  String sleepRecordedBy(String provider) {
    return 'سجّله $provider';
  }

  @override
  String get sleepUseThisInstead => 'استخدم هذا بدلًا منه';

  @override
  String get sleepWeekTitle => 'هذا الأسبوع';

  @override
  String get sleepWeekAverage => 'المتوسط';

  @override
  String get sleepWeekConsistency => 'الانتظام';

  @override
  String get sleepWeekOnTarget => 'ضمن الهدف';

  @override
  String sleepNightsCounted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ليلة',
      few: '$count ليالٍ',
      two: 'ليلتان',
      one: 'ليلة واحدة',
    );
    return '$_temp0';
  }

  @override
  String sleepNightsOf(int count, int total) {
    return '$count من $total ليالٍ';
  }

  @override
  String sleepVariability(String amount) {
    return '±$amount';
  }

  @override
  String sleepOnTargetRatio(int count, int total) {
    return '$count من $total';
  }

  @override
  String get sleepNoData => 'لا بيانات';

  @override
  String get sleepInsufficient => 'لا توجد ليالٍ كافية بعد';

  @override
  String sleepInsufficientFor(int have, int need) {
    return 'لا توجد ليالٍ كافية بعد — $have من $need';
  }

  @override
  String get sleepWeekUnchanged => 'تقريبًا كما الأسبوع الماضي';

  @override
  String sleepWeekImproved(String amount) {
    return '$amount أكثر من الأسبوع الماضي';
  }

  @override
  String sleepWeekDeclined(String amount) {
    return '$amount أقل من الأسبوع الماضي';
  }

  @override
  String get sleepInsightsTitle => 'ماذا يعني هذا';

  @override
  String get sleepInsightsPending => 'تجري قراءة لياليك…';

  @override
  String get sleepInsightsUnavailable =>
      'لا يمكن استخلاص نتيجة من الليالي المسجَّلة حتى الآن.';

  @override
  String sleepInsightBasis(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ليلة',
      few: '$count ليالٍ',
      two: 'ليلتين',
      one: 'ليلة واحدة',
    );
    return 'بناءً على $_temp0';
  }

  @override
  String get sleepStageLight => 'خفيف';

  @override
  String get sleepStageDeep => 'عميق';

  @override
  String get sleepStageRem => 'حركة العين السريعة';

  @override
  String get sleepStageAwake => 'مستيقظ';

  @override
  String get sleepStageAsleep => 'نائم';

  @override
  String get sleepStageInBed => 'في السرير';

  @override
  String get sleepNoStages => 'المراحل غير متاحة من هذا المصدر.';

  @override
  String sleepDurationHm(int hours, int minutes) {
    return '$hoursس $minutesد';
  }

  @override
  String sleepDurationM(int minutes) {
    return '$minutesد';
  }

  @override
  String sleepDurationH(int hours) {
    return '$hoursس';
  }

  @override
  String get hubSleep => 'النوم';

  @override
  String get hubNoSleepYet => 'لا توجد ليالٍ بعد';

  @override
  String sleepInsightDuration(String amount) {
    return 'بلغ متوسط نومك $amount في الليلة.';
  }

  @override
  String sleepInsightWeekBetter(String amount) {
    return 'هذا $amount أكثر من الأسبوع السابق.';
  }

  @override
  String sleepInsightWeekWorse(String amount) {
    return 'هذا $amount أقل من الأسبوع السابق.';
  }

  @override
  String get sleepInsightWeekSame => 'هذا تقريبًا كما الأسبوع السابق.';

  @override
  String sleepInsightConsistent(String amount) {
    return 'ظل توقيت نومك ثابتًا، بتفاوت $amount.';
  }

  @override
  String sleepInsightIrregular(String amount) {
    return 'تفاوت توقيت نومك بمقدار $amount خلال الأسبوع.';
  }

  @override
  String sleepInsightAdherence(int count, int total) {
    return 'التزمت بموعد نومك المستهدف في $count من $total ليالٍ.';
  }

  @override
  String get sleepInsightTrendUp => 'خلال الأسابيع الماضية أصبحت لياليك أطول.';

  @override
  String get sleepInsightTrendDown =>
      'خلال الأسابيع الماضية أصبحت لياليك أقصر.';

  @override
  String get sleepUnitHour => 'س';

  @override
  String get sleepAboutTitle => 'كيف يعمل قسم النوم';

  @override
  String get sleepAboutIntro =>
      'النوم مُدخَل تعافٍ يخدم تدريبك. إليك بالضبط ما يفعله ZIVO به، وما لن يدّعيه.';

  @override
  String get sleepAboutSessionTitle => 'ما هي جلسة النوم';

  @override
  String get sleepAboutSessionBody =>
      'الضغط على «سأنام الآن» يفتح جلسة فقط — لا مؤقّت يعمل ولا هاتفك ينصت. وعندما تضغط «استيقظت» يتحوّل هذان الوقتان إلى ليلة مسجَّلة باسمك.';

  @override
  String get sleepAboutTrackedTitle => 'ماذا يقرأ ZIVO';

  @override
  String sleepAboutTrackedBody(String provider) {
    return 'في كل مرة تفتح فيها هذه الشاشة يعيد ZIVO قراءة $provider ويبني الأسبوع الماضي من جديد: متى نمت، ومتى استيقظت، وكم نمت فعليًا، وأي استيقاظ بينهما.';
  }

  @override
  String get sleepAboutSourcesTitle => 'كل رقم يذكر مصدره';

  @override
  String get sleepAboutSourcesBody =>
      '«مقيس» يعني أن ساعة سجّلته، و«سجّلته بنفسك» يعني أنك أو تطبيقًا آخر أدخله يدويًا. وعند اختلاف مصدرين يختار ZIVO أحدهما ويحتفظ بالآخر — ولا يحسب متوسطًا بينهما لينتج ليلة لم ينمها أحد.';

  @override
  String get sleepAboutWeekTitle => 'لماذا تبقى بعض الأرقام فارغة';

  @override
  String get sleepAboutWeekBody =>
      'المتوسط على ليلة واحدة ليس متوسطًا. تبقى أرقام الأسبوع فارغة حتى تتوفر ليالٍ كافية، ويوضح كل رقم كم ليلة ينقصه.';

  @override
  String get sleepAboutLimitsTitle => 'ما لن يفعله';

  @override
  String get sleepAboutLimitsBody =>
      'لا توجد درجة للنوم ولا سلسلة أيام. يستطيع ZIVO أن يخبرك كم نمت وكم كان جدولك منتظمًا، لكنه لا يستطيع أن يخبرك إن كانت الليلة جيدة.';

  @override
  String get sleepAboutDone => 'فهمت';

  @override
  String get sleepSessionOpen => 'نائم';

  @override
  String get sleepMarkSoFar => 'حتى الآن';

  @override
  String get sleepMarkJustNow => 'الآن';

  @override
  String get sleepMarkHint =>
      'اضغط «استيقظت» عندما تستيقظ — عندها تُسجَّل الليلة.';

  @override
  String get sleepLoadFailedTitle => 'تعذّر تحميل بيانات نومك';

  @override
  String get sleepLoadFailedBody =>
      'تعذّر على ZIVO قراءة الليالي المحفوظة بالفعل. تحقّق من اتصالك ثم أعد المحاولة.';

  @override
  String get sleepRetry => 'أعد المحاولة';

  @override
  String get sleepLoading => 'جارٍ تحميل بيانات نومك';

  @override
  String sleepGateProgress(int have, int need) {
    return '$have من $need ليالٍ';
  }

  @override
  String get sleepVsLastWeek => 'مقارنة بالأسبوع الماضي';

  @override
  String get sleepMarkFailed =>
      'تعذّر الحفظ الآن. تحقّق من اتصالك ثم أعد المحاولة.';

  @override
  String get sleepUnitMinute => 'د';
}
