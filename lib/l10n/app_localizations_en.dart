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
}
