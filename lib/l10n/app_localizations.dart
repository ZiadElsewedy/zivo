import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// The app name. Not translated.
  ///
  /// In en, this message translates to:
  /// **'ZIVO'**
  String get appTitle;

  /// Confirms and stores an edit.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// Dismisses without saving.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// Closes a finished flow.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// Removes something permanently.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// Opens something for editing.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// Creates a new item.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// Takes one item off a list.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// Advances a step in a flow.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionNext;

  /// Re-runs an action that failed.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// Bottom bar: the Today surface.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get tabToday;

  /// Bottom bar: the module launcher.
  ///
  /// In en, this message translates to:
  /// **'Hub'**
  String get tabHub;

  /// Bottom bar: the AI coach.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get tabAsk;

  /// Bottom bar: profile and settings.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get tabYou;

  /// Title of the Diet screen.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get dietTitle;

  /// A meal in today's plan, numbered in order. The primary label on the Diet screen — the plan's own meal name is shown quietly beneath it.
  ///
  /// In en, this message translates to:
  /// **'Meal {number}'**
  String dietMealNumber(int number);

  /// The single number on the Diet screen: calories remaining today.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal left'**
  String dietKcalLeft(int kcal);

  /// Shown instead of dietKcalLeft once the day's allowance is exceeded.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal over'**
  String dietKcalOver(int kcal);

  /// Section heading for the food log — anything eaten outside the plan.
  ///
  /// In en, this message translates to:
  /// **'Eaten today'**
  String get dietEatenToday;

  /// Button that opens the food log sheet.
  ///
  /// In en, this message translates to:
  /// **'Add something you ate'**
  String get dietLogSomething;

  /// Section heading for supplement items.
  ///
  /// In en, this message translates to:
  /// **'Supplements'**
  String get dietSupplements;

  /// Shown when the active plan has no day for today.
  ///
  /// In en, this message translates to:
  /// **'No meals planned today'**
  String get dietNoPlanToday;

  /// Empty state when the user has no diet plan at all.
  ///
  /// In en, this message translates to:
  /// **'No diet yet'**
  String get dietNoPlan;

  /// Opens the sheet with every way to create a plan.
  ///
  /// In en, this message translates to:
  /// **'Add a diet'**
  String get dietAddPlan;

  /// Opens the plan library.
  ///
  /// In en, this message translates to:
  /// **'Your diets'**
  String get dietYourPlans;

  /// Opens the screen holding the target, verdict and full plan.
  ///
  /// In en, this message translates to:
  /// **'Plan details'**
  String get dietPlanDetails;

  /// Title of the one screen that collects height, weight, sex and activity.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get bodyTitle;

  /// Height prompt. Deliberately a plain question, not a labelled field.
  ///
  /// In en, this message translates to:
  /// **'How tall are you?'**
  String get bodyHeightQuestion;

  /// Weight prompt.
  ///
  /// In en, this message translates to:
  /// **'What do you weigh?'**
  String get bodyWeightQuestion;

  /// Sex prompt, used by the energy equation.
  ///
  /// In en, this message translates to:
  /// **'Sex'**
  String get bodySexQuestion;

  /// Activity level prompt.
  ///
  /// In en, this message translates to:
  /// **'How active are you?'**
  String get bodyActivityQuestion;

  /// Sex option.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get bodySexMale;

  /// Sex option.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get bodySexFemale;

  /// Centimetres, the height unit.
  ///
  /// In en, this message translates to:
  /// **'cm'**
  String get unitCm;

  /// Kilograms, the weight unit.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get unitKg;

  /// Kilocalories.
  ///
  /// In en, this message translates to:
  /// **'kcal'**
  String get unitKcal;

  /// Grams, the macro unit.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get unitGrams;

  /// Settings row that opens the language picker.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Language option. Written in its own language on purpose.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Language option. Written in its own language on purpose.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get settingsLanguageArabic;

  /// Language option: follow the device locale.
  ///
  /// In en, this message translates to:
  /// **'Match my phone'**
  String get settingsLanguageSystem;

  /// Heading for the chips of foods to build the plan around.
  ///
  /// In en, this message translates to:
  /// **'Foods you like'**
  String get prefsLikes;

  /// One-line note under the likes chips.
  ///
  /// In en, this message translates to:
  /// **'ZIVO builds around these.'**
  String get prefsLikesNote;

  /// Heading for the chips of foods to leave out.
  ///
  /// In en, this message translates to:
  /// **'Foods you won\'t eat'**
  String get prefsAvoid;

  /// One-line note under the avoid chips.
  ///
  /// In en, this message translates to:
  /// **'Left out of the plan.'**
  String get prefsAvoidNote;

  /// Heading for the allergen chips.
  ///
  /// In en, this message translates to:
  /// **'Allergies'**
  String get prefsAllergies;

  /// Note under the allergen chips. Deliberately says the check is not a guarantee.
  ///
  /// In en, this message translates to:
  /// **'ZIVO refuses a plan that contains these. Still read it yourself.'**
  String get prefsAllergiesNote;

  /// Heading for the one free-text field on the preferences screen.
  ///
  /// In en, this message translates to:
  /// **'Anything else'**
  String get prefsNotes;

  /// Placeholder for the free-text notes field.
  ///
  /// In en, this message translates to:
  /// **'I train at 6am and eat straight after'**
  String get prefsNotesHint;

  /// Chip that opens a text field for something not in the list.
  ///
  /// In en, this message translates to:
  /// **'Other…'**
  String get prefsOther;

  /// Title of the sheet opened by the Other chip.
  ///
  /// In en, this message translates to:
  /// **'Add your own'**
  String get prefsAddYourOwn;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Chicken'**
  String get foodChicken;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Beef'**
  String get foodBeef;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Fish'**
  String get foodFish;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Tuna'**
  String get foodTuna;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Eggs'**
  String get foodEggs;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Rice'**
  String get foodRice;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Pasta'**
  String get foodPasta;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Bread'**
  String get foodBread;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Potatoes'**
  String get foodPotato;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Oats'**
  String get foodOats;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Yoghurt'**
  String get foodYoghurt;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Cheese'**
  String get foodCheese;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Beans and lentils'**
  String get foodBeans;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Vegetables'**
  String get foodVegetables;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Fruit'**
  String get foodFruit;

  /// Food chip.
  ///
  /// In en, this message translates to:
  /// **'Nuts'**
  String get foodNuts;

  /// Allergen chip.
  ///
  /// In en, this message translates to:
  /// **'Peanuts'**
  String get allergenPeanuts;

  /// Allergen chip.
  ///
  /// In en, this message translates to:
  /// **'Tree nuts'**
  String get allergenTreeNuts;

  /// Allergen chip.
  ///
  /// In en, this message translates to:
  /// **'Milk'**
  String get allergenMilk;

  /// Allergen chip.
  ///
  /// In en, this message translates to:
  /// **'Eggs'**
  String get allergenEggs;

  /// Allergen chip.
  ///
  /// In en, this message translates to:
  /// **'Fish'**
  String get allergenFish;

  /// Allergen chip.
  ///
  /// In en, this message translates to:
  /// **'Shellfish'**
  String get allergenShellfish;

  /// Allergen chip.
  ///
  /// In en, this message translates to:
  /// **'Soy'**
  String get allergenSoy;

  /// Allergen chip.
  ///
  /// In en, this message translates to:
  /// **'Gluten'**
  String get allergenGluten;

  /// Allergen chip.
  ///
  /// In en, this message translates to:
  /// **'Sesame'**
  String get allergenSesame;

  /// One-line reason the body-data screen exists. Replaced four sentences of explanation.
  ///
  /// In en, this message translates to:
  /// **'ZIVO needs these to work out what your plan does to your weight.'**
  String get bodyIntro;

  /// Note under the weight field: says where the number goes, in one line.
  ///
  /// In en, this message translates to:
  /// **'Saved to your weigh-in log.'**
  String get bodyWeighInNote;

  /// Note under the weight field once a weigh-in exists.
  ///
  /// In en, this message translates to:
  /// **'Last weigh-in {ago}. Change the number to log a new one.'**
  String bodyLastWeighIn(String ago);

  /// Shown when the entered height is outside the plausible range.
  ///
  /// In en, this message translates to:
  /// **'Heights go in centimetres, not metres.'**
  String get bodyHeightRange;

  /// Quiet row that reveals the optional known-maintenance field. Phrased as something the user knows about themselves, not as an engine input.
  ///
  /// In en, this message translates to:
  /// **'I already know my daily calories'**
  String get bodyKnowMaintenance;

  /// Note under the known-maintenance field, shown only once revealed.
  ///
  /// In en, this message translates to:
  /// **'From a test, a coach, or your own tracking. ZIVO will use it instead of its own estimate.'**
  String get bodyMaintenanceNote;

  /// Shown when the known-maintenance figure is implausible.
  ///
  /// In en, this message translates to:
  /// **'That looks like a typo.'**
  String get bodyMaintenanceRange;

  /// Confirmation after saving body data.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get bodySaved;

  /// Home greeting before noon, when the name is known.
  ///
  /// In en, this message translates to:
  /// **'Morning, {name}'**
  String greetingMorningNamed(String name);

  /// Home greeting between noon and 6pm.
  ///
  /// In en, this message translates to:
  /// **'Afternoon, {name}'**
  String greetingAfternoonNamed(String name);

  /// Home greeting after 6pm.
  ///
  /// In en, this message translates to:
  /// **'Evening, {name}'**
  String greetingEveningNamed(String name);

  /// Home greeting before noon with no name on file.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetingMorning;

  /// Home greeting between noon and 6pm with no name on file.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingAfternoon;

  /// Home greeting after 6pm with no name on file.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetingEvening;

  /// Hub module tile.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get hubWorkout;

  /// Hub module tile.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get hubDiet;

  /// Hub module tile.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get hubExpenses;

  /// Hub module tile.
  ///
  /// In en, this message translates to:
  /// **'Moments'**
  String get hubMoments;

  /// Hub tile subtitle when no plan exists.
  ///
  /// In en, this message translates to:
  /// **'No plan yet'**
  String get hubNoPlanYet;

  /// Hub tile subtitle when no moments exist.
  ///
  /// In en, this message translates to:
  /// **'No moments yet'**
  String get hubNoMomentsYet;

  /// Placeholder on a module that isn't built yet.
  ///
  /// In en, this message translates to:
  /// **'Coming next.'**
  String get comingNext;

  /// Body of the shared error state.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again in a moment.'**
  String get errorCheckConnection;

  /// The shared back chip's label.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// Accessibility label for Today's mic button.
  ///
  /// In en, this message translates to:
  /// **'Quick log by voice'**
  String get todayQuickLogVoice;

  /// Accessibility label for Today's time-of-day glyph.
  ///
  /// In en, this message translates to:
  /// **'Daytime'**
  String get todayDaytime;

  /// Accessibility label for Today's time-of-day glyph.
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get todayEvening;

  /// Accessibility label for Today's time-of-day glyph.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get todayNight;

  /// Caption above the next training session on Today. All-caps mono.
  ///
  /// In en, this message translates to:
  /// **'NEXT SESSION'**
  String get todayNextSession;

  /// Where the next session sits in the plan's rotation.
  ///
  /// In en, this message translates to:
  /// **'WEEK {week} · DAY {day}'**
  String todayPlanPosition(int week, int day);

  /// Title of Today's empty training card.
  ///
  /// In en, this message translates to:
  /// **'No training plan yet'**
  String get todayNoPlanTitle;

  /// Body of Today's empty training card.
  ///
  /// In en, this message translates to:
  /// **'Import your split from a PDF or photo and ZIVO turns it into a real rotating plan — or build one by hand.'**
  String get todayNoPlanBody;

  /// Primary action on Today's empty training card.
  ///
  /// In en, this message translates to:
  /// **'Import a plan'**
  String get todayImportPlan;

  /// Secondary action on Today's empty training card.
  ///
  /// In en, this message translates to:
  /// **'Build manually instead'**
  String get todayBuildManually;

  /// Shown when a plan exists but has no days yet.
  ///
  /// In en, this message translates to:
  /// **'Add training days and exercises to this split and it will show up here, ready to start.'**
  String get todayEmptySplitBody;

  /// Action that opens the plan editor.
  ///
  /// In en, this message translates to:
  /// **'Edit split'**
  String get todayEditSplit;

  /// Heading above Today's first-run shortcuts.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get todayGetStarted;

  /// First-run shortcut. The line break is deliberate — it sits in a narrow tile.
  ///
  /// In en, this message translates to:
  /// **'Import a\nworkout plan'**
  String get todayImportWorkoutPlan;

  /// First-run shortcut. The line break is deliberate — it sits in a narrow tile.
  ///
  /// In en, this message translates to:
  /// **'Add an\nexpense'**
  String get todayAddExpense;

  /// Caption on the Today pulse card.
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get pulseToday;

  /// Shown on the pulse card's training ring before the first session.
  ///
  /// In en, this message translates to:
  /// **'NOT YET TODAY'**
  String get pulseNotYetToday;

  /// Label of the pulse card's training stat.
  ///
  /// In en, this message translates to:
  /// **'Trained'**
  String get pulseTrained;

  /// Label of the pulse card's step stat.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get pulseSteps;

  /// Caption under the step count, naming the daily goal.
  ///
  /// In en, this message translates to:
  /// **'OF {goal}'**
  String pulseOfGoal(String goal);

  /// Shown where a step count would be on a device with no step sensor.
  ///
  /// In en, this message translates to:
  /// **'NO SENSOR'**
  String get pulseNoSensor;

  /// Label of the pulse card's training-volume stat.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get pulseVolume;

  /// Shown before any sets are logged.
  ///
  /// In en, this message translates to:
  /// **'NO SETS YET'**
  String get pulseNoSetsYet;

  /// Shown where a week-over-week comparison would be, in the first week.
  ///
  /// In en, this message translates to:
  /// **'FIRST WEEK'**
  String get pulseFirstWeek;

  /// Heading of the pulse card's streak/trend section.
  ///
  /// In en, this message translates to:
  /// **'Momentum'**
  String get pulseMomentum;

  /// Shown before a training streak exists.
  ///
  /// In en, this message translates to:
  /// **'NO STREAK YET'**
  String get pulseNoStreakYet;

  /// Shown before any session is logged.
  ///
  /// In en, this message translates to:
  /// **'NO SESSIONS YET'**
  String get pulseNoSessionsYet;

  /// Heading above the insight nudges.
  ///
  /// In en, this message translates to:
  /// **'Worth knowing'**
  String get pulseWorthKnowing;

  /// Insight headline when a training streak is running.
  ///
  /// In en, this message translates to:
  /// **'{days}-day training streak'**
  String insightStreakTitle(int days);

  /// Body of the streak insight.
  ///
  /// In en, this message translates to:
  /// **'Momentum is real right now — protect it with today\'s session.'**
  String get insightStreakBody;

  /// Insight headline after a long gap between sessions.
  ///
  /// In en, this message translates to:
  /// **'Rest has stretched to {days} days'**
  String insightRestTitle(int days);

  /// Body of the rest-gap insight. Deliberately not scolding.
  ///
  /// In en, this message translates to:
  /// **'No guilt — just the next small session whenever you\'re ready.'**
  String get insightRestBody;

  /// Insight headline when meals are still unticked in the evening.
  ///
  /// In en, this message translates to:
  /// **'Evening check-in'**
  String get insightEveningTitle;

  /// Body when exactly one planned meal is unticked and no calorie figure is available.
  ///
  /// In en, this message translates to:
  /// **'One meal still open today — worth closing it out.'**
  String get insightMealsLeftOne;

  /// Body when exactly one planned meal is unticked. The ~ marks an estimated figure.
  ///
  /// In en, this message translates to:
  /// **'One meal still open today (~{kcal} kcal) — worth closing it out.'**
  String insightMealsLeftOneKcal(int kcal);

  /// Body when several planned meals are unticked and no calorie figure is available.
  ///
  /// In en, this message translates to:
  /// **'{count} meals still open today.'**
  String insightMealsLeftMany(int count);

  /// Body when several planned meals are unticked.
  ///
  /// In en, this message translates to:
  /// **'{count} meals still open today (~{kcal} kcal left).'**
  String insightMealsLeftManyKcal(int count, int kcal);

  /// Insight headline when this week outspends the same stretch last week.
  ///
  /// In en, this message translates to:
  /// **'Spending is running ~{percent}% hot'**
  String insightSpendTitle(int percent);

  /// Body of the spending insight.
  ///
  /// In en, this message translates to:
  /// **'This week vs the same stretch last week — worth a glance.'**
  String get insightSpendBody;

  /// Insight headline when the step goal is at risk.
  ///
  /// In en, this message translates to:
  /// **'Steps are behind today'**
  String get insightStepsTitle;

  /// Body when the step goal is within easy reach.
  ///
  /// In en, this message translates to:
  /// **'Only {steps} steps from the goal — an easy walk closes it.'**
  String insightStepsClose(int steps);

  /// Body when the step goal is further off.
  ///
  /// In en, this message translates to:
  /// **'{steps} steps to go — even ten minutes helps.'**
  String insightStepsFar(int steps);

  /// Insight headline for a downward weight trend.
  ///
  /// In en, this message translates to:
  /// **'Weight down {kg} kg over {days} days'**
  String insightWeightDownTitle(String kg, int days);

  /// Insight headline for an upward weight trend.
  ///
  /// In en, this message translates to:
  /// **'Weight up {kg} kg over {days} days'**
  String insightWeightUpTitle(String kg, int days);

  /// Body for a downward weight trend.
  ///
  /// In en, this message translates to:
  /// **'Steady progress — keep eating enough to train hard.'**
  String get insightWeightDownBody;

  /// Body for an upward weight trend.
  ///
  /// In en, this message translates to:
  /// **'Nothing dramatic — watch the trend, not any single day.'**
  String get insightWeightUpBody;

  /// Title of the Workout hub.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get workoutTitle;

  /// Workout hub: opens the progress screen.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get workoutProgress;

  /// Workout hub section heading.
  ///
  /// In en, this message translates to:
  /// **'Training'**
  String get workoutTraining;

  /// Workout hub section heading for the weigh-in log.
  ///
  /// In en, this message translates to:
  /// **'Bodyweight'**
  String get workoutBodyweight;

  /// Opens the split library.
  ///
  /// In en, this message translates to:
  /// **'Splits'**
  String get workoutSplits;

  /// Opens week-over-week analysis.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get workoutAnalysis;

  /// Opens the session history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get workoutHistory;

  /// Action when no plan exists.
  ///
  /// In en, this message translates to:
  /// **'Create plan'**
  String get workoutCreatePlan;

  /// Action when a plan exists.
  ///
  /// In en, this message translates to:
  /// **'Edit plan'**
  String get workoutEditPlan;

  /// Empty state on the workout surfaces.
  ///
  /// In en, this message translates to:
  /// **'No workout plan yet'**
  String get workoutNoPlanYet;

  /// Shown when the rotation has nothing queued.
  ///
  /// In en, this message translates to:
  /// **'No day up next.'**
  String get workoutNoDayUpNext;

  /// Heading above the whole rotation.
  ///
  /// In en, this message translates to:
  /// **'Full cycle'**
  String get workoutFullCycle;

  /// Note under the rotation, telling the user they aren't locked to the suggested day.
  ///
  /// In en, this message translates to:
  /// **'Today\'s pick is marked — but any day is fair game. Life doesn\'t always follow the rotation.'**
  String get workoutAnyDayNote;

  /// All-caps caption above the next session.
  ///
  /// In en, this message translates to:
  /// **'UP NEXT'**
  String get workoutUpNext;

  /// Sentence-case heading above the next session.
  ///
  /// In en, this message translates to:
  /// **'Next up'**
  String get workoutNextUp;

  /// State of a session already started.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get workoutInProgress;

  /// All-caps badge on a session already started.
  ///
  /// In en, this message translates to:
  /// **'IN PROGRESS'**
  String get workoutInProgressCaps;

  /// Begins a session.
  ///
  /// In en, this message translates to:
  /// **'Start workout'**
  String get workoutStart;

  /// Returns to a session already started.
  ///
  /// In en, this message translates to:
  /// **'Resume workout'**
  String get workoutResume;

  /// Pauses the running session.
  ///
  /// In en, this message translates to:
  /// **'Pause workout'**
  String get workoutPause;

  /// Begins the session for a specific rotation day.
  ///
  /// In en, this message translates to:
  /// **'Start this day'**
  String get workoutStartThisDay;

  /// Opens the sheet for picking a different day.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get workoutChange;

  /// Title of the day-picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Change workout'**
  String get workoutChangeWorkout;

  /// A rotation day: its slot and its name.
  ///
  /// In en, this message translates to:
  /// **'Day {slot} · {label}'**
  String workoutDayLabel(String slot, String label);

  /// All-caps rotation-day badge.
  ///
  /// In en, this message translates to:
  /// **'DAY {slot}'**
  String workoutDaySlot(String slot);

  /// Caption on the up-next card's exercise count.
  ///
  /// In en, this message translates to:
  /// **'EXERCISES'**
  String get workoutExercises;

  /// Caption on the up-next card's set count.
  ///
  /// In en, this message translates to:
  /// **'SETS'**
  String get workoutSets;

  /// Caption on the up-next card's duration estimate.
  ///
  /// In en, this message translates to:
  /// **'MINUTES'**
  String get workoutMinutes;

  /// Confirmation before starting a session.
  ///
  /// In en, this message translates to:
  /// **'Ready to start {day}?'**
  String workoutReadyToStart(String day);

  /// Confirmation before resuming a session.
  ///
  /// In en, this message translates to:
  /// **'Ready to jump back in?'**
  String get workoutReadyToResume;

  /// Short confirm label on the start sheet.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get actionResume;

  /// Short confirm label on the start sheet.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get actionStart;

  /// The most recent logged bodyweight.
  ///
  /// In en, this message translates to:
  /// **'Last weigh-in: {kg} kg'**
  String weighInLast(String kg);

  /// Records a new bodyweight entry.
  ///
  /// In en, this message translates to:
  /// **'Log weigh-in'**
  String get weighInLog;

  /// Shown before any bodyweight is logged.
  ///
  /// In en, this message translates to:
  /// **'NO WEIGH-INS YET'**
  String get weighInNone;

  /// Prompt under the empty bodyweight chart.
  ///
  /// In en, this message translates to:
  /// **'Log one to start the trend.'**
  String get weighInStartTrend;

  /// How long ago the latest weigh-in was.
  ///
  /// In en, this message translates to:
  /// **'Logged {ago} ago'**
  String weighInLoggedAgo(String ago);

  /// Caption on a stat tile.
  ///
  /// In en, this message translates to:
  /// **'TOTAL'**
  String get statTotal;

  /// Label of the sessions stat tile.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get statSessions;

  /// Caption on the streak tile.
  ///
  /// In en, this message translates to:
  /// **'DAYS'**
  String get statDays;

  /// Label of the streak stat tile.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get statStreak;

  /// Caption on the duration tile — average minutes.
  ///
  /// In en, this message translates to:
  /// **'MIN AVG'**
  String get statMinAvg;

  /// Label of the duration stat tile.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get statDuration;

  /// Label of the usual-start-time stat tile.
  ///
  /// In en, this message translates to:
  /// **'Usual start'**
  String get statUsualStart;

  /// All-caps caption marking today.
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get commonToday;

  /// Shown with exactly one weigh-in on file.
  ///
  /// In en, this message translates to:
  /// **'Logged {ago} ago · one more reading draws the trend.'**
  String weighInOneMore(String ago);

  /// Title of the discard-session dialog.
  ///
  /// In en, this message translates to:
  /// **'Discard this workout?'**
  String get liveDiscardTitle;

  /// Body of the discard-session dialog. Names both consequences.
  ///
  /// In en, this message translates to:
  /// **'You\'ll lose this session\'s progress and the plan won\'t advance.'**
  String get liveDiscardBody;

  /// Dismisses the discard dialog.
  ///
  /// In en, this message translates to:
  /// **'Keep going'**
  String get liveKeepGoing;

  /// Confirms discarding the session.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get liveDiscard;

  /// Menu action that opens the discard dialog.
  ///
  /// In en, this message translates to:
  /// **'Discard workout'**
  String get liveDiscardWorkout;

  /// Shown when the day has no exercises.
  ///
  /// In en, this message translates to:
  /// **'NO EXERCISES'**
  String get liveNoExercises;

  /// Shown when there is no current exercise or set.
  ///
  /// In en, this message translates to:
  /// **'Nothing to do.'**
  String get liveNothingToDo;

  /// Confirmation caption after a set is recorded.
  ///
  /// In en, this message translates to:
  /// **'SET LOGGED'**
  String get liveSetLogged;

  /// Confirmation caption with the reps and load just recorded.
  ///
  /// In en, this message translates to:
  /// **'SET LOGGED · {detail}'**
  String liveSetLoggedDetail(String detail);

  /// How many sets are done so far. Count is zero-padded by the caller.
  ///
  /// In en, this message translates to:
  /// **'{count} SETS LOGGED'**
  String liveSetsLogged(String count);

  /// All-caps caption on the reps field.
  ///
  /// In en, this message translates to:
  /// **'REPS'**
  String get liveReps;

  /// All-caps caption on the weight field.
  ///
  /// In en, this message translates to:
  /// **'WEIGHT · KG'**
  String get liveWeightKg;

  /// Sentence-case label on the reps correction field.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get liveRepsField;

  /// Sentence-case label on the weight correction field.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get liveWeightField;

  /// Marks the set currently in progress.
  ///
  /// In en, this message translates to:
  /// **'NOW'**
  String get liveNow;

  /// The session's paused state.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get livePaused;

  /// All-caps paused badge.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get livePausedCaps;

  /// Caption on the dimmed paused screen.
  ///
  /// In en, this message translates to:
  /// **'PAUSED · TAP TO RESUME'**
  String get livePausedTapResume;

  /// The warm-up phase before the first set.
  ///
  /// In en, this message translates to:
  /// **'Pre-workout'**
  String get livePreWorkout;

  /// Caption above the first exercise during warm-up.
  ///
  /// In en, this message translates to:
  /// **'FIRST UP'**
  String get liveFirstUp;

  /// Skips straight to the first set.
  ///
  /// In en, this message translates to:
  /// **'Skip warm-up'**
  String get liveSkipWarmUp;

  /// The rest phase between sets.
  ///
  /// In en, this message translates to:
  /// **'REST'**
  String get liveRest;

  /// Ends the rest timer early.
  ///
  /// In en, this message translates to:
  /// **'Skip rest'**
  String get liveSkipRest;

  /// How long the rest was meant to be.
  ///
  /// In en, this message translates to:
  /// **'OF {total} PLANNED'**
  String liveRestPlanned(String total);

  /// Heading of the finished-session screen.
  ///
  /// In en, this message translates to:
  /// **'Workout complete'**
  String get liveWorkoutComplete;

  /// Ends the session and writes it to history.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get liveFinish;

  /// Heading of the personal-records celebration on the finished-session screen, shown when this session set one or more PRs.
  ///
  /// In en, this message translates to:
  /// **'New personal records'**
  String get livePrsTitle;

  /// Explains the prefilled goal.
  ///
  /// In en, this message translates to:
  /// **'Matching your previous set'**
  String get liveMatchingPrevious;

  /// Shown when there is no previous performance to match.
  ///
  /// In en, this message translates to:
  /// **'First time'**
  String get liveFirstTime;

  /// Caption when the goal equals last session's.
  ///
  /// In en, this message translates to:
  /// **'MATCHING LAST'**
  String get liveMatchingLast;

  /// One set in the list, by position.
  ///
  /// In en, this message translates to:
  /// **'Set {position}'**
  String liveSetNumber(int position);

  /// All-caps set badge.
  ///
  /// In en, this message translates to:
  /// **'SET {number}'**
  String liveSetNumberCaps(int number);

  /// All-caps set badge when a weight is shown alongside.
  ///
  /// In en, this message translates to:
  /// **'SET {number} · KG'**
  String liveSetNumberKg(int number);

  /// State of a set the user skipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get liveSkipped;

  /// All-caps badge on a skipped set.
  ///
  /// In en, this message translates to:
  /// **'SKIPPED'**
  String get liveSkippedCaps;

  /// Skips the current set.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get liveSkip;

  /// Records the current set.
  ///
  /// In en, this message translates to:
  /// **'Log set'**
  String get liveLogSet;

  /// Confirms a previously-skipped set as done.
  ///
  /// In en, this message translates to:
  /// **'Mark done'**
  String get liveMarkDone;

  /// Prompt when correcting a skipped set.
  ///
  /// In en, this message translates to:
  /// **'Enter what you actually did to mark this done.'**
  String get liveCorrectSkipped;

  /// Prompt when correcting a logged set.
  ///
  /// In en, this message translates to:
  /// **'Correct the reps or weight actually logged.'**
  String get liveCorrectLogged;

  /// Caption above the set's target.
  ///
  /// In en, this message translates to:
  /// **'GOAL'**
  String get liveGoal;

  /// Caption above what was done last session.
  ///
  /// In en, this message translates to:
  /// **'LAST TIME'**
  String get liveLastTime;

  /// Caption above the rep range.
  ///
  /// In en, this message translates to:
  /// **'TARGET RANGE'**
  String get liveTargetRange;

  /// Progression note: the load went up.
  ///
  /// In en, this message translates to:
  /// **'Weight up — you hit your reps last time'**
  String get liveWeightUp;

  /// Progression note: the load came down.
  ///
  /// In en, this message translates to:
  /// **'Weight eased — rebuild with clean reps'**
  String get liveWeightEased;

  /// Progression note: add a rep rather than weight.
  ///
  /// In en, this message translates to:
  /// **'Same load, one more rep'**
  String get liveSameLoadMoreRep;

  /// Quick-pick chip that repeats the previous weight.
  ///
  /// In en, this message translates to:
  /// **'Same · {kg}kg'**
  String liveSameWeight(String kg);

  /// Prompt to link Spotify from the rest screen.
  ///
  /// In en, this message translates to:
  /// **'CONNECT MUSIC'**
  String get liveConnectMusic;

  /// Dismisses a sheet.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// All-caps back affordance on the live session screen.
  ///
  /// In en, this message translates to:
  /// **'BACK'**
  String get actionBackCaps;

  /// How the load compares to the previous set today.
  ///
  /// In en, this message translates to:
  /// **'{delta}kg from your previous set'**
  String liveDeltaWeight(String delta);

  /// How the reps compare to the previous set today.
  ///
  /// In en, this message translates to:
  /// **'{delta} reps from your previous set'**
  String liveDeltaReps(String delta);

  /// A rep count on its own, when no load was recorded.
  ///
  /// In en, this message translates to:
  /// **'{reps} reps'**
  String liveRepsValue(int reps);

  /// A load on its own, when no rep count was recorded.
  ///
  /// In en, this message translates to:
  /// **'{kg} kg'**
  String liveWeightValue(String kg);

  /// Reps and load together — the usual case.
  ///
  /// In en, this message translates to:
  /// **'{reps} × {kg} kg'**
  String liveRepsByWeight(int reps, String kg);

  /// Built-in expense category.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get categoryFood;

  /// Built-in expense category.
  ///
  /// In en, this message translates to:
  /// **'Coffee'**
  String get categoryCoffee;

  /// Built-in expense category.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get categoryTransport;

  /// Built-in expense category — the weekly shop. Unrelated to the diet feature.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get categoryGroceries;

  /// Built-in expense category.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get categoryShopping;

  /// Built-in expense category, and the fallback for an unknown id.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get categoryOther;

  /// Title of the Expenses screen.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesTitle;

  /// Empty state on the Expenses list.
  ///
  /// In en, this message translates to:
  /// **'Nothing spent yet — a calm start.'**
  String get expensesEmpty;

  /// Title when logging a new expense.
  ///
  /// In en, this message translates to:
  /// **'New expense'**
  String get expenseNew;

  /// Title when editing an existing expense.
  ///
  /// In en, this message translates to:
  /// **'Edit expense'**
  String get expenseEdit;

  /// Removes an expense.
  ///
  /// In en, this message translates to:
  /// **'Delete expense'**
  String get expenseDelete;

  /// Label of the note field.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get expenseNote;

  /// Placeholder in the note field.
  ///
  /// In en, this message translates to:
  /// **'What was it for?'**
  String get expenseNoteHint;

  /// Opens the note field.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get expenseAddNote;

  /// Save button carrying the amount about to be recorded.
  ///
  /// In en, this message translates to:
  /// **'Save · {amount}'**
  String expenseSaveAmount(String amount);

  /// Caption above the wallet balance.
  ///
  /// In en, this message translates to:
  /// **'WALLET'**
  String get walletCaps;

  /// Caption on the wallet empty state.
  ///
  /// In en, this message translates to:
  /// **'SET UP YOUR WALLET'**
  String get walletSetUp;

  /// Prompt when setting the starting balance.
  ///
  /// In en, this message translates to:
  /// **'How much do you have right now?'**
  String get walletHowMuchNow;

  /// Explains that the wallet updates itself.
  ///
  /// In en, this message translates to:
  /// **'Every expense you log deducts from it automatically.'**
  String get walletDeductNote;

  /// Action on the wallet empty state.
  ///
  /// In en, this message translates to:
  /// **'Set starting balance'**
  String get walletSetStarting;

  /// Adds funds to the wallet.
  ///
  /// In en, this message translates to:
  /// **'Top up'**
  String get walletTopUp;

  /// Title of the top-up sheet.
  ///
  /// In en, this message translates to:
  /// **'Top up wallet'**
  String get walletTopUpTitle;

  /// Title of the set-balance sheet.
  ///
  /// In en, this message translates to:
  /// **'Set wallet balance'**
  String get walletSetBalanceTitle;

  /// Prompt in the top-up sheet.
  ///
  /// In en, this message translates to:
  /// **'How much are you adding?'**
  String get walletHowMuchAdding;

  /// Confirms a new balance.
  ///
  /// In en, this message translates to:
  /// **'Save balance'**
  String get walletSaveBalance;

  /// Confirms a top-up.
  ///
  /// In en, this message translates to:
  /// **'Add funds'**
  String get walletAddFunds;

  /// Caption above the week's spend bars.
  ///
  /// In en, this message translates to:
  /// **'THIS WEEK'**
  String get expensesThisWeek;

  /// Title of the add-category sheet.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get categoryNew;

  /// Placeholder for a new category's name.
  ///
  /// In en, this message translates to:
  /// **'e.g. Subscriptions'**
  String get categoryNewHint;

  /// Caption above the icon picker.
  ///
  /// In en, this message translates to:
  /// **'ICON'**
  String get categoryIconCaps;

  /// Confirms creating a category.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get categoryAdd;

  /// Title of the quick-capture sheet.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get captureTitle;

  /// Quick-capture route.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get captureExpense;

  /// Quick-capture route subtitle.
  ///
  /// In en, this message translates to:
  /// **'Amount, category — in seconds'**
  String get captureExpenseDetail;

  /// Quick-capture route.
  ///
  /// In en, this message translates to:
  /// **'Moment'**
  String get captureMoment;

  /// Quick-capture route subtitle.
  ///
  /// In en, this message translates to:
  /// **'Photo + a line'**
  String get captureMomentDetail;

  /// Quick-capture route.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get captureWorkout;

  /// Quick-capture route subtitle.
  ///
  /// In en, this message translates to:
  /// **'Log a training session'**
  String get captureWorkoutDetail;

  /// A date chip meaning the current day.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateToday;

  /// A date chip meaning the previous day.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dateYesterday;

  /// Label of the calories field.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get nutritionCalories;

  /// Label of the protein field.
  ///
  /// In en, this message translates to:
  /// **'Protein (g)'**
  String get nutritionProtein;

  /// Label of the carbs field.
  ///
  /// In en, this message translates to:
  /// **'Carbs (g)'**
  String get nutritionCarbs;

  /// Label of the fat field.
  ///
  /// In en, this message translates to:
  /// **'Fat (g)'**
  String get nutritionFat;

  /// Label of the per-100g calories field when defining a custom food.
  ///
  /// In en, this message translates to:
  /// **'Calories / 100g'**
  String get nutritionCaloriesPer100g;

  /// Saves the daily target.
  ///
  /// In en, this message translates to:
  /// **'Save target'**
  String get targetsSave;

  /// Shown wherever a target is missing.
  ///
  /// In en, this message translates to:
  /// **'No daily target set'**
  String get targetsNoneSet;

  /// Heading of the sheet listing the stored body data the calculator will run on.
  ///
  /// In en, this message translates to:
  /// **'ZIVO will use'**
  String get targetsZivoWillUse;

  /// Applies the calculated proposal to the target form.
  ///
  /// In en, this message translates to:
  /// **'Fill the fields'**
  String get targetsFillFields;

  /// Opens the body-data screen from the calculator sheet.
  ///
  /// In en, this message translates to:
  /// **'Change my body data'**
  String get targetsChangeBodyData;

  /// Opens the calculator.
  ///
  /// In en, this message translates to:
  /// **'Work it out from my body data'**
  String get targetsFromBodyData;

  /// Label in the stored-body-data list.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get bodyWeightLabel;

  /// Label in the stored-body-data list.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get bodyHeightLabel;

  /// Label in the stored-body-data list.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get bodyAgeLabel;

  /// Label in the stored-body-data list.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get bodyActivityLabel;

  /// Title of the delete-plan dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete this plan?'**
  String get planDeleteTitle;

  /// Title of the plan editor.
  ///
  /// In en, this message translates to:
  /// **'Edit diet plan'**
  String get planEditTitle;

  /// Removes a plan.
  ///
  /// In en, this message translates to:
  /// **'Delete plan'**
  String get planDelete;

  /// Placeholder for the plan's name.
  ///
  /// In en, this message translates to:
  /// **'Plan name'**
  String get planNameHint;

  /// Saves the edited plan.
  ///
  /// In en, this message translates to:
  /// **'Save plan'**
  String get planSave;

  /// Empty state in the plan editor.
  ///
  /// In en, this message translates to:
  /// **'No days yet.'**
  String get planNoDays;

  /// Adds a day to the plan.
  ///
  /// In en, this message translates to:
  /// **'Add day'**
  String get planAddDay;

  /// Adds a meal to a day.
  ///
  /// In en, this message translates to:
  /// **'Add meal'**
  String get planAddMeal;

  /// Adds a food item to a meal.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get planAddItem;

  /// Title of the add-item sheet.
  ///
  /// In en, this message translates to:
  /// **'Add food item'**
  String get planAddFoodItem;

  /// The default day label — a plan with one day that repeats.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get planEveryDay;

  /// Placeholder for a day's name.
  ///
  /// In en, this message translates to:
  /// **'Day label (optional)'**
  String get planDayLabelHint;

  /// Placeholder for a meal's name.
  ///
  /// In en, this message translates to:
  /// **'Meal name'**
  String get planMealNameHint;

  /// Placeholder for a food's name.
  ///
  /// In en, this message translates to:
  /// **'Food name'**
  String get planFoodNameHint;

  /// Short label for a quantity field.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get planQty;

  /// Title of the plan library.
  ///
  /// In en, this message translates to:
  /// **'Your plans'**
  String get plansTitle;

  /// Makes a plan the active one.
  ///
  /// In en, this message translates to:
  /// **'Follow this plan'**
  String get plansFollow;

  /// Archives the active plan.
  ///
  /// In en, this message translates to:
  /// **'Stop following'**
  String get plansStopFollowing;

  /// Title of the plan-generation preferences screen.
  ///
  /// In en, this message translates to:
  /// **'Build me a plan'**
  String get prefsBuildTitle;

  /// Starts plan generation.
  ///
  /// In en, this message translates to:
  /// **'Build my plan'**
  String get prefsBuild;

  /// Placeholder in the typed/dictated description field.
  ///
  /// In en, this message translates to:
  /// **'Breakfast is…'**
  String get dictateHint;

  /// Sends the description to the extractor.
  ///
  /// In en, this message translates to:
  /// **'Turn this into a plan'**
  String get dictateTurnIntoPlan;

  /// Stops the recording.
  ///
  /// In en, this message translates to:
  /// **'Done talking'**
  String get dictateDoneTalking;

  /// Prompt at the top of the food-log sheet.
  ///
  /// In en, this message translates to:
  /// **'What did you eat?'**
  String get logWhatDidYouEat;

  /// Returns from a food's detail to the search list.
  ///
  /// In en, this message translates to:
  /// **'Back to search'**
  String get logBackToSearch;

  /// Records the chosen food.
  ///
  /// In en, this message translates to:
  /// **'Log it'**
  String get logIt;

  /// Offers to define a food the catalog doesn't have.
  ///
  /// In en, this message translates to:
  /// **'Add \"{query}\" as my own food'**
  String logAddOwnFood(String query);

  /// Title of the custom-food form.
  ///
  /// In en, this message translates to:
  /// **'Your own food'**
  String get logYourOwnFood;

  /// Label of the custom food's name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get logFoodName;

  /// Saves a custom food.
  ///
  /// In en, this message translates to:
  /// **'Save food'**
  String get logSaveFood;

  /// Marks a meal as eaten.
  ///
  /// In en, this message translates to:
  /// **'Eaten'**
  String get dietEaten;

  /// Accepts the plan's own daily figure as the target.
  ///
  /// In en, this message translates to:
  /// **'Save as my target'**
  String get adoptSaveAsTarget;

  /// Capture route: a document or a picture of one.
  ///
  /// In en, this message translates to:
  /// **'PDF or photo'**
  String get addDietPdfOrPhoto;

  /// Subtitle of the document capture route.
  ///
  /// In en, this message translates to:
  /// **'Your nutritionist\'s plan, or a picture of one.'**
  String get addDietPdfOrPhotoDetail;

  /// Capture route: dictation.
  ///
  /// In en, this message translates to:
  /// **'Say it out loud'**
  String get addDietDictate;

  /// Subtitle of the dictation route.
  ///
  /// In en, this message translates to:
  /// **'Describe your meals; ZIVO writes them down.'**
  String get addDietDictateDetail;

  /// Capture route: typing a description.
  ///
  /// In en, this message translates to:
  /// **'Type it out'**
  String get addDietType;

  /// Subtitle of the typing route.
  ///
  /// In en, this message translates to:
  /// **'Write your meals in your own words.'**
  String get addDietTypeDetail;

  /// Capture route: ZIVO generates the plan.
  ///
  /// In en, this message translates to:
  /// **'Build one for me'**
  String get addDietGenerate;

  /// Subtitle of the generation route.
  ///
  /// In en, this message translates to:
  /// **'Tell ZIVO what you eat; it designs the plan.'**
  String get addDietGenerateDetail;

  /// Capture route: the full editor.
  ///
  /// In en, this message translates to:
  /// **'Build it meal by meal'**
  String get addDietManual;

  /// Subtitle of the manual route.
  ///
  /// In en, this message translates to:
  /// **'The full editor, nothing extracted for you.'**
  String get addDietManualDetail;

  /// Note under the add-a-diet sheet's title.
  ///
  /// In en, this message translates to:
  /// **'However it reaches ZIVO, you review every meal and every figure before it is saved.'**
  String get addDietIntro;

  /// Title of the delete-moment confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete moment?'**
  String get momentDeleteTitle;

  /// Body of the delete-moment confirmation. Names both consequences.
  ///
  /// In en, this message translates to:
  /// **'This removes it from your moments. The photo on your device is also removed.'**
  String get momentDeleteBody;

  /// Body of the delete-diet-plan confirmation.
  ///
  /// In en, this message translates to:
  /// **'This removes \"{name}\" and all its days and meals. This can\'t be undone.'**
  String dietPlanDeleteBody(String name);

  /// Body of the delete-diet-plan confirmation shown where archiving is the gentler alternative.
  ///
  /// In en, this message translates to:
  /// **'This removes {name} for good. Archiving keeps it and takes it off the Diet screen just the same.'**
  String dietPlanArchiveHint(String name);

  /// Title of the delete-logged-session confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete this session?'**
  String get sessionDeleteTitle;

  /// Body of the delete-logged-session confirmation.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes your \"{day}\" session and everything logged in it. This can\'t be undone.'**
  String sessionDeleteBody(String day);

  /// Title of the delete-split confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String splitDeleteTitle(String name);

  /// Body of the delete-split confirmation. Says explicitly that history survives.
  ///
  /// In en, this message translates to:
  /// **'This removes the split and all its days and exercises. Logged history for it is kept, just no longer editable here. This can\'t be undone.'**
  String get splitDeleteBody;

  /// Title of the delete-workout-plan confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete this plan?'**
  String get workoutPlanDeleteTitle;

  /// Body of the delete-workout-plan confirmation.
  ///
  /// In en, this message translates to:
  /// **'This removes \"{name}\" and all its days and exercises. This can\'t be undone.'**
  String workoutPlanDeleteBody(String name);

  /// Title of the delete confirmation inside the split editor, where which split is being edited is already obvious.
  ///
  /// In en, this message translates to:
  /// **'Delete this split?'**
  String get splitDeleteTitlePlain;

  /// Toast: a spend row that was recorded locally didn't reach the server.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that expense.'**
  String get expenseSaveFailed;

  /// Toast: a spend row removed locally didn't reach the server.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete that expense.'**
  String get expenseDeleteFailed;

  /// Toast: a food-log entry recorded locally didn't reach the server.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t log that food.'**
  String get dietLogFailed;

  /// Bottom-bar action: authorize and attach to the Spotify app.
  ///
  /// In en, this message translates to:
  /// **'Connect Spotify'**
  String get musicConnect;

  /// Bottom-bar action: re-attach after the Spotify connection dropped.
  ///
  /// In en, this message translates to:
  /// **'Reconnect Spotify'**
  String get musicReconnect;

  /// Bottom-bar state while the Spotify handshake is in flight.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get musicConnecting;

  /// Bottom-bar state when the Spotify app isn't on this device.
  ///
  /// In en, this message translates to:
  /// **'Install Spotify to play'**
  String get musicInstallSpotify;

  /// Bottom-bar state: connected to Spotify, but no track is loaded.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing'**
  String get musicNothingPlaying;

  /// Accessibility label for the bottom bar's skip-back control.
  ///
  /// In en, this message translates to:
  /// **'Previous track'**
  String get musicPrevious;

  /// Accessibility label for the bottom bar's skip-forward control.
  ///
  /// In en, this message translates to:
  /// **'Next track'**
  String get musicNext;

  /// Accessibility label for the bottom bar's play control.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get musicPlay;

  /// Accessibility label for the bottom bar's pause control.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get musicPause;

  /// Settings action: unlink this device so the app stops reconnecting to Spotify on its own.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Spotify'**
  String get musicDisconnect;

  /// Generic failure copy for a surface whose data could not be read.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this.'**
  String get errorCouldntLoad;

  /// A lift's overall direction: strength is trending up over recent sessions.
  ///
  /// In en, this message translates to:
  /// **'Progressing'**
  String get workoutStatusProgressing;

  /// A lift's overall direction: steady — neither building nor losing.
  ///
  /// In en, this message translates to:
  /// **'Holding'**
  String get workoutStatusHolding;

  /// A lift's overall direction: unchanged for several sessions; needs a change.
  ///
  /// In en, this message translates to:
  /// **'Plateaued'**
  String get workoutStatusPlateaued;

  /// A lift's overall direction: strength has declined recently.
  ///
  /// In en, this message translates to:
  /// **'Trending down'**
  String get workoutStatusTrendingDown;

  /// A lift's overall direction: too few sessions logged to judge a trend yet.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get workoutStatusBuilding;

  /// One session versus the previous one: better.
  ///
  /// In en, this message translates to:
  /// **'Improved'**
  String get workoutToneImproved;

  /// One session versus the previous one: the same. Not a failure.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get workoutToneMatched;

  /// One session versus the previous one: some measures up, some down.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get workoutToneMixed;

  /// One session versus the previous one: worse.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get workoutToneDown;

  /// Shown when the body-weight history fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load weigh-ins.'**
  String get workoutBodyweightLoadError;

  /// Subtitle counting the user's logged weigh-ins.
  ///
  /// In en, this message translates to:
  /// **'{count} weigh-ins logged'**
  String workoutWeighInsLogged(int count);

  /// The kilogram unit as a micro-label beside a number. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'KG'**
  String get workoutUnitKg;

  /// Body-weight change over the last 30 days, e.g. "−1.4 KG · 30D". The change already carries its sign.
  ///
  /// In en, this message translates to:
  /// **'{change} KG · 30D'**
  String workoutBodyweightChange30d(String change);

  /// Empty state on the body-weight history page.
  ///
  /// In en, this message translates to:
  /// **'Log your first weigh-in to start the trend.'**
  String get workoutBodyweightEmpty;

  /// Group header over the current week in the session history. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'THIS WEEK'**
  String get workoutThisWeekCaps;

  /// Group header over the previous week in the session history. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'LAST WEEK'**
  String get workoutLastWeekCaps;

  /// Label under a count of training sessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get workoutSessionsLabel;

  /// Label under the total time spent training.
  ///
  /// In en, this message translates to:
  /// **'Trained'**
  String get workoutTrained;

  /// Label under a count for the current week.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get workoutThisWeek;

  /// A finished training session.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get workoutSessionCompleted;

  /// A training session that is still running.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get workoutSessionInProgress;

  /// A training session that was left unfinished.
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get workoutSessionNotCompleted;

  /// How many exercises a logged session contained.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 exercise} other{{count} exercises}}'**
  String workoutExerciseCount(int count);

  /// How many of a session's sets were completed, e.g. "12/15 sets".
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} sets'**
  String workoutSetsOfTotal(int done, int total);

  /// Empty state title on the session history page.
  ///
  /// In en, this message translates to:
  /// **'No sessions logged yet.'**
  String get workoutNoSessionsTitle;

  /// Empty state body on the session history page.
  ///
  /// In en, this message translates to:
  /// **'Finish a workout and it shows up here.'**
  String get workoutNoSessionsBody;

  /// Shown when the session list fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load sessions.'**
  String get workoutSessionsLoadError;

  /// Sessions drill-down subtitle when nothing at all has been logged.
  ///
  /// In en, this message translates to:
  /// **'No completed workouts yet.'**
  String get workoutNoCompletedWorkouts;

  /// Sessions drill-down subtitle: how many workouts were finished.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 completed workout} other{{count} completed workouts}}'**
  String workoutCompletedCount(int count);

  /// Sessions drill-down subtitle when there are only unfinished entries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{No completed workouts · 1 entry} other{No completed workouts · {count} entries}}'**
  String workoutNoCompletedWithEntries(int count);

  /// Sessions drill-down subtitle combining the completed count with the unfinished count.
  ///
  /// In en, this message translates to:
  /// **'{completed} · {notCompleted} not completed'**
  String workoutCompletedAndNotCompleted(String completed, int notCompleted);

  /// Empty card on the Sessions drill-down.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet — finished workouts land here.'**
  String get workoutSessionsEmpty;

  /// A training session the user stopped before finishing.
  ///
  /// In en, this message translates to:
  /// **'Ended early'**
  String get workoutSessionEndedEarly;

  /// Completed sets out of the session total, as a caps micro-label.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} SETS'**
  String workoutSetsCaps(int done, int total);

  /// The number of consecutive days trained.
  ///
  /// In en, this message translates to:
  /// **'Day streak'**
  String get workoutDayStreak;

  /// Label under a zero day-streak.
  ///
  /// In en, this message translates to:
  /// **'No active streak — complete a workout to start one.'**
  String get workoutNoActiveStreak;

  /// Label under the current day-streak number.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day in your current streak} other{days in your current streak}}'**
  String workoutStreakDays(int count);

  /// Label under the all-time best day streak.
  ///
  /// In en, this message translates to:
  /// **'best day streak ever'**
  String get workoutBestStreak;

  /// Empty card on the Day streak drill-down.
  ///
  /// In en, this message translates to:
  /// **'Train today and day one starts now.'**
  String get workoutStreakEmpty;

  /// How many sessions a streak day contained, as a caps micro-label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 SESSION} other{{count} SESSIONS}}'**
  String workoutSessionsCountCaps(int count);

  /// How long a training session lasts.
  ///
  /// In en, this message translates to:
  /// **'Session length'**
  String get workoutSessionLength;

  /// Label under an unavailable average session length.
  ///
  /// In en, this message translates to:
  /// **'Complete a workout to see your average.'**
  String get workoutNoAverageYet;

  /// Label under the average session duration.
  ///
  /// In en, this message translates to:
  /// **'average completed session'**
  String get workoutAverageSession;

  /// Empty card on the Session length drill-down.
  ///
  /// In en, this message translates to:
  /// **'Durations appear once you finish workouts.'**
  String get workoutDurationsEmpty;

  /// When the user usually starts training.
  ///
  /// In en, this message translates to:
  /// **'Start times'**
  String get workoutStartTimes;

  /// Label under an unavailable usual start time.
  ///
  /// In en, this message translates to:
  /// **'Complete a workout to see your usual start time.'**
  String get workoutNoStartTimeYet;

  /// Label under the average training start time.
  ///
  /// In en, this message translates to:
  /// **'when you usually start training'**
  String get workoutUsualStartTime;

  /// Empty card on the Start times drill-down.
  ///
  /// In en, this message translates to:
  /// **'Your start times will show up here.'**
  String get workoutStartTimesEmpty;

  /// Stands in for a date when that date is today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get workoutToday;

  /// A relative time, e.g. "3h ago". {value} is an already-formatted span like "3h".
  ///
  /// In en, this message translates to:
  /// **'{value} ago'**
  String workoutAgo(String value);

  /// Section label over the active training split.
  ///
  /// In en, this message translates to:
  /// **'Current split'**
  String get workoutCurrentSplit;

  /// Section label over the most recent training sessions.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get workoutRecentActivity;

  /// Empty card under Recent activity.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t logged a session yet.'**
  String get workoutNoSessionYet;

  /// Section label over the links into the detailed analysis pages.
  ///
  /// In en, this message translates to:
  /// **'Go deeper'**
  String get workoutGoDeeper;

  /// Link into the full training analysis page.
  ///
  /// In en, this message translates to:
  /// **'Full analysis'**
  String get workoutFullAnalysis;

  /// Subtitle under the Full analysis link.
  ///
  /// In en, this message translates to:
  /// **'Exercise-by-exercise, per training day'**
  String get workoutFullAnalysisDetail;

  /// Link into the full session history page.
  ///
  /// In en, this message translates to:
  /// **'All history'**
  String get workoutAllHistory;

  /// Subtitle under the All history link.
  ///
  /// In en, this message translates to:
  /// **'Every session you have logged'**
  String get workoutAllHistoryDetail;

  /// Subtitle under the Splits link.
  ///
  /// In en, this message translates to:
  /// **'Switch or edit your training splits'**
  String get workoutSplitsDetail;

  /// Label under the all-time completed session count.
  ///
  /// In en, this message translates to:
  /// **'Total sessions'**
  String get workoutTotalSessions;

  /// Label under the average session duration.
  ///
  /// In en, this message translates to:
  /// **'Avg length'**
  String get workoutAvgLength;

  /// Caps link out of the progress summary card into the analysis page.
  ///
  /// In en, this message translates to:
  /// **'SEE FULL ANALYSIS'**
  String get workoutSeeFullAnalysisCaps;

  /// Caps link out of a section into its full list.
  ///
  /// In en, this message translates to:
  /// **'SEE ALL'**
  String get workoutSeeAllCaps;

  /// How many personal records were set. "PR" is personal record.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 PR} other{{count} PRs}}'**
  String workoutPrCount(int count);

  /// How many training sessions have been completed in total.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session completed} other{{count} sessions completed}}'**
  String workoutSessionsCompletedCount(int count);

  /// Compact pill linking to the training plan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get workoutPlanShort;

  /// A finished session's relative time plus how long it ran, e.g. "3h ago · 52m".
  ///
  /// In en, this message translates to:
  /// **'{value} ago · {duration}'**
  String workoutAgoWithDuration(String value, String duration);

  /// Section label over recently set personal records.
  ///
  /// In en, this message translates to:
  /// **'Recent PRs'**
  String get workoutRecentPrs;

  /// Section label over the exercises that are progressing.
  ///
  /// In en, this message translates to:
  /// **'What\'s going well'**
  String get workoutGoingWell;

  /// Trailing count beside the "going well" section.
  ///
  /// In en, this message translates to:
  /// **'{count} improving'**
  String workoutImprovingCount(int count);

  /// Section label over the exercises that are declining.
  ///
  /// In en, this message translates to:
  /// **'What\'s getting worse'**
  String get workoutGettingWorse;

  /// Trailing count beside the "getting worse" section.
  ///
  /// In en, this message translates to:
  /// **'{count} declining'**
  String workoutDecliningCount(int count);

  /// Section label over the exercises that have plateaued.
  ///
  /// In en, this message translates to:
  /// **'Stalled — needs a change'**
  String get workoutStalled;

  /// Trailing count beside the "stalled" section.
  ///
  /// In en, this message translates to:
  /// **'{count} flat'**
  String workoutFlatCount(int count);

  /// Section label over planned exercises that are not being trained.
  ///
  /// In en, this message translates to:
  /// **'What\'s being skipped'**
  String get workoutBeingSkipped;

  /// Trailing count beside the "being skipped" section: how many planned exercises are neglected.
  ///
  /// In en, this message translates to:
  /// **'{skipped} of {planned}'**
  String workoutSkippedOfPlanned(int skipped, int planned);

  /// Section label over the suggested next step.
  ///
  /// In en, this message translates to:
  /// **'Focus next'**
  String get workoutFocusNext;

  /// Section label over the weekly working-set volume.
  ///
  /// In en, this message translates to:
  /// **'Training volume'**
  String get workoutTrainingVolume;

  /// Section label over the full exercise list.
  ///
  /// In en, this message translates to:
  /// **'All exercises'**
  String get workoutAllExercises;

  /// Hint beside the All exercises section.
  ///
  /// In en, this message translates to:
  /// **'tap to drill in'**
  String get workoutTapToDrillIn;

  /// Caps label over the summary verdict card.
  ///
  /// In en, this message translates to:
  /// **'OVERALL'**
  String get workoutOverallCaps;

  /// A personal record for the heaviest weight lifted.
  ///
  /// In en, this message translates to:
  /// **'Heaviest'**
  String get workoutPrHeaviest;

  /// A personal record for the most repetitions performed.
  ///
  /// In en, this message translates to:
  /// **'Most reps'**
  String get workoutPrMostReps;

  /// A personal record for the best estimated one-rep max.
  ///
  /// In en, this message translates to:
  /// **'Best strength'**
  String get workoutPrBestStrength;

  /// An unloaded set, described by its repetitions alone.
  ///
  /// In en, this message translates to:
  /// **'{reps} reps'**
  String workoutRepsOnly(int reps);

  /// A loaded set, e.g. "100kg × 8".
  ///
  /// In en, this message translates to:
  /// **'{weight}kg × {reps}'**
  String workoutWeightByReps(String weight, int reps);

  /// A status word with its strength change, e.g. "Progressing · +4% strength".
  ///
  /// In en, this message translates to:
  /// **'{status} · {change} strength'**
  String workoutStatusWithStrength(String status, String change);

  /// Why a planned exercise is flagged: it has never been performed.
  ///
  /// In en, this message translates to:
  /// **'Planned but never trained'**
  String get workoutNeverTrained;

  /// Why a planned exercise is flagged: it has not been trained recently.
  ///
  /// In en, this message translates to:
  /// **'{days} days since last — on {day}'**
  String workoutStaleSince(int days, String day);

  /// Shown when there is no previous week of volume to compare against.
  ///
  /// In en, this message translates to:
  /// **'No prior week to compare'**
  String get workoutNoPriorWeek;

  /// Volume change against the previous week, e.g. "+12% vs last week".
  ///
  /// In en, this message translates to:
  /// **'{change} vs last week'**
  String workoutVsLastWeek(String change);

  /// Shown when this week's volume matches last week's.
  ///
  /// In en, this message translates to:
  /// **'Same as last week'**
  String get workoutSameAsLastWeek;

  /// Caption over the weekly volume number, noting warm-ups are excluded.
  ///
  /// In en, this message translates to:
  /// **'This week · working sets only'**
  String get workoutThisWeekWorkingSets;

  /// Empty state title on the analysis page.
  ///
  /// In en, this message translates to:
  /// **'Complete a few sessions to start tracking progress.'**
  String get workoutAnalysisEmptyTitle;

  /// Empty state body on the analysis page.
  ///
  /// In en, this message translates to:
  /// **'Once you\'ve logged the same exercise a few times, ZIVO will show your strength trend, PRs, and what to focus on next.'**
  String get workoutAnalysisEmptyBody;

  /// Section label over the estimated-1RM chart for a loaded lift.
  ///
  /// In en, this message translates to:
  /// **'Strength trend'**
  String get workoutStrengthTrend;

  /// Section label over the volume chart for an unloaded movement.
  ///
  /// In en, this message translates to:
  /// **'Volume trend'**
  String get workoutVolumeTrend;

  /// Section label over the summary metric tiles.
  ///
  /// In en, this message translates to:
  /// **'At a glance'**
  String get workoutAtAGlance;

  /// Section label over this exercise's personal records.
  ///
  /// In en, this message translates to:
  /// **'Personal records'**
  String get workoutPersonalRecords;

  /// Section label over the session-by-session timeline.
  ///
  /// In en, this message translates to:
  /// **'Session history'**
  String get workoutSessionHistory;

  /// Trailing count beside the Session history label.
  ///
  /// In en, this message translates to:
  /// **'{count} logged'**
  String workoutSessionsLogged(int count);

  /// The change in estimated strength, e.g. "+4% est. strength".
  ///
  /// In en, this message translates to:
  /// **'{change} est. strength'**
  String workoutEstStrengthChange(String change);

  /// Caps micro-label under the current estimated one-rep max. "1RM" is one-rep max.
  ///
  /// In en, this message translates to:
  /// **'EST. 1RM'**
  String get workoutEst1rmCaps;

  /// Caps marker over the coaching insight's first line.
  ///
  /// In en, this message translates to:
  /// **'WHAT HAPPENED'**
  String get workoutWhatHappenedCaps;

  /// Caps marker over the coaching insight's second line.
  ///
  /// In en, this message translates to:
  /// **'WHY IT MATTERS'**
  String get workoutWhyItMattersCaps;

  /// Caps marker over the coaching insight's recommended action.
  ///
  /// In en, this message translates to:
  /// **'DO THIS'**
  String get workoutDoThisCaps;

  /// Caps axis label on the strength chart.
  ///
  /// In en, this message translates to:
  /// **'EST. 1RM (KG)'**
  String get workoutEst1rmUnitCaps;

  /// Caps axis label on the volume chart.
  ///
  /// In en, this message translates to:
  /// **'VOLUME (KG)'**
  String get workoutVolumeUnitCaps;

  /// Left end of a chart's time axis.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get workoutOldest;

  /// Right end of a chart's time axis.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get workoutLatest;

  /// Metric tile: the highest estimated one-rep max reached.
  ///
  /// In en, this message translates to:
  /// **'Best est. 1RM'**
  String get workoutBestEst1rm;

  /// Metric tile: total working volume for this exercise.
  ///
  /// In en, this message translates to:
  /// **'Total volume'**
  String get workoutTotalVolume;

  /// Metric tile: how often this exercise is trained.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get workoutFrequency;

  /// Unit beside a per-week frequency.
  ///
  /// In en, this message translates to:
  /// **'/wk'**
  String get workoutPerWeek;

  /// Metric tile: when this exercise was last performed.
  ///
  /// In en, this message translates to:
  /// **'Last trained'**
  String get workoutLastTrained;

  /// Unit beside a number of days since the exercise was last trained.
  ///
  /// In en, this message translates to:
  /// **'days ago'**
  String get workoutDaysAgo;

  /// Personal record row: the heaviest weight lifted.
  ///
  /// In en, this message translates to:
  /// **'Heaviest load'**
  String get workoutPrHeaviestLoad;

  /// A weight in kilograms, e.g. "100kg".
  ///
  /// In en, this message translates to:
  /// **'{value}kg'**
  String workoutKgValue(String value);

  /// Caps ordinal over one session in the timeline.
  ///
  /// In en, this message translates to:
  /// **'SESSION {index}'**
  String workoutSessionNumberCaps(int index);

  /// Micro-label under a count of working sets.
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get workoutSetsShort;

  /// Micro-label under the heaviest set of a session.
  ///
  /// In en, this message translates to:
  /// **'Top set'**
  String get workoutTopSet;

  /// Micro-label under a session's total volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get workoutVolumeShort;

  /// Micro-label under a session's best estimated one-rep max.
  ///
  /// In en, this message translates to:
  /// **'Est 1RM'**
  String get workoutEst1rmShort;

  /// Caps label over the deltas against the previous session.
  ///
  /// In en, this message translates to:
  /// **'VS PREVIOUS SESSION'**
  String get workoutVsPreviousSessionCaps;

  /// One-letter marker on a drop set. Kept latin in both languages, as a symbol.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get workoutSetDropsetShort;

  /// One-letter marker on a set taken to failure. Kept latin in both languages, as a symbol.
  ///
  /// In en, this message translates to:
  /// **'F'**
  String get workoutSetFailureShort;

  /// Badge on a session that set a personal best.
  ///
  /// In en, this message translates to:
  /// **'PB'**
  String get workoutPbCaps;

  /// Empty state title on the per-exercise analysis page.
  ///
  /// In en, this message translates to:
  /// **'No completed sessions with this exercise yet.'**
  String get workoutExerciseEmptyTitle;

  /// Empty state body on the per-exercise analysis page.
  ///
  /// In en, this message translates to:
  /// **'Log it in a session and its full history, trend, and session-to-session comparison will appear here.'**
  String get workoutExerciseEmptyBody;

  /// Delta chip: this session set a new personal best.
  ///
  /// In en, this message translates to:
  /// **'New PB'**
  String get workoutNewPb;

  /// Delta chip: how estimated strength moved, e.g. "e1RM +4%".
  ///
  /// In en, this message translates to:
  /// **'e1RM {change}'**
  String workoutDeltaE1rm(String change);

  /// Delta chip: how the working load moved, e.g. "Load +2.5kg".
  ///
  /// In en, this message translates to:
  /// **'Load {change}'**
  String workoutDeltaLoad(String change);

  /// Delta chip: how the top-set reps moved, e.g. "Reps +2".
  ///
  /// In en, this message translates to:
  /// **'Reps {change}'**
  String workoutDeltaReps(String change);

  /// Delta chip: how session volume moved, e.g. "Volume +8%".
  ///
  /// In en, this message translates to:
  /// **'Volume {change}'**
  String workoutDeltaVolume(String change);

  /// Delta chip: this session matched the previous one.
  ///
  /// In en, this message translates to:
  /// **'No meaningful change'**
  String get workoutNoMeaningfulChange;

  /// A duration over an hour, e.g. "1h 12m". Abbreviations: h = hours, m = minutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String workoutDurationHm(int hours, int minutes);

  /// A duration under an hour, e.g. "52m". Abbreviation: m = minutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String workoutDurationM(int minutes);

  /// A duration in hours with a decimal, e.g. "3.5h". Abbreviation: h = hours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String workoutDurationH(String hours);

  /// The AI chat surface's title.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get askTitle;

  /// Starts a fresh conversation. Also what an untitled thread is shown as — the stored sentinel stays English.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get askNewChat;

  /// Opens the list of past conversations.
  ///
  /// In en, this message translates to:
  /// **'Chat history'**
  String get askChatHistory;

  /// Opens the picker for how long or detailed ZIVO's replies should be.
  ///
  /// In en, this message translates to:
  /// **'Reply style'**
  String get askReplyStyle;

  /// Header of the conversation list sheet.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get askChats;

  /// Empty state in the conversation list.
  ///
  /// In en, this message translates to:
  /// **'No chats yet.'**
  String get askNoChats;

  /// Explains the optional name field when starting a new chat.
  ///
  /// In en, this message translates to:
  /// **'Name it so you can find it later — or leave it blank and the first message will title it.'**
  String get askNameItHint;

  /// Placeholder in the new-chat name field.
  ///
  /// In en, this message translates to:
  /// **'e.g. Workout changes'**
  String get askNamePlaceholder;

  /// Confirms creating the new conversation.
  ///
  /// In en, this message translates to:
  /// **'Start chatting'**
  String get askStartChatting;

  /// Title of the confirmation before deleting a conversation.
  ///
  /// In en, this message translates to:
  /// **'Delete this chat?'**
  String get askDeleteChatTitle;

  /// Body of the confirmation before deleting a conversation.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes \"{title}\" and everything in it. This can\'t be undone.'**
  String askDeleteChatBody(String title);

  /// Confirm button on the delete-conversation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get askDeleteChatConfirm;

  /// The assistant introducing itself on the empty chat screen. "ZIVO" is the product name and is never translated.
  ///
  /// In en, this message translates to:
  /// **'Hey, I\'m ZIVO.'**
  String get askGreeting;

  /// What the assistant can help with, on the empty chat screen.
  ///
  /// In en, this message translates to:
  /// **'Training, diet and spending. Ask me anything — or let me log it for you.'**
  String get askIntro;

  /// Tappable example question on the empty chat screen.
  ///
  /// In en, this message translates to:
  /// **'What did I spend this week?'**
  String get askSuggestSpend;

  /// Tappable example question on the empty chat screen.
  ///
  /// In en, this message translates to:
  /// **'How is my training going?'**
  String get askSuggestTraining;

  /// Tappable example question on the empty chat screen.
  ///
  /// In en, this message translates to:
  /// **'What\'s left on my diet today?'**
  String get askSuggestDiet;

  /// Tappable example question on the empty chat screen.
  ///
  /// In en, this message translates to:
  /// **'Summarise my week'**
  String get askSuggestWeek;

  /// Title when a message could not be sent. "ZIVO" is the product name.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach ZIVO'**
  String get askUnreachableTitle;

  /// Body when a message could not be sent.
  ///
  /// In en, this message translates to:
  /// **'Your message wasn’t sent.'**
  String get askUnreachableBody;

  /// Sends the failed message again.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get askRetry;

  /// Shown when a conversation could not be created or renamed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that — try again.'**
  String get askSaveFailed;

  /// Shown when confirming or cancelling a proposed change failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t do that just now. Try again.'**
  String get askActionFailed;

  /// The assistant is composing a reply. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get askThinking;

  /// The assistant is interpreting the question. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Understanding…'**
  String get askUnderstanding;

  /// Generic progress line while the assistant runs a step. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get askWorking;

  /// The assistant is drafting a change for the user to confirm. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Preparing your change…'**
  String get askPreparingChange;

  /// Shown when a turn is taking unusually long. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Still working on this one…'**
  String get askStillWorking;

  /// Progress line: the assistant is reading today's summary. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Reading your day…'**
  String get askReadingDay;

  /// Progress line: the assistant is reading the diet log. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Reading today\'s diet…'**
  String get askReadingDiet;

  /// Progress line: the assistant is reading workout history. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Reading your training…'**
  String get askReadingTraining;

  /// Progress line: the assistant is reading the expense log. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Reading your spending…'**
  String get askReadingSpending;

  /// Progress line: the assistant is building a weekly summary. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Summarising your week…'**
  String get askSummarisingWeek;

  /// Progress line: the assistant is resolving a food item. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Looking that food up…'**
  String get askLookingUpFood;

  /// Progress line: the assistant is computing nutrition figures. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Working out the numbers…'**
  String get askCalculating;

  /// A proposed change the user accepted.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get askProposalConfirmed;

  /// A proposed change the user rejected.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get askProposalCancelled;

  /// A proposed change that timed out before the user answered.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get askProposalExpired;

  /// Accepts a change ZIVO proposed. A deletion says "Delete" instead.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get askProposalConfirm;

  /// Kind label on a proposal card: ZIVO wants to add an expense.
  ///
  /// In en, this message translates to:
  /// **'New expense'**
  String get askActionNewExpense;

  /// Kind label on a proposal card: ZIVO wants to change an expense.
  ///
  /// In en, this message translates to:
  /// **'Edit expense'**
  String get askActionEditExpense;

  /// Kind label on a proposal card: ZIVO wants to remove an expense.
  ///
  /// In en, this message translates to:
  /// **'Delete expense'**
  String get askActionDeleteExpense;

  /// Kind label on a proposal card: ZIVO wants to mark a meal eaten.
  ///
  /// In en, this message translates to:
  /// **'Diet plan'**
  String get askActionDietPlan;

  /// Kind label on a proposal card: ZIVO wants to log food.
  ///
  /// In en, this message translates to:
  /// **'Log food'**
  String get askActionLogFood;

  /// Kind label on a proposal card for anything else.
  ///
  /// In en, this message translates to:
  /// **'Suggestion'**
  String get askActionSuggestion;

  /// How many food items a log-food proposal covers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 food} other{{count} foods}}'**
  String askFoodCount(int count);

  /// Total calories across a proposal's food items.
  ///
  /// In en, this message translates to:
  /// **'{total} kcal'**
  String askKcalTotal(String total);

  /// Shown when the device offers no microphone or recorder.
  ///
  /// In en, this message translates to:
  /// **'Voice input isn\'t available right now.'**
  String get askVoiceUnavailable;

  /// Shown when microphone permission was denied.
  ///
  /// In en, this message translates to:
  /// **'Turn on microphone access to use voice input.'**
  String get askMicPermission;

  /// Shown when the recorder failed to start.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the microphone — try again.'**
  String get askMicStartFailed;

  /// Shown when a recording produced no speech.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t catch that — try recording again.'**
  String get askDidntCatchThat;

  /// Shown when transcription failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t transcribe that — check your connection and try again.'**
  String get askTranscribeFailed;

  /// Shown when transcription ran past its timeout.
  ///
  /// In en, this message translates to:
  /// **'That took too long — check your connection and try again.'**
  String get askTranscribeTimeout;

  /// Shown when a transcription returned empty text.
  ///
  /// In en, this message translates to:
  /// **'Nothing came through — try again.'**
  String get askNothingCameThrough;

  /// Shown while a voice note is being turned into text. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get askTranscribing;

  /// Accessibility label for cancelling an in-progress recording.
  ///
  /// In en, this message translates to:
  /// **'Discard recording'**
  String get askDiscardRecording;

  /// Accessibility label for cancelling a transcription.
  ///
  /// In en, this message translates to:
  /// **'Discard voice note'**
  String get askDiscardVoiceNote;

  /// Retries a failed voice note.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get askTryAgain;

  /// Elapsed seconds beside a transcription spinner. Leading separator is intentional.
  ///
  /// In en, this message translates to:
  /// **' · {seconds}s'**
  String askSecondsElapsed(int seconds);

  /// Placeholder in the chat composer. "ZIVO" is the product name. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Ask ZIVO…'**
  String get askComposerHint;

  /// Accessibility label for the composer's microphone button.
  ///
  /// In en, this message translates to:
  /// **'Record a voice note'**
  String get askRecordVoiceNote;

  /// Shown mid-recording when no speech has been detected.
  ///
  /// In en, this message translates to:
  /// **'Can\'t hear you yet — speak closer to the mic.'**
  String get askSilenceHint;

  /// Title of the quick voice-capture sheet.
  ///
  /// In en, this message translates to:
  /// **'Voice log'**
  String get askVoiceLog;

  /// Subtitle of the quick voice-capture sheet.
  ///
  /// In en, this message translates to:
  /// **'Say it once — it lands in Ask ready to send.'**
  String get askVoiceLogSubtitle;

  /// Prompt above the record button in the quick voice-capture sheet.
  ///
  /// In en, this message translates to:
  /// **'Tap and speak'**
  String get askTapAndSpeak;

  /// Two example utterances shown under the record button.
  ///
  /// In en, this message translates to:
  /// **'\"add 40 EGP parking\" · \"finished chest day\"'**
  String get askVoiceExamples;

  /// The user's display name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get profileName;

  /// The user's date of birth.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get profileDateOfBirth;

  /// An email sign-in method.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get profileEmail;

  /// Title of the one-time profile completion screen shown after sign-up.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get profileCompleteTitle;

  /// Subtitle of the profile completion screen. "ZIVO" is the product name.
  ///
  /// In en, this message translates to:
  /// **'A couple of details to personalise ZIVO.'**
  String get profileCompleteSubtitle;

  /// Shown when saving the profile failed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t save your profile. Please try again.'**
  String get profileSaveFailed;

  /// Signs out of the half-set-up account so a different one can be used.
  ///
  /// In en, this message translates to:
  /// **'Use another account'**
  String get profileUseAnotherAccount;

  /// Advances to the next step of a flow.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// Accessibility label for the button that opens Settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get profileSettings;

  /// Section header over the account details. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get profileAccountCaps;

  /// Section header over the sign-in methods. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'SIGN-IN'**
  String get profileSignInCaps;

  /// Title of the sheet for changing the display name.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get profileEditName;

  /// Placeholder in the name field.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get profileYourName;

  /// Fallback heading when the account has no name to show.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get profileSignedIn;

  /// Badge on a confirmed email address. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'VERIFIED'**
  String get profileVerifiedCaps;

  /// Badge on an email address that has not been confirmed. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'UNVERIFIED'**
  String get profileUnverifiedCaps;

  /// Badge on a linked sign-in provider. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'CONNECTED'**
  String get profileConnectedCaps;

  /// The email/password sign-in method. Google and Apple are brand names and stay untranslated.
  ///
  /// In en, this message translates to:
  /// **'Email & password'**
  String get profileEmailAndPassword;

  /// A date of birth followed by the age it implies, e.g. "AUG 20, 1998 · 27".
  ///
  /// In en, this message translates to:
  /// **'{date} · {age}'**
  String profileDobWithAge(String date, int age);

  /// Label under the number of completed training sessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get profileStatSessions;

  /// Label under how many months the user has been using ZIVO.
  ///
  /// In en, this message translates to:
  /// **'Months in'**
  String get profileStatMonthsIn;

  /// Label under the all-time training volume.
  ///
  /// In en, this message translates to:
  /// **'Lifetime'**
  String get profileStatLifetime;

  /// Section label over the user's short bio.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get profileAbout;

  /// Prompt on the empty bio card.
  ///
  /// In en, this message translates to:
  /// **'Add a few words about yourself.'**
  String get profileAboutEmpty;

  /// Placeholder in the bio editor. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'A few words about yourself…'**
  String get profileAboutHint;

  /// Characters used out of the limit, under the bio editor.
  ///
  /// In en, this message translates to:
  /// **'{used} / {max}'**
  String profileCharCount(int used, int max);

  /// Title of the sheet for changing the profile photo.
  ///
  /// In en, this message translates to:
  /// **'Profile Photo'**
  String get profilePhotoTitle;

  /// Picks a new profile photo from the library.
  ///
  /// In en, this message translates to:
  /// **'Choose Photo'**
  String get profileChoosePhoto;

  /// Clears the current profile photo.
  ///
  /// In en, this message translates to:
  /// **'Remove Photo'**
  String get profileRemovePhoto;

  /// Title of the iOS photo cropper.
  ///
  /// In en, this message translates to:
  /// **'Move & Scale'**
  String get profileCropTitle;

  /// Confirms the crop on the iOS photo cropper.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get profileCropDone;

  /// Title of the Android photo cropper.
  ///
  /// In en, this message translates to:
  /// **'Edit Photo'**
  String get profileEditPhoto;

  /// A diet goal: eat below maintenance to lose fat.
  ///
  /// In en, this message translates to:
  /// **'Fat loss'**
  String get dietGoalFatLoss;

  /// A diet goal: hold weight steady.
  ///
  /// In en, this message translates to:
  /// **'Maintain'**
  String get dietGoalMaintain;

  /// A diet goal: eat above maintenance to build muscle.
  ///
  /// In en, this message translates to:
  /// **'Muscle gain'**
  String get dietGoalMuscleGain;

  /// A diet goal: build muscle while losing fat at once.
  ///
  /// In en, this message translates to:
  /// **'Recomposition'**
  String get dietGoalRecomp;

  /// What choosing the fat-loss goal means for the numbers.
  ///
  /// In en, this message translates to:
  /// **'Eat below maintenance to lose fat, keeping protein high.'**
  String get dietGoalFatLossDetail;

  /// What choosing the maintain goal means for the numbers.
  ///
  /// In en, this message translates to:
  /// **'Hold weight steady at roughly maintenance calories.'**
  String get dietGoalMaintainDetail;

  /// What choosing the muscle-gain goal means for the numbers.
  ///
  /// In en, this message translates to:
  /// **'Eat above maintenance to support building muscle.'**
  String get dietGoalMuscleGainDetail;

  /// What choosing the recomposition goal means for the numbers.
  ///
  /// In en, this message translates to:
  /// **'Hold calories near maintenance with protein high enough to build while leaning out.'**
  String get dietGoalRecompDetail;

  /// Where a calorie target came from: the user entered it.
  ///
  /// In en, this message translates to:
  /// **'You set this'**
  String get dietTargetSourceManual;

  /// Where a calorie target came from: derived from height, weight, age and activity.
  ///
  /// In en, this message translates to:
  /// **'Calculated from your body data'**
  String get dietTargetSourceCalculated;

  /// Where a calorie target came from: the active plan's own total.
  ///
  /// In en, this message translates to:
  /// **'Adopted from your plan\'s daily total'**
  String get dietTargetSourcePlan;

  /// What is still missing before ZIVO can measure real maintenance calories.
  ///
  /// In en, this message translates to:
  /// **'two weigh-ins'**
  String get dietCalibrationNeedsWeighIns;

  /// What is still missing before ZIVO can measure real maintenance calories.
  ///
  /// In en, this message translates to:
  /// **'weigh-ins at least {days} days apart'**
  String dietCalibrationNeedsLongerWindow(int days);

  /// What is still missing before ZIVO can measure real maintenance calories.
  ///
  /// In en, this message translates to:
  /// **'more days of food logged'**
  String get dietCalibrationNeedsMoreDays;

  /// The protein macronutrient.
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get dietMacroProtein;

  /// The carbohydrate macronutrient.
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get dietMacroCarbs;

  /// The fat macronutrient.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get dietMacroFat;

  /// Section label over what has been eaten today.
  ///
  /// In en, this message translates to:
  /// **'Today so far'**
  String get dietTodaySoFar;

  /// How many calories have been eaten today. {kcal} may carry a "~" prefix when estimated.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal eaten'**
  String dietKcalEaten(String kcal);

  /// Section label over the calorie/macro target.
  ///
  /// In en, this message translates to:
  /// **'Your target'**
  String get dietYourTarget;

  /// Section label over today's macro progress bars.
  ///
  /// In en, this message translates to:
  /// **'Macros today'**
  String get dietMacrosToday;

  /// Section label over the verdict on whether the plan gains or loses weight.
  ///
  /// In en, this message translates to:
  /// **'What this plan does'**
  String get dietWhatPlanDoes;

  /// Section label over the coach's read on today.
  ///
  /// In en, this message translates to:
  /// **'Today\'s read'**
  String get dietTodaysRead;

  /// Section label over every day of the plan.
  ///
  /// In en, this message translates to:
  /// **'Full plan'**
  String get dietFullPlan;

  /// How many days a plan covers, as a caps micro-label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 DAY} other{{count} DAYS}}'**
  String dietDayCountCaps(int count);

  /// Explains why setting a calorie target is worth doing.
  ///
  /// In en, this message translates to:
  /// **'Set one and the numbers above become progress toward a goal — and your coach can tell you where you stand.'**
  String get dietNoTargetBody;

  /// Adopts the plan's own daily total as the calorie target. {kcal} may carry a "~" prefix.
  ///
  /// In en, this message translates to:
  /// **'Use this plan\'s {kcal} kcal'**
  String dietUseThisPlanKcal(String kcal);

  /// A target summarised as its goal and daily calories.
  ///
  /// In en, this message translates to:
  /// **'{goal} · {kcal} KCAL/DAY'**
  String dietGoalKcalPerDayCaps(String goal, int kcal);

  /// Warning under a calorie target set below the safe floor.
  ///
  /// In en, this message translates to:
  /// **'{source} · below {kcal} kcal — worth checking with a professional'**
  String dietBelowSafeFloor(String source, int kcal);

  /// Prompt to add the body data needed to judge the plan.
  ///
  /// In en, this message translates to:
  /// **'Is this plan making you gain or lose?'**
  String get dietGainOrLose;

  /// What body data is still missing, e.g. "your height and your current weight".
  ///
  /// In en, this message translates to:
  /// **'ZIVO needs {missing} to work it out.'**
  String dietNeedsToWorkOut(String missing);

  /// Joins two items into a phrase.
  ///
  /// In en, this message translates to:
  /// **'{first} and {second}'**
  String dietListTwo(String first, String second);

  /// Joins three or more items; {leading} is already comma-separated.
  ///
  /// In en, this message translates to:
  /// **'{leading} and {last}'**
  String dietListMany(String leading, String last);

  /// Caps label on the plan verdict card. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'THIS PLAN'**
  String get dietThisPlanCaps;

  /// Caps link to edit height, weight and activity. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'BODY DATA'**
  String get dietBodyDataCaps;

  /// Says how many days the plan average rests on, and how many had no calorie data.
  ///
  /// In en, this message translates to:
  /// **'Averaged over {counted, plural, =1{1 day} other{{counted} days}}; {missing, plural, =1{1 day has} other{{missing} days have}} no calorie figures.'**
  String dietAveragedOver(int counted, int missing);

  /// How much protein the plan provides relative to bodyweight.
  ///
  /// In en, this message translates to:
  /// **'Protein {grams} g per kg of bodyweight.'**
  String dietProteinPerKg(String grams);

  /// Nudge to log a fresh weigh-in.
  ///
  /// In en, this message translates to:
  /// **'Your last weigh-in is {days} days old — weight drives this figure, so it is worth updating.'**
  String dietStaleWeighIn(int days);

  /// Safety warning on a plan below the minimum safe calories.
  ///
  /// In en, this message translates to:
  /// **'This plan is under {kcal} kcal a day. Sustained intake down here belongs with a doctor, not an app.'**
  String dietUnderSafeFloor(int kcal);

  /// What is still needed before real maintenance calories can be measured.
  ///
  /// In en, this message translates to:
  /// **'Log {missing} and ZIVO can measure what you actually burn, instead of estimating it.'**
  String dietCalibrationPrompt(String missing);

  /// The measured maintenance differs from the one currently in use.
  ///
  /// In en, this message translates to:
  /// **'Your last {days} days say you actually burn about {measured} — not the {used} above. Worth updating.'**
  String dietMeasuredDisagrees(int days, int measured, int used);

  /// Summarises the measured maintenance window.
  ///
  /// In en, this message translates to:
  /// **'Measured from your last {days} days: {intake} kcal a day eaten, {change}.'**
  String dietMeasuredFrom(int days, int intake, String change);

  /// Weight did not meaningfully change over the measured window.
  ///
  /// In en, this message translates to:
  /// **'weight steady'**
  String get dietWeightSteady;

  /// Weight rose over the measured window.
  ///
  /// In en, this message translates to:
  /// **'weight up {kg} kg'**
  String dietWeightUp(String kg);

  /// Weight fell over the measured window.
  ///
  /// In en, this message translates to:
  /// **'weight down {kg} kg'**
  String dietWeightDown(String kg);

  /// Grams eaten out of the target for one macro. {target} may carry a "~" prefix.
  ///
  /// In en, this message translates to:
  /// **'{eaten}/{target}g'**
  String dietMacroProgress(String eaten, String target);

  /// A plan day's calorie total. {kcal} may carry a "~" prefix when estimated.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal'**
  String dietDayKcal(String kcal);

  /// Body data still missing, phrased to drop into a sentence.
  ///
  /// In en, this message translates to:
  /// **'your current weight'**
  String get dietMissingWeight;

  /// Body data still missing, phrased to drop into a sentence.
  ///
  /// In en, this message translates to:
  /// **'your height'**
  String get dietMissingHeight;

  /// Body data still missing: which Mifflin-St Jeor form to use. Phrased to drop into a sentence.
  ///
  /// In en, this message translates to:
  /// **'the BMR formula ZIVO should use'**
  String get dietMissingSex;

  /// Body data still missing, phrased to drop into a sentence.
  ///
  /// In en, this message translates to:
  /// **'how active your week is'**
  String get dietMissingActivity;

  /// Body data still missing, phrased to drop into a sentence.
  ///
  /// In en, this message translates to:
  /// **'your date of birth'**
  String get dietMissingDateOfBirth;

  /// A nutrition reference database. A proper name — keep it untranslated.
  ///
  /// In en, this message translates to:
  /// **'USDA FoodData Central'**
  String get dietSourceUsda;

  /// A food the user entered themselves.
  ///
  /// In en, this message translates to:
  /// **'Your own food'**
  String get dietSourceUserCustom;

  /// Nutrition figures taken from the user's own plan.
  ///
  /// In en, this message translates to:
  /// **'Your diet plan'**
  String get dietSourcePlan;

  /// Empty state headline when the user has never had a plan.
  ///
  /// In en, this message translates to:
  /// **'No diet plan yet.'**
  String get dietNoPlanYetHeadline;

  /// Empty state headline when every plan is archived.
  ///
  /// In en, this message translates to:
  /// **'You\'re not following a plan.'**
  String get dietNotFollowingHeadline;

  /// Empty state body listing the ways to add a diet plan.
  ///
  /// In en, this message translates to:
  /// **'Import a document or a photo, say it out loud, type it out, or build one by hand — I\'ll fill in the calories and macros.'**
  String get dietNoPlanYetBody;

  /// Empty state body when plans exist but none is active.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 plan is archived — pick one back up, or add another.} other{{count} plans are archived — pick one back up, or add another.}}'**
  String dietArchivedPlans(int count);

  /// Opens the list of saved diet plans.
  ///
  /// In en, this message translates to:
  /// **'See your plans'**
  String get dietSeeYourPlans;

  /// Where a logged food's figures came from.
  ///
  /// In en, this message translates to:
  /// **'from your plan'**
  String get dietFromYourPlan;

  /// A logged amount and its unit, e.g. "150 g".
  ///
  /// In en, this message translates to:
  /// **'{quantity} {unit}'**
  String dietQuantityUnit(String quantity, String unit);

  /// How many of today's planned meals have been ticked.
  ///
  /// In en, this message translates to:
  /// **'{eaten} of {total} meals eaten'**
  String dietMealsEaten(int eaten, int total);

  /// Caps note when a plan carries no calorie figures. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'NO CALORIE DATA YET'**
  String get dietNoCalorieDataCaps;

  /// Caps label under the hero figure when the target is exceeded. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'KCAL OVER'**
  String get dietKcalOverCaps;

  /// Caps label under the hero figure. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'KCAL LEFT'**
  String get dietKcalLeftCaps;

  /// Caps label under the hero figure when measured against the plan rather than a target.
  ///
  /// In en, this message translates to:
  /// **'KCAL LEFT OF PLAN'**
  String get dietKcalLeftOfPlanCaps;

  /// Caps prefix marking a figure that rests on estimated values. Trailing space is intentional.
  ///
  /// In en, this message translates to:
  /// **'EST. '**
  String get dietEstPrefixCaps;

  /// How many food items a meal contains.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String dietItemCount(int count);

  /// Opens a meal's full breakdown.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get dietViewDetails;

  /// An activity level.
  ///
  /// In en, this message translates to:
  /// **'Sedentary'**
  String get dietActivitySedentary;

  /// An activity level.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get dietActivityLight;

  /// An activity level.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get dietActivityModerate;

  /// An activity level.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get dietActivityHigh;

  /// An activity level.
  ///
  /// In en, this message translates to:
  /// **'Very high'**
  String get dietActivityAthlete;

  /// What the sedentary activity level describes.
  ///
  /// In en, this message translates to:
  /// **'Desk job, little deliberate exercise'**
  String get dietActivitySedentaryDetail;

  /// What the light activity level describes.
  ///
  /// In en, this message translates to:
  /// **'Training 1–3 days a week'**
  String get dietActivityLightDetail;

  /// What the moderate activity level describes.
  ///
  /// In en, this message translates to:
  /// **'Training 3–5 days a week'**
  String get dietActivityModerateDetail;

  /// What the high activity level describes.
  ///
  /// In en, this message translates to:
  /// **'Training 6–7 days a week'**
  String get dietActivityHighDetail;

  /// What the very-high activity level describes.
  ///
  /// In en, this message translates to:
  /// **'Hard training daily, or a physical job on top'**
  String get dietActivityAthleteDetail;

  /// The body data a calculated target was derived from.
  ///
  /// In en, this message translates to:
  /// **'{weight} kg · {activity} · {maintenance} kcal maintenance'**
  String dietTargetBasisSummary(
    String weight,
    String activity,
    int maintenance,
  );

  /// Title when no target exists yet.
  ///
  /// In en, this message translates to:
  /// **'Set your target'**
  String get dietSetYourTarget;

  /// Title when editing an existing target.
  ///
  /// In en, this message translates to:
  /// **'Daily target'**
  String get dietDailyTarget;

  /// Explains why the calorie and macro targets matter.
  ///
  /// In en, this message translates to:
  /// **'Your coach uses these numbers for everything it tells you. Until they\'re set, it can describe your plan but not how you\'re doing against it.'**
  String get dietTargetsIntro;

  /// Section label over the diet goal picker.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get dietGoal;

  /// Section label over the calorie and macro fields.
  ///
  /// In en, this message translates to:
  /// **'Daily numbers'**
  String get dietDailyNumbers;

  /// Badge marking figures derived from body data. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'CALCULATED'**
  String get dietCalculatedCaps;

  /// Explains that macro fields are optional.
  ///
  /// In en, this message translates to:
  /// **'Only calories are required. Leave a macro blank if you aren\'t tracking it — blank means untracked, not zero.'**
  String get dietOnlyCaloriesRequired;

  /// Explains what the calculate button does.
  ///
  /// In en, this message translates to:
  /// **'Fills the fields with a starting point you can edit. Nothing is saved until you tap Save.'**
  String get dietFillFieldsHint;

  /// Warning before saving a calorie target below the safe floor.
  ///
  /// In en, this message translates to:
  /// **'{calories} kcal is below {floor}, which is under what ZIVO should be coaching. You can still save it, but eating this low is worth talking through with a doctor or a registered dietitian first.'**
  String dietBelowSafeWarning(int calories, int floor);

  /// Explains how a calculated target was derived.
  ///
  /// In en, this message translates to:
  /// **'From {weight}kg at {activity} activity: {bmr} kcal at rest, {maintenance} kcal to maintain, adjusted for {goal}. These are population estimates — adjust them from what the scale actually does.'**
  String dietCalculatedFrom(
    String weight,
    String activity,
    int bmr,
    int maintenance,
    String goal,
  );

  /// The BMR formula variable, not a profile field.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get dietSexMale;

  /// The BMR formula variable, not a profile field.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get dietSexFemale;

  /// Nudge before calculating a target from an old weight.
  ///
  /// In en, this message translates to:
  /// **'Your last weigh-in was {days} days ago. Worth logging a new one first.'**
  String dietStaleWeighInPrompt(int days);

  /// A weight in kilograms.
  ///
  /// In en, this message translates to:
  /// **'{value} kg'**
  String dietKgValue(String value);

  /// A height in centimetres.
  ///
  /// In en, this message translates to:
  /// **'{value} cm'**
  String dietCmValue(int value);

  /// Which catalog a food search is running against.
  ///
  /// In en, this message translates to:
  /// **'Searching {source}.'**
  String dietSearching(String source);

  /// Placeholder in the food search field. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'chicken breast, rice, olive oil…'**
  String get dietFoodSearchHint;

  /// Validation when the amount field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount.'**
  String get dietEnterAmount;

  /// Validation when the amount is zero or negative.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount above zero.'**
  String get dietEnterAmountAboveZero;

  /// A food's energy density.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal / 100g'**
  String dietKcalPer100g(int kcal);

  /// A food's energy density, tighter spacing for a compact row.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal/100g'**
  String dietKcalPer100gTight(int kcal);

  /// Prompt before any search term is entered.
  ///
  /// In en, this message translates to:
  /// **'Type a food to search.'**
  String get dietTypeToSearch;

  /// Shown when a food search returns nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the catalog matches \"{query}\".'**
  String dietNoCatalogMatch(String query);

  /// Explains why a food may be missing, and offers to add it.
  ///
  /// In en, this message translates to:
  /// **'It\'s a USDA catalog, so it\'s thin on regional and home cooking. Rather than guess, tell ZIVO what this food is once and it\'ll remember.'**
  String get dietCatalogThinBody;

  /// An energy figure in kilocalories.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal'**
  String dietKcalValue(int kcal);

  /// A compact macro breakdown. P/C/F abbreviate protein, carbs and fat.
  ///
  /// In en, this message translates to:
  /// **'P {protein}g · C {carbs}g · F {fat}g · {grams}g'**
  String dietMacroLine(String protein, String carbs, String fat, String grams);

  /// Why a non-weight unit was rejected for this food.
  ///
  /// In en, this message translates to:
  /// **'ZIVO only has this food by weight — enter it in grams. Converting {unit} would mean guessing a density.'**
  String dietWeightOnlyFood(String unit);

  /// Which units this food does support.
  ///
  /// In en, this message translates to:
  /// **'ZIVO doesn\'t have {unit} for this food. Use grams, or: {alternatives}'**
  String dietNoSuchUnit(String unit, String alternatives);

  /// Explains the custom-food fields.
  ///
  /// In en, this message translates to:
  /// **'Per 100g, from the label or your own measure. ZIVO stores these as yours and never overwrites them.'**
  String get dietCustomFoodHint;

  /// Caps label over the maintenance calorie figure. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'MAINTENANCE'**
  String get dietMaintenanceCaps;

  /// A daily energy figure.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal a day'**
  String dietKcalPerDay(int kcal);

  /// Where the maintenance figure came from: the user typed it.
  ///
  /// In en, this message translates to:
  /// **'The figure you gave. ZIVO uses it as-is.'**
  String get dietMaintenanceGiven;

  /// Where the maintenance figure came from: a formula.
  ///
  /// In en, this message translates to:
  /// **'Estimated from these numbers — a population average, not a measurement of you.'**
  String get dietMaintenanceEstimated;

  /// How long since the last weigh-in.
  ///
  /// In en, this message translates to:
  /// **'{days} days ago'**
  String dietDaysAgo(int days);

  /// How long since the last weigh-in.
  ///
  /// In en, this message translates to:
  /// **'{weeks} weeks ago'**
  String dietWeeksAgo(int weeks);

  /// How long since the last weigh-in.
  ///
  /// In en, this message translates to:
  /// **'{months} months ago'**
  String dietMonthsAgo(int months);

  /// A cuisine chip.
  ///
  /// In en, this message translates to:
  /// **'Egyptian'**
  String get dietCuisineEgyptian;

  /// A cuisine chip.
  ///
  /// In en, this message translates to:
  /// **'Mediterranean'**
  String get dietCuisineMediterranean;

  /// A cuisine chip.
  ///
  /// In en, this message translates to:
  /// **'Levantine'**
  String get dietCuisineLevantine;

  /// A cuisine chip.
  ///
  /// In en, this message translates to:
  /// **'Indian'**
  String get dietCuisineIndian;

  /// A cuisine chip.
  ///
  /// In en, this message translates to:
  /// **'Asian'**
  String get dietCuisineAsian;

  /// A cuisine chip.
  ///
  /// In en, this message translates to:
  /// **'Western'**
  String get dietCuisineWestern;

  /// Assertion note explaining the import page has one mode per run.
  ///
  /// In en, this message translates to:
  /// **'A run either reads material or designs a plan — never both.'**
  String get dietImportOneRun;

  /// Progress line while generating a plan. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Choosing foods you like…'**
  String get dietGeneratingFoods;

  /// Progress line while generating a plan. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Looking up real calories for each one…'**
  String get dietGeneratingCalories;

  /// Progress line while generating a plan. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Sizing the portions to your target…'**
  String get dietGeneratingPortions;

  /// Shown when a picked document could not be read.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that file.'**
  String get dietFileReadFailed;

  /// Shown when a picked document exceeds the size limit.
  ///
  /// In en, this message translates to:
  /// **'That file is too large — please choose one under {mb} MB.'**
  String dietFileTooLarge(int mb);

  /// Title of the diet import screen.
  ///
  /// In en, this message translates to:
  /// **'Import Plan'**
  String get dietImportPlanTitle;

  /// Title while a plan is being generated.
  ///
  /// In en, this message translates to:
  /// **'Building your plan'**
  String get dietBuildingYourPlan;

  /// Title while a document is being read.
  ///
  /// In en, this message translates to:
  /// **'Reading your plan'**
  String get dietReadingYourPlan;

  /// Prompt to pick a document or photo.
  ///
  /// In en, this message translates to:
  /// **'Select your diet plan'**
  String get dietSelectYourPlan;

  /// Explains what importing a document does.
  ///
  /// In en, this message translates to:
  /// **'Choose a PDF or a photo of your plan and I\'ll map it into a real, editable plan — estimating calories and macros wherever the document doesn\'t state them.'**
  String get dietSelectYourPlanBody;

  /// Failure title after a generation attempt.
  ///
  /// In en, this message translates to:
  /// **'ZIVO couldn\'t build that plan'**
  String get dietCouldntBuildPlan;

  /// Failure title when the document was not recognised.
  ///
  /// In en, this message translates to:
  /// **'This doesn\'t look like a diet plan'**
  String get dietNotADietPlan;

  /// Retry action after a failed import.
  ///
  /// In en, this message translates to:
  /// **'Choose a different file'**
  String get dietChooseDifferentFile;

  /// Retry action after a failed generation.
  ///
  /// In en, this message translates to:
  /// **'Go back and edit'**
  String get dietGoBackAndEdit;

  /// Tail of a sentence offering the manual builder as a fallback.
  ///
  /// In en, this message translates to:
  /// **'build the plan manually.'**
  String get dietBuildManually;

  /// Explains how plan generation works.
  ///
  /// In en, this message translates to:
  /// **'ZIVO picks the foods and looks up what they actually weigh in calories — it doesn\'t guess them. Tell it what you eat and it will build a day you can review before anything is saved.'**
  String get dietPreferencesIntro;

  /// Section label over the meals-per-day picker.
  ///
  /// In en, this message translates to:
  /// **'Meals a day'**
  String get dietMealsADay;

  /// Why the meals-per-day choice matters.
  ///
  /// In en, this message translates to:
  /// **'The single biggest reason a plan survives a working week, or does not.'**
  String get dietMealsADayNote;

  /// Section label over the cuisine chips.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get dietKitchen;

  /// Marks a section that can be skipped. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'OPTIONAL'**
  String get dietOptionalCaps;

  /// Reassurance above the generate button.
  ///
  /// In en, this message translates to:
  /// **'Nothing is saved until you review the plan and tap Save.'**
  String get dietNothingSavedUntilReview;

  /// Confirms the generated plan will match the calorie target.
  ///
  /// In en, this message translates to:
  /// **'Sized to your target — {kcal} kcal a day.'**
  String dietSizedToTarget(int kcal);

  /// Shown when generating a plan with no calorie target set.
  ///
  /// In en, this message translates to:
  /// **'ZIVO will still build the plan, but it has no figure to size the portions to. Set one first and the day comes out fitted to it.'**
  String get dietNoTargetToSizeTo;

  /// Note under a single saved plan.
  ///
  /// In en, this message translates to:
  /// **'One plan. Import or write another and you can switch between them without losing either.'**
  String get dietOnePlanNote;

  /// Note under several saved plans.
  ///
  /// In en, this message translates to:
  /// **'{count} plans. One is in force at a time — the Diet screen always shows that one.'**
  String dietManyPlansNote(int count);

  /// Empty state in the plans library.
  ///
  /// In en, this message translates to:
  /// **'No plans yet.'**
  String get dietNoPlansYet;

  /// How many days a plan covers, on its card. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 DAY} other{{count} DAYS}}'**
  String dietDaysCaps(int count);

  /// A plan's average daily energy. {kcal} may carry a "~" prefix.
  ///
  /// In en, this message translates to:
  /// **'{kcal} KCAL/DAY'**
  String dietKcalPerDayCaps(String kcal);

  /// The plan currently in force. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'FOLLOWING'**
  String get dietFollowingCaps;

  /// A shelved plan. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'ARCHIVED'**
  String get dietArchivedCaps;

  /// An unfinished plan. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'DRAFT'**
  String get dietDraftCaps;

  /// Section label over a meal's items.
  ///
  /// In en, this message translates to:
  /// **'What’s in it'**
  String get dietWhatsInIt;

  /// Empty state on a meal with no items.
  ///
  /// In en, this message translates to:
  /// **'No items listed for this meal.'**
  String get dietNoItemsListed;

  /// Undoes marking a meal eaten.
  ///
  /// In en, this message translates to:
  /// **'Mark as not eaten'**
  String get dietMarkNotEaten;

  /// Marks a meal as eaten.
  ///
  /// In en, this message translates to:
  /// **'Done — mark as eaten'**
  String get dietMarkEaten;

  /// One-letter abbreviation for protein.
  ///
  /// In en, this message translates to:
  /// **'P'**
  String get dietMacroP;

  /// One-letter abbreviation for carbohydrates.
  ///
  /// In en, this message translates to:
  /// **'C'**
  String get dietMacroC;

  /// One-letter abbreviation for fat.
  ///
  /// In en, this message translates to:
  /// **'F'**
  String get dietMacroF;

  /// A weight in grams.
  ///
  /// In en, this message translates to:
  /// **'{grams}g'**
  String dietGramsValue(int grams);

  /// Title of the sheet that adopts a plan total as the calorie target.
  ///
  /// In en, this message translates to:
  /// **'Use your plan\'s numbers'**
  String get dietUsePlanNumbers;

  /// A plan's average daily calories. {kcal} may carry a "~" prefix.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal a day, averaged over the {days} days of {plan}.'**
  String dietPlanAverageOverDays(String kcal, int days, String plan);

  /// A plan's daily calories. {kcal} may carry a "~" prefix.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal a day, from {plan}.'**
  String dietPlanFrom(String kcal, String plan);

  /// Caveat on a plan average that skipped days.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day has no calorie figures and is not in that average.} other{{count} days have no calorie figures and are not in that average.}}'**
  String dietDaysWithoutCalories(int count);

  /// Section label over the goal picker in the adopt sheet.
  ///
  /// In en, this message translates to:
  /// **'What is it for?'**
  String get dietWhatIsItFor;

  /// Why a goal is required alongside a calorie target.
  ///
  /// In en, this message translates to:
  /// **'The same calories mean different things depending on what you\'re doing. ZIVO needs this to say how you\'re doing against them.'**
  String get dietWhyGoalMatters;

  /// Warning before adopting a plan below the safe floor.
  ///
  /// In en, this message translates to:
  /// **'This plan averages under {kcal} kcal a day. Adopting it as a target is worth talking through with a doctor or a registered dietitian first.'**
  String dietPlanBelowSafeFloor(int kcal);

  /// A meal that repeats on every day of the plan.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get dietEveryDay;

  /// Deletes a day from the plan.
  ///
  /// In en, this message translates to:
  /// **'Remove day'**
  String get dietRemoveDay;

  /// Deletes a meal from a day.
  ///
  /// In en, this message translates to:
  /// **'Remove meal'**
  String get dietRemoveMeal;

  /// Deletes a food from a meal.
  ///
  /// In en, this message translates to:
  /// **'Remove item'**
  String get dietRemoveItem;

  /// Column header over a food's unit. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'UNIT'**
  String get dietUnitCaps;

  /// Title when dictating a diet plan.
  ///
  /// In en, this message translates to:
  /// **'Describe your diet'**
  String get dietDescribeYourDiet;

  /// Title when typing a diet plan.
  ///
  /// In en, this message translates to:
  /// **'Type it out'**
  String get dietTypeItOut;

  /// Explains dictating or typing a diet plan.
  ///
  /// In en, this message translates to:
  /// **'Say or write what you eat in a day — meals, foods and rough amounts. ZIVO turns it into a plan you review before anything is saved.'**
  String get dietDictateBody;

  /// An example utterance for dictating a diet plan.
  ///
  /// In en, this message translates to:
  /// **'Example: \"Breakfast is three eggs and 60 grams of oats. Lunch is 200 grams of chicken with rice and salad.\"'**
  String get dietDictateExample;

  /// Collapses a finding's reasoning. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'HIDE'**
  String get dietHideCaps;

  /// Expands a finding's reasoning. Set in caps in English.
  ///
  /// In en, this message translates to:
  /// **'WHY'**
  String get dietWhyCaps;

  /// How a diet plan was created.
  ///
  /// In en, this message translates to:
  /// **'Written by hand'**
  String get dietSourceManual;

  /// How a diet plan was created.
  ///
  /// In en, this message translates to:
  /// **'Imported from a document'**
  String get dietSourcePdf;

  /// How a diet plan was created.
  ///
  /// In en, this message translates to:
  /// **'Imported from a photo'**
  String get dietSourcePhoto;

  /// How a diet plan was created.
  ///
  /// In en, this message translates to:
  /// **'Dictated'**
  String get dietSourceDictated;

  /// How a diet plan was created.
  ///
  /// In en, this message translates to:
  /// **'Built by ZIVO'**
  String get dietSourceGenerated;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
