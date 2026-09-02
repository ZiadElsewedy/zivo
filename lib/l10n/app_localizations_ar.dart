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
  String get planDayLabelHint => 'اسم اليوم (اختياري)';

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
  String get dietEaten => 'أُكلت';

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
}
