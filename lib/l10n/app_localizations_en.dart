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
  String get livePrsTitle => 'New personal records';

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

  @override
  String get expenseSaveFailed => 'Couldn\'t save that expense.';

  @override
  String get expenseDeleteFailed => 'Couldn\'t delete that expense.';

  @override
  String get dietLogFailed => 'Couldn\'t log that food.';

  @override
  String get musicConnect => 'Connect Spotify';

  @override
  String get musicReconnect => 'Reconnect Spotify';

  @override
  String get musicConnecting => 'Connecting…';

  @override
  String get musicInstallSpotify => 'Install Spotify to play';

  @override
  String get musicNothingPlaying => 'Nothing playing';

  @override
  String get musicPrevious => 'Previous track';

  @override
  String get musicNext => 'Next track';

  @override
  String get musicPlay => 'Play';

  @override
  String get musicPause => 'Pause';

  @override
  String get musicDisconnect => 'Disconnect Spotify';

  @override
  String get errorCouldntLoad => 'Couldn\'t load this.';

  @override
  String get workoutStatusProgressing => 'Progressing';

  @override
  String get workoutStatusHolding => 'Holding';

  @override
  String get workoutStatusPlateaued => 'Plateaued';

  @override
  String get workoutStatusTrendingDown => 'Trending down';

  @override
  String get workoutStatusBuilding => 'Building';

  @override
  String get workoutToneImproved => 'Improved';

  @override
  String get workoutToneMatched => 'Matched';

  @override
  String get workoutToneMixed => 'Mixed';

  @override
  String get workoutToneDown => 'Down';

  @override
  String get workoutBodyweightLoadError => 'Couldn\'t load weigh-ins.';

  @override
  String workoutWeighInsLogged(int count) {
    return '$count weigh-ins logged';
  }

  @override
  String get workoutUnitKg => 'KG';

  @override
  String workoutBodyweightChange30d(String change) {
    return '$change KG · 30D';
  }

  @override
  String get workoutBodyweightEmpty =>
      'Log your first weigh-in to start the trend.';

  @override
  String get workoutThisWeekCaps => 'THIS WEEK';

  @override
  String get workoutLastWeekCaps => 'LAST WEEK';

  @override
  String get workoutSessionsLabel => 'Sessions';

  @override
  String get workoutTrained => 'Trained';

  @override
  String get workoutThisWeek => 'This week';

  @override
  String get workoutSessionCompleted => 'Completed';

  @override
  String get workoutSessionInProgress => 'In progress';

  @override
  String get workoutSessionNotCompleted => 'Not completed';

  @override
  String workoutExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '1 exercise',
    );
    return '$_temp0';
  }

  @override
  String workoutSetsOfTotal(int done, int total) {
    return '$done/$total sets';
  }

  @override
  String get workoutNoSessionsTitle => 'No sessions logged yet.';

  @override
  String get workoutNoSessionsBody => 'Finish a workout and it shows up here.';

  @override
  String get workoutSessionsLoadError => 'Couldn\'t load sessions.';

  @override
  String get workoutNoCompletedWorkouts => 'No completed workouts yet.';

  @override
  String workoutCompletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count completed workouts',
      one: '1 completed workout',
    );
    return '$_temp0';
  }

  @override
  String workoutNoCompletedWithEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No completed workouts · $count entries',
      one: 'No completed workouts · 1 entry',
    );
    return '$_temp0';
  }

  @override
  String workoutCompletedAndNotCompleted(String completed, int notCompleted) {
    return '$completed · $notCompleted not completed';
  }

  @override
  String get workoutSessionsEmpty =>
      'Nothing here yet — finished workouts land here.';

  @override
  String get workoutSessionEndedEarly => 'Ended early';

  @override
  String workoutSetsCaps(int done, int total) {
    return '$done/$total SETS';
  }

  @override
  String get workoutDayStreak => 'Day streak';

  @override
  String get workoutNoActiveStreak =>
      'No active streak — complete a workout to start one.';

  @override
  String workoutStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days in your current streak',
      one: 'day in your current streak',
    );
    return '$_temp0';
  }

  @override
  String get workoutBestStreak => 'best day streak ever';

  @override
  String get workoutStreakEmpty => 'Train today and day one starts now.';

  @override
  String workoutSessionsCountCaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count SESSIONS',
      one: '1 SESSION',
    );
    return '$_temp0';
  }

  @override
  String get workoutSessionLength => 'Session length';

  @override
  String get workoutNoAverageYet => 'Complete a workout to see your average.';

  @override
  String get workoutAverageSession => 'average completed session';

  @override
  String get workoutDurationsEmpty =>
      'Durations appear once you finish workouts.';

  @override
  String get workoutStartTimes => 'Start times';

  @override
  String get workoutNoStartTimeYet =>
      'Complete a workout to see your usual start time.';

  @override
  String get workoutUsualStartTime => 'when you usually start training';

  @override
  String get workoutStartTimesEmpty => 'Your start times will show up here.';

  @override
  String get workoutToday => 'Today';

  @override
  String workoutAgo(String value) {
    return '$value ago';
  }

  @override
  String get workoutCurrentSplit => 'Current split';

  @override
  String get workoutRecentActivity => 'Recent activity';

  @override
  String get workoutNoSessionYet => 'You haven\'t logged a session yet.';

  @override
  String get workoutGoDeeper => 'Go deeper';

  @override
  String get workoutFullAnalysis => 'Full analysis';

  @override
  String get workoutFullAnalysisDetail =>
      'Exercise-by-exercise, per training day';

  @override
  String get workoutAllHistory => 'All history';

  @override
  String get workoutAllHistoryDetail => 'Every session you have logged';

  @override
  String get workoutSplitsDetail => 'Switch or edit your training splits';

  @override
  String get workoutTotalSessions => 'Total sessions';

  @override
  String get workoutAvgLength => 'Avg length';

  @override
  String get workoutSeeFullAnalysisCaps => 'SEE FULL ANALYSIS';

  @override
  String get workoutSeeAllCaps => 'SEE ALL';

  @override
  String workoutPrCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PRs',
      one: '1 PR',
    );
    return '$_temp0';
  }

  @override
  String workoutSessionsCompletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions completed',
      one: '1 session completed',
    );
    return '$_temp0';
  }

  @override
  String get workoutPlanShort => 'Plan';

  @override
  String workoutAgoWithDuration(String value, String duration) {
    return '$value ago · $duration';
  }

  @override
  String get workoutRecentPrs => 'Recent PRs';

  @override
  String get workoutGoingWell => 'What\'s going well';

  @override
  String workoutImprovingCount(int count) {
    return '$count improving';
  }

  @override
  String get workoutGettingWorse => 'What\'s getting worse';

  @override
  String workoutDecliningCount(int count) {
    return '$count declining';
  }

  @override
  String get workoutStalled => 'Stalled — needs a change';

  @override
  String workoutFlatCount(int count) {
    return '$count flat';
  }

  @override
  String get workoutBeingSkipped => 'What\'s being skipped';

  @override
  String workoutSkippedOfPlanned(int skipped, int planned) {
    return '$skipped of $planned';
  }

  @override
  String get workoutFocusNext => 'Focus next';

  @override
  String get workoutTrainingVolume => 'Training volume';

  @override
  String get workoutAllExercises => 'All exercises';

  @override
  String get workoutTapToDrillIn => 'tap to drill in';

  @override
  String get workoutOverallCaps => 'OVERALL';

  @override
  String get workoutPrHeaviest => 'Heaviest';

  @override
  String get workoutPrMostReps => 'Most reps';

  @override
  String get workoutPrBestStrength => 'Best strength';

  @override
  String workoutRepsOnly(int reps) {
    return '$reps reps';
  }

  @override
  String workoutWeightByReps(String weight, int reps) {
    return '${weight}kg × $reps';
  }

  @override
  String workoutStatusWithStrength(String status, String change) {
    return '$status · $change strength';
  }

  @override
  String get workoutNeverTrained => 'Planned but never trained';

  @override
  String workoutStaleSince(int days, String day) {
    return '$days days since last — on $day';
  }

  @override
  String get workoutNoPriorWeek => 'No prior week to compare';

  @override
  String workoutVsLastWeek(String change) {
    return '$change vs last week';
  }

  @override
  String get workoutSameAsLastWeek => 'Same as last week';

  @override
  String get workoutThisWeekWorkingSets => 'This week · working sets only';

  @override
  String get workoutAnalysisEmptyTitle =>
      'Complete a few sessions to start tracking progress.';

  @override
  String get workoutAnalysisEmptyBody =>
      'Once you\'ve logged the same exercise a few times, ZIVO will show your strength trend, PRs, and what to focus on next.';

  @override
  String get workoutStrengthTrend => 'Strength trend';

  @override
  String get workoutVolumeTrend => 'Volume trend';

  @override
  String get workoutAtAGlance => 'At a glance';

  @override
  String get workoutPersonalRecords => 'Personal records';

  @override
  String get workoutSessionHistory => 'Session history';

  @override
  String workoutSessionsLogged(int count) {
    return '$count logged';
  }

  @override
  String workoutEstStrengthChange(String change) {
    return '$change est. strength';
  }

  @override
  String get workoutEst1rmCaps => 'EST. 1RM';

  @override
  String get workoutWhatHappenedCaps => 'WHAT HAPPENED';

  @override
  String get workoutWhyItMattersCaps => 'WHY IT MATTERS';

  @override
  String get workoutDoThisCaps => 'DO THIS';

  @override
  String get workoutEst1rmUnitCaps => 'EST. 1RM (KG)';

  @override
  String get workoutVolumeUnitCaps => 'VOLUME (KG)';

  @override
  String get workoutOldest => 'Oldest';

  @override
  String get workoutLatest => 'Latest';

  @override
  String get workoutBestEst1rm => 'Best est. 1RM';

  @override
  String get workoutTotalVolume => 'Total volume';

  @override
  String get workoutFrequency => 'Frequency';

  @override
  String get workoutPerWeek => '/wk';

  @override
  String get workoutLastTrained => 'Last trained';

  @override
  String get workoutDaysAgo => 'days ago';

  @override
  String get workoutPrHeaviestLoad => 'Heaviest load';

  @override
  String workoutKgValue(String value) {
    return '${value}kg';
  }

  @override
  String workoutSessionNumberCaps(int index) {
    return 'SESSION $index';
  }

  @override
  String get workoutSetsShort => 'Sets';

  @override
  String get workoutTopSet => 'Top set';

  @override
  String get workoutVolumeShort => 'Volume';

  @override
  String get workoutEst1rmShort => 'Est 1RM';

  @override
  String get workoutVsPreviousSessionCaps => 'VS PREVIOUS SESSION';

  @override
  String get workoutSetDropsetShort => 'D';

  @override
  String get workoutSetFailureShort => 'F';

  @override
  String get workoutPbCaps => 'PB';

  @override
  String get workoutExerciseEmptyTitle =>
      'No completed sessions with this exercise yet.';

  @override
  String get workoutExerciseEmptyBody =>
      'Log it in a session and its full history, trend, and session-to-session comparison will appear here.';

  @override
  String get workoutNewPb => 'New PB';

  @override
  String workoutDeltaE1rm(String change) {
    return 'e1RM $change';
  }

  @override
  String workoutDeltaLoad(String change) {
    return 'Load $change';
  }

  @override
  String workoutDeltaReps(String change) {
    return 'Reps $change';
  }

  @override
  String workoutDeltaVolume(String change) {
    return 'Volume $change';
  }

  @override
  String get workoutNoMeaningfulChange => 'No meaningful change';

  @override
  String workoutDurationHm(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String workoutDurationM(int minutes) {
    return '${minutes}m';
  }

  @override
  String workoutDurationH(String hours) {
    return '${hours}h';
  }

  @override
  String get askTitle => 'Ask';

  @override
  String get askNewChat => 'New chat';

  @override
  String get askChatHistory => 'Chat history';

  @override
  String get askReplyStyle => 'Reply style';

  @override
  String get askChats => 'Chats';

  @override
  String get askNoChats => 'No chats yet.';

  @override
  String get askNameItHint =>
      'Name it so you can find it later — or leave it blank and the first message will title it.';

  @override
  String get askNamePlaceholder => 'e.g. Workout changes';

  @override
  String get askStartChatting => 'Start chatting';

  @override
  String get askDeleteChatTitle => 'Delete this chat?';

  @override
  String askDeleteChatBody(String title) {
    return 'This permanently removes \"$title\" and everything in it. This can\'t be undone.';
  }

  @override
  String get askDeleteChatConfirm => 'Delete chat';

  @override
  String get askGreeting => 'Hey, I\'m ZIVO.';

  @override
  String get askIntro =>
      'Training, diet and spending. Ask me anything — or let me log it for you.';

  @override
  String get askSuggestSpend => 'What did I spend this week?';

  @override
  String get askSuggestTraining => 'How is my training going?';

  @override
  String get askSuggestDiet => 'What\'s left on my diet today?';

  @override
  String get askSuggestWeek => 'Summarise my week';

  @override
  String get askUnreachableTitle => 'Couldn\'t reach ZIVO';

  @override
  String get askUnreachableBody => 'Your message wasn’t sent.';

  @override
  String get askRetry => 'Retry';

  @override
  String get askSaveFailed => 'Couldn\'t save that — try again.';

  @override
  String get askActionFailed => 'Couldn\'t do that just now. Try again.';

  @override
  String get askThinking => 'Thinking…';

  @override
  String get askUnderstanding => 'Understanding…';

  @override
  String get askWorking => 'Working…';

  @override
  String get askPreparingChange => 'Preparing your change…';

  @override
  String get askStillWorking => 'Still working on this one…';

  @override
  String get askReadingDay => 'Reading your day…';

  @override
  String get askReadingDiet => 'Reading today\'s diet…';

  @override
  String get askReadingTraining => 'Reading your training…';

  @override
  String get askReadingSpending => 'Reading your spending…';

  @override
  String get askSummarisingWeek => 'Summarising your week…';

  @override
  String get askLookingUpFood => 'Looking that food up…';

  @override
  String get askCalculating => 'Working out the numbers…';

  @override
  String get askProposalConfirmed => 'Confirmed';

  @override
  String get askProposalCancelled => 'Cancelled';

  @override
  String get askProposalExpired => 'Expired';

  @override
  String get askProposalConfirm => 'Confirm';

  @override
  String get askActionNewExpense => 'New expense';

  @override
  String get askActionEditExpense => 'Edit expense';

  @override
  String get askActionDeleteExpense => 'Delete expense';

  @override
  String get askActionDietPlan => 'Diet plan';

  @override
  String get askActionLogFood => 'Log food';

  @override
  String get askActionSuggestion => 'Suggestion';

  @override
  String askFoodCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count foods',
      one: '1 food',
    );
    return '$_temp0';
  }

  @override
  String askKcalTotal(String total) {
    return '$total kcal';
  }

  @override
  String get askVoiceUnavailable => 'Voice input isn\'t available right now.';

  @override
  String get askMicPermission =>
      'Turn on microphone access to use voice input.';

  @override
  String get askMicStartFailed => 'Couldn\'t start the microphone — try again.';

  @override
  String get askDidntCatchThat => 'Didn\'t catch that — try recording again.';

  @override
  String get askTranscribeFailed =>
      'Couldn\'t transcribe that — check your connection and try again.';

  @override
  String get askTranscribeTimeout =>
      'That took too long — check your connection and try again.';

  @override
  String get askNothingCameThrough => 'Nothing came through — try again.';

  @override
  String get askTranscribing => 'Transcribing…';

  @override
  String get askDiscardRecording => 'Discard recording';

  @override
  String get askDiscardVoiceNote => 'Discard voice note';

  @override
  String get askTryAgain => 'Try again';

  @override
  String askSecondsElapsed(int seconds) {
    return ' · ${seconds}s';
  }

  @override
  String get askComposerHint => 'Ask ZIVO…';

  @override
  String get askRecordVoiceNote => 'Record a voice note';

  @override
  String get askSilenceHint => 'Can\'t hear you yet — speak closer to the mic.';

  @override
  String get askVoiceLog => 'Voice log';

  @override
  String get askVoiceLogSubtitle =>
      'Say it once — it lands in Ask ready to send.';

  @override
  String get askTapAndSpeak => 'Tap and speak';

  @override
  String get askVoiceExamples =>
      '\"add 40 EGP parking\" · \"finished chest day\"';
}
