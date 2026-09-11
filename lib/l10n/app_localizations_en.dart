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
  String get pulseWeekOverWeek => 'WoW';

  @override
  String get hubTitle => 'Hub';

  @override
  String get hubConnected => 'Connected';

  @override
  String hubWorkoutResume(String day) {
    return '$day · resume';
  }

  @override
  String hubWorkoutUpNext(String day) {
    return '$day · up next';
  }

  @override
  String hubDietStat(int eaten, int total, String kcal) {
    return '$eaten of $total · $kcal kcal';
  }

  @override
  String hubExpensesStat(String amount) {
    return '$amount this week';
  }

  @override
  String hubMomentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count moments',
      one: '1 moment',
    );
    return '$_temp0';
  }

  @override
  String get connectedBackingUp => 'Backing up';

  @override
  String get connectedNotConnected => 'Not connected';

  @override
  String get connectedConnected => 'Connected';

  @override
  String get connectedPlaying => 'Playing';

  @override
  String get connectedPaused => 'Paused';

  @override
  String get connectedConnecting => 'Connecting…';

  @override
  String get connectedCouldntConnect => 'Couldn’t connect';

  @override
  String get connectedPremiumRequired => 'Premium required';

  @override
  String get connectedInstallSpotify => 'Install Spotify';

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
  String todayEmptySplitTitle(String plan) {
    return '$plan has no days';
  }

  @override
  String get todayEmptySplitBody =>
      'Add training days and exercises to this split and it will show up here, ready to start.';

  @override
  String get todayEditSplit => 'Edit split';

  @override
  String get todayGetStarted => 'Get started';

  @override
  String get todayGetStartedBody =>
      'Import a plan or log a spend — ZIVO builds Today from there.';

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
  String get workoutMoreSection => 'More';

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
  String get workoutChangeSwap => 'Swap';

  @override
  String get workoutChangeSkip => 'Skip';

  @override
  String workoutChangeSwapNote(String day) {
    return '$day takes the slot you pick — the cycle stays whole.';
  }

  @override
  String workoutChangeSkipNote(String day) {
    return '$day is skipped this cycle.';
  }

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
  String get planDaySlot => 'Slot';

  @override
  String get planDaySlotHint => 'A';

  @override
  String get planDayLabel => 'Label';

  @override
  String get planDayLabelHint => 'Day label (optional)';

  @override
  String get planDayNotesOptional => 'Notes (optional)';

  @override
  String get workoutShortestSession => 'shortest';

  @override
  String get workoutLongestSession => 'longest';

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
  String get dietBasisLogged => 'logged by you';

  @override
  String get dietBasisTicked => 'from ticked meals, not weighed';

  @override
  String get dietBasisNothing => 'nothing logged yet';

  @override
  String get dietFindingObservation => 'Observation';

  @override
  String get dietFindingAnalysis => 'Analysis';

  @override
  String get dietFindingSuggestion => 'Suggestion';

  @override
  String get dietFindingWarning => 'Warning';

  @override
  String get dietFindingGoingWell => 'Going well';

  @override
  String get dietFindingWorthKnowing => 'Worth knowing';

  @override
  String get dietEaten => 'Eaten';

  @override
  String get dietNotEaten => 'Not eaten';

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
  String get workoutBodyweightAllWeighIns => 'All weigh-ins';

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
  String get streakOrbitTitle => 'Consistency';

  @override
  String get streakOrbitBestLabel => 'Best streak';

  @override
  String get streakOrbitTrainedTotal => 'Days trained';

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
  String get workoutExercisesBrowse => 'Exercises';

  @override
  String get workoutSearchExercises => 'Search exercises';

  @override
  String workoutNoMatches(String query) {
    return 'No exercises match “$query”.';
  }

  @override
  String workoutExerciseCountCaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count MOVEMENTS',
      one: '1 MOVEMENT',
    );
    return '$_temp0';
  }

  @override
  String get workoutMuscleChest => 'Chest';

  @override
  String get workoutMuscleBack => 'Back';

  @override
  String get workoutMuscleLegs => 'Legs';

  @override
  String get workoutMuscleShoulders => 'Shoulders';

  @override
  String get workoutMuscleArms => 'Arms';

  @override
  String get workoutMuscleCore => 'Core';

  @override
  String get workoutMuscleOther => 'Other';

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
  String workoutRepsSpec(String reps) {
    return '$reps reps';
  }

  @override
  String workoutSetCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sets',
      one: '1 set',
    );
    return '$_temp0';
  }

  @override
  String get workoutToFailure => 'To failure';

  @override
  String get planDefaultRest => 'Default rest';

  @override
  String planDefaultRestValue(String time) {
    return 'Default rest · $time';
  }

  @override
  String get planDefaultRestNote =>
      'Sets every exercise in this plan to this rest. Editing one exercise afterward still overrides it individually.';

  @override
  String get planSetAll => 'Set all';

  @override
  String workoutRestFor(String time) {
    return 'rest $time';
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
  String get timeAgoNow => 'now';

  @override
  String timeAgoMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String timeAgoHours(int hours) {
    return '${hours}h';
  }

  @override
  String timeAgoDays(int days) {
    return '${days}d';
  }

  @override
  String get askReplyStyleConcise => 'Concise';

  @override
  String get askReplyStyleBalanced => 'Balanced';

  @override
  String get askReplyStyleDetailed => 'Detailed';

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
  String get askInputSubmit => 'Send';

  @override
  String get askInputSent => 'Sent';

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

  @override
  String get profileName => 'Name';

  @override
  String get profileDateOfBirth => 'Date of birth';

  @override
  String get profileEmail => 'Email';

  @override
  String get profileCompleteTitle => 'Complete your profile';

  @override
  String get profileCompleteSubtitle =>
      'A couple of details to personalise ZIVO.';

  @override
  String get profileSaveFailed =>
      'We couldn\'t save your profile. Please try again.';

  @override
  String get profileUseAnotherAccount => 'Use another account';

  @override
  String get actionContinue => 'Continue';

  @override
  String get profileSettings => 'Settings';

  @override
  String get profileAccountCaps => 'ACCOUNT';

  @override
  String get profileSignInCaps => 'SIGN-IN';

  @override
  String get profileEditName => 'Edit name';

  @override
  String get profileYourName => 'Your name';

  @override
  String get profileSignedIn => 'Signed in';

  @override
  String get profileVerifiedCaps => 'VERIFIED';

  @override
  String get profileUnverifiedCaps => 'UNVERIFIED';

  @override
  String get profileConnectedCaps => 'CONNECTED';

  @override
  String get profileEmailAndPassword => 'Email & password';

  @override
  String profileDobWithAge(String date, int age) {
    return '$date · $age';
  }

  @override
  String get profileStatSessions => 'Sessions';

  @override
  String get profileStatMonthsIn => 'Months in';

  @override
  String get profileStatLifetime => 'Lifetime';

  @override
  String get profileAbout => 'About';

  @override
  String get profileAboutEmpty => 'Add a few words about yourself.';

  @override
  String get profileAboutHint => 'A few words about yourself…';

  @override
  String profileCharCount(int used, int max) {
    return '$used / $max';
  }

  @override
  String get profilePhotoTitle => 'Profile Photo';

  @override
  String get profileChoosePhoto => 'Choose Photo';

  @override
  String get profileRemovePhoto => 'Remove Photo';

  @override
  String get profileCropTitle => 'Move & Scale';

  @override
  String get profileCropDone => 'Choose';

  @override
  String get profileEditPhoto => 'Edit Photo';

  @override
  String get dietGoalFatLoss => 'Fat loss';

  @override
  String get dietGoalMaintain => 'Maintain';

  @override
  String get dietGoalMuscleGain => 'Muscle gain';

  @override
  String get dietGoalRecomp => 'Recomposition';

  @override
  String get dietGoalFatLossDetail =>
      'Eat below maintenance to lose fat, keeping protein high.';

  @override
  String get dietGoalMaintainDetail =>
      'Hold weight steady at roughly maintenance calories.';

  @override
  String get dietGoalMuscleGainDetail =>
      'Eat above maintenance to support building muscle.';

  @override
  String get dietGoalRecompDetail =>
      'Hold calories near maintenance with protein high enough to build while leaning out.';

  @override
  String get dietTargetSourceManual => 'You set this';

  @override
  String get dietTargetSourceCalculated => 'Calculated from your body data';

  @override
  String get dietTargetSourcePlan => 'Adopted from your plan\'s daily total';

  @override
  String get dietCalibrationNeedsWeighIns => 'two weigh-ins';

  @override
  String dietCalibrationNeedsLongerWindow(int days) {
    return 'weigh-ins at least $days days apart';
  }

  @override
  String get dietCalibrationNeedsMoreDays => 'more days of food logged';

  @override
  String get dietMacroProtein => 'Protein';

  @override
  String get dietMacroCarbs => 'Carbs';

  @override
  String get dietMacroFat => 'Fat';

  @override
  String get dietTodaySoFar => 'Today so far';

  @override
  String dietKcalEaten(String kcal) {
    return '$kcal kcal eaten';
  }

  @override
  String get dietYourTarget => 'Your target';

  @override
  String get dietMacrosToday => 'Macros today';

  @override
  String get dietWhatPlanDoes => 'What this plan does';

  @override
  String get dietTodaysRead => 'Today\'s read';

  @override
  String get dietFullPlan => 'Full plan';

  @override
  String dietDayCountCaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count DAYS',
      one: '1 DAY',
    );
    return '$_temp0';
  }

  @override
  String get dietNoTargetBody =>
      'Set one and the numbers above become progress toward a goal — and your coach can tell you where you stand.';

  @override
  String dietUseThisPlanKcal(String kcal) {
    return 'Use this plan\'s $kcal kcal';
  }

  @override
  String dietGoalKcalPerDayCaps(String goal, int kcal) {
    return '$goal · $kcal KCAL/DAY';
  }

  @override
  String dietBelowSafeFloor(String source, int kcal) {
    return '$source · below $kcal kcal — worth checking with a professional';
  }

  @override
  String get dietGainOrLose => 'Is this plan making you gain or lose?';

  @override
  String dietNeedsToWorkOut(String missing) {
    return 'ZIVO needs $missing to work it out.';
  }

  @override
  String dietListTwo(String first, String second) {
    return '$first and $second';
  }

  @override
  String dietListMany(String leading, String last) {
    return '$leading and $last';
  }

  @override
  String get dietThisPlanCaps => 'THIS PLAN';

  @override
  String get dietBodyDataCaps => 'BODY DATA';

  @override
  String dietAveragedOver(int counted, int missing) {
    String _temp0 = intl.Intl.pluralLogic(
      counted,
      locale: localeName,
      other: '$counted days',
      one: '1 day',
    );
    String _temp1 = intl.Intl.pluralLogic(
      missing,
      locale: localeName,
      other: '$missing days have',
      one: '1 day has',
    );
    return 'Averaged over $_temp0; $_temp1 no calorie figures.';
  }

  @override
  String dietProteinPerKg(String grams) {
    return 'Protein $grams g per kg of bodyweight.';
  }

  @override
  String dietStaleWeighIn(int days) {
    return 'Your last weigh-in is $days days old — weight drives this figure, so it is worth updating.';
  }

  @override
  String dietUnderSafeFloor(int kcal) {
    return 'This plan is under $kcal kcal a day. Sustained intake down here belongs with a doctor, not an app.';
  }

  @override
  String dietCalibrationPrompt(String missing) {
    return 'Log $missing and ZIVO can measure what you actually burn, instead of estimating it.';
  }

  @override
  String dietMeasuredDisagrees(int days, int measured, int used) {
    return 'Your last $days days say you actually burn about $measured — not the $used above. Worth updating.';
  }

  @override
  String dietMeasuredFrom(int days, int intake, String change) {
    return 'Measured from your last $days days: $intake kcal a day eaten, $change.';
  }

  @override
  String get dietWeightSteady => 'weight steady';

  @override
  String dietWeightUp(String kg) {
    return 'weight up $kg kg';
  }

  @override
  String dietWeightDown(String kg) {
    return 'weight down $kg kg';
  }

  @override
  String dietMacroProgress(String eaten, String target) {
    return '$eaten/${target}g';
  }

  @override
  String dietDayKcal(String kcal) {
    return '$kcal kcal';
  }

  @override
  String get dietMissingWeight => 'your current weight';

  @override
  String get dietMissingHeight => 'your height';

  @override
  String get dietMissingSex => 'the BMR formula ZIVO should use';

  @override
  String get dietMissingActivity => 'how active your week is';

  @override
  String get dietMissingDateOfBirth => 'your date of birth';

  @override
  String get dietSourceUsda => 'USDA FoodData Central';

  @override
  String get dietSourceUserCustom => 'Your own food';

  @override
  String get dietSourcePlan => 'Your diet plan';

  @override
  String get dietNoPlanYetHeadline => 'No diet plan yet.';

  @override
  String get dietNotFollowingHeadline => 'You\'re not following a plan.';

  @override
  String get dietNoPlanYetBody =>
      'Import a document or a photo, say it out loud, type it out, or build one by hand — I\'ll fill in the calories and macros.';

  @override
  String dietArchivedPlans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plans are archived — pick one back up, or add another.',
      one: '1 plan is archived — pick one back up, or add another.',
    );
    return '$_temp0';
  }

  @override
  String get dietSeeYourPlans => 'See your plans';

  @override
  String get dietFromYourPlan => 'from your plan';

  @override
  String dietQuantityUnit(String quantity, String unit) {
    return '$quantity $unit';
  }

  @override
  String dietKcalLeftOfTarget(String kcal) {
    return '$kcal kcal left of target';
  }

  @override
  String dietKcalLeftOfPlan(String kcal) {
    return '$kcal kcal left of plan';
  }

  @override
  String dietKcalOverTarget(String kcal) {
    return '$kcal kcal over target';
  }

  @override
  String dietMealsEaten(int eaten, int total) {
    return '$eaten of $total meals eaten';
  }

  @override
  String get dietNoCalorieDataCaps => 'NO CALORIE DATA YET';

  @override
  String get dietKcalOverCaps => 'KCAL OVER';

  @override
  String get dietKcalLeftCaps => 'KCAL LEFT';

  @override
  String get dietKcalLeftOfPlanCaps => 'KCAL LEFT OF PLAN';

  @override
  String get dietEstPrefixCaps => 'EST. ';

  @override
  String dietItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get dietViewDetails => 'View details';

  @override
  String get dietActivitySedentary => 'Sedentary';

  @override
  String get dietActivityLight => 'Light';

  @override
  String get dietActivityModerate => 'Moderate';

  @override
  String get dietActivityHigh => 'High';

  @override
  String get dietActivityAthlete => 'Very high';

  @override
  String get dietActivitySedentaryDetail =>
      'Desk job, little deliberate exercise';

  @override
  String get dietActivityLightDetail => 'Training 1–3 days a week';

  @override
  String get dietActivityModerateDetail => 'Training 3–5 days a week';

  @override
  String get dietActivityHighDetail => 'Training 6–7 days a week';

  @override
  String get dietActivityAthleteDetail =>
      'Hard training daily, or a physical job on top';

  @override
  String dietTargetBasisSummary(
    String weight,
    String activity,
    int maintenance,
  ) {
    return '$weight kg · $activity · $maintenance kcal maintenance';
  }

  @override
  String get dietSetYourTarget => 'Set your target';

  @override
  String get dietDailyTarget => 'Daily target';

  @override
  String get dietTargetsIntro =>
      'Your coach uses these numbers for everything it tells you. Until they\'re set, it can describe your plan but not how you\'re doing against it.';

  @override
  String get dietGoal => 'Goal';

  @override
  String get dietDailyNumbers => 'Daily numbers';

  @override
  String get dietCalculatedCaps => 'CALCULATED';

  @override
  String get dietOnlyCaloriesRequired =>
      'Only calories are required. Leave a macro blank if you aren\'t tracking it — blank means untracked, not zero.';

  @override
  String get dietFillFieldsHint =>
      'Fills the fields with a starting point you can edit. Nothing is saved until you tap Save.';

  @override
  String dietBelowSafeWarning(int calories, int floor) {
    return '$calories kcal is below $floor, which is under what ZIVO should be coaching. You can still save it, but eating this low is worth talking through with a doctor or a registered dietitian first.';
  }

  @override
  String dietCalculatedFrom(
    String weight,
    String activity,
    int bmr,
    int maintenance,
    String goal,
  ) {
    return 'From ${weight}kg at $activity activity: $bmr kcal at rest, $maintenance kcal to maintain, adjusted for $goal. These are population estimates — adjust them from what the scale actually does.';
  }

  @override
  String get dietSexMale => 'Male';

  @override
  String get dietSexFemale => 'Female';

  @override
  String dietStaleWeighInPrompt(int days) {
    return 'Your last weigh-in was $days days ago. Worth logging a new one first.';
  }

  @override
  String dietKgValue(String value) {
    return '$value kg';
  }

  @override
  String dietCmValue(int value) {
    return '$value cm';
  }

  @override
  String dietSearching(String source) {
    return 'Searching $source.';
  }

  @override
  String get dietFoodSearchHint => 'chicken breast, rice, olive oil…';

  @override
  String get dietEnterAmount => 'Enter an amount.';

  @override
  String get dietEnterAmountAboveZero => 'Enter an amount above zero.';

  @override
  String dietKcalPer100g(int kcal) {
    return '$kcal kcal / 100g';
  }

  @override
  String dietKcalPer100gTight(int kcal) {
    return '$kcal kcal/100g';
  }

  @override
  String get dietTypeToSearch => 'Type a food to search.';

  @override
  String dietNoCatalogMatch(String query) {
    return 'Nothing in the catalog matches \"$query\".';
  }

  @override
  String get dietCatalogThinBody =>
      'It\'s a USDA catalog, so it\'s thin on regional and home cooking. Rather than guess, tell ZIVO what this food is once and it\'ll remember.';

  @override
  String dietKcalValue(int kcal) {
    return '$kcal kcal';
  }

  @override
  String dietMacroLine(String protein, String carbs, String fat, String grams) {
    return 'P ${protein}g · C ${carbs}g · F ${fat}g · ${grams}g';
  }

  @override
  String dietWeightOnlyFood(String unit) {
    return 'ZIVO only has this food by weight — enter it in grams. Converting $unit would mean guessing a density.';
  }

  @override
  String dietNoSuchUnit(String unit, String alternatives) {
    return 'ZIVO doesn\'t have $unit for this food. Use grams, or: $alternatives';
  }

  @override
  String get dietCustomFoodHint =>
      'Per 100g, from the label or your own measure. ZIVO stores these as yours and never overwrites them.';

  @override
  String get dietMaintenanceCaps => 'MAINTENANCE';

  @override
  String dietKcalPerDay(int kcal) {
    return '$kcal kcal a day';
  }

  @override
  String get dietMaintenanceGiven => 'The figure you gave. ZIVO uses it as-is.';

  @override
  String get dietMaintenanceEstimated =>
      'Estimated from these numbers — a population average, not a measurement of you.';

  @override
  String dietDaysAgo(int days) {
    return '$days days ago';
  }

  @override
  String dietWeeksAgo(int weeks) {
    return '$weeks weeks ago';
  }

  @override
  String dietMonthsAgo(int months) {
    return '$months months ago';
  }

  @override
  String get dietCuisineEgyptian => 'Egyptian';

  @override
  String get dietCuisineMediterranean => 'Mediterranean';

  @override
  String get dietCuisineLevantine => 'Levantine';

  @override
  String get dietCuisineIndian => 'Indian';

  @override
  String get dietCuisineAsian => 'Asian';

  @override
  String get dietCuisineWestern => 'Western';

  @override
  String get dietImportOneRun =>
      'A run either reads material or designs a plan — never both.';

  @override
  String get dietGeneratingFoods => 'Choosing foods you like…';

  @override
  String get dietGeneratingCalories => 'Looking up real calories for each one…';

  @override
  String get dietGeneratingPortions => 'Sizing the portions to your target…';

  @override
  String get dietFileReadFailed => 'Couldn\'t read that file.';

  @override
  String dietFileTooLarge(int mb) {
    return 'That file is too large — please choose one under $mb MB.';
  }

  @override
  String get dietImportPlanTitle => 'Import Plan';

  @override
  String get dietBuildingYourPlan => 'Building your plan';

  @override
  String get dietReadingYourPlan => 'Reading your plan';

  @override
  String get dietSelectYourPlan => 'Select your diet plan';

  @override
  String get dietSelectYourPlanBody =>
      'Choose a PDF or a photo of your plan and I\'ll map it into a real, editable plan — estimating calories and macros wherever the document doesn\'t state them.';

  @override
  String get dietCouldntBuildPlan => 'ZIVO couldn\'t build that plan';

  @override
  String get dietNotADietPlan => 'This doesn\'t look like a diet plan';

  @override
  String get dietChooseDifferentFile => 'Choose a different file';

  @override
  String get dietGoBackAndEdit => 'Go back and edit';

  @override
  String get dietBuildManually => 'build the plan manually.';

  @override
  String get dietPreferencesIntro =>
      'ZIVO picks the foods and looks up what they actually weigh in calories — it doesn\'t guess them. Tell it what you eat and it will build a day you can review before anything is saved.';

  @override
  String get dietMealsADay => 'Meals a day';

  @override
  String get dietMealsADayNote =>
      'The single biggest reason a plan survives a working week, or does not.';

  @override
  String get dietKitchen => 'Kitchen';

  @override
  String get dietOptionalCaps => 'OPTIONAL';

  @override
  String get dietNothingSavedUntilReview =>
      'Nothing is saved until you review the plan and tap Save.';

  @override
  String dietSizedToTarget(int kcal) {
    return 'Sized to your target — $kcal kcal a day.';
  }

  @override
  String get dietNoTargetToSizeTo =>
      'ZIVO will still build the plan, but it has no figure to size the portions to. Set one first and the day comes out fitted to it.';

  @override
  String get dietOnePlanNote =>
      'One plan. Import or write another and you can switch between them without losing either.';

  @override
  String dietManyPlansNote(int count) {
    return '$count plans. One is in force at a time — the Diet screen always shows that one.';
  }

  @override
  String get dietNoPlansYet => 'No plans yet.';

  @override
  String dietDaysCaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count DAYS',
      one: '1 DAY',
    );
    return '$_temp0';
  }

  @override
  String dietKcalPerDayCaps(String kcal) {
    return '$kcal KCAL/DAY';
  }

  @override
  String get dietFollowingCaps => 'FOLLOWING';

  @override
  String get dietArchivedCaps => 'ARCHIVED';

  @override
  String get dietDraftCaps => 'DRAFT';

  @override
  String get dietWhatsInIt => 'What’s in it';

  @override
  String get dietSupplementMark => 'Supplement';

  @override
  String get dietNoItemsListed => 'No items listed for this meal.';

  @override
  String get dietMarkNotEaten => 'Mark as not eaten';

  @override
  String get dietMarkEaten => 'Done — mark as eaten';

  @override
  String get dietMacroP => 'P';

  @override
  String get dietMacroC => 'C';

  @override
  String get dietMacroF => 'F';

  @override
  String dietGramsValue(int grams) {
    return '${grams}g';
  }

  @override
  String get dietUsePlanNumbers => 'Use your plan\'s numbers';

  @override
  String dietPlanAverageOverDays(String kcal, int days, String plan) {
    return '$kcal kcal a day, averaged over the $days days of $plan.';
  }

  @override
  String dietPlanFrom(String kcal, String plan) {
    return '$kcal kcal a day, from $plan.';
  }

  @override
  String dietDaysWithoutCalories(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days have no calorie figures and are not in that average.',
      one: '1 day has no calorie figures and is not in that average.',
    );
    return '$_temp0';
  }

  @override
  String get dietWhatIsItFor => 'What is it for?';

  @override
  String get dietWhyGoalMatters =>
      'The same calories mean different things depending on what you\'re doing. ZIVO needs this to say how you\'re doing against them.';

  @override
  String dietPlanBelowSafeFloor(int kcal) {
    return 'This plan averages under $kcal kcal a day. Adopting it as a target is worth talking through with a doctor or a registered dietitian first.';
  }

  @override
  String get dietEveryDay => 'Every day';

  @override
  String get dietRemoveDay => 'Remove day';

  @override
  String get dietRemoveMeal => 'Remove meal';

  @override
  String get dietRemoveItem => 'Remove item';

  @override
  String get dietUnitCaps => 'UNIT';

  @override
  String get dietDescribeYourDiet => 'Describe your diet';

  @override
  String get dietTypeItOut => 'Type it out';

  @override
  String get dietDictateBody =>
      'Say or write what you eat in a day — meals, foods and rough amounts. ZIVO turns it into a plan you review before anything is saved.';

  @override
  String get dietDictateExample =>
      'Example: \"Breakfast is three eggs and 60 grams of oats. Lunch is 200 grams of chicken with rice and salad.\"';

  @override
  String get dietHideCaps => 'HIDE';

  @override
  String get dietWhyCaps => 'WHY';

  @override
  String get dietSourceManual => 'Written by hand';

  @override
  String get dietSourcePdf => 'Imported from a document';

  @override
  String get dietSourcePhoto => 'Imported from a photo';

  @override
  String get dietSourceDictated => 'Dictated';

  @override
  String get dietSourceGenerated => 'Built by ZIVO';

  @override
  String get dateTodayLower => 'today';

  @override
  String get dateYesterdayLower => 'yesterday';

  @override
  String get mediaCapturedOnAnotherDevice => 'Captured on another device';

  @override
  String get mediaOnAnotherBackupAccount => 'In another Drive account';

  @override
  String get storageTitle => 'Storage & Sync';

  @override
  String get storageSectionBackup => 'BACKUP & SYNC';

  @override
  String get storageSectionInstant => 'INSTANT SYNC';

  @override
  String get storageSectionDevicePhotos => 'DEVICE PHOTOS';

  @override
  String get storageUploadToDrive => 'Upload to Drive';

  @override
  String get storageSaveToPhotos => 'Save to Photos';

  @override
  String get storageAccountNote =>
      'Each ZIVO account keeps its own photos in its own Drive folder, so accounts never mix — even if they use the same Google Drive.';

  @override
  String get storageOnThisDevice => 'On this device';

  @override
  String get storageLocalFirst => 'Your photos are saved here first, always.';

  @override
  String storageSavedHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos saved here.',
      one: '1 photo saved here.',
    );
    return '$_temp0';
  }

  @override
  String get storageConnectDrive => 'Connect Google Drive';

  @override
  String get storageBackUpNow => 'Back up now';

  @override
  String get storageSync => 'Sync';

  @override
  String get storageDisconnect => 'Disconnect';

  @override
  String get storageUnavailableInBuild => 'Unavailable in this build';

  @override
  String get storageConnectedOnDevice => 'Connected on this device';

  @override
  String get storageNotConnectedOnDevice => 'Not connected on this device';

  @override
  String get storageConnectFailed => 'Couldn’t connect Google Drive.';

  @override
  String get storageConnectedToast => 'Google Drive connected on this device.';

  @override
  String get storageDisconnectedToast =>
      'Google Drive disconnected on this device.';

  @override
  String get storageAlreadyBackedUp => 'Everything is already backed up.';

  @override
  String get storageNothingNew => 'Nothing new to download.';

  @override
  String storageBackedUpToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Backed up $count photos to Drive.',
      one: 'Backed up 1 photo to Drive.',
    );
    return '$_temp0';
  }

  @override
  String storageDownloadedToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Downloaded $count photos from Drive.',
      one: 'Downloaded 1 photo from Drive.',
    );
    return '$_temp0';
  }

  @override
  String storageOtherAccountTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos in another Google account',
      one: '1 photo in another Google account',
    );
    return '$_temp0';
  }

  @override
  String get storageOtherAccountBody =>
      'Backed up before you switched accounts. Back up now copies the ones still on this device; for the rest, reconnect that account.';

  @override
  String get storageBackingUp => 'Backing up…';

  @override
  String get storageSyncing => 'Syncing…';

  @override
  String get storageCheckingPhotos => 'Checking your photos…';

  @override
  String storageProgressCount(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'photos',
      one: 'photo',
    );
    return '$done of $total $_temp0';
  }

  @override
  String get storageNothingYetTitle => 'Nothing to back up yet';

  @override
  String get storageNothingYetBody => 'Photos you add will back up here.';

  @override
  String get storageAllBackedUpTitle => 'All backed up';

  @override
  String storageAllSafeBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos are safe in Google Drive.',
      one: '1 photo is safe in Google Drive.',
    );
    return '$_temp0';
  }

  @override
  String storagePartialTitle(int backedUp, int total) {
    return '$backedUp of $total backed up';
  }

  @override
  String storagePendingBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos are waiting to back up.',
      one: '1 photo is waiting to back up.',
    );
    return '$_temp0';
  }

  @override
  String get sessionNoExercises => 'No exercises logged.';

  @override
  String get sessionDetailsTitle => 'Session details';

  @override
  String get sessionStatusCompleted => 'Completed';

  @override
  String get sessionStatusActive => 'In progress';

  @override
  String get sessionStatusAbandoned => 'Not completed';

  @override
  String get sessionStatDuration => 'Duration';

  @override
  String get sessionStatTime => 'Time';

  @override
  String get sessionStatExercises => 'Exercises';

  @override
  String get sessionStatSetsDone => 'Sets done';

  @override
  String sessionSetNumber(int index) {
    return 'Set $index';
  }

  @override
  String get sessionSetSkipped => 'Skipped';

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
      other: '$reps reps',
      one: '1 rep',
    );
    return '$_temp0';
  }

  @override
  String sessionSetRepsUnknown(String reps) {
    return '$reps reps';
  }

  @override
  String sessionTimeRange(String start, String end) {
    return '$start–$end';
  }

  @override
  String get splitsTitle => 'Splits';

  @override
  String get splitNewAction => 'New split';

  @override
  String splitCopyName(String name) {
    return '$name copy';
  }

  @override
  String splitDayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String splitMeta(String days, String exercises) {
    return '$days · $exercises';
  }

  @override
  String get splitSetActive => 'Set as active';

  @override
  String get actionDuplicate => 'Duplicate';

  @override
  String get splitActiveBadge => 'Active';

  @override
  String get splitsEmptyTitle => 'No splits yet.';

  @override
  String get splitsEmptyBody => 'Tap + to build your first one.';

  @override
  String workoutThisWeekCount(int count) {
    return '$count THIS WEEK';
  }

  @override
  String get workoutLogTodaysWeight => 'Log today\'s weight';

  @override
  String get workoutWeighInFailed =>
      'Couldn\'t save that weigh-in — check your connection and try again.';

  @override
  String get workoutNoPlanImportHint =>
      'Import a PDF or photo and I\'ll turn it into a real split, or build one from scratch.';

  @override
  String workoutWeightDeltaWindow(String delta) {
    return '$delta KG · 30D';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionApp => 'App';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsSectionMusic => 'Music';

  @override
  String get settingsSectionMedia => 'Media';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'Match my phone';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsBuild => 'Build';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy';

  @override
  String get settingsChangePassword => 'Change password';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String settingsVersionLine(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String settingsVersionValue(String version, String build) {
    return '$version ($build)';
  }

  @override
  String get settingsStorageSync => 'Storage & sync';

  @override
  String get settingsStorageSyncValue => 'Photos · Drive';

  @override
  String get connectedConnectedPaused => 'CONNECTED · PAUSED';

  @override
  String get connectedConnectedPlaying => 'CONNECTED · PLAYING';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authNameOptional => 'Name (optional)';

  @override
  String get authConfirmPassword => 'Confirm password';

  @override
  String get authNewPassword => 'New password';

  @override
  String get authCurrentPassword => 'Current password';

  @override
  String get authConfirmNewPassword => 'Confirm new password';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authHaveAccount => 'Already have an account?  ';

  @override
  String get authNewToZivo => 'New to ZIVO?  ';

  @override
  String get authTitleSignUp => 'Make your space.';

  @override
  String get authTitleSignIn => 'Your whole day, in one place.';

  @override
  String get authSignInWithApple => 'Sign in with Apple';

  @override
  String get authContinueWithGoogle => 'Continue with Google';

  @override
  String get authPasswordUpdated => 'Password updated.';

  @override
  String get authPasswordUpdatedSignIn =>
      'Password updated. Sign in with your new password.';

  @override
  String get authSignedOutOtherDevice =>
      'Your account was signed in on another device.';

  @override
  String authShowField(String label) {
    return 'Show $label';
  }

  @override
  String authHideField(String label) {
    return 'Hide $label';
  }

  @override
  String authOtpFieldLabel(int length) {
    return '$length-digit verification code';
  }

  @override
  String authCodeWrongWithAttempts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'That code isn’t right. $count tries left.',
      one: 'That code isn’t right. 1 try left.',
    );
    return '$_temp0';
  }

  @override
  String get authCodeWrong => 'That code isn’t right.';

  @override
  String get authCodeExpired => 'That code has expired. Send a new one.';

  @override
  String get authCodeTooManyAttempts => 'Too many attempts. Send a new code.';

  @override
  String get authCodeSent => 'A new code is on its way.';

  @override
  String get authSending => 'Sending…';

  @override
  String authResendIn(int seconds) {
    return 'Resend code in ${seconds}s';
  }

  @override
  String get authResendCode => 'Resend code';

  @override
  String get authDidntGetIt => 'Didn’t get it?  ';

  @override
  String get authResetTitle => 'Reset your password';

  @override
  String get authResetSubtitle =>
      'Enter your account email and we’ll send you a 6-digit code.';

  @override
  String get authSendCode => 'Send code';

  @override
  String get authEnterCode => 'Enter the code';

  @override
  String get authCodeSentTo => 'Enter the 6-digit code we sent to\n';

  @override
  String get authThenChoosePassword => ', then choose a new password.';

  @override
  String get authResetPassword => 'Reset password';

  @override
  String get authEmailLooksWrong => 'That email address doesn\'t look right.';

  @override
  String get authVerifyTitle => 'Verify your email';

  @override
  String get authVerify => 'Verify';

  @override
  String get authUseAnotherAccount => 'Use another account';

  @override
  String get authChangePasswordSubtitle =>
      'Confirm it’s you, then choose a new one.';

  @override
  String get authConfirmItsYou => 'Confirm it’s you';

  @override
  String get authUpdatePassword => 'Update password';

  @override
  String get authDeleteAccountBody =>
      'This permanently deletes your account and everything in it — workouts, diet, moments, expenses, and profile. This cannot be undone.';

  @override
  String get authDeleteConfirmPassword => 'Enter your password to confirm';

  @override
  String get authDeleteMyAccount => 'Delete my account';

  @override
  String get authPasswordStrength => 'Password strength';

  @override
  String get authPasswordStrong => 'Strong';

  @override
  String get authPasswordAlmost => 'Almost';

  @override
  String get authPasswordWeak => 'Weak';

  @override
  String get authPasswordsMatch => 'Passwords match';

  @override
  String get authPasswordsDontMatch => 'Passwords don\'t match';

  @override
  String authRuleState(String rule, String state) {
    return '$rule: $state';
  }

  @override
  String get authRuleMet => 'met';

  @override
  String get authRuleNotMet => 'not met';

  @override
  String get authRuleMinLength => 'At least 8 characters';

  @override
  String get authRuleMinLengthShort => '8+ characters';

  @override
  String get authRuleUppercase => 'One uppercase letter';

  @override
  String get authRuleUppercaseShort => 'Uppercase';

  @override
  String get authRuleLowercase => 'One lowercase letter';

  @override
  String get authRuleLowercaseShort => 'Lowercase';

  @override
  String get authRuleNumber => 'One number';

  @override
  String get authRuleNumberShort => 'Number';

  @override
  String get settingsPermanent => 'PERMANENT';

  @override
  String get momentTakePhoto => 'Take Photo';

  @override
  String get momentChooseFromLibrary => 'Choose from Library';

  @override
  String get momentEditPhoto => 'Edit Photo';

  @override
  String get momentEditTitle => 'Edit moment';

  @override
  String get momentNewTitle => 'New moment';

  @override
  String get momentDeleteAction => 'Delete moment';

  @override
  String get momentNoteHint => 'Say something…';

  @override
  String get momentSave => 'Save moment';

  @override
  String get momentAdd => 'Add moment';

  @override
  String get momentAddPhoto => 'Add a photo';

  @override
  String get momentRetake => 'Retake';

  @override
  String get momentRemove => 'Remove';

  @override
  String get momentSaveFailed => 'Couldn\'t save that moment.';

  @override
  String get momentDeleteFailed => 'Couldn\'t delete that moment.';

  @override
  String get momentsTitle => 'Moments';

  @override
  String get momentsFilterAll => 'All';

  @override
  String get momentsFilterPhotos => 'Photos';

  @override
  String get momentsFilterNotes => 'Notes';

  @override
  String get momentsFilterCamera => 'Camera';

  @override
  String get momentsFilterLibrary => 'Library';

  @override
  String get momentsEmptyTitle => 'Nothing logged yet';

  @override
  String get momentsEmptyBody =>
      'Snap a lift, a meal, or a scale reading — moments attach to the session you were in.';

  @override
  String get momentsEmptyCamera => 'No camera photos yet.';

  @override
  String get momentsEmptyLibrary => 'Nothing from your library yet.';

  @override
  String get momentsEmptyPhotos => 'No photos yet.';

  @override
  String get momentsEmptyNotes => 'No notes yet.';

  @override
  String get momentsEmptyOther => 'Nothing else logged yet';

  @override
  String get momentUntitled => 'Untitled';

  @override
  String get momentUntitledFull => 'Untitled moment';

  @override
  String get momentPhotoInfo => 'Photo info';

  @override
  String momentPhotoPosition(int index, int total) {
    return '$index of $total';
  }

  @override
  String get metaDate => 'Date';

  @override
  String get metaTime => 'Time';

  @override
  String get metaTimeZone => 'Time zone';

  @override
  String get metaCapturedWith => 'Captured with';

  @override
  String get metaDimensions => 'Dimensions';

  @override
  String get metaFileSize => 'File size';

  @override
  String get metaType => 'Type';

  @override
  String get metaLocation => 'Location';

  @override
  String get metaBackup => 'Backup';

  @override
  String get metaOnThisDevice => 'On this device';

  @override
  String get metaInPhotos => 'Photos';

  @override
  String get metaNotBackedUp => 'Not backed up yet';

  @override
  String get metaInDriveTapToDownload => 'In Google Drive — tap to download';

  @override
  String get captureSourceCamera => 'Camera';

  @override
  String get captureSourceLibrary => 'Photo Library';

  @override
  String get captureSourceUnknown => 'Unknown';

  @override
  String get musicNowPlaying => 'NOW PLAYING';

  @override
  String get musicClosePlayer => 'Close player';

  @override
  String get musicReadOnly =>
      'Playing on another device — controls are read-only here.';

  @override
  String get musicPreviousTrack => 'Previous track';

  @override
  String get musicNextTrack => 'Next track';

  @override
  String get musicShuffleOn => 'Shuffle on';

  @override
  String get musicShuffleOff => 'Shuffle off';

  @override
  String get musicRepeatOff => 'Repeat off';

  @override
  String get musicRepeatAll => 'Repeat all';

  @override
  String get musicRepeatOne => 'Repeat one';

  @override
  String get musicAuthFailed =>
      'Spotify didn\'t authorize the connection. Make sure you\'re signed in to Spotify, then try again.';

  @override
  String get musicTryAgain => 'Try again';

  @override
  String get musicPremiumRequired =>
      'Spotify Premium is required to control playback here.';

  @override
  String get musicConnectPrompt => 'Connect Spotify to see what\'s playing.';

  @override
  String get musicConnectSpotify => 'Connect Spotify';

  @override
  String musicTimeLeft(String time) {
    return '$time LEFT';
  }

  @override
  String musicStripMeta(String artist, String remaining) {
    return '$artist · $remaining';
  }

  @override
  String musicNowPlayingSemantics(String title, String artist) {
    return 'Now playing: $title by $artist. Open the player.';
  }

  @override
  String musicBatteryPercent(int percent) {
    return '$percent%';
  }

  @override
  String get importCouldntReadFile => 'Couldn\'t read that file.';

  @override
  String get importFileTooLarge =>
      'That file is too large — please choose one under 7 MB.';

  @override
  String get importSaveFailed =>
      'Couldn\'t save that split — check your connection and try again.';

  @override
  String get importReviewTitle => 'Review import';

  @override
  String get importPlanTitle => 'Import Plan';

  @override
  String get importSelectTitle => 'Select your training plan';

  @override
  String get importSelectBody =>
      'Choose a PDF or a photo of your plan and I\'ll map it into a real, editable split.';

  @override
  String get importChooseDifferentFile => 'Choose a different file';

  @override
  String get importStartOver => 'Start over';

  @override
  String get importNotAPlan => 'This doesn\'t look like a workout plan';

  @override
  String get importGoBackAndEdit => 'Go back and edit';

  @override
  String get importHeresWhatIFound => 'HERE\'S WHAT I FOUND';

  @override
  String get importDoingIt => 'Importing…';

  @override
  String get importThisSplit => 'Import this split';

  @override
  String get importEditBefore => 'Edit before importing';

  @override
  String importDayHeading(String slot, String label) {
    return 'Day $slot · $label';
  }

  @override
  String get importNoExercisesForDay => 'No exercises found for this day.';

  @override
  String get importComplete => 'Import complete';

  @override
  String importSummary(String name, String days, String exercises) {
    return '\"$name\" added to your splits — $days, $exercises.';
  }

  @override
  String importPlanShape(String days, String exercises) {
    return '$days · $exercises total';
  }

  @override
  String get importBuildManually => 'build the split manually.';

  @override
  String get exerciseEditTitle => 'Edit exercise';

  @override
  String get exerciseAddTitle => 'Add exercise';

  @override
  String get exerciseName => 'Name';

  @override
  String get exerciseNameHint => 'Bench Press';

  @override
  String get exerciseMuscleGroup => 'Muscle group (optional)';

  @override
  String get exerciseMuscleGroupHint => 'Chest';

  @override
  String get exerciseSets => 'Sets';

  @override
  String get exerciseRepTarget => 'REP TARGET';

  @override
  String get exerciseTargetFixed => 'Fixed';

  @override
  String get exerciseTargetRange => 'Range';

  @override
  String get exerciseMinReps => 'Min reps';

  @override
  String get exerciseMaxReps => 'Max reps';

  @override
  String get exerciseReps => 'Reps';

  @override
  String get exerciseWeightKg => 'Weight (kg)';

  @override
  String get exerciseSaveChanges => 'Save changes';

  @override
  String get workoutCaptureSaveFailed => 'Couldn\'t save that workout.';

  @override
  String get workoutCaptureDeleteFailed => 'Couldn\'t delete that workout.';

  @override
  String get workoutCaptureEditTitle => 'Edit workout';

  @override
  String get workoutCaptureNewTitle => 'New workout';

  @override
  String get workoutCaptureDelete => 'Delete workout';

  @override
  String get workoutCaptureNameHint => 'Name this session';

  @override
  String get workoutCaptureSave => 'Save workout';

  @override
  String get workoutCaptureNoExercises => 'No exercises yet.';

  @override
  String get workoutCaptureExerciseName => 'Exercise name';

  @override
  String get workoutCaptureRemove => 'Remove';

  @override
  String get importAppCheckDebug =>
      'The app couldn\'t verify itself (App Check). Register this build\'s debug token in the Firebase console, then try again.';

  @override
  String get importAppCheckFailed =>
      'Couldn\'t verify this app install. Please try again in a moment.';

  @override
  String get importServiceUnavailable =>
      'The import service isn\'t available right now — please try again later.';

  @override
  String get importNetworkProblem =>
      'Network problem reaching the import service — check your connection and try again.';

  @override
  String importCouldntRead(String manualFallback) {
    return 'Couldn\'t read that plan — try a clearer photo or PDF, or $manualFallback';
  }

  @override
  String importUnsupportedFileType(String extension) {
    return 'Unsupported file type: $extension';
  }

  @override
  String get describeMicNeeded =>
      'ZIVO needs microphone access to take this down. You can type it instead.';

  @override
  String get describeRecordFailed =>
      'Couldn\'t start recording. You can type it instead.';

  @override
  String get describeNothingRecorded =>
      'Nothing was recorded. Try again, or type it instead.';

  @override
  String get describeYourDescription => 'Your description';

  @override
  String get describeCheckWords =>
      'Check the words before you continue — a mis-heard detail becomes a number downstream.';

  @override
  String get describeSayItInstead => 'Say it instead';

  @override
  String get describeAddMoreByVoice => 'Add more by voice';

  @override
  String get describeWritingItDown => 'Writing it down…';

  @override
  String get describeListening => 'Listening';

  @override
  String get describeDiscard => 'Discard';

  @override
  String get importReadingDocument => 'Reading the document…';

  @override
  String importFoundNamed(String name) {
    return 'Found \"$name\"…';
  }

  @override
  String get importAnalyzing => 'Analyzing your plan';

  @override
  String get importBuildManuallyInstead => 'Build manually instead';

  @override
  String importSectionItems(String section, String items) {
    return '$section · $items';
  }

  @override
  String importItemCountDay(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String importItemCountMeal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count meals',
      one: '1 meal',
    );
    return '$_temp0';
  }

  @override
  String get workoutDescribeTitleVoice => 'Describe your training';

  @override
  String get workoutDescribeTitleType => 'Type it out';

  @override
  String get workoutDescribeBody =>
      'Say or write your split — the days, the exercises, and the sets and reps for each. ZIVO turns it into a real, editable split you review before anything is saved.';

  @override
  String get workoutDescribeExample =>
      'Example: \"Day A is push — bench press 4 sets of 8, incline dumbbell press 3 by 10, then cable flyes 3 by 15. Day B is pull…\"';

  @override
  String get workoutDescribeHint => 'Day A is push…';

  @override
  String get workoutDescribeSubmit => 'Turn this into a split';

  @override
  String get workoutDescribeDoneTalking => 'Done talking';

  @override
  String get addPlanTitle => 'Add a training plan';

  @override
  String get addPlanBody =>
      'However your split arrives, it lands in the same editor to review before anything is saved.';

  @override
  String get addPlanPdfTitle => 'PDF or photo';

  @override
  String get addPlanPdfBody =>
      'A coach\'s plan, a screenshot, a photo of a page';

  @override
  String get addPlanVoiceTitle => 'Say it out loud';

  @override
  String get addPlanVoiceBody => 'Describe your split and ZIVO writes it down';

  @override
  String get addPlanTypeTitle => 'Type it out';

  @override
  String get addPlanTypeBody => 'Write your split in a few lines';

  @override
  String get addPlanManualTitle => 'Build by hand';

  @override
  String get addPlanManualBody => 'Add days and exercises yourself';

  @override
  String importItemCountExercise(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '1 exercise',
    );
    return '$_temp0';
  }

  @override
  String importItemCountGeneric(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String pulseTrainedFor(String day, int minutes) {
    return '$day · $minutes MIN';
  }

  @override
  String pulseUnderWay(String day) {
    return '$day · UNDER WAY';
  }

  @override
  String pulseStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-day streak',
      one: '1-day streak',
    );
    return '$_temp0';
  }

  @override
  String pulseSessionsLast7(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count SESSIONS · LAST 7 DAYS',
      one: '1 SESSION · LAST 7 DAYS',
    );
    return '$_temp0';
  }

  @override
  String pulseWeightSpan(int days) {
    return 'KG · ${days}D';
  }

  @override
  String expenseSpentToday(String amount) {
    return '$amount SPENT TODAY';
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
  String get planEditSplitTitle => 'Edit split';

  @override
  String get planEditPlanTitle => 'Edit workout plan';

  @override
  String get planNewSplitTitle => 'New split';

  @override
  String get planNewPlanTitle => 'New workout plan';

  @override
  String get planDeleteSplit => 'Delete split';

  @override
  String get planDeletePlan => 'Delete plan';

  @override
  String get planName => 'Plan name';

  @override
  String get privacyTitle => 'Privacy';

  @override
  String privacyIntro(String date) {
    return 'How ZIVO handles your data.\nLast updated $date.';
  }

  @override
  String get privacyOverviewLabel => 'OVERVIEW';

  @override
  String get privacyOverviewBody =>
      'ZIVO is a private, personal application for organizing the parts of your day — moments, workouts, diet, expenses, and more — in one calm place. This policy explains what ZIVO stores, how it is used, and the choices you have.';

  @override
  String get privacyShortLabel => 'THE SHORT VERSION';

  @override
  String get privacyShortBullet1 =>
      'Your content is private to your account and never sold or shared for ads.';

  @override
  String get privacyShortBullet2 =>
      'ZIVO does not use your data or your content to train third-party models.';

  @override
  String get privacyShortBullet3 =>
      'Backups live in your own Google Drive, under your own control.';

  @override
  String get privacyShortBullet4 =>
      'You can delete your content at any time, from inside the app.';

  @override
  String get privacyAccountLabel => 'ACCOUNT & AUTHENTICATION';

  @override
  String get privacyAccountBody =>
      'ZIVO uses Firebase Authentication to sign you in, with Apple, Google, or email/password as sign-in options. Depending on the method you choose, ZIVO receives basic account details such as your name, email address, and a unique account identifier. That identifier is what keeps every piece of your data scoped to your account only.';

  @override
  String get privacyOtpLabel => 'EMAIL VERIFICATION CODES';

  @override
  String get privacyOtpBody =>
      'If you sign in with email, ZIVO sends a short verification code to confirm your address. Codes are hashed before storage, expire within minutes, and are used for nothing beyond verifying that the address is yours.';

  @override
  String get privacyContentLabel => 'YOUR CONTENT';

  @override
  String get privacyContentBody =>
      'Everything you create in ZIVO — moments, workout plans and sessions, diet plans and entries, expense logs, body-weight entries, and profile details — is stored in your account so the app can show it back to you across your devices. It is private to you and not visible to other users.';

  @override
  String get privacyPhotosLabel => 'PHOTOS & LOCAL STORAGE';

  @override
  String get privacyPhotosBody =>
      'Where a feature lets you attach a photo (such as Moments or your profile), ZIVO accesses your photo library only when you pick or capture an image. Media lives first on your device; cloud backup happens only through the backup target you explicitly choose.';

  @override
  String get privacyAskLabel => 'AI ASSISTANT (“ASK”)';

  @override
  String get privacyAskBody =>
      'Ask is an opt-in assistant that can answer questions about your own data — your workouts, meals, and spending. When you send a message, the relevant context is processed by the model provider solely to answer you. Conversations are stored privately in your account so history works across devices, and are never used to train third-party models.';

  @override
  String get privacySpotifyLabel => 'SPOTIFY';

  @override
  String get privacySpotifyBody =>
      'The music feature connects to your own Spotify account when you ask it to. ZIVO uses Spotify’s official SDK to control playback and read what’s currently playing. You can disconnect at any time, from Settings.';

  @override
  String get privacyMetadataLabel => 'ACCOUNT & SECURITY METADATA';

  @override
  String get privacyMetadataBody =>
      'To keep your account safe and supportable, ZIVO keeps a small record of authentication events — when your account was created, when you last signed in and how, and when verification emails were sent. This metadata is security bookkeeping: it is never sold, shared, or used for advertising.';

  @override
  String get privacyDriveLabel => 'GOOGLE DRIVE BACKUP';

  @override
  String get privacyDriveBody =>
      'Backup is optional and, if enabled, runs against your own Google Drive — using Google’s most restrictive drive.file scope, which lets ZIVO see and manage only the files it created itself. ZIVO never requests broad access to your Drive, and your files remain under your control there.';

  @override
  String get privacySharingLabel => 'DATA SHARING';

  @override
  String get privacySharingBody =>
      'ZIVO does not sell or rent personal data. Data is processed only by the infrastructure needed to run the app — Google Firebase (authentication, database, functions) — plus the integrations you explicitly enable: your own Google Drive and your own Spotify account.';

  @override
  String get privacyRetentionLabel => 'RETENTION & DELETION';

  @override
  String get privacyRetentionBody =>
      'Your content is retained until you delete it or delete your account. Files in your own Google Drive stay there until you remove them, and Drive access can be revoked at any time — from Settings or from your Google Account’s third-party access page.';

  @override
  String get privacySecurityLabel => 'SECURITY';

  @override
  String get privacySecurityBody =>
      'Access is enforced end-to-end: Firebase Authentication for identity and Firestore security rules so only your authenticated account can read or write your data. Verification codes are stored only as salted hashes. Data is encrypted in transit.';

  @override
  String get privacyChangesLabel => 'CHANGES TO THIS POLICY';

  @override
  String get privacyChangesBody =>
      'This policy may be updated as features evolve. The “last updated” date always reflects the most recent revision.';

  @override
  String get privacyContactLabel => 'CONTACT';

  @override
  String privacyContactBody(String email) {
    return 'Questions about privacy or your data can be sent to $email.';
  }

  @override
  String get sleepTitle => 'Sleep';

  @override
  String get sleepHubSubtitle => 'Last night';

  @override
  String get sleepLastNight => 'Last night';

  @override
  String get sleepNoDataTitle => 'No sleep recorded';

  @override
  String get sleepNoDataBody =>
      'Log a night yourself, or connect a device that tracks sleep.';

  @override
  String get sleepNotVisibleTitle => 'No sleep data visible to ZIVO';

  @override
  String sleepNotVisibleBody(String provider) {
    return '$provider doesn\'t say whether an app was refused access, so this may mean permission is off rather than that there\'s nothing there.';
  }

  @override
  String get sleepPermissionDeniedTitle => 'ZIVO can\'t read your sleep';

  @override
  String sleepPermissionDeniedBody(String provider) {
    return 'Allow Sleep access in $provider to see nights measured by your watch or another app.';
  }

  @override
  String get sleepUnavailableTitle => 'No health app on this device';

  @override
  String get sleepUnavailableBody => 'You can still log nights yourself.';

  @override
  String sleepHistoryUnavailable(String provider) {
    return 'Older nights need history access in $provider.';
  }

  @override
  String get sleepSyncFailed => 'Couldn\'t read sleep just now.';

  @override
  String sleepConnect(String provider) {
    return 'Connect $provider';
  }

  @override
  String get sleepProviderApple => 'Apple Health';

  @override
  String get sleepProviderHealthConnect => 'Health Connect';

  @override
  String get sleepProviderYou => 'You';

  @override
  String get sleepGoingToSleep => 'I\'m going to sleep';

  @override
  String get sleepImAwake => 'I\'m awake';

  @override
  String sleepMarkOpenSince(String time) {
    return 'Sleeping since $time';
  }

  @override
  String get sleepMarkCancel => 'Not sleeping after all';

  @override
  String get sleepEditNight => 'Edit this night';

  @override
  String get sleepEditHint =>
      'Your correction is saved as your own, and the measured times are kept.';

  @override
  String sleepOnsetMeasured(String time) {
    return 'Asleep $time';
  }

  @override
  String sleepOnsetPlatform(String time) {
    return 'Sleep recorded $time';
  }

  @override
  String sleepOnsetReported(String time) {
    return 'You logged $time';
  }

  @override
  String sleepOnsetEstimated(String time) {
    return 'Likely asleep around $time';
  }

  @override
  String sleepWakeMeasured(String time) {
    return 'Awake $time';
  }

  @override
  String sleepWakePlatform(String time) {
    return 'Wake recorded $time';
  }

  @override
  String sleepWakeReported(String time) {
    return 'You logged $time';
  }

  @override
  String sleepWakeEstimated(String time) {
    return 'Likely awake around $time';
  }

  @override
  String sleepLastPhoneUse(String time) {
    return 'Last phone use $time';
  }

  @override
  String get sleepMethodMeasured => 'Measured';

  @override
  String get sleepMethodRecorded => 'Recorded';

  @override
  String get sleepMethodLogged => 'Logged by you';

  @override
  String get sleepMethodEstimated => 'Estimate';

  @override
  String get sleepConfidenceHigh => 'High confidence';

  @override
  String get sleepConfidenceMedium => 'Medium confidence';

  @override
  String get sleepConfidenceLow => 'Low confidence';

  @override
  String sleepSourceChip(String provider, String method) {
    return '$provider · $method';
  }

  @override
  String get sleepDurationLabel => 'Asleep';

  @override
  String get sleepTimeInBedLabel => 'In bed';

  @override
  String get sleepEfficiencyLabel => 'Efficiency';

  @override
  String get sleepEfficiencyUnknown => 'Not tracked';

  @override
  String sleepInterruptionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count interruptions',
      one: '1 interruption',
      zero: 'No interruptions',
    );
    return '$_temp0';
  }

  @override
  String sleepNapCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count naps',
      one: '1 nap',
    );
    return '$_temp0';
  }

  @override
  String get sleepSpansDstNote =>
      'This night crossed a clock change, so its length differs from the times shown.';

  @override
  String get sleepTargetsTitle => 'Your targets';

  @override
  String get sleepTargetBedtime => 'Bedtime';

  @override
  String get sleepTargetWake => 'Wake';

  @override
  String get sleepTargetDuration => 'Sleep length';

  @override
  String get sleepTargetsHint =>
      'Used for the target line and nothing else — ZIVO never scores a night.';

  @override
  String get sleepNoTargets => 'Set a target to see how your nights compare.';

  @override
  String sleepDeltaLonger(String amount, String target) {
    return '$amount more than your $target target';
  }

  @override
  String sleepDeltaShorter(String amount, String target) {
    return '$amount less than your $target target';
  }

  @override
  String sleepDeltaOnTarget(String target) {
    return 'On your $target target';
  }

  @override
  String sleepBedtimeLater(String amount) {
    return '$amount later than your target bedtime';
  }

  @override
  String sleepBedtimeEarlier(String amount) {
    return '$amount earlier than your target bedtime';
  }

  @override
  String get sleepBedtimeOnTarget => 'On your target bedtime';

  @override
  String get sleepWhyTitle => 'Why this number?';

  @override
  String get sleepWhySole => 'Only one source had this night.';

  @override
  String get sleepWhyMethod =>
      'Chosen because it was measured rather than entered or estimated.';

  @override
  String get sleepWhyCoverage =>
      'Chosen because more of the night was actually recorded.';

  @override
  String get sleepWhyDetail => 'Chosen because it included sleep stages.';

  @override
  String get sleepWhyOverride => 'You set this night yourself.';

  @override
  String sleepDisagreement(String provider, String amount) {
    return '$provider recorded a different time — $amount apart.';
  }

  @override
  String get sleepCoverageLabel => 'Recorded coverage';

  @override
  String sleepRecordedBy(String provider) {
    return 'Recorded by $provider';
  }

  @override
  String get sleepUseThisInstead => 'Use this one instead';

  @override
  String get sleepWeekTitle => 'This week';

  @override
  String get sleepWeekAverage => 'Average';

  @override
  String get sleepWeekConsistency => 'Consistency';

  @override
  String get sleepWeekOnTarget => 'On target';

  @override
  String sleepNightsCounted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nights',
      one: '1 night',
    );
    return '$_temp0';
  }

  @override
  String sleepNightsOf(int count, int total) {
    return '$count of $total nights';
  }

  @override
  String sleepVariability(String amount) {
    return '±$amount';
  }

  @override
  String sleepOnTargetRatio(int count, int total) {
    return '$count of $total';
  }

  @override
  String get sleepNoData => 'No data';

  @override
  String get sleepInsufficient => 'Not enough nights yet';

  @override
  String sleepInsufficientFor(int have, int need) {
    return 'Not enough nights yet — $have of $need';
  }

  @override
  String get sleepWeekUnchanged => 'About the same as last week';

  @override
  String sleepWeekImproved(String amount) {
    return '$amount more than last week';
  }

  @override
  String sleepWeekDeclined(String amount) {
    return '$amount less than last week';
  }

  @override
  String get sleepInsightsTitle => 'What this means';

  @override
  String get sleepInsightsPending => 'Reading your nights…';

  @override
  String get sleepInsightsUnavailable =>
      'No conclusion can be drawn from the nights recorded so far.';

  @override
  String sleepInsightBasis(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nights',
      one: '1 night',
    );
    return 'Based on $_temp0';
  }

  @override
  String get sleepStageLight => 'Light';

  @override
  String get sleepStageDeep => 'Deep';

  @override
  String get sleepStageRem => 'REM';

  @override
  String get sleepStageAwake => 'Awake';

  @override
  String get sleepStageAsleep => 'Asleep';

  @override
  String get sleepStageInBed => 'In bed';

  @override
  String get sleepNoStages => 'Stages aren\'t available from this source.';

  @override
  String sleepDurationHm(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String sleepDurationM(int minutes) {
    return '${minutes}m';
  }

  @override
  String sleepDurationH(int hours) {
    return '${hours}h';
  }

  @override
  String get hubSleep => 'Sleep';

  @override
  String get hubNoSleepYet => 'No nights yet';

  @override
  String sleepInsightDuration(String amount) {
    return 'You\'ve averaged $amount a night.';
  }

  @override
  String sleepInsightWeekBetter(String amount) {
    return 'That\'s $amount more than the week before.';
  }

  @override
  String sleepInsightWeekWorse(String amount) {
    return 'That\'s $amount less than the week before.';
  }

  @override
  String get sleepInsightWeekSame =>
      'That\'s about the same as the week before.';

  @override
  String sleepInsightConsistent(String amount) {
    return 'Your sleep timing held steady, varying by $amount.';
  }

  @override
  String sleepInsightIrregular(String amount) {
    return 'Your sleep timing moved around by $amount across the week.';
  }

  @override
  String sleepInsightAdherence(int count, int total) {
    return 'You hit your target bedtime on $count of $total nights.';
  }

  @override
  String get sleepInsightTrendUp =>
      'Over the last few weeks your nights have been getting longer.';

  @override
  String get sleepInsightTrendDown =>
      'Over the last few weeks your nights have been getting shorter.';

  @override
  String get sleepUnitHour => 'h';

  @override
  String get sleepAboutTitle => 'How Sleep works';

  @override
  String get sleepAboutIntro =>
      'Sleep is a recovery input to your training. Here is exactly what ZIVO does with it, and what it will not claim.';

  @override
  String get sleepAboutSessionTitle => 'What a sleep session is';

  @override
  String get sleepAboutSessionBody =>
      'Tapping “I\'m going to sleep” opens a session and nothing else — no timer runs and your phone is not listening. When you tap “I\'m awake”, those two moments become the night, marked as logged by you.';

  @override
  String get sleepAboutTrackedTitle => 'What ZIVO reads';

  @override
  String sleepAboutTrackedBody(String provider) {
    return 'Each time you open this screen ZIVO re-reads $provider and rebuilds the last week: when you fell asleep, when you woke, how long you were actually asleep, and any time awake in between.';
  }

  @override
  String get sleepAboutSourcesTitle => 'Every number says where it came from';

  @override
  String get sleepAboutSourcesBody =>
      '“Measured” means a watch recorded it. “Logged by you” means you or an app typed it. When two sources disagree ZIVO picks one and keeps the other — it never averages them into a night nobody slept.';

  @override
  String get sleepAboutWeekTitle => 'Why some figures are blank';

  @override
  String get sleepAboutWeekBody =>
      'An average over one night is not an average. Weekly figures stay blank until enough nights exist, and each one shows how many it still needs.';

  @override
  String get sleepAboutLimitsTitle => 'What it will not do';

  @override
  String get sleepAboutLimitsBody =>
      'There is no sleep score and no streak. ZIVO can tell you how long you slept and how steady your schedule is; it cannot tell you whether the night was good.';

  @override
  String get sleepAboutDone => 'Got it';

  @override
  String get sleepSessionOpen => 'Sleeping';

  @override
  String get sleepMarkSoFar => 'So far';

  @override
  String get sleepMarkJustNow => 'Just now';

  @override
  String get sleepMarkHint =>
      'Tap “I\'m awake” when you get up — that is when the night is recorded.';

  @override
  String get sleepLoadFailedTitle => 'Couldn\'t load your sleep';

  @override
  String get sleepLoadFailedBody =>
      'ZIVO couldn\'t read the nights it has already saved. Check your connection and try again.';

  @override
  String get sleepRetry => 'Try again';

  @override
  String get sleepLoading => 'Loading your sleep';

  @override
  String sleepGateNeeds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Needs $count nights',
      one: 'Needs 1 night',
    );
    return '$_temp0';
  }

  @override
  String get sleepVsLastWeek => 'vs last week';

  @override
  String get sleepMarkFailed =>
      'Couldn\'t save that just now. Check your connection and try again.';

  @override
  String get sleepUnitMinute => 'm';

  @override
  String sleepHistoryStat(String average, String nights) {
    return 'Average $average · $nights';
  }

  @override
  String sleepNightsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nights ago',
      two: '2 nights ago',
    );
    return '$_temp0';
  }

  @override
  String get sleepStaleNotice =>
      'Nothing has been recorded since. This is your most recent night, not last night.';

  @override
  String get sleepStagesTitle => 'Stages';

  @override
  String sleepStagesUnavailable(String provider) {
    return '$provider recorded when you slept, but not which stages.';
  }

  @override
  String sleepStagesPartial(String amount) {
    return 'Staged for $amount of the night.';
  }

  @override
  String get sleepTimingTitle => 'Timing';

  @override
  String get sleepDetailTitle => 'Detail';

  @override
  String get sleepAgainstTargetTitle => 'Against your target';

  @override
  String sleepContextLonger(String amount, String average) {
    return '$amount longer than your average of $average.';
  }

  @override
  String sleepContextShorter(String amount, String average) {
    return '$amount shorter than your average of $average.';
  }

  @override
  String sleepContextTypical(String average) {
    return 'About your usual — you average $average.';
  }

  @override
  String sleepContextBasis(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nights',
      one: '1 night',
    );
    return 'Over $_temp0';
  }

  @override
  String get sleepHistoryTitle => 'Sleep history';

  @override
  String get sleepHistorySubtitle => 'Your weeks, night by night';

  @override
  String sleepWeekRange(String start, String end) {
    return '$start – $end';
  }

  @override
  String get sleepWeekCurrent => 'This week';

  @override
  String get sleepWeekEarlier => 'Earlier week';

  @override
  String get sleepWeekLater => 'Later week';

  @override
  String get sleepWeekEmpty => 'No nights were recorded in this week.';

  @override
  String get sleepWeekNightsTitle => 'Every night';

  @override
  String get sleepWeekTypicalTitle => 'Typical night';

  @override
  String get sleepWeekMedian => 'Median';

  @override
  String get sleepWeekBedtime => 'Bedtime';

  @override
  String get sleepWeekWake => 'Wake';

  @override
  String get sleepWeekCompositionTitle => 'Typical composition';

  @override
  String sleepWeekCompositionBasis(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count staged nights',
      one: '1 staged night',
    );
    return 'Averaged over $_temp0';
  }

  @override
  String get sleepWeekNoStages => 'No night this week carried stage detail.';

  @override
  String get sleepTrendTitle => 'Longer run';

  @override
  String get sleepTrendRising => 'Your nights have been getting longer.';

  @override
  String get sleepTrendFalling => 'Your nights have been getting shorter.';

  @override
  String get sleepTrendFlat => 'Your nights have held steady.';

  @override
  String sleepTrendBasis(int count, int days) {
    return '$count nights across $days days';
  }

  @override
  String sleepTrendNeedMore(int have, int need, int days) {
    return 'A trend needs $need nights across $days days. You have $have.';
  }

  @override
  String get sleepNightRowNoData => 'Nothing recorded';

  @override
  String sleepNightRowRange(String start, String end) {
    return '$start → $end';
  }

  @override
  String get liveFinishNow => 'Finish now';

  @override
  String get liveFinishNowTitle => 'Finish here?';

  @override
  String liveFinishNowBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sets are still unlogged. They stay unlogged — nothing is recorded as done.',
      one:
          '1 set is still unlogged. It stays unlogged — nothing is recorded as done.',
    );
    return '$_temp0';
  }

  @override
  String workoutStreakRule(int days) {
    return 'Train at least every $days days';
  }

  @override
  String get workoutStreakRestDay => 'Rest day';

  @override
  String get workoutStreakRestored => 'Restored';

  @override
  String workoutStreakDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days left to train',
      one: '1 day left to train',
      zero: 'Train today to keep it',
    );
    return '$_temp0';
  }

  @override
  String get workoutStreakBroken => 'No active streak';

  @override
  String get workoutStreakRestore => 'Restore this day';

  @override
  String get workoutStreakRestoreTitle => 'Restore this day?';

  @override
  String get workoutStreakRestoreBody =>
      'It bridges the gap so your streak survives. It does not add a workout, and it never counts as one.';

  @override
  String workoutStreakRestoreUnavailable(int days) {
    return 'One restore every $days days';
  }

  @override
  String get workoutStreakWhyMissed => 'Why no training?';

  @override
  String get workoutStreakReasonSaved =>
      'Context only — it never changes your streak.';

  @override
  String get missedDayRest => 'Rest';

  @override
  String get missedDayRecovery => 'Recovery';

  @override
  String get missedDayTravel => 'Travel';

  @override
  String get missedDayIllness => 'Illness';

  @override
  String get missedDayBusy => 'Too busy';

  @override
  String get missedDayOther => 'Something else';

  @override
  String get missedDayNone => 'No reason given';

  @override
  String get sessionDurationMeasured => 'Timed by ZIVO';

  @override
  String get sessionDurationAutoClosed => 'Closed at your last set';

  @override
  String get sessionDurationCorrected => 'You set this';

  @override
  String get sessionDurationUnknown => 'Duration unknown';

  @override
  String get sessionNeedsDuration => 'Needs a duration';

  @override
  String get sessionNeedsDurationBody =>
      'This session ran longer than a workout plausibly does, so it is left out of your averages until you set its length. Everything you logged is kept.';

  @override
  String get sessionSetDuration => 'Set duration';

  @override
  String get sessionDurationMinutes => 'Minutes';

  @override
  String get sessionDurationUseMeasured => 'Use the measured time';

  @override
  String get sessionVoid => 'Void this session';

  @override
  String get sessionVoidTitle => 'Void this session?';

  @override
  String get sessionVoidBody =>
      'It stays in your history exactly as logged, and stops counting toward your streak, averages and analysis.';

  @override
  String get sessionVoided => 'Voided';

  @override
  String get sessionUnvoid => 'Count this session again';

  @override
  String get sessionVoidReason => 'Why?';

  @override
  String get voidReasonBadDuration => 'The time is wrong';

  @override
  String get voidReasonLoggedByMistake => 'Logged by mistake';

  @override
  String get voidReasonNotMine => 'Wasn\'t me';

  @override
  String get voidReasonOther => 'Something else';

  @override
  String get sessionCannotDelete =>
      'A session that recorded work is voided, not deleted — so your history stays trustworthy.';

  @override
  String statDurationOver(int counted, int total) {
    return 'over $counted of $total';
  }

  @override
  String get statDurationAllExcluded => 'no usable session lengths yet';

  @override
  String get workoutSettings => 'Training settings';

  @override
  String get workoutMaxSessionTitle => 'Maximum session length';

  @override
  String get workoutMaxSessionBody =>
      'A workout still running past this, with nothing logged for a while, is treated as one you forgot to close. It is ended at your last logged set — never padded out, and never filled in with sets you did not do.';

  @override
  String get trainingDayMarkSaveFailed => 'Couldn\'t save that day.';

  @override
  String get sessionUpdateFailed => 'Couldn\'t update that session.';

  @override
  String get workoutSettingsSaveFailed => 'Couldn\'t save that setting.';

  @override
  String get remindersTitle => 'Reminders';

  @override
  String get remindersIntro =>
      'Get a notification when it\'s time to eat, train, or anything else you schedule.';

  @override
  String get remindersEmpty => 'No reminders yet';

  @override
  String get remindersEmptyBody =>
      'Add one to be reminded at the same time on the days you choose.';

  @override
  String get remindersAdd => 'Add reminder';

  @override
  String get remindersNewTitle => 'New reminder';

  @override
  String get remindersEditTitle => 'Edit reminder';

  @override
  String get remindersLabelHint => 'Name (e.g. Breakfast, Leg day)';

  @override
  String get remindersKindMeal => 'Meal';

  @override
  String get remindersKindWorkout => 'Workout';

  @override
  String get remindersKindGeneral => 'General';

  @override
  String get remindersTimeLabel => 'Time';

  @override
  String get remindersRepeatLabel => 'Repeat';

  @override
  String get remindersEveryDay => 'Every day';

  @override
  String get remindersSave => 'Save';

  @override
  String get remindersDelete => 'Delete reminder';

  @override
  String get remindersDeleteConfirm => 'Delete this reminder?';

  @override
  String get remindersSaveFailed => 'Couldn\'t save that reminder.';

  @override
  String get remindersPermissionDenied =>
      'Turn on notifications for ZIVO in your phone\'s settings to get reminders.';

  @override
  String get remindersSyncFromPlan => 'Sync from your plan';

  @override
  String get remindersSyncWorkout => 'Sync with my plan';

  @override
  String get remindersSyncWorkoutHint =>
      'Shows your next scheduled workout, and keeps it up to date.';

  @override
  String get remindersPickMeal => 'Which meal?';

  @override
  String get remindersMealItems => 'Items';

  @override
  String get remindersAddItem => 'Add item';

  @override
  String get remindersNoMealPlan => 'No active meal plan to sync from.';

  @override
  String get remindersNoWorkoutPlan => 'No active workout plan to sync from.';

  @override
  String get remindersSyncedBadge => 'Synced';
}
