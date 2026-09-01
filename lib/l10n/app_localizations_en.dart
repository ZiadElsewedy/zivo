// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ZIVO';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDone => 'Done';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionNext => 'Next';

  @override
  String get actionRetry => 'Try again';

  @override
  String get tabToday => 'Today';

  @override
  String get tabHub => 'Hub';

  @override
  String get tabAsk => 'Ask';

  @override
  String get tabYou => 'You';

  @override
  String get dietTitle => 'Diet';

  @override
  String dietMealNumber(int number) {
    return 'Meal $number';
  }

  @override
  String dietKcalLeft(int kcal) {
    return '$kcal kcal left';
  }

  @override
  String dietKcalOver(int kcal) {
    return '$kcal kcal over';
  }

  @override
  String get dietEatenToday => 'Eaten today';

  @override
  String get dietLogSomething => 'Add something you ate';

  @override
  String get dietSupplements => 'Supplements';

  @override
  String get dietNoPlanToday => 'No meals planned today';

  @override
  String get dietNoPlan => 'No diet yet';

  @override
  String get dietAddPlan => 'Add a diet';

  @override
  String get dietYourPlans => 'Your diets';

  @override
  String get dietPlanDetails => 'Plan details';

  @override
  String get bodyTitle => 'About you';

  @override
  String get bodyHeightQuestion => 'How tall are you?';

  @override
  String get bodyWeightQuestion => 'What do you weigh?';

  @override
  String get bodySexQuestion => 'Sex';

  @override
  String get bodyActivityQuestion => 'How active are you?';

  @override
  String get bodySexMale => 'Male';

  @override
  String get bodySexFemale => 'Female';

  @override
  String get unitCm => 'cm';

  @override
  String get unitKg => 'kg';

  @override
  String get unitKcal => 'kcal';

  @override
  String get unitGrams => 'g';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageArabic => 'العربية';

  @override
  String get settingsLanguageSystem => 'Match my phone';

  @override
  String get prefsLikes => 'Foods you like';

  @override
  String get prefsLikesNote => 'ZIVO builds around these.';

  @override
  String get prefsAvoid => 'Foods you won\'t eat';

  @override
  String get prefsAvoidNote => 'Left out of the plan.';

  @override
  String get prefsAllergies => 'Allergies';

  @override
  String get prefsAllergiesNote =>
      'ZIVO refuses a plan that contains these. Still read it yourself.';

  @override
  String get prefsNotes => 'Anything else';

  @override
  String get prefsNotesHint => 'I train at 6am and eat straight after';

  @override
  String get prefsOther => 'Other…';

  @override
  String get prefsAddYourOwn => 'Add your own';

  @override
  String get foodChicken => 'Chicken';

  @override
  String get foodBeef => 'Beef';

  @override
  String get foodFish => 'Fish';

  @override
  String get foodTuna => 'Tuna';

  @override
  String get foodEggs => 'Eggs';

  @override
  String get foodRice => 'Rice';

  @override
  String get foodPasta => 'Pasta';

  @override
  String get foodBread => 'Bread';

  @override
  String get foodPotato => 'Potatoes';

  @override
  String get foodOats => 'Oats';

  @override
  String get foodYoghurt => 'Yoghurt';

  @override
  String get foodCheese => 'Cheese';

  @override
  String get foodBeans => 'Beans and lentils';

  @override
  String get foodVegetables => 'Vegetables';

  @override
  String get foodFruit => 'Fruit';

  @override
  String get foodNuts => 'Nuts';

  @override
  String get allergenPeanuts => 'Peanuts';

  @override
  String get allergenTreeNuts => 'Tree nuts';

  @override
  String get allergenMilk => 'Milk';

  @override
  String get allergenEggs => 'Eggs';

  @override
  String get allergenFish => 'Fish';

  @override
  String get allergenShellfish => 'Shellfish';

  @override
  String get allergenSoy => 'Soy';

  @override
  String get allergenGluten => 'Gluten';

  @override
  String get allergenSesame => 'Sesame';

  @override
  String get bodyIntro =>
      'ZIVO needs these to work out what your plan does to your weight.';

  @override
  String get bodyWeighInNote => 'Saved to your weigh-in log.';

  @override
  String bodyLastWeighIn(String ago) {
    return 'Last weigh-in $ago. Change the number to log a new one.';
  }

  @override
  String get bodyHeightRange => 'Heights go in centimetres, not metres.';

  @override
  String get bodyKnowMaintenance => 'I already know my daily calories';

  @override
  String get bodyMaintenanceNote =>
      'From a test, a coach, or your own tracking. ZIVO will use it instead of its own estimate.';

  @override
  String get bodyMaintenanceRange => 'That looks like a typo.';

  @override
  String get bodySaved => 'Saved';

  @override
  String greetingMorningNamed(String name) {
    return 'Morning, $name';
  }

  @override
  String greetingAfternoonNamed(String name) {
    return 'Afternoon, $name';
  }

  @override
  String greetingEveningNamed(String name) {
    return 'Evening, $name';
  }

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String get hubWorkout => 'Workout';

  @override
  String get hubDiet => 'Diet';

  @override
  String get hubExpenses => 'Expenses';

  @override
  String get hubMoments => 'Moments';

  @override
  String get hubRecent => 'Recent';

  @override
  String get hubNoPlanYet => 'No plan yet';

  @override
  String get hubNoMomentsYet => 'No moments yet';

  @override
  String get comingNext => 'Coming next.';

  @override
  String get errorCheckConnection =>
      'Check your connection and try again in a moment.';

  @override
  String get actionBack => 'Back';

  @override
  String get todayQuickLogVoice => 'Quick log by voice';

  @override
  String get todayDaytime => 'Daytime';

  @override
  String get todayEvening => 'Evening';

  @override
  String get todayNight => 'Night';

  @override
  String get todayNextSession => 'NEXT SESSION';

  @override
  String todayPlanPosition(int week, int day) {
    return 'WEEK $week · DAY $day';
  }

  @override
  String get todayNoPlanTitle => 'No training plan yet';

  @override
  String get todayNoPlanBody =>
      'Import your split from a PDF or photo and ZIVO turns it into a real rotating plan — or build one by hand.';

  @override
  String get todayImportPlan => 'Import a plan';

  @override
  String get todayBuildManually => 'Build manually instead';

  @override
  String get todayEmptySplitBody =>
      'Add training days and exercises to this split and it will show up here, ready to start.';

  @override
  String get todayEditSplit => 'Edit split';

  @override
  String get todayGetStarted => 'Get started';

  @override
  String get todayImportWorkoutPlan => 'Import a\nworkout plan';

  @override
  String get todayAddExpense => 'Add an\nexpense';

  @override
  String get pulseToday => 'TODAY';

  @override
  String get pulseNotYetToday => 'NOT YET TODAY';

  @override
  String get pulseTrained => 'Trained';

  @override
  String get pulseSteps => 'Steps';

  @override
  String pulseOfGoal(String goal) {
    return 'OF $goal';
  }

  @override
  String get pulseNoSensor => 'NO SENSOR';

  @override
  String get pulseVolume => 'Volume';

  @override
  String get pulseNoSetsYet => 'NO SETS YET';

  @override
  String get pulseFirstWeek => 'FIRST WEEK';

  @override
  String get pulseMomentum => 'Momentum';

  @override
  String get pulseNoStreakYet => 'NO STREAK YET';

  @override
  String get pulseNoSessionsYet => 'NO SESSIONS YET';

  @override
  String get pulseWorthKnowing => 'Worth knowing';

  @override
  String insightStreakTitle(int days) {
    return '$days-day training streak';
  }

  @override
  String get insightStreakBody =>
      'Momentum is real right now — protect it with today\'s session.';

  @override
  String insightRestTitle(int days) {
    return 'Rest has stretched to $days days';
  }

  @override
  String get insightRestBody =>
      'No guilt — just the next small session whenever you\'re ready.';

  @override
  String get insightEveningTitle => 'Evening check-in';

  @override
  String get insightMealsLeftOne =>
      'One meal still open today — worth closing it out.';

  @override
  String insightMealsLeftOneKcal(int kcal) {
    return 'One meal still open today (~$kcal kcal) — worth closing it out.';
  }

  @override
  String insightMealsLeftMany(int count) {
    return '$count meals still open today.';
  }

  @override
  String insightMealsLeftManyKcal(int count, int kcal) {
    return '$count meals still open today (~$kcal kcal left).';
  }

  @override
  String insightSpendTitle(int percent) {
    return 'Spending is running ~$percent% hot';
  }

  @override
  String get insightSpendBody =>
      'This week vs the same stretch last week — worth a glance.';

  @override
  String get insightStepsTitle => 'Steps are behind today';

  @override
  String insightStepsClose(int steps) {
    return 'Only $steps steps from the goal — an easy walk closes it.';
  }

  @override
  String insightStepsFar(int steps) {
    return '$steps steps to go — even ten minutes helps.';
  }

  @override
  String insightWeightDownTitle(String kg, int days) {
    return 'Weight down $kg kg over $days days';
  }

  @override
  String insightWeightUpTitle(String kg, int days) {
    return 'Weight up $kg kg over $days days';
  }

  @override
  String get insightWeightDownBody =>
      'Steady progress — keep eating enough to train hard.';

  @override
  String get insightWeightUpBody =>
      'Nothing dramatic — watch the trend, not any single day.';

  @override
  String get workoutTitle => 'Workout';

  @override
  String get workoutProgress => 'Progress';

  @override
  String get workoutTraining => 'Training';

  @override
  String get workoutBodyweight => 'Bodyweight';

  @override
  String get workoutSplits => 'Splits';

  @override
  String get workoutAnalysis => 'Analysis';

  @override
  String get workoutHistory => 'History';

  @override
  String get workoutCreatePlan => 'Create plan';

  @override
  String get workoutEditPlan => 'Edit plan';

  @override
  String get workoutNoPlanYet => 'No workout plan yet';

  @override
  String get workoutNoDayUpNext => 'No day up next.';

  @override
  String get workoutFullCycle => 'Full cycle';

  @override
  String get workoutAnyDayNote =>
      'Today\'s pick is marked — but any day is fair game. Life doesn\'t always follow the rotation.';

  @override
  String get workoutUpNext => 'UP NEXT';

  @override
  String get workoutNextUp => 'Next up';

  @override
  String get workoutInProgress => 'In progress';

  @override
  String get workoutInProgressCaps => 'IN PROGRESS';

  @override
  String get workoutStart => 'Start workout';

  @override
  String get workoutResume => 'Resume workout';

  @override
  String get workoutPause => 'Pause workout';

  @override
  String get workoutStartThisDay => 'Start this day';

  @override
  String get workoutChange => 'Change';

  @override
  String get workoutChangeWorkout => 'Change workout';

  @override
  String workoutDayLabel(String slot, String label) {
    return 'Day $slot · $label';
  }

  @override
  String workoutDaySlot(String slot) {
    return 'DAY $slot';
  }

  @override
  String get workoutExercises => 'EXERCISES';

  @override
  String get workoutSets => 'SETS';

  @override
  String get workoutMinutes => 'MINUTES';

  @override
  String workoutReadyToStart(String day) {
    return 'Ready to start $day?';
  }

  @override
  String get workoutReadyToResume => 'Ready to jump back in?';

  @override
  String get actionResume => 'Resume';

  @override
  String get actionStart => 'Start';

  @override
  String weighInLast(String kg) {
    return 'Last weigh-in: $kg kg';
  }

  @override
  String get weighInLog => 'Log weigh-in';

  @override
  String get weighInNone => 'NO WEIGH-INS YET';

  @override
  String get weighInStartTrend => 'Log one to start the trend.';

  @override
  String weighInLoggedAgo(String ago) {
    return 'Logged $ago ago';
  }

  @override
  String get statTotal => 'TOTAL';

  @override
  String get statSessions => 'Sessions';

  @override
  String get statDays => 'DAYS';

  @override
  String get statStreak => 'Streak';

  @override
  String get statMinAvg => 'MIN AVG';

  @override
  String get statDuration => 'Duration';

  @override
  String get statUsualStart => 'Usual start';

  @override
  String get commonToday => 'TODAY';

  @override
  String weighInOneMore(String ago) {
    return 'Logged $ago ago · one more reading draws the trend.';
  }

  @override
  String get liveDiscardTitle => 'Discard this workout?';

  @override
  String get liveDiscardBody =>
      'You\'ll lose this session\'s progress and the plan won\'t advance.';

  @override
  String get liveKeepGoing => 'Keep going';

  @override
  String get liveDiscard => 'Discard';

  @override
  String get liveDiscardWorkout => 'Discard workout';

  @override
  String get liveNoExercises => 'NO EXERCISES';

  @override
  String get liveNothingToDo => 'Nothing to do.';

  @override
  String get liveSetLogged => 'SET LOGGED';

  @override
  String liveSetLoggedDetail(String detail) {
    return 'SET LOGGED · $detail';
  }

  @override
  String liveSetsLogged(String count) {
    return '$count SETS LOGGED';
  }

  @override
  String get liveReps => 'REPS';

  @override
  String get liveWeightKg => 'WEIGHT · KG';

  @override
  String get liveRepsField => 'Reps';

  @override
  String get liveWeightField => 'Weight (kg)';

  @override
  String get liveNow => 'NOW';

  @override
  String get livePaused => 'Paused';

  @override
  String get livePausedCaps => 'PAUSED';

  @override
  String get livePausedTapResume => 'PAUSED · TAP TO RESUME';

  @override
  String get livePreWorkout => 'Pre-workout';

  @override
  String get liveFirstUp => 'FIRST UP';

  @override
  String get liveSkipWarmUp => 'Skip warm-up';

  @override
  String get liveRest => 'REST';

  @override
  String get liveSkipRest => 'Skip rest';

  @override
  String liveRestPlanned(String total) {
    return 'OF $total PLANNED';
  }

  @override
  String get liveWorkoutComplete => 'Workout complete';

  @override
  String get liveFinish => 'Finish';

  @override
  String get liveMatchingPrevious => 'Matching your previous set';

  @override
  String get liveFirstTime => 'First time';

  @override
  String get liveMatchingLast => 'MATCHING LAST';

  @override
  String liveSetNumber(int position) {
    return 'Set $position';
  }

  @override
  String liveSetNumberCaps(int number) {
    return 'SET $number';
  }

  @override
  String liveSetNumberKg(int number) {
    return 'SET $number · KG';
  }

  @override
  String get liveSkipped => 'Skipped';

  @override
  String get liveSkippedCaps => 'SKIPPED';

  @override
  String get liveSkip => 'Skip';

  @override
  String get liveLogSet => 'Log set';

  @override
  String get liveMarkDone => 'Mark done';

  @override
  String get liveCorrectSkipped =>
      'Enter what you actually did to mark this done.';

  @override
  String get liveCorrectLogged => 'Correct the reps or weight actually logged.';

  @override
  String get liveGoal => 'GOAL';

  @override
  String get liveLastTime => 'LAST TIME';

  @override
  String get liveTargetRange => 'TARGET RANGE';

  @override
  String get liveWeightUp => 'Weight up — you hit your reps last time';

  @override
  String get liveWeightEased => 'Weight eased — rebuild with clean reps';

  @override
  String get liveSameLoadMoreRep => 'Same load, one more rep';

  @override
  String liveSameWeight(String kg) {
    return 'Same · ${kg}kg';
  }

  @override
  String get liveConnectMusic => 'CONNECT MUSIC';

  @override
  String get actionClose => 'Close';

  @override
  String get actionBackCaps => 'BACK';

  @override
  String liveDeltaWeight(String delta) {
    return '${delta}kg from your previous set';
  }

  @override
  String liveDeltaReps(String delta) {
    return '$delta reps from your previous set';
  }

  @override
  String liveRepsValue(int reps) {
    return '$reps reps';
  }

  @override
  String liveWeightValue(String kg) {
    return '$kg kg';
  }

  @override
  String liveRepsByWeight(int reps, String kg) {
    return '$reps × $kg kg';
  }

  @override
  String get categoryFood => 'Food';

  @override
  String get categoryCoffee => 'Coffee';

  @override
  String get categoryTransport => 'Transport';

  @override
  String get categoryGroceries => 'Groceries';

  @override
  String get categoryShopping => 'Shopping';

  @override
  String get categoryOther => 'Other';

  @override
  String get expensesTitle => 'Expenses';

  @override
  String get expensesEmpty => 'Nothing spent yet — a calm start.';

  @override
  String get expenseNew => 'New expense';

  @override
  String get expenseEdit => 'Edit expense';

  @override
  String get expenseDelete => 'Delete expense';

  @override
  String get expenseNote => 'Note';

  @override
  String get expenseNoteHint => 'What was it for?';

  @override
  String get expenseAddNote => 'Add note';

  @override
  String expenseSaveAmount(String amount) {
    return 'Save · $amount';
  }

  @override
  String get walletCaps => 'WALLET';

  @override
  String get walletSetUp => 'SET UP YOUR WALLET';

  @override
  String get walletHowMuchNow => 'How much do you have right now?';

  @override
  String get walletDeductNote =>
      'Every expense you log deducts from it automatically.';

  @override
  String get walletSetStarting => 'Set starting balance';

  @override
  String get walletTopUp => 'Top up';

  @override
  String get walletTopUpTitle => 'Top up wallet';

  @override
  String get walletSetBalanceTitle => 'Set wallet balance';

  @override
  String get walletHowMuchAdding => 'How much are you adding?';

  @override
  String get walletSaveBalance => 'Save balance';

  @override
  String get walletAddFunds => 'Add funds';

  @override
  String get expensesThisWeek => 'THIS WEEK';

  @override
  String get categoryNew => 'New category';

  @override
  String get categoryNewHint => 'e.g. Subscriptions';

  @override
  String get categoryIconCaps => 'ICON';

  @override
  String get categoryAdd => 'Add category';

  @override
  String get captureTitle => 'Capture';

  @override
  String get captureExpense => 'Expense';

  @override
  String get captureExpenseDetail => 'Amount, category — in seconds';

  @override
  String get captureMoment => 'Moment';

  @override
  String get captureMomentDetail => 'Photo + a line';

  @override
  String get captureWorkout => 'Workout';

  @override
  String get captureWorkoutDetail => 'Log a training session';

  @override
  String get dateToday => 'Today';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String get nutritionCalories => 'Calories';

  @override
  String get nutritionProtein => 'Protein (g)';

  @override
  String get nutritionCarbs => 'Carbs (g)';

  @override
  String get nutritionFat => 'Fat (g)';

  @override
  String get nutritionCaloriesPer100g => 'Calories / 100g';

  @override
  String get targetsSave => 'Save target';

  @override
  String get targetsNoneSet => 'No daily target set';

  @override
  String get targetsZivoWillUse => 'ZIVO will use';

  @override
  String get targetsFillFields => 'Fill the fields';

  @override
  String get targetsChangeBodyData => 'Change my body data';

  @override
  String get targetsFromBodyData => 'Work it out from my body data';

  @override
  String get bodyWeightLabel => 'Weight';

  @override
  String get bodyHeightLabel => 'Height';

  @override
  String get bodyAgeLabel => 'Age';

  @override
  String get bodyActivityLabel => 'Activity';

  @override
  String get planDeleteTitle => 'Delete this plan?';

  @override
  String get planEditTitle => 'Edit diet plan';

  @override
  String get planDelete => 'Delete plan';

  @override
  String get planNameHint => 'Plan name';

  @override
  String get planSave => 'Save plan';

  @override
  String get planNoDays => 'No days yet.';

  @override
  String get planAddDay => 'Add day';

  @override
  String get planAddMeal => 'Add meal';

  @override
  String get planAddItem => 'Add item';

  @override
  String get planAddFoodItem => 'Add food item';

  @override
  String get planEveryDay => 'Every day';

  @override
  String get planDayLabelHint => 'Day label (optional)';

  @override
  String get planMealNameHint => 'Meal name';

  @override
  String get planFoodNameHint => 'Food name';

  @override
  String get planQty => 'Qty';

  @override
  String get plansTitle => 'Your plans';

  @override
  String get plansFollow => 'Follow this plan';

  @override
  String get plansStopFollowing => 'Stop following';

  @override
  String get prefsBuildTitle => 'Build me a plan';

  @override
  String get prefsBuild => 'Build my plan';

  @override
  String get dictateHint => 'Breakfast is…';

  @override
  String get dictateTurnIntoPlan => 'Turn this into a plan';

  @override
  String get dictateDoneTalking => 'Done talking';

  @override
  String get logWhatDidYouEat => 'What did you eat?';

  @override
  String get logBackToSearch => 'Back to search';

  @override
  String get logIt => 'Log it';

  @override
  String logAddOwnFood(String query) {
    return 'Add \"$query\" as my own food';
  }

  @override
  String get logYourOwnFood => 'Your own food';

  @override
  String get logFoodName => 'Name';

  @override
  String get logSaveFood => 'Save food';

  @override
  String get dietEaten => 'Eaten';

  @override
  String get adoptSaveAsTarget => 'Save as my target';

  @override
  String get addDietPdfOrPhoto => 'PDF or photo';

  @override
  String get addDietPdfOrPhotoDetail =>
      'Your nutritionist\'s plan, or a picture of one.';

  @override
  String get addDietDictate => 'Say it out loud';

  @override
  String get addDietDictateDetail =>
      'Describe your meals; ZIVO writes them down.';

  @override
  String get addDietType => 'Type it out';

  @override
  String get addDietTypeDetail => 'Write your meals in your own words.';

  @override
  String get addDietGenerate => 'Build one for me';

  @override
  String get addDietGenerateDetail =>
      'Tell ZIVO what you eat; it designs the plan.';

  @override
  String get addDietManual => 'Build it meal by meal';

  @override
  String get addDietManualDetail =>
      'The full editor, nothing extracted for you.';

  @override
  String get addDietIntro =>
      'However it reaches ZIVO, you review every meal and every figure before it is saved.';

  @override
  String get momentDeleteTitle => 'Delete moment?';

  @override
  String get momentDeleteBody =>
      'This removes it from your moments. The photo on your device is also removed.';

  @override
  String dietPlanDeleteBody(String name) {
    return 'This removes \"$name\" and all its days and meals. This can\'t be undone.';
  }

  @override
  String dietPlanArchiveHint(String name) {
    return 'This removes $name for good. Archiving keeps it and takes it off the Diet screen just the same.';
  }

  @override
  String get sessionDeleteTitle => 'Delete this session?';

  @override
  String sessionDeleteBody(String day) {
    return 'This permanently removes your \"$day\" session and everything logged in it. This can\'t be undone.';
  }

  @override
  String splitDeleteTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get splitDeleteBody =>
      'This removes the split and all its days and exercises. Logged history for it is kept, just no longer editable here. This can\'t be undone.';

  @override
  String get workoutPlanDeleteTitle => 'Delete this plan?';

  @override
  String workoutPlanDeleteBody(String name) {
    return 'This removes \"$name\" and all its days and exercises. This can\'t be undone.';
  }

  @override
  String get splitDeleteTitlePlain => 'Delete this split?';
}
