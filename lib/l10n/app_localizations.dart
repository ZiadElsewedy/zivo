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
