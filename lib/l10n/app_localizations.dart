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

  /// Heading above the Hub's recent-activity rows.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get hubRecent;

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
