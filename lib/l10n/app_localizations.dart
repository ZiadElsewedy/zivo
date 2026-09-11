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

  /// Today's Volume ring: the change is week-over-week. Short by design — it sits under a figure in a small ring.
  ///
  /// In en, this message translates to:
  /// **'WoW'**
  String get pulseWeekOverWeek;

  /// The Hub tab's display title.
  ///
  /// In en, this message translates to:
  /// **'Hub'**
  String get hubTitle;

  /// Section label over the band of services ZIVO talks to (Spotify, Google Drive).
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get hubConnected;

  /// Hub workout tile: a session on this day is in progress and can be resumed.
  ///
  /// In en, this message translates to:
  /// **'{day} · resume'**
  String hubWorkoutResume(String day);

  /// Hub workout tile: the plan day that comes next.
  ///
  /// In en, this message translates to:
  /// **'{day} · up next'**
  String hubWorkoutUpNext(String day);

  /// Hub diet tile: meals eaten out of the day's total, and the calories left. {kcal} already carries a leading ~ when the figure is an estimate.
  ///
  /// In en, this message translates to:
  /// **'{eaten} of {total} · {kcal} kcal'**
  String hubDietStat(int eaten, int total, String kcal);

  /// Hub expenses tile: what has been spent this week, already formatted with its currency.
  ///
  /// In en, this message translates to:
  /// **'{amount} this week'**
  String hubExpensesStat(String amount);

  /// Hub moments tile: how many moments have been captured.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 moment} other{{count} moments}}'**
  String hubMomentsCount(int count);

  /// Hub Connected band: Google Drive is connected and photos are being backed up to it.
  ///
  /// In en, this message translates to:
  /// **'Backing up'**
  String get connectedBackingUp;

  /// Hub Connected band: this service has not been connected on this device.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get connectedNotConnected;

  /// Hub Connected band: Spotify is connected but nothing is playing.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectedConnected;

  /// Hub Connected band: Spotify is playing a track.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get connectedPlaying;

  /// Hub Connected band: Spotify is connected and paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get connectedPaused;

  /// Hub Connected band: a connection attempt is in flight.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connectedConnecting;

  /// Hub Connected band: the service refused the connection.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t connect'**
  String get connectedCouldntConnect;

  /// Hub Connected band: Spotify needs a Premium account to control playback.
  ///
  /// In en, this message translates to:
  /// **'Premium required'**
  String get connectedPremiumRequired;

  /// Hub Connected band: the Spotify app is not on this phone.
  ///
  /// In en, this message translates to:
  /// **'Install Spotify'**
  String get connectedInstallSpotify;

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

  /// Title of Today's card for a plan that exists but has no training days. {plan} is the plan's own name.
  ///
  /// In en, this message translates to:
  /// **'{plan} has no days'**
  String todayEmptySplitTitle(String plan);

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

  /// Body line under Today's first-run heading, naming the two ways in.
  ///
  /// In en, this message translates to:
  /// **'Import a plan or log a spend — ZIVO builds Today from there.'**
  String get todayGetStartedBody;

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

  /// Section label over the Workout plan page's drill-down rows (Splits, Analysis, History).
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get workoutMoreSection;

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

  /// Day-picker mode: the picked day trades places with the day that was due, so nothing leaves the cycle.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get workoutChangeSwap;

  /// Day-picker mode: train the picked day and let the day that was due drop out of this cycle.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get workoutChangeSkip;

  /// Explains the Swap mode, naming the day that was due.
  ///
  /// In en, this message translates to:
  /// **'{day} takes the slot you pick — the cycle stays whole.'**
  String workoutChangeSwapNote(String day);

  /// Explains the Skip mode, naming the day that was due.
  ///
  /// In en, this message translates to:
  /// **'{day} is skipped this cycle.'**
  String workoutChangeSkipNote(String day);

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

  /// The short letter or number identifying a training day within a split (A, B, 1, 2).
  ///
  /// In en, this message translates to:
  /// **'Slot'**
  String get planDaySlot;

  /// Example slot value shown in the empty field.
  ///
  /// In en, this message translates to:
  /// **'A'**
  String get planDaySlotHint;

  /// The training day's name field.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get planDayLabel;

  /// Placeholder for a day's name.
  ///
  /// In en, this message translates to:
  /// **'Day label (optional)'**
  String get planDayLabelHint;

  /// Free-text notes on a training day; may be left blank.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get planDayNotesOptional;

  /// Caption under the shortest recorded session's duration.
  ///
  /// In en, this message translates to:
  /// **'shortest'**
  String get workoutShortestSession;

  /// Caption under the longest recorded session's duration.
  ///
  /// In en, this message translates to:
  /// **'longest'**
  String get workoutLongestSession;

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

  /// Caption under a consumed figure: the number came from food the user logged.
  ///
  /// In en, this message translates to:
  /// **'logged by you'**
  String get dietBasisLogged;

  /// Caption under a consumed figure: the number is the plan's expectation for meals ticked off, not a measurement.
  ///
  /// In en, this message translates to:
  /// **'from ticked meals, not weighed'**
  String get dietBasisTicked;

  /// Caption under a consumed figure when nothing has been logged.
  ///
  /// In en, this message translates to:
  /// **'nothing logged yet'**
  String get dietBasisNothing;

  /// Register of one coach finding: a plain statement of fact.
  ///
  /// In en, this message translates to:
  /// **'Observation'**
  String get dietFindingObservation;

  /// Register of one coach finding: a worked-out reading of the numbers.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get dietFindingAnalysis;

  /// Register of one coach finding: something to consider doing.
  ///
  /// In en, this message translates to:
  /// **'Suggestion'**
  String get dietFindingSuggestion;

  /// Register of one coach finding: something that needs attention.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get dietFindingWarning;

  /// Register of one coach finding: encouragement.
  ///
  /// In en, this message translates to:
  /// **'Going well'**
  String get dietFindingGoingWell;

  /// Register of one coach finding: a clarification.
  ///
  /// In en, this message translates to:
  /// **'Worth knowing'**
  String get dietFindingWorthKnowing;

  /// Marks a meal as eaten.
  ///
  /// In en, this message translates to:
  /// **'Eaten'**
  String get dietEaten;

  /// A meal marked back to not eaten, on ZIVO's confirmation card.
  ///
  /// In en, this message translates to:
  /// **'Not eaten'**
  String get dietNotEaten;

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

  /// Section label over the full list of logged weigh-ins, newest first.
  ///
  /// In en, this message translates to:
  /// **'All weigh-ins'**
  String get workoutBodyweightAllWeighIns;

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

  /// Title of the streak-orbit page opened from Today's Momentum card.
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get streakOrbitTitle;

  /// Label under the all-time best streak figure on the streak-orbit page.
  ///
  /// In en, this message translates to:
  /// **'Best streak'**
  String get streakOrbitBestLabel;

  /// Label under the lifetime count of distinct days the user trained, on the streak-orbit page.
  ///
  /// In en, this message translates to:
  /// **'Days trained'**
  String get streakOrbitTrainedTotal;

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

  /// Section label over the searchable, category-grouped exercise browser on the Analysis page.
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get workoutExercisesBrowse;

  /// Placeholder in the exercise search field on the Analysis page.
  ///
  /// In en, this message translates to:
  /// **'Search exercises'**
  String get workoutSearchExercises;

  /// Shown when the exercise search finds nothing.
  ///
  /// In en, this message translates to:
  /// **'No exercises match “{query}”.'**
  String workoutNoMatches(String query);

  /// Caps count of movements beside a muscle-category header on the Analysis browser.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 MOVEMENT} other{{count} MOVEMENTS}}'**
  String workoutExerciseCountCaps(int count);

  /// Muscle-group category header on the Analysis browser.
  ///
  /// In en, this message translates to:
  /// **'Chest'**
  String get workoutMuscleChest;

  /// Muscle-group category header on the Analysis browser.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get workoutMuscleBack;

  /// Muscle-group category header on the Analysis browser.
  ///
  /// In en, this message translates to:
  /// **'Legs'**
  String get workoutMuscleLegs;

  /// Muscle-group category header on the Analysis browser.
  ///
  /// In en, this message translates to:
  /// **'Shoulders'**
  String get workoutMuscleShoulders;

  /// Muscle-group category header on the Analysis browser.
  ///
  /// In en, this message translates to:
  /// **'Arms'**
  String get workoutMuscleArms;

  /// Muscle-group category header on the Analysis browser.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get workoutMuscleCore;

  /// Fallback category header for exercises with no recognised muscle group.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get workoutMuscleOther;

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

  /// A planned set described by its rep target, which may be a range ("8–10 reps") rather than a single number.
  ///
  /// In en, this message translates to:
  /// **'{reps} reps'**
  String workoutRepsSpec(String reps);

  /// How many sets a planned exercise has, e.g. "3 sets".
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 set} other{{count} sets}}'**
  String workoutSetCount(num count);

  /// A set with no rep target — taken until no more reps are possible.
  ///
  /// In en, this message translates to:
  /// **'To failure'**
  String get workoutToFailure;

  /// The bulk control that sets one rest value on every exercise in a plan.
  ///
  /// In en, this message translates to:
  /// **'Default rest'**
  String get planDefaultRest;

  /// The bulk-rest row, showing the value it would apply. {time} is a clock duration like 1:30.
  ///
  /// In en, this message translates to:
  /// **'Default rest · {time}'**
  String planDefaultRestValue(String time);

  /// Explains that the bulk rest is a starting point, not a lock.
  ///
  /// In en, this message translates to:
  /// **'Sets every exercise in this plan to this rest. Editing one exercise afterward still overrides it individually.'**
  String get planDefaultRestNote;

  /// Applies the chosen rest to every exercise in the plan.
  ///
  /// In en, this message translates to:
  /// **'Set all'**
  String get planSetAll;

  /// The rest window in a planned set's spec line, e.g. "rest 1:30". Lower case: it sits mid-line after a separator.
  ///
  /// In en, this message translates to:
  /// **'rest {time}'**
  String workoutRestFor(String time);

  /// The head of a collapsed set line — how many sets at what rep target, e.g. "3 × 8–10". The × is a symbol in both languages.
  ///
  /// In en, this message translates to:
  /// **'{count} × {reps}'**
  String workoutSetsBy(int count, String reps);

  /// Caption under a workout day's title: which plan it belongs to and how many exercises it holds.
  ///
  /// In en, this message translates to:
  /// **'{plan} · {exercises}'**
  String workoutPlanDayMeta(String plan, String exercises);

  /// A planned exercise's meta line: its set count and the muscle group it trains.
  ///
  /// In en, this message translates to:
  /// **'{sets} · {muscleGroup}'**
  String workoutExerciseMeta(String sets, String muscleGroup);

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

  /// Compact relative timestamp for something that happened under a minute ago.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get timeAgoNow;

  /// Compact relative timestamp in minutes, e.g. 5m.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String timeAgoMinutes(int minutes);

  /// Compact relative timestamp in hours, e.g. 3h.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String timeAgoHours(int hours);

  /// Compact relative timestamp in days, e.g. 2d.
  ///
  /// In en, this message translates to:
  /// **'{days}d'**
  String timeAgoDays(int days);

  /// Reply-style option: short, to-the-point answers.
  ///
  /// In en, this message translates to:
  /// **'Concise'**
  String get askReplyStyleConcise;

  /// Reply-style option: the default reply length.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get askReplyStyleBalanced;

  /// Reply-style option: longer, fuller answers.
  ///
  /// In en, this message translates to:
  /// **'Detailed'**
  String get askReplyStyleDetailed;

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

  /// Button on the assistant's input form that sends the entered values back to the coach.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get askInputSubmit;

  /// State of the input-form button after the user has submitted their values.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get askInputSent;

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

  /// Today's diet glance: calories remaining, measured against the user's own daily target. {kcal} already carries a leading ~ when the figure rests on estimates.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal left of target'**
  String dietKcalLeftOfTarget(String kcal);

  /// Today's diet glance: calories remaining, measured against the day's plan total. {kcal} already carries a leading ~ when the figure rests on estimates.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal left of plan'**
  String dietKcalLeftOfPlan(String kcal);

  /// Today's diet glance: calories past the user's own daily target. {kcal} already carries a leading ~ when the figure rests on estimates.
  ///
  /// In en, this message translates to:
  /// **'{kcal} kcal over target'**
  String dietKcalOverTarget(String kcal);

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

  /// Marks the meal-detail screen as a supplement rather than food. A small caption beside the calorie figure.
  ///
  /// In en, this message translates to:
  /// **'Supplement'**
  String get dietSupplementMark;

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

  /// Lower-case "today", for dropping mid-sentence (e.g. "Last weigh-in: today").
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get dateTodayLower;

  /// Lower-case "yesterday", for dropping mid-sentence.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get dateYesterdayLower;

  /// Shown on a photo tile whose bytes are not on this device and were never backed up anywhere.
  ///
  /// In en, this message translates to:
  /// **'Captured on another device'**
  String get mediaCapturedOnAnotherDevice;

  /// Shown on a photo tile that is backed up to a Google Drive account this device is not connected to.
  ///
  /// In en, this message translates to:
  /// **'In another Drive account'**
  String get mediaOnAnotherBackupAccount;

  /// Title of the screen that answers where your photos live.
  ///
  /// In en, this message translates to:
  /// **'Storage & Sync'**
  String get storageTitle;

  /// Section label over the Google Drive card. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'BACKUP & SYNC'**
  String get storageSectionBackup;

  /// Section label over the auto-upload switch.
  ///
  /// In en, this message translates to:
  /// **'INSTANT SYNC'**
  String get storageSectionInstant;

  /// Section label over the save-to-system-Photos switch.
  ///
  /// In en, this message translates to:
  /// **'DEVICE PHOTOS'**
  String get storageSectionDevicePhotos;

  /// Switch: upload each capture to Drive as it is taken.
  ///
  /// In en, this message translates to:
  /// **'Upload to Drive'**
  String get storageUploadToDrive;

  /// Switch: also copy each capture into the phone's own photo library.
  ///
  /// In en, this message translates to:
  /// **'Save to Photos'**
  String get storageSaveToPhotos;

  /// Footnote explaining per-account isolation inside one Google Drive.
  ///
  /// In en, this message translates to:
  /// **'Each ZIVO account keeps its own photos in its own Drive folder, so accounts never mix — even if they use the same Google Drive.'**
  String get storageAccountNote;

  /// Title of the card describing local storage, which is always on.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get storageOnThisDevice;

  /// Local storage card subtitle when there are no photos yet.
  ///
  /// In en, this message translates to:
  /// **'Your photos are saved here first, always.'**
  String get storageLocalFirst;

  /// Local storage card subtitle: how many photos are on this device.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo saved here.} other{{count} photos saved here.}}'**
  String storageSavedHere(int count);

  /// Primary button that starts the interactive Drive sign-in.
  ///
  /// In en, this message translates to:
  /// **'Connect Google Drive'**
  String get storageConnectDrive;

  /// Button that uploads every not-yet-backed-up photo.
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get storageBackUpNow;

  /// Button that downloads photos backed up from another device.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get storageSync;

  /// Button that clears this device's Drive connection.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get storageDisconnect;

  /// Drive card subtitle when the build ships without a backup provider.
  ///
  /// In en, this message translates to:
  /// **'Unavailable in this build'**
  String get storageUnavailableInBuild;

  /// Drive card subtitle when connected but the account email is unknown.
  ///
  /// In en, this message translates to:
  /// **'Connected on this device'**
  String get storageConnectedOnDevice;

  /// Drive card subtitle when this device has no connection.
  ///
  /// In en, this message translates to:
  /// **'Not connected on this device'**
  String get storageNotConnectedOnDevice;

  /// Toast when the interactive connect was cancelled or failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t connect Google Drive.'**
  String get storageConnectFailed;

  /// Toast after a successful connect.
  ///
  /// In en, this message translates to:
  /// **'Google Drive connected on this device.'**
  String get storageConnectedToast;

  /// Toast after disconnecting.
  ///
  /// In en, this message translates to:
  /// **'Google Drive disconnected on this device.'**
  String get storageDisconnectedToast;

  /// Toast when Back up now found nothing to upload.
  ///
  /// In en, this message translates to:
  /// **'Everything is already backed up.'**
  String get storageAlreadyBackedUp;

  /// Toast when Sync found nothing to fetch.
  ///
  /// In en, this message translates to:
  /// **'Nothing new to download.'**
  String get storageNothingNew;

  /// Toast reporting how many photos were uploaded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Backed up 1 photo to Drive.} other{Backed up {count} photos to Drive.}}'**
  String storageBackedUpToast(int count);

  /// Toast reporting how many photos were downloaded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Downloaded 1 photo from Drive.} other{Downloaded {count} photos from Drive.}}'**
  String storageDownloadedToast(int count);

  /// Notice title: photos whose only cloud copy is in a Drive account this device is not signed into.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo in another Google account} other{{count} photos in another Google account}}'**
  String storageOtherAccountTitle(int count);

  /// Notice body explaining the two ways out of an account switch.
  ///
  /// In en, this message translates to:
  /// **'Backed up before you switched accounts. Back up now copies the ones still on this device; for the rest, reconnect that account.'**
  String get storageOtherAccountBody;

  /// Live banner title while an upload run is in flight.
  ///
  /// In en, this message translates to:
  /// **'Backing up…'**
  String get storageBackingUp;

  /// Live banner title while a download run is in flight.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get storageSyncing;

  /// Live banner subtitle before the run knows how many photos it will move.
  ///
  /// In en, this message translates to:
  /// **'Checking your photos…'**
  String get storageCheckingPhotos;

  /// Live banner subtitle: how far through the run we are.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} {total, plural, =1{photo} other{photos}}'**
  String storageProgressCount(int done, int total);

  /// Status banner title when the library is empty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to back up yet'**
  String get storageNothingYetTitle;

  /// Status banner subtitle when the library is empty.
  ///
  /// In en, this message translates to:
  /// **'Photos you add will back up here.'**
  String get storageNothingYetBody;

  /// Status banner title when every photo is safe in Drive.
  ///
  /// In en, this message translates to:
  /// **'All backed up'**
  String get storageAllBackedUpTitle;

  /// Status banner subtitle when everything is backed up.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo is safe in Google Drive.} other{{count} photos are safe in Google Drive.}}'**
  String storageAllSafeBody(int count);

  /// Status banner title when some photos still need uploading.
  ///
  /// In en, this message translates to:
  /// **'{backedUp} of {total} backed up'**
  String storagePartialTitle(int backedUp, int total);

  /// Status banner subtitle counting the photos still to upload.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo is waiting to back up.} other{{count} photos are waiting to back up.}}'**
  String storagePendingBody(int count);

  /// Session details: the session finished with nothing recorded in it.
  ///
  /// In en, this message translates to:
  /// **'No exercises logged.'**
  String get sessionNoExercises;

  /// Title of the page showing one logged workout session.
  ///
  /// In en, this message translates to:
  /// **'Session details'**
  String get sessionDetailsTitle;

  /// Session status: the workout was finished.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get sessionStatusCompleted;

  /// Session status: the workout is still running.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get sessionStatusActive;

  /// Session status: the workout was left unfinished.
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get sessionStatusAbandoned;

  /// Session details hero stat: how long the workout took.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get sessionStatDuration;

  /// Session details hero stat: the clock range the workout ran over.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get sessionStatTime;

  /// Session details hero stat: how many exercises the session held.
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get sessionStatExercises;

  /// Session details hero stat: completed sets out of the planned total.
  ///
  /// In en, this message translates to:
  /// **'Sets done'**
  String get sessionStatSetsDone;

  /// Label on one row of a logged exercise, numbering the set.
  ///
  /// In en, this message translates to:
  /// **'Set {index}'**
  String sessionSetNumber(int index);

  /// Marker on a set the user skipped rather than performed.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get sessionSetSkipped;

  /// Rate of Perceived Exertion badge on a logged set. RPE is a training term and stays latin in Arabic.
  ///
  /// In en, this message translates to:
  /// **'RPE {value}'**
  String sessionSetRpe(String value);

  /// A logged set stated as weight by repetitions, e.g. "60kg × 8". Both sides are already formatted.
  ///
  /// In en, this message translates to:
  /// **'{weight} × {reps}'**
  String sessionSetWeightByReps(String weight, String reps);

  /// A logged bodyweight set, stated by repetitions alone.
  ///
  /// In en, this message translates to:
  /// **'{reps, plural, =1{1 rep} other{{reps} reps}}'**
  String sessionSetRepsOnly(int reps);

  /// A logged set whose rep figure is a symbol rather than a number (AMRAP, or an em dash when nothing was recorded).
  ///
  /// In en, this message translates to:
  /// **'{reps} reps'**
  String sessionSetRepsUnknown(String reps);

  /// The clock range a session ran over, e.g. "18:04–19:12".
  ///
  /// In en, this message translates to:
  /// **'{start}–{end}'**
  String sessionTimeRange(String start, String end);

  /// Title of the page listing every training split.
  ///
  /// In en, this message translates to:
  /// **'Splits'**
  String get splitsTitle;

  /// Accessibility label on the button that creates a split.
  ///
  /// In en, this message translates to:
  /// **'New split'**
  String get splitNewAction;

  /// The name given to a duplicated split. Becomes the stored plan name, so it is written in the language the user duplicated it in.
  ///
  /// In en, this message translates to:
  /// **'{name} copy'**
  String splitCopyName(String name);

  /// How many days a split rotates through.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String splitDayCount(int count);

  /// A split row's meta line: its day count and its total exercise count.
  ///
  /// In en, this message translates to:
  /// **'{days} · {exercises}'**
  String splitMeta(String days, String exercises);

  /// Action that makes this split the one in play.
  ///
  /// In en, this message translates to:
  /// **'Set as active'**
  String get splitSetActive;

  /// Action that copies an item.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get actionDuplicate;

  /// Badge on the split currently in play.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get splitActiveBadge;

  /// Empty state on the splits page.
  ///
  /// In en, this message translates to:
  /// **'No splits yet.'**
  String get splitsEmptyTitle;

  /// Empty state subtitle pointing at the create button.
  ///
  /// In en, this message translates to:
  /// **'Tap + to build your first one.'**
  String get splitsEmptyBody;

  /// Trailing caption on the Training section: sessions done this week. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'{count} THIS WEEK'**
  String workoutThisWeekCount(int count);

  /// Title of the card that records a weigh-in.
  ///
  /// In en, this message translates to:
  /// **'Log today\'s weight'**
  String get workoutLogTodaysWeight;

  /// Snack bar when a weigh-in could not be written.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that weigh-in — check your connection and try again.'**
  String get workoutWeighInFailed;

  /// Empty state under "no plan yet", offering the two ways to get one. ZIVO speaking in the first person.
  ///
  /// In en, this message translates to:
  /// **'Import a PDF or photo and I\'ll turn it into a real split, or build one from scratch.'**
  String get workoutNoPlanImportHint;

  /// Trailing caption on the Bodyweight section: the signed change over the last 30 days. A delta always states its own window.
  ///
  /// In en, this message translates to:
  /// **'{delta} KG · 30D'**
  String workoutWeightDeltaWindow(String delta);

  /// Title of the settings page.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings section holding app-wide preferences.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsSectionApp;

  /// Settings section holding account actions.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// Settings section for the Spotify connection.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get settingsSectionMusic;

  /// Settings section for photo storage and backup.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get settingsSectionMedia;

  /// Settings row: the app theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// Theme picker option: the app's near-black skin.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Theme picker option: the app's paper skin.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme picker option: follow the device's light/dark setting.
  ///
  /// In en, this message translates to:
  /// **'Match my phone'**
  String get settingsThemeSystem;

  /// Settings row: the app version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// Settings row: which build configuration is running.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get settingsBuild;

  /// Settings row opening the privacy policy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get settingsPrivacyPolicy;

  /// Settings row opening the change-password flow.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsChangePassword;

  /// Settings row opening the delete-account flow.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// Button that ends the session on this device.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// Footer line stating the running version and build number.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String settingsVersionLine(String version, String build);

  /// The version row’s value: version and build number.
  ///
  /// In en, this message translates to:
  /// **'{version} ({build})'**
  String settingsVersionValue(String version, String build);

  /// Settings row opening the Storage & Sync screen.
  ///
  /// In en, this message translates to:
  /// **'Storage & sync'**
  String get settingsStorageSync;

  /// Value beside the Storage & sync row, naming what it covers.
  ///
  /// In en, this message translates to:
  /// **'Photos · Drive'**
  String get settingsStorageSyncValue;

  /// Settings: Spotify is connected and playback is paused. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'CONNECTED · PAUSED'**
  String get connectedConnectedPaused;

  /// Settings: Spotify is connected and playing.
  ///
  /// In en, this message translates to:
  /// **'CONNECTED · PLAYING'**
  String get connectedConnectedPlaying;

  /// Label on the email field.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// Label on the password field.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// Label on the optional display-name field at sign-up.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get authNameOptional;

  /// Label on the field that repeats a new password.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get authConfirmPassword;

  /// Label on the new-password field.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get authNewPassword;

  /// Label on the field confirming the existing password.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get authCurrentPassword;

  /// Label on the field repeating the new password.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get authConfirmNewPassword;

  /// Button that signs an existing user in.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// Button that registers a new user.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// Link to the password reset flow.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// Prompt beside the link that switches to sign-in. Trailing spaces separate it from the link.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?  '**
  String get authHaveAccount;

  /// Prompt beside the link that switches to sign-up.
  ///
  /// In en, this message translates to:
  /// **'New to ZIVO?  '**
  String get authNewToZivo;

  /// Hero line above the sign-up form.
  ///
  /// In en, this message translates to:
  /// **'Make your space.'**
  String get authTitleSignUp;

  /// Hero line above the sign-in form, and the splash tagline.
  ///
  /// In en, this message translates to:
  /// **'Your whole day, in one place.'**
  String get authTitleSignIn;

  /// Apple sign-in button. Apple requires this exact wording per locale.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple'**
  String get authSignInWithApple;

  /// Google sign-in button.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueWithGoogle;

  /// Toast after the password was changed from within the app.
  ///
  /// In en, this message translates to:
  /// **'Password updated.'**
  String get authPasswordUpdated;

  /// Message on the sign-in screen after a password reset completes.
  ///
  /// In en, this message translates to:
  /// **'Password updated. Sign in with your new password.'**
  String get authPasswordUpdatedSignIn;

  /// Message on the sign-in screen after this device was signed out because the account became active on another device (single-device session enforcement).
  ///
  /// In en, this message translates to:
  /// **'Your account was signed in on another device.'**
  String get authSignedOutOtherDevice;

  /// Accessibility label on the reveal toggle of an obscured field.
  ///
  /// In en, this message translates to:
  /// **'Show {label}'**
  String authShowField(String label);

  /// Accessibility label on the hide toggle of a revealed field.
  ///
  /// In en, this message translates to:
  /// **'Hide {label}'**
  String authHideField(String label);

  /// Accessibility label on the one-time-code input.
  ///
  /// In en, this message translates to:
  /// **'{length}-digit verification code'**
  String authOtpFieldLabel(int length);

  /// Wrong verification code, naming how many tries remain.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{That code isn’t right. 1 try left.} other{That code isn’t right. {count} tries left.}}'**
  String authCodeWrongWithAttempts(int count);

  /// Wrong verification code, with no attempt count to show.
  ///
  /// In en, this message translates to:
  /// **'That code isn’t right.'**
  String get authCodeWrong;

  /// The verification code timed out.
  ///
  /// In en, this message translates to:
  /// **'That code has expired. Send a new one.'**
  String get authCodeExpired;

  /// The user exhausted their code attempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Send a new code.'**
  String get authCodeTooManyAttempts;

  /// Confirmation that a fresh verification code was sent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way.'**
  String get authCodeSent;

  /// The resend request is in flight.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get authSending;

  /// Cooldown before another code may be requested.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {seconds}s'**
  String authResendIn(int seconds);

  /// Link that requests a fresh code.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get authResendCode;

  /// Prompt beside the resend link. Trailing spaces separate it from the link.
  ///
  /// In en, this message translates to:
  /// **'Didn’t get it?  '**
  String get authDidntGetIt;

  /// Title of the password reset screen.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get authResetTitle;

  /// Subtitle of the password reset screen.
  ///
  /// In en, this message translates to:
  /// **'Enter your account email and we’ll send you a 6-digit code.'**
  String get authResetSubtitle;

  /// Button that emails a reset code.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get authSendCode;

  /// Title of the step where the emailed code is typed in.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get authEnterCode;

  /// Lead-in before the masked email address. Ends with a newline so the address sits on its own line.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code we sent to\n'**
  String get authCodeSentTo;

  /// Tail after the masked email address on the reset screen.
  ///
  /// In en, this message translates to:
  /// **', then choose a new password.'**
  String get authThenChoosePassword;

  /// Button that commits the new password.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get authResetPassword;

  /// Validation message for a malformed email address.
  ///
  /// In en, this message translates to:
  /// **'That email address doesn\'t look right.'**
  String get authEmailLooksWrong;

  /// Title of the email verification screen.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get authVerifyTitle;

  /// Button that submits the verification code.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get authVerify;

  /// Link that signs out of the unverified account so another can be used.
  ///
  /// In en, this message translates to:
  /// **'Use another account'**
  String get authUseAnotherAccount;

  /// Subtitle of the change-password screen.
  ///
  /// In en, this message translates to:
  /// **'Confirm it’s you, then choose a new one.'**
  String get authChangePasswordSubtitle;

  /// Section title over the current-password field.
  ///
  /// In en, this message translates to:
  /// **'Confirm it’s you'**
  String get authConfirmItsYou;

  /// Button that commits the password change.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get authUpdatePassword;

  /// Body of the delete-account confirmation sheet.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account and everything in it — workouts, diet, moments, expenses, and profile. This cannot be undone.'**
  String get authDeleteAccountBody;

  /// Label on the reauthentication field before deletion.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to confirm'**
  String get authDeleteConfirmPassword;

  /// The button that actually deletes the account.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get authDeleteMyAccount;

  /// Label over the password strength meter.
  ///
  /// In en, this message translates to:
  /// **'Password strength'**
  String get authPasswordStrength;

  /// Password strength: every rule met.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get authPasswordStrong;

  /// Password strength: most rules met.
  ///
  /// In en, this message translates to:
  /// **'Almost'**
  String get authPasswordAlmost;

  /// Password strength: few rules met.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get authPasswordWeak;

  /// The confirmation field matches the password.
  ///
  /// In en, this message translates to:
  /// **'Passwords match'**
  String get authPasswordsMatch;

  /// The confirmation field does not match the password.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match'**
  String get authPasswordsDontMatch;

  /// Accessibility label pairing a password rule with whether it is satisfied.
  ///
  /// In en, this message translates to:
  /// **'{rule}: {state}'**
  String authRuleState(String rule, String state);

  /// A password rule the current password satisfies.
  ///
  /// In en, this message translates to:
  /// **'met'**
  String get authRuleMet;

  /// A password rule the current password fails.
  ///
  /// In en, this message translates to:
  /// **'not met'**
  String get authRuleNotMet;

  /// Password rule: minimum length.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get authRuleMinLength;

  /// Chip-sized form of the minimum-length rule.
  ///
  /// In en, this message translates to:
  /// **'8+ characters'**
  String get authRuleMinLengthShort;

  /// Password rule: at least one capital letter.
  ///
  /// In en, this message translates to:
  /// **'One uppercase letter'**
  String get authRuleUppercase;

  /// Chip-sized form of the uppercase rule.
  ///
  /// In en, this message translates to:
  /// **'Uppercase'**
  String get authRuleUppercaseShort;

  /// Password rule: at least one lowercase letter.
  ///
  /// In en, this message translates to:
  /// **'One lowercase letter'**
  String get authRuleLowercase;

  /// Chip-sized form of the lowercase rule.
  ///
  /// In en, this message translates to:
  /// **'Lowercase'**
  String get authRuleLowercaseShort;

  /// Password rule: at least one digit.
  ///
  /// In en, this message translates to:
  /// **'One number'**
  String get authRuleNumber;

  /// Chip-sized form of the number rule.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get authRuleNumberShort;

  /// Value beside Delete account, stating its consequence before the tap. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'PERMANENT'**
  String get settingsPermanent;

  /// Action sheet: use the camera.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get momentTakePhoto;

  /// Action sheet: pick an existing photo.
  ///
  /// In en, this message translates to:
  /// **'Choose from Library'**
  String get momentChooseFromLibrary;

  /// Title of the built-in crop/rotate editor.
  ///
  /// In en, this message translates to:
  /// **'Edit Photo'**
  String get momentEditPhoto;

  /// Header when an existing moment is open for editing.
  ///
  /// In en, this message translates to:
  /// **'Edit moment'**
  String get momentEditTitle;

  /// Header when a moment is being created.
  ///
  /// In en, this message translates to:
  /// **'New moment'**
  String get momentNewTitle;

  /// Accessibility label on the delete action.
  ///
  /// In en, this message translates to:
  /// **'Delete moment'**
  String get momentDeleteAction;

  /// Placeholder in the moment’s note field.
  ///
  /// In en, this message translates to:
  /// **'Say something…'**
  String get momentNoteHint;

  /// Commits an edit to an existing moment.
  ///
  /// In en, this message translates to:
  /// **'Save moment'**
  String get momentSave;

  /// Commits a newly created moment.
  ///
  /// In en, this message translates to:
  /// **'Add moment'**
  String get momentAdd;

  /// Empty photo slot on the capture screen.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get momentAddPhoto;

  /// Replaces the attached photo.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get momentRetake;

  /// Detaches the photo from the moment.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get momentRemove;

  /// Error when a moment could not be written.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that moment.'**
  String get momentSaveFailed;

  /// Error when a moment could not be removed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete that moment.'**
  String get momentDeleteFailed;

  /// Title of the moments timeline.
  ///
  /// In en, this message translates to:
  /// **'Moments'**
  String get momentsTitle;

  /// Timeline filter: everything.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get momentsFilterAll;

  /// Timeline filter: moments with a photo.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get momentsFilterPhotos;

  /// Timeline filter: moments that are text only.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get momentsFilterNotes;

  /// Timeline filter: photos taken in the app.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get momentsFilterCamera;

  /// Timeline filter: photos picked from the phone.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get momentsFilterLibrary;

  /// Timeline empty state title.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged yet'**
  String get momentsEmptyTitle;

  /// Timeline empty state body explaining what a moment is for.
  ///
  /// In en, this message translates to:
  /// **'Snap a lift, a meal, or a scale reading — moments attach to the session you were in.'**
  String get momentsEmptyBody;

  /// Empty state for the Camera filter.
  ///
  /// In en, this message translates to:
  /// **'No camera photos yet.'**
  String get momentsEmptyCamera;

  /// Empty state for the Library filter.
  ///
  /// In en, this message translates to:
  /// **'Nothing from your library yet.'**
  String get momentsEmptyLibrary;

  /// Empty state for the Photos filter.
  ///
  /// In en, this message translates to:
  /// **'No photos yet.'**
  String get momentsEmptyPhotos;

  /// Empty state for the Notes filter.
  ///
  /// In en, this message translates to:
  /// **'No notes yet.'**
  String get momentsEmptyNotes;

  /// Empty state for the remaining filter.
  ///
  /// In en, this message translates to:
  /// **'Nothing else logged yet'**
  String get momentsEmptyOther;

  /// Stand-in for a moment with no note, in the timeline.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get momentUntitled;

  /// Stand-in for a moment with no note, in the photo viewer.
  ///
  /// In en, this message translates to:
  /// **'Untitled moment'**
  String get momentUntitledFull;

  /// Opens the photo metadata sheet.
  ///
  /// In en, this message translates to:
  /// **'Photo info'**
  String get momentPhotoInfo;

  /// Which photo of the set is on screen in the viewer.
  ///
  /// In en, this message translates to:
  /// **'{index} of {total}'**
  String momentPhotoPosition(int index, int total);

  /// Photo metadata row: the capture date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get metaDate;

  /// Photo metadata row: the capture time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get metaTime;

  /// Photo metadata row: the capture time zone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get metaTimeZone;

  /// Photo metadata row: the camera or device used.
  ///
  /// In en, this message translates to:
  /// **'Captured with'**
  String get metaCapturedWith;

  /// Photo metadata row: pixel width and height.
  ///
  /// In en, this message translates to:
  /// **'Dimensions'**
  String get metaDimensions;

  /// Photo metadata row: how large the file is.
  ///
  /// In en, this message translates to:
  /// **'File size'**
  String get metaFileSize;

  /// Photo metadata row: the file format.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get metaType;

  /// Photo metadata row: where it was taken.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get metaLocation;

  /// Photo metadata row: where the cloud copy lives.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get metaBackup;

  /// Backup state: local only.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get metaOnThisDevice;

  /// Backup state: also copied to the system photo library.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get metaInPhotos;

  /// Backup state: no cloud copy exists.
  ///
  /// In en, this message translates to:
  /// **'Not backed up yet'**
  String get metaNotBackedUp;

  /// Backup state: the only copy is remote and can be fetched.
  ///
  /// In en, this message translates to:
  /// **'In Google Drive — tap to download'**
  String get metaInDriveTapToDownload;

  /// How a photo was captured: with the in-app camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get captureSourceCamera;

  /// How a photo was captured: picked from the phone’s library.
  ///
  /// In en, this message translates to:
  /// **'Photo Library'**
  String get captureSourceLibrary;

  /// How a photo was captured: not recorded.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get captureSourceUnknown;

  /// Eyebrow over the full-screen player. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'NOW PLAYING'**
  String get musicNowPlaying;

  /// Accessibility label on the player’s dismiss control.
  ///
  /// In en, this message translates to:
  /// **'Close player'**
  String get musicClosePlayer;

  /// Notice when playback is on a remote Spotify device this app can only observe.
  ///
  /// In en, this message translates to:
  /// **'Playing on another device — controls are read-only here.'**
  String get musicReadOnly;

  /// Accessibility label on the previous-track control.
  ///
  /// In en, this message translates to:
  /// **'Previous track'**
  String get musicPreviousTrack;

  /// Accessibility label on the next-track control.
  ///
  /// In en, this message translates to:
  /// **'Next track'**
  String get musicNextTrack;

  /// Accessibility state: shuffle is enabled.
  ///
  /// In en, this message translates to:
  /// **'Shuffle on'**
  String get musicShuffleOn;

  /// Accessibility state: shuffle is disabled.
  ///
  /// In en, this message translates to:
  /// **'Shuffle off'**
  String get musicShuffleOff;

  /// Accessibility state: repeat is disabled.
  ///
  /// In en, this message translates to:
  /// **'Repeat off'**
  String get musicRepeatOff;

  /// Accessibility state: repeat the whole context.
  ///
  /// In en, this message translates to:
  /// **'Repeat all'**
  String get musicRepeatAll;

  /// Accessibility state: repeat the current track.
  ///
  /// In en, this message translates to:
  /// **'Repeat one'**
  String get musicRepeatOne;

  /// Error when Spotify refused the authorization handshake.
  ///
  /// In en, this message translates to:
  /// **'Spotify didn\'t authorize the connection. Make sure you\'re signed in to Spotify, then try again.'**
  String get musicAuthFailed;

  /// Retries a failed Spotify connection.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get musicTryAgain;

  /// Error when the account cannot control playback remotely.
  ///
  /// In en, this message translates to:
  /// **'Spotify Premium is required to control playback here.'**
  String get musicPremiumRequired;

  /// Prompt on the player before Spotify has ever been connected.
  ///
  /// In en, this message translates to:
  /// **'Connect Spotify to see what\'s playing.'**
  String get musicConnectPrompt;

  /// Starts the Spotify connection flow.
  ///
  /// In en, this message translates to:
  /// **'Connect Spotify'**
  String get musicConnectSpotify;

  /// How much of the track remains, beside the artist on the compact strip. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'{time} LEFT'**
  String musicTimeLeft(String time);

  /// Compact strip subtitle: the artist and how much time is left.
  ///
  /// In en, this message translates to:
  /// **'{artist} · {remaining}'**
  String musicStripMeta(String artist, String remaining);

  /// Accessibility summary of the now-playing strip.
  ///
  /// In en, this message translates to:
  /// **'Now playing: {title} by {artist}. Open the player.'**
  String musicNowPlayingSemantics(String title, String artist);

  /// Battery level of the Spotify playback device.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String musicBatteryPercent(int percent);

  /// Error when the chosen file could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that file.'**
  String get importCouldntReadFile;

  /// Error when the chosen file exceeds the upload limit.
  ///
  /// In en, this message translates to:
  /// **'That file is too large — please choose one under 7 MB.'**
  String get importFileTooLarge;

  /// Error when the imported split could not be written.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that split — check your connection and try again.'**
  String get importSaveFailed;

  /// Header while the extracted plan is being checked.
  ///
  /// In en, this message translates to:
  /// **'Review import'**
  String get importReviewTitle;

  /// Header of the import screen.
  ///
  /// In en, this message translates to:
  /// **'Import Plan'**
  String get importPlanTitle;

  /// Title of the file-picking step.
  ///
  /// In en, this message translates to:
  /// **'Select your training plan'**
  String get importSelectTitle;

  /// Body of the file-picking step. ZIVO speaking in the first person.
  ///
  /// In en, this message translates to:
  /// **'Choose a PDF or a photo of your plan and I\'ll map it into a real, editable split.'**
  String get importSelectBody;

  /// Retries the import with another file.
  ///
  /// In en, this message translates to:
  /// **'Choose a different file'**
  String get importChooseDifferentFile;

  /// Abandons the current import.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get importStartOver;

  /// Shown when extraction found nothing plan-shaped in the file.
  ///
  /// In en, this message translates to:
  /// **'This doesn\'t look like a workout plan'**
  String get importNotAPlan;

  /// Returns to the previous step of the import.
  ///
  /// In en, this message translates to:
  /// **'Go back and edit'**
  String get importGoBackAndEdit;

  /// Eyebrow over the extracted plan preview. ZIVO speaking. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'HERE\'S WHAT I FOUND'**
  String get importHeresWhatIFound;

  /// The import is in flight.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get importDoingIt;

  /// Commits the extracted plan.
  ///
  /// In en, this message translates to:
  /// **'Import this split'**
  String get importThisSplit;

  /// Opens the plan editor on the extracted plan.
  ///
  /// In en, this message translates to:
  /// **'Edit before importing'**
  String get importEditBefore;

  /// Heading over one day in the import preview.
  ///
  /// In en, this message translates to:
  /// **'Day {slot} · {label}'**
  String importDayHeading(String slot, String label);

  /// A day in the extracted plan that came back empty.
  ///
  /// In en, this message translates to:
  /// **'No exercises found for this day.'**
  String get importNoExercisesForDay;

  /// Title of the success step.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get importComplete;

  /// Success summary naming the plan and what it contains.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" added to your splits — {days}, {exercises}.'**
  String importSummary(String name, String days, String exercises);

  /// Preview caption: how many days and exercises the extracted plan holds.
  ///
  /// In en, this message translates to:
  /// **'{days} · {exercises} total'**
  String importPlanShape(String days, String exercises);

  /// Tail of the sentence offering the manual route instead of importing.
  ///
  /// In en, this message translates to:
  /// **'build the split manually.'**
  String get importBuildManually;

  /// Header when editing an existing exercise.
  ///
  /// In en, this message translates to:
  /// **'Edit exercise'**
  String get exerciseEditTitle;

  /// Header when adding an exercise, and the button that does it.
  ///
  /// In en, this message translates to:
  /// **'Add exercise'**
  String get exerciseAddTitle;

  /// Label on the exercise name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get exerciseName;

  /// Example exercise name shown as a hint.
  ///
  /// In en, this message translates to:
  /// **'Bench Press'**
  String get exerciseNameHint;

  /// Label on the muscle group field.
  ///
  /// In en, this message translates to:
  /// **'Muscle group (optional)'**
  String get exerciseMuscleGroup;

  /// Example muscle group shown as a hint.
  ///
  /// In en, this message translates to:
  /// **'Chest'**
  String get exerciseMuscleGroupHint;

  /// Label on the set-count field.
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get exerciseSets;

  /// Section label over the rep target options. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'REP TARGET'**
  String get exerciseRepTarget;

  /// Rep target mode: a single number.
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get exerciseTargetFixed;

  /// Rep target mode: a min and a max.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get exerciseTargetRange;

  /// Label on the lower bound of a rep range.
  ///
  /// In en, this message translates to:
  /// **'Min reps'**
  String get exerciseMinReps;

  /// Label on the upper bound of a rep range.
  ///
  /// In en, this message translates to:
  /// **'Max reps'**
  String get exerciseMaxReps;

  /// Label on the rep-count field.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get exerciseReps;

  /// Label on the target weight field.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get exerciseWeightKg;

  /// Commits an edit to an existing exercise.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get exerciseSaveChanges;

  /// Error when a logged workout could not be written.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that workout.'**
  String get workoutCaptureSaveFailed;

  /// Error when a logged workout could not be removed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete that workout.'**
  String get workoutCaptureDeleteFailed;

  /// Header when editing a logged workout.
  ///
  /// In en, this message translates to:
  /// **'Edit workout'**
  String get workoutCaptureEditTitle;

  /// Header when logging a new workout.
  ///
  /// In en, this message translates to:
  /// **'New workout'**
  String get workoutCaptureNewTitle;

  /// Accessibility label on the delete action.
  ///
  /// In en, this message translates to:
  /// **'Delete workout'**
  String get workoutCaptureDelete;

  /// Placeholder for the session name.
  ///
  /// In en, this message translates to:
  /// **'Name this session'**
  String get workoutCaptureNameHint;

  /// Commits the logged workout.
  ///
  /// In en, this message translates to:
  /// **'Save workout'**
  String get workoutCaptureSave;

  /// Empty state in the workout capture list.
  ///
  /// In en, this message translates to:
  /// **'No exercises yet.'**
  String get workoutCaptureNoExercises;

  /// Label on the exercise name field in capture.
  ///
  /// In en, this message translates to:
  /// **'Exercise name'**
  String get workoutCaptureExerciseName;

  /// Removes an exercise row from the logged workout.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get workoutCaptureRemove;

  /// Debug-build App Check failure, naming the exact fix for a developer.
  ///
  /// In en, this message translates to:
  /// **'The app couldn\'t verify itself (App Check). Register this build\'s debug token in the Firebase console, then try again.'**
  String get importAppCheckDebug;

  /// Release-build App Check failure, without the developer detail.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify this app install. Please try again in a moment.'**
  String get importAppCheckFailed;

  /// The backend import callable is missing or undeployed. Nothing is wrong with the file.
  ///
  /// In en, this message translates to:
  /// **'The import service isn\'t available right now — please try again later.'**
  String get importServiceUnavailable;

  /// A timeout or transport failure reaching the import backend.
  ///
  /// In en, this message translates to:
  /// **'Network problem reaching the import service — check your connection and try again.'**
  String get importNetworkProblem;

  /// Generic extraction failure. {manualFallback} is the "…or build it manually" tail, which differs per importer.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that plan — try a clearer photo or PDF, or {manualFallback}'**
  String importCouldntRead(String manualFallback);

  /// The picked file is not a PDF or an image. Developer-facing detail carried in a thrown error.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file type: {extension}'**
  String importUnsupportedFileType(String extension);

  /// Shown when microphone permission is refused during a voice description.
  ///
  /// In en, this message translates to:
  /// **'ZIVO needs microphone access to take this down. You can type it instead.'**
  String get describeMicNeeded;

  /// The recorder failed to start.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start recording. You can type it instead.'**
  String get describeRecordFailed;

  /// The recording came back empty.
  ///
  /// In en, this message translates to:
  /// **'Nothing was recorded. Try again, or type it instead.'**
  String get describeNothingRecorded;

  /// Section label over the transcribed text.
  ///
  /// In en, this message translates to:
  /// **'Your description'**
  String get describeYourDescription;

  /// Warning that a transcription error propagates into the generated plan.
  ///
  /// In en, this message translates to:
  /// **'Check the words before you continue — a mis-heard detail becomes a number downstream.'**
  String get describeCheckWords;

  /// Switches from typing to voice.
  ///
  /// In en, this message translates to:
  /// **'Say it instead'**
  String get describeSayItInstead;

  /// Appends another voice segment.
  ///
  /// In en, this message translates to:
  /// **'Add more by voice'**
  String get describeAddMoreByVoice;

  /// Transcription is in flight.
  ///
  /// In en, this message translates to:
  /// **'Writing it down…'**
  String get describeWritingItDown;

  /// The recorder is capturing audio.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get describeListening;

  /// Throws away the current recording.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get describeDiscard;

  /// Status line while the file is being parsed.
  ///
  /// In en, this message translates to:
  /// **'Reading the document…'**
  String get importReadingDocument;

  /// Status line naming the plan the extractor recognised.
  ///
  /// In en, this message translates to:
  /// **'Found \"{name}\"…'**
  String importFoundNamed(String name);

  /// Title of the analysing step.
  ///
  /// In en, this message translates to:
  /// **'Analyzing your plan'**
  String get importAnalyzing;

  /// Abandons the import and opens the empty editor.
  ///
  /// In en, this message translates to:
  /// **'Build manually instead'**
  String get importBuildManuallyInstead;

  /// Status line pairing the section being read with how many items are in it.
  ///
  /// In en, this message translates to:
  /// **'{section} · {items}'**
  String importSectionItems(String section, String items);

  /// How many days the extractor has read so far.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String importItemCountDay(int count);

  /// How many meals the extractor has read so far.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 meal} other{{count} meals}}'**
  String importItemCountMeal(int count);

  /// Title when describing a split by voice.
  ///
  /// In en, this message translates to:
  /// **'Describe your training'**
  String get workoutDescribeTitleVoice;

  /// Title when typing a split out.
  ///
  /// In en, this message translates to:
  /// **'Type it out'**
  String get workoutDescribeTitleType;

  /// Explains what to say or write when describing a split.
  ///
  /// In en, this message translates to:
  /// **'Say or write your split — the days, the exercises, and the sets and reps for each. ZIVO turns it into a real, editable split you review before anything is saved.'**
  String get workoutDescribeBody;

  /// A worked example of the level of detail to give.
  ///
  /// In en, this message translates to:
  /// **'Example: \"Day A is push — bench press 4 sets of 8, incline dumbbell press 3 by 10, then cable flyes 3 by 15. Day B is pull…\"'**
  String get workoutDescribeExample;

  /// Placeholder in the split description field.
  ///
  /// In en, this message translates to:
  /// **'Day A is push…'**
  String get workoutDescribeHint;

  /// Sends the description off to be turned into a plan.
  ///
  /// In en, this message translates to:
  /// **'Turn this into a split'**
  String get workoutDescribeSubmit;

  /// Stops the voice recording.
  ///
  /// In en, this message translates to:
  /// **'Done talking'**
  String get workoutDescribeDoneTalking;

  /// Title of the sheet offering the four ways to add a plan.
  ///
  /// In en, this message translates to:
  /// **'Add a training plan'**
  String get addPlanTitle;

  /// Reassurance that every route ends in the same review step.
  ///
  /// In en, this message translates to:
  /// **'However your split arrives, it lands in the same editor to review before anything is saved.'**
  String get addPlanBody;

  /// Route: import a document.
  ///
  /// In en, this message translates to:
  /// **'PDF or photo'**
  String get addPlanPdfTitle;

  /// Examples of documents that can be imported.
  ///
  /// In en, this message translates to:
  /// **'A coach\'s plan, a screenshot, a photo of a page'**
  String get addPlanPdfBody;

  /// Route: describe the plan by voice.
  ///
  /// In en, this message translates to:
  /// **'Say it out loud'**
  String get addPlanVoiceTitle;

  /// What the voice route does.
  ///
  /// In en, this message translates to:
  /// **'Describe your split and ZIVO writes it down'**
  String get addPlanVoiceBody;

  /// Route: type the plan in prose.
  ///
  /// In en, this message translates to:
  /// **'Type it out'**
  String get addPlanTypeTitle;

  /// What the typing route does.
  ///
  /// In en, this message translates to:
  /// **'Write your split in a few lines'**
  String get addPlanTypeBody;

  /// Route: use the editor directly.
  ///
  /// In en, this message translates to:
  /// **'Build by hand'**
  String get addPlanManualTitle;

  /// What the manual route does.
  ///
  /// In en, this message translates to:
  /// **'Add days and exercises yourself'**
  String get addPlanManualBody;

  /// How many exercises the extractor has read so far.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 exercise} other{{count} exercises}}'**
  String importItemCountExercise(int count);

  /// How many items the extractor has read so far, when the kind is not known.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String importItemCountGeneric(int count);

  /// Today's Trained ring: which day was trained and for how long. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'{day} · {minutes} MIN'**
  String pulseTrainedFor(String day, int minutes);

  /// Today's Trained ring: a session for this day is in progress.
  ///
  /// In en, this message translates to:
  /// **'{day} · UNDER WAY'**
  String pulseUnderWay(String day);

  /// Momentum: consecutive days trained.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1-day streak} other{{count}-day streak}}'**
  String pulseStreakDays(int count);

  /// Momentum: how many sessions in the trailing week. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 SESSION · LAST 7 DAYS} other{{count} SESSIONS · LAST 7 DAYS}}'**
  String pulseSessionsLast7(int count);

  /// Bodyweight delta caption: the unit and the window it is measured over.
  ///
  /// In en, this message translates to:
  /// **'KG · {days}D'**
  String pulseWeightSpan(int days);

  /// Header caption on the expenses list. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'{amount} SPENT TODAY'**
  String expenseSpentToday(String amount);

  /// A money figure and its currency code.
  ///
  /// In en, this message translates to:
  /// **'{amount} {currency}'**
  String expenseAmountWithCurrency(String amount, String currency);

  /// An expense row’s meta line: when it was logged and what it was for.
  ///
  /// In en, this message translates to:
  /// **'{time} · {category}'**
  String expenseRowMeta(String time, String category);

  /// Header when editing an existing split.
  ///
  /// In en, this message translates to:
  /// **'Edit split'**
  String get planEditSplitTitle;

  /// Header when editing the active plan.
  ///
  /// In en, this message translates to:
  /// **'Edit workout plan'**
  String get planEditPlanTitle;

  /// Header when creating a split.
  ///
  /// In en, this message translates to:
  /// **'New split'**
  String get planNewSplitTitle;

  /// Header when creating the active plan.
  ///
  /// In en, this message translates to:
  /// **'New workout plan'**
  String get planNewPlanTitle;

  /// Accessibility label on the split delete action.
  ///
  /// In en, this message translates to:
  /// **'Delete split'**
  String get planDeleteSplit;

  /// Accessibility label on the plan delete action.
  ///
  /// In en, this message translates to:
  /// **'Delete plan'**
  String get planDeletePlan;

  /// Label on the plan name field.
  ///
  /// In en, this message translates to:
  /// **'Plan name'**
  String get planName;

  /// Title of the privacy policy page.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyTitle;

  /// Subtitle under the privacy title, carrying the revision date.
  ///
  /// In en, this message translates to:
  /// **'How ZIVO handles your data.\nLast updated {date}.'**
  String privacyIntro(String date);

  /// Privacy section label. Upper case in English by design.
  ///
  /// In en, this message translates to:
  /// **'OVERVIEW'**
  String get privacyOverviewLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'ZIVO is a private, personal application for organizing the parts of your day — moments, workouts, diet, expenses, and more — in one calm place. This policy explains what ZIVO stores, how it is used, and the choices you have.'**
  String get privacyOverviewBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'THE SHORT VERSION'**
  String get privacyShortLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'Your content is private to your account and never sold or shared for ads.'**
  String get privacyShortBullet1;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'ZIVO does not use your data or your content to train third-party models.'**
  String get privacyShortBullet2;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'Backups live in your own Google Drive, under your own control.'**
  String get privacyShortBullet3;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'You can delete your content at any time, from inside the app.'**
  String get privacyShortBullet4;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT & AUTHENTICATION'**
  String get privacyAccountLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'ZIVO uses Firebase Authentication to sign you in, with Apple, Google, or email/password as sign-in options. Depending on the method you choose, ZIVO receives basic account details such as your name, email address, and a unique account identifier. That identifier is what keeps every piece of your data scoped to your account only.'**
  String get privacyAccountBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'EMAIL VERIFICATION CODES'**
  String get privacyOtpLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'If you sign in with email, ZIVO sends a short verification code to confirm your address. Codes are hashed before storage, expire within minutes, and are used for nothing beyond verifying that the address is yours.'**
  String get privacyOtpBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'YOUR CONTENT'**
  String get privacyContentLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'Everything you create in ZIVO — moments, workout plans and sessions, diet plans and entries, expense logs, body-weight entries, and profile details — is stored in your account so the app can show it back to you across your devices. It is private to you and not visible to other users.'**
  String get privacyContentBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'PHOTOS & LOCAL STORAGE'**
  String get privacyPhotosLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'Where a feature lets you attach a photo (such as Moments or your profile), ZIVO accesses your photo library only when you pick or capture an image. Media lives first on your device; cloud backup happens only through the backup target you explicitly choose.'**
  String get privacyPhotosBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'AI ASSISTANT (“ASK”)'**
  String get privacyAskLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'Ask is an opt-in assistant that can answer questions about your own data — your workouts, meals, and spending. When you send a message, the relevant context is processed by the model provider solely to answer you. Conversations are stored privately in your account so history works across devices, and are never used to train third-party models.'**
  String get privacyAskBody;

  /// Privacy section label. The brand name stays latin in both languages.
  ///
  /// In en, this message translates to:
  /// **'SPOTIFY'**
  String get privacySpotifyLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'The music feature connects to your own Spotify account when you ask it to. ZIVO uses Spotify’s official SDK to control playback and read what’s currently playing. You can disconnect at any time, from Settings.'**
  String get privacySpotifyBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT & SECURITY METADATA'**
  String get privacyMetadataLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'To keep your account safe and supportable, ZIVO keeps a small record of authentication events — when your account was created, when you last signed in and how, and when verification emails were sent. This metadata is security bookkeeping: it is never sold, shared, or used for advertising.'**
  String get privacyMetadataBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'GOOGLE DRIVE BACKUP'**
  String get privacyDriveLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'Backup is optional and, if enabled, runs against your own Google Drive — using Google’s most restrictive drive.file scope, which lets ZIVO see and manage only the files it created itself. ZIVO never requests broad access to your Drive, and your files remain under your control there.'**
  String get privacyDriveBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'DATA SHARING'**
  String get privacySharingLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'ZIVO does not sell or rent personal data. Data is processed only by the infrastructure needed to run the app — Google Firebase (authentication, database, functions) — plus the integrations you explicitly enable: your own Google Drive and your own Spotify account.'**
  String get privacySharingBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'RETENTION & DELETION'**
  String get privacyRetentionLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'Your content is retained until you delete it or delete your account. Files in your own Google Drive stay there until you remove them, and Drive access can be revoked at any time — from Settings or from your Google Account’s third-party access page.'**
  String get privacyRetentionBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'SECURITY'**
  String get privacySecurityLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'Access is enforced end-to-end: Firebase Authentication for identity and Firestore security rules so only your authenticated account can read or write your data. Verification codes are stored only as salted hashes. Data is encrypted in transit.'**
  String get privacySecurityBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'CHANGES TO THIS POLICY'**
  String get privacyChangesLabel;

  /// A section of the privacy policy. This is a legal document: it must stay a faithful statement of the English, not a loose paraphrase.
  ///
  /// In en, this message translates to:
  /// **'This policy may be updated as features evolve. The “last updated” date always reflects the most recent revision.'**
  String get privacyChangesBody;

  /// Privacy section label.
  ///
  /// In en, this message translates to:
  /// **'CONTACT'**
  String get privacyContactLabel;

  /// Privacy section: how to reach the owner. The address is a placeholder so it is never translated or reordered.
  ///
  /// In en, this message translates to:
  /// **'Questions about privacy or your data can be sent to {email}.'**
  String privacyContactBody(String email);

  /// The Sleep feature's title.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get sleepTitle;

  /// Hub tile caption above last night's figure.
  ///
  /// In en, this message translates to:
  /// **'Last night'**
  String get sleepHubSubtitle;

  /// Section label for the most recent night.
  ///
  /// In en, this message translates to:
  /// **'Last night'**
  String get sleepLastNight;

  /// Empty state title when we know the store is readable and empty.
  ///
  /// In en, this message translates to:
  /// **'No sleep recorded'**
  String get sleepNoDataTitle;

  /// Empty state body when the store is readable and genuinely empty.
  ///
  /// In en, this message translates to:
  /// **'Log a night yourself, or connect a device that tracks sleep.'**
  String get sleepNoDataBody;

  /// Empty state title when we cannot confirm we were allowed to read. Must never claim the user has no sleep data.
  ///
  /// In en, this message translates to:
  /// **'No sleep data visible to ZIVO'**
  String get sleepNotVisibleTitle;

  /// Explains that an empty read can mean a refused permission. Named because Apple deliberately hides read denial.
  ///
  /// In en, this message translates to:
  /// **'{provider} doesn\'t say whether an app was refused access, so this may mean permission is off rather than that there\'s nothing there.'**
  String sleepNotVisibleBody(String provider);

  /// Empty state title when the platform confirmed a refusal.
  ///
  /// In en, this message translates to:
  /// **'ZIVO can\'t read your sleep'**
  String get sleepPermissionDeniedTitle;

  /// Body when the platform confirmed a refusal.
  ///
  /// In en, this message translates to:
  /// **'Allow Sleep access in {provider} to see nights measured by your watch or another app.'**
  String sleepPermissionDeniedBody(String provider);

  /// Shown when the host has no health provider at all.
  ///
  /// In en, this message translates to:
  /// **'No health app on this device'**
  String get sleepUnavailableTitle;

  /// Reassures that manual logging still works with no health provider.
  ///
  /// In en, this message translates to:
  /// **'You can still log nights yourself.'**
  String get sleepUnavailableBody;

  /// Android refused reads beyond 30 days.
  ///
  /// In en, this message translates to:
  /// **'Older nights need history access in {provider}.'**
  String sleepHistoryUnavailable(String provider);

  /// A sync failed for an unclassified reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read sleep just now.'**
  String get sleepSyncFailed;

  /// Button that opens the health permission prompt.
  ///
  /// In en, this message translates to:
  /// **'Connect {provider}'**
  String sleepConnect(String provider);

  /// Apple's health store, as Apple names it.
  ///
  /// In en, this message translates to:
  /// **'Apple Health'**
  String get sleepProviderApple;

  /// Google's health store. Not translated — it is a product name.
  ///
  /// In en, this message translates to:
  /// **'Health Connect'**
  String get sleepProviderHealthConnect;

  /// The provider name on a night the user logged themselves.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get sleepProviderYou;

  /// Opens a user-reported sleep mark.
  ///
  /// In en, this message translates to:
  /// **'I\'m going to sleep'**
  String get sleepGoingToSleep;

  /// Closes an open sleep mark into a night.
  ///
  /// In en, this message translates to:
  /// **'I\'m awake'**
  String get sleepImAwake;

  /// Shown while a sleep mark is open and not yet closed.
  ///
  /// In en, this message translates to:
  /// **'Sleeping since {time}'**
  String sleepMarkOpenSince(String time);

  /// Discards an open sleep mark without creating a night.
  ///
  /// In en, this message translates to:
  /// **'Not sleeping after all'**
  String get sleepMarkCancel;

  /// Opens the manual correction sheet.
  ///
  /// In en, this message translates to:
  /// **'Edit this night'**
  String get sleepEditNight;

  /// Explains that an edit overrides rather than erases the measurement.
  ///
  /// In en, this message translates to:
  /// **'Your correction is saved as your own, and the measured times are kept.'**
  String get sleepEditHint;

  /// Sleep onset from a sensor measurement. States it plainly.
  ///
  /// In en, this message translates to:
  /// **'Asleep {time}'**
  String sleepOnsetMeasured(String time);

  /// Sleep onset from a platform record we cannot attribute to a sensor. Deliberately weaker than 'Asleep'.
  ///
  /// In en, this message translates to:
  /// **'Sleep recorded {time}'**
  String sleepOnsetPlatform(String time);

  /// Sleep onset the user reported. Never phrased as a detection.
  ///
  /// In en, this message translates to:
  /// **'You logged {time}'**
  String sleepOnsetReported(String time);

  /// Sleep onset inferred from device behaviour. Hedged, and rounded to the quarter hour.
  ///
  /// In en, this message translates to:
  /// **'Likely asleep around {time}'**
  String sleepOnsetEstimated(String time);

  /// Wake time from a sensor measurement.
  ///
  /// In en, this message translates to:
  /// **'Awake {time}'**
  String sleepWakeMeasured(String time);

  /// Wake time from an unattributed platform record.
  ///
  /// In en, this message translates to:
  /// **'Wake recorded {time}'**
  String sleepWakePlatform(String time);

  /// Wake time the user reported.
  ///
  /// In en, this message translates to:
  /// **'You logged {time}'**
  String sleepWakeReported(String time);

  /// Wake time inferred from device behaviour.
  ///
  /// In en, this message translates to:
  /// **'Likely awake around {time}'**
  String sleepWakeEstimated(String time);

  /// A device-activity timestamp. Never re-worded into a sleep claim.
  ///
  /// In en, this message translates to:
  /// **'Last phone use {time}'**
  String sleepLastPhoneUse(String time);

  /// Badge for a sensor measurement.
  ///
  /// In en, this message translates to:
  /// **'Measured'**
  String get sleepMethodMeasured;

  /// Badge for a platform record of unknown sensor origin.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get sleepMethodRecorded;

  /// Badge for a user-reported night.
  ///
  /// In en, this message translates to:
  /// **'Logged by you'**
  String get sleepMethodLogged;

  /// Badge for an inferred night.
  ///
  /// In en, this message translates to:
  /// **'Estimate'**
  String get sleepMethodEstimated;

  /// Confidence badge.
  ///
  /// In en, this message translates to:
  /// **'High confidence'**
  String get sleepConfidenceHigh;

  /// Confidence badge.
  ///
  /// In en, this message translates to:
  /// **'Medium confidence'**
  String get sleepConfidenceMedium;

  /// Confidence badge.
  ///
  /// In en, this message translates to:
  /// **'Low confidence'**
  String get sleepConfidenceLow;

  /// The source chip under every sleep figure. Provider first, then how it was produced.
  ///
  /// In en, this message translates to:
  /// **'{provider} · {method}'**
  String sleepSourceChip(String provider, String method);

  /// Label for time actually asleep.
  ///
  /// In en, this message translates to:
  /// **'Asleep'**
  String get sleepDurationLabel;

  /// Label for time in bed.
  ///
  /// In en, this message translates to:
  /// **'In bed'**
  String get sleepTimeInBedLabel;

  /// Label for asleep divided by time in bed.
  ///
  /// In en, this message translates to:
  /// **'Efficiency'**
  String get sleepEfficiencyLabel;

  /// Shown where efficiency cannot be computed. Never a percentage.
  ///
  /// In en, this message translates to:
  /// **'Not tracked'**
  String get sleepEfficiencyUnknown;

  /// Awake bouts inside a night.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No interruptions} =1{1 interruption} other{{count} interruptions}}'**
  String sleepInterruptionCount(int count);

  /// Short episodes outside the main sleep.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 nap} other{{count} naps}}'**
  String sleepNapCount(int count);

  /// Annotates a night spanning a DST transition.
  ///
  /// In en, this message translates to:
  /// **'This night crossed a clock change, so its length differs from the times shown.'**
  String get sleepSpansDstNote;

  /// Title of the targets sheet.
  ///
  /// In en, this message translates to:
  /// **'Your targets'**
  String get sleepTargetsTitle;

  /// Target bedtime field.
  ///
  /// In en, this message translates to:
  /// **'Bedtime'**
  String get sleepTargetBedtime;

  /// Target wake time field.
  ///
  /// In en, this message translates to:
  /// **'Wake'**
  String get sleepTargetWake;

  /// Target sleep duration field.
  ///
  /// In en, this message translates to:
  /// **'Sleep length'**
  String get sleepTargetDuration;

  /// States that targets are a reference, not a grade.
  ///
  /// In en, this message translates to:
  /// **'Used for the target line and nothing else — ZIVO never scores a night.'**
  String get sleepTargetsHint;

  /// Shown where a target delta would go before targets are set.
  ///
  /// In en, this message translates to:
  /// **'Set a target to see how your nights compare.'**
  String get sleepNoTargets;

  /// Slept longer than the target.
  ///
  /// In en, this message translates to:
  /// **'{amount} more than your {target} target'**
  String sleepDeltaLonger(String amount, String target);

  /// Slept less than the target.
  ///
  /// In en, this message translates to:
  /// **'{amount} less than your {target} target'**
  String sleepDeltaShorter(String amount, String target);

  /// Slept within rounding of the target.
  ///
  /// In en, this message translates to:
  /// **'On your {target} target'**
  String sleepDeltaOnTarget(String target);

  /// Went to bed later than target.
  ///
  /// In en, this message translates to:
  /// **'{amount} later than your target bedtime'**
  String sleepBedtimeLater(String amount);

  /// Went to bed earlier than target.
  ///
  /// In en, this message translates to:
  /// **'{amount} earlier than your target bedtime'**
  String sleepBedtimeEarlier(String amount);

  /// Bedtime landed within tolerance.
  ///
  /// In en, this message translates to:
  /// **'On your target bedtime'**
  String get sleepBedtimeOnTarget;

  /// Opens the provenance sheet.
  ///
  /// In en, this message translates to:
  /// **'Why this number?'**
  String get sleepWhyTitle;

  /// Resolution explanation: no contest.
  ///
  /// In en, this message translates to:
  /// **'Only one source had this night.'**
  String get sleepWhySole;

  /// Resolution explanation: better method tier.
  ///
  /// In en, this message translates to:
  /// **'Chosen because it was measured rather than entered or estimated.'**
  String get sleepWhyMethod;

  /// Resolution explanation: better coverage.
  ///
  /// In en, this message translates to:
  /// **'Chosen because more of the night was actually recorded.'**
  String get sleepWhyCoverage;

  /// Resolution explanation: richer stage data.
  ///
  /// In en, this message translates to:
  /// **'Chosen because it included sleep stages.'**
  String get sleepWhyDetail;

  /// Resolution explanation: user override.
  ///
  /// In en, this message translates to:
  /// **'You set this night yourself.'**
  String get sleepWhyOverride;

  /// Shows how far an alternate source disagrees. Never averaged away.
  ///
  /// In en, this message translates to:
  /// **'{provider} recorded a different time — {amount} apart.'**
  String sleepDisagreement(String provider, String amount);

  /// Share of the night backed by real samples.
  ///
  /// In en, this message translates to:
  /// **'Recorded coverage'**
  String get sleepCoverageLabel;

  /// Names the writing app.
  ///
  /// In en, this message translates to:
  /// **'Recorded by {provider}'**
  String sleepRecordedBy(String provider);

  /// Switches the night to an alternate source.
  ///
  /// In en, this message translates to:
  /// **'Use this one instead'**
  String get sleepUseThisInstead;

  /// Weekly view title.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get sleepWeekTitle;

  /// Weekly average duration label.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get sleepWeekAverage;

  /// Weekly midpoint variability label.
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get sleepWeekConsistency;

  /// Weekly bedtime adherence label.
  ///
  /// In en, this message translates to:
  /// **'On target'**
  String get sleepWeekOnTarget;

  /// How many nights a figure rests on. Always shown beside it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 night} other{{count} nights}}'**
  String sleepNightsCounted(int count);

  /// Nights with data out of the window's length.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} nights'**
  String sleepNightsOf(int count, int total);

  /// Variability figure, e.g. ±48 min.
  ///
  /// In en, this message translates to:
  /// **'±{amount}'**
  String sleepVariability(String amount);

  /// Nights on target out of nights with data.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total}'**
  String sleepOnTargetRatio(int count, int total);

  /// Label on a night with nothing recorded. Never a zero.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get sleepNoData;

  /// Shown where a gated figure would go.
  ///
  /// In en, this message translates to:
  /// **'Not enough nights yet'**
  String get sleepInsufficient;

  /// Shown where a gated figure would go, with how far off it is.
  ///
  /// In en, this message translates to:
  /// **'Not enough nights yet — {have} of {need}'**
  String sleepInsufficientFor(int have, int need);

  /// Week-over-week difference inside the noise floor. A real finding, not a failure.
  ///
  /// In en, this message translates to:
  /// **'About the same as last week'**
  String get sleepWeekUnchanged;

  /// Week-over-week improvement past the noise floor.
  ///
  /// In en, this message translates to:
  /// **'{amount} more than last week'**
  String sleepWeekImproved(String amount);

  /// Week-over-week decline past the noise floor.
  ///
  /// In en, this message translates to:
  /// **'{amount} less than last week'**
  String sleepWeekDeclined(String amount);

  /// Section label above generated insights.
  ///
  /// In en, this message translates to:
  /// **'What this means'**
  String get sleepInsightsTitle;

  /// While insights are being generated.
  ///
  /// In en, this message translates to:
  /// **'Reading your nights…'**
  String get sleepInsightsPending;

  /// Shown when the fact sheet is too thin for any claim.
  ///
  /// In en, this message translates to:
  /// **'No conclusion can be drawn from the nights recorded so far.'**
  String get sleepInsightsUnavailable;

  /// Provenance footnote under a generated insight.
  ///
  /// In en, this message translates to:
  /// **'Based on {count, plural, =1{1 night} other{{count} nights}}'**
  String sleepInsightBasis(int count);

  /// Sleep stage.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get sleepStageLight;

  /// Sleep stage.
  ///
  /// In en, this message translates to:
  /// **'Deep'**
  String get sleepStageDeep;

  /// Sleep stage.
  ///
  /// In en, this message translates to:
  /// **'REM'**
  String get sleepStageRem;

  /// Sleep stage.
  ///
  /// In en, this message translates to:
  /// **'Awake'**
  String get sleepStageAwake;

  /// Sleep stage with no grading available.
  ///
  /// In en, this message translates to:
  /// **'Asleep'**
  String get sleepStageAsleep;

  /// Bed-occupancy state, not a sleep stage.
  ///
  /// In en, this message translates to:
  /// **'In bed'**
  String get sleepStageInBed;

  /// Shown in place of a stage breakdown when the source has none.
  ///
  /// In en, this message translates to:
  /// **'Stages aren\'t available from this source.'**
  String get sleepNoStages;

  /// A duration in hours and minutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String sleepDurationHm(int hours, int minutes);

  /// A duration under an hour.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String sleepDurationM(int minutes);

  /// A whole number of hours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String sleepDurationH(int hours);

  /// Hub module card label for Sleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get hubSleep;

  /// Hub Sleep card stat before any night is recorded.
  ///
  /// In en, this message translates to:
  /// **'No nights yet'**
  String get hubNoSleepYet;

  /// Deterministic insight: the window's average sleep length.
  ///
  /// In en, this message translates to:
  /// **'You\'ve averaged {amount} a night.'**
  String sleepInsightDuration(String amount);

  /// Deterministic insight: week-over-week improvement past the noise floor.
  ///
  /// In en, this message translates to:
  /// **'That\'s {amount} more than the week before.'**
  String sleepInsightWeekBetter(String amount);

  /// Deterministic insight: week-over-week decline past the noise floor.
  ///
  /// In en, this message translates to:
  /// **'That\'s {amount} less than the week before.'**
  String sleepInsightWeekWorse(String amount);

  /// Deterministic insight: the difference is inside the noise floor, which is a finding rather than a failure to find one.
  ///
  /// In en, this message translates to:
  /// **'That\'s about the same as the week before.'**
  String get sleepInsightWeekSame;

  /// Deterministic insight: low midpoint variability.
  ///
  /// In en, this message translates to:
  /// **'Your sleep timing held steady, varying by {amount}.'**
  String sleepInsightConsistent(String amount);

  /// Deterministic insight: high midpoint variability.
  ///
  /// In en, this message translates to:
  /// **'Your sleep timing moved around by {amount} across the week.'**
  String sleepInsightIrregular(String amount);

  /// Deterministic insight: bedtime adherence.
  ///
  /// In en, this message translates to:
  /// **'You hit your target bedtime on {count} of {total} nights.'**
  String sleepInsightAdherence(int count, int total);

  /// Deterministic insight: a rising Theil-Sen slope. Direction only, because a slope in minutes per night is not a figure a reader can use.
  ///
  /// In en, this message translates to:
  /// **'Over the last few weeks your nights have been getting longer.'**
  String get sleepInsightTrendUp;

  /// Deterministic insight: a falling Theil-Sen slope.
  ///
  /// In en, this message translates to:
  /// **'Over the last few weeks your nights have been getting shorter.'**
  String get sleepInsightTrendDown;

  /// The hours unit in a sleep duration. Rendered as its own smaller span beside the number, never inside the mono run — Azeret Mono has no Arabic, so an interpolated Arabic letter falls back to a system face with different metrics.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get sleepUnitHour;

  /// Title of the sheet behind the header's info button — what the feature does and what it refuses to claim.
  ///
  /// In en, this message translates to:
  /// **'How Sleep works'**
  String get sleepAboutTitle;

  /// Opening line of the how-it-works sheet.
  ///
  /// In en, this message translates to:
  /// **'Sleep is a recovery input to your training. Here is exactly what ZIVO does with it, and what it will not claim.'**
  String get sleepAboutIntro;

  /// How-it-works heading: the manual log.
  ///
  /// In en, this message translates to:
  /// **'What a sleep session is'**
  String get sleepAboutSessionTitle;

  /// How-it-works body: what opening and closing a manual sleep mark actually does. Names both buttons so the sentence matches the screen.
  ///
  /// In en, this message translates to:
  /// **'Tapping “I\'m going to sleep” opens a session and nothing else — no timer runs and your phone is not listening. When you tap “I\'m awake”, those two moments become the night, marked as logged by you.'**
  String get sleepAboutSessionBody;

  /// How-it-works heading: the automatic half.
  ///
  /// In en, this message translates to:
  /// **'What ZIVO reads'**
  String get sleepAboutTrackedTitle;

  /// How-it-works body: the health-store read. The provider is the platform's own store name.
  ///
  /// In en, this message translates to:
  /// **'Each time you open this screen ZIVO re-reads {provider} and rebuilds the last week: when you fell asleep, when you woke, how long you were actually asleep, and any time awake in between.'**
  String sleepAboutTrackedBody(String provider);

  /// How-it-works heading: provenance.
  ///
  /// In en, this message translates to:
  /// **'Every number says where it came from'**
  String get sleepAboutSourcesTitle;

  /// How-it-works body: what the source chip means, and why sources are chosen rather than merged.
  ///
  /// In en, this message translates to:
  /// **'“Measured” means a watch recorded it. “Logged by you” means you or an app typed it. When two sources disagree ZIVO picks one and keeps the other — it never averages them into a night nobody slept.'**
  String get sleepAboutSourcesBody;

  /// How-it-works heading: the gates on weekly figures.
  ///
  /// In en, this message translates to:
  /// **'Why some figures are blank'**
  String get sleepAboutWeekTitle;

  /// How-it-works body: why a weekly figure can be empty.
  ///
  /// In en, this message translates to:
  /// **'An average over one night is not an average. Weekly figures stay blank until enough nights exist, and each one shows how many it still needs.'**
  String get sleepAboutWeekBody;

  /// How-it-works heading: the deliberate limits.
  ///
  /// In en, this message translates to:
  /// **'What it will not do'**
  String get sleepAboutLimitsTitle;

  /// How-it-works body: no score, no grade.
  ///
  /// In en, this message translates to:
  /// **'There is no sleep score and no streak. ZIVO can tell you how long you slept and how steady your schedule is; it cannot tell you whether the night was good.'**
  String get sleepAboutLimitsBody;

  /// Dismisses the how-it-works sheet.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get sleepAboutDone;

  /// Label on the card shown while a sleep session is open.
  ///
  /// In en, this message translates to:
  /// **'Sleeping'**
  String get sleepSessionOpen;

  /// Caption under the elapsed time of an open sleep session.
  ///
  /// In en, this message translates to:
  /// **'So far'**
  String get sleepMarkSoFar;

  /// Elapsed time of a sleep session opened less than a minute ago, where a duration would read as zero.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get sleepMarkJustNow;

  /// Explains that an open session becomes a night only when it is closed.
  ///
  /// In en, this message translates to:
  /// **'Tap “I\'m awake” when you get up — that is when the night is recorded.'**
  String get sleepMarkHint;

  /// Shown when the saved-nights stream failed, as opposed to the health store being unreadable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your sleep'**
  String get sleepLoadFailedTitle;

  /// Body for a failed read of stored nights.
  ///
  /// In en, this message translates to:
  /// **'ZIVO couldn\'t read the nights it has already saved. Check your connection and try again.'**
  String get sleepLoadFailedBody;

  /// Re-opens the storage streams after a failed read.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get sleepRetry;

  /// Accessibility label for the placeholder shown while last night is still loading.
  ///
  /// In en, this message translates to:
  /// **'Loading your sleep'**
  String get sleepLoading;

  /// Compact caption under a weekly figure that has not passed its gate: how many nights it needs before it can be shown. States the requirement, not the coverage: the section header above already says how many nights the week has, and two near-identical N-of-M-nights strings on one card read as the same fact twice.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Needs 1 night} other{Needs {count} nights}}'**
  String sleepGateNeeds(int count);

  /// Label above the week-over-week comparison sentence.
  ///
  /// In en, this message translates to:
  /// **'vs last week'**
  String get sleepVsLastWeek;

  /// A manual sleep action (opening or closing a session) failed to persist.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that just now. Check your connection and try again.'**
  String get sleepMarkFailed;

  /// The minutes unit in a sleep duration. See sleepUnitHour.
  ///
  /// In en, this message translates to:
  /// **'m'**
  String get sleepUnitMinute;

  /// Second line of the row that opens the history page: the week's mean sleep and the nights it rests on.
  ///
  /// In en, this message translates to:
  /// **'Average {average} · {nights}'**
  String sleepHistoryStat(String average, String nights);

  /// Headline label when the most recent recorded night is not last night. Never used for 0 or 1, which say 'Last night' instead.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =2{2 nights ago} other{{count} nights ago}}'**
  String sleepNightsAgo(int count);

  /// Shown under the headline when the most recent night is more than a day old, so a real figure is not mistaken for this morning's.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been recorded since. This is your most recent night, not last night.'**
  String get sleepStaleNotice;

  /// Section label above the sleep-stage breakdown of a single night.
  ///
  /// In en, this message translates to:
  /// **'Stages'**
  String get sleepStagesTitle;

  /// Shown in place of the stage breakdown when the source measured the night without grading it. Names the source so the absence is attributable.
  ///
  /// In en, this message translates to:
  /// **'{provider} recorded when you slept, but not which stages.'**
  String sleepStagesUnavailable(String provider);

  /// Caption under a stage breakdown that covers less than the whole session, so the shares are not read as covering all of it.
  ///
  /// In en, this message translates to:
  /// **'Staged for {amount} of the night.'**
  String sleepStagesPartial(String amount);

  /// Section label above the bed-to-wake chart for a single night.
  ///
  /// In en, this message translates to:
  /// **'Timing'**
  String get sleepTimingTitle;

  /// Section label above the measured detail rows of a night (time in bed, efficiency, interruptions).
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get sleepDetailTitle;

  /// Section label above the actual-versus-target lines for a night.
  ///
  /// In en, this message translates to:
  /// **'Against your target'**
  String get sleepAgainstTargetTitle;

  /// One line of context putting last night against the recent average. Only shown when the average passed its gate.
  ///
  /// In en, this message translates to:
  /// **'{amount} longer than your average of {average}.'**
  String sleepContextLonger(String amount, String average);

  /// See sleepContextLonger.
  ///
  /// In en, this message translates to:
  /// **'{amount} shorter than your average of {average}.'**
  String sleepContextShorter(String amount, String average);

  /// Context line when last night is within the noise floor of the recent average.
  ///
  /// In en, this message translates to:
  /// **'About your usual — you average {average}.'**
  String sleepContextTypical(String average);

  /// The n behind the comparison-to-average line.
  ///
  /// In en, this message translates to:
  /// **'Over {count, plural, =1{1 night} other{{count} nights}}'**
  String sleepContextBasis(int count);

  /// Title of the weekly/history page, and the label of the row that opens it.
  ///
  /// In en, this message translates to:
  /// **'Sleep history'**
  String get sleepHistoryTitle;

  /// Second line of the row on the Sleep page that opens the history view.
  ///
  /// In en, this message translates to:
  /// **'Your weeks, night by night'**
  String get sleepHistorySubtitle;

  /// The date span of the week being shown on the history page.
  ///
  /// In en, this message translates to:
  /// **'{start} – {end}'**
  String sleepWeekRange(String start, String end);

  /// Label for the seven days ending today on the history page.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get sleepWeekCurrent;

  /// Accessibility label for the control that pages back one week on the history page.
  ///
  /// In en, this message translates to:
  /// **'Earlier week'**
  String get sleepWeekEarlier;

  /// Accessibility label for the control that pages forward one week on the history page.
  ///
  /// In en, this message translates to:
  /// **'Later week'**
  String get sleepWeekLater;

  /// Empty state for a week on the history page that contains no data at all.
  ///
  /// In en, this message translates to:
  /// **'No nights were recorded in this week.'**
  String get sleepWeekEmpty;

  /// Section label above the day-by-day list on the history page.
  ///
  /// In en, this message translates to:
  /// **'Every night'**
  String get sleepWeekNightsTitle;

  /// Section label above the week's average duration, bedtime and wake time.
  ///
  /// In en, this message translates to:
  /// **'Typical night'**
  String get sleepWeekTypicalTitle;

  /// Label for the week's median sleep duration, shown beside the mean.
  ///
  /// In en, this message translates to:
  /// **'Median'**
  String get sleepWeekMedian;

  /// Label for the week's typical (circular mean) bedtime.
  ///
  /// In en, this message translates to:
  /// **'Bedtime'**
  String get sleepWeekBedtime;

  /// Label for the week's typical (circular mean) wake time.
  ///
  /// In en, this message translates to:
  /// **'Wake'**
  String get sleepWeekWake;

  /// Section label above the week's average sleep-stage split.
  ///
  /// In en, this message translates to:
  /// **'Typical composition'**
  String get sleepWeekCompositionTitle;

  /// The n behind the weekly stage averages — counted over nights that carried stage detail, not all nights.
  ///
  /// In en, this message translates to:
  /// **'Averaged over {count, plural, =1{1 staged night} other{{count} staged nights}}'**
  String sleepWeekCompositionBasis(int count);

  /// Shown in place of the weekly stage split when too few nights were staged.
  ///
  /// In en, this message translates to:
  /// **'No night this week carried stage detail.'**
  String get sleepWeekNoStages;

  /// Section label above the multi-week trend on the history page.
  ///
  /// In en, this message translates to:
  /// **'Longer run'**
  String get sleepTrendTitle;

  /// Trend direction over the last four weeks.
  ///
  /// In en, this message translates to:
  /// **'Your nights have been getting longer.'**
  String get sleepTrendRising;

  /// Trend direction over the last four weeks.
  ///
  /// In en, this message translates to:
  /// **'Your nights have been getting shorter.'**
  String get sleepTrendFalling;

  /// Trend direction when the slope is inside the flat band — a finding, not a failure to find one.
  ///
  /// In en, this message translates to:
  /// **'Your nights have held steady.'**
  String get sleepTrendFlat;

  /// The evidence behind the trend statement.
  ///
  /// In en, this message translates to:
  /// **'{count} nights across {days} days'**
  String sleepTrendBasis(int count, int days);

  /// Shown instead of a trend when the gate has not passed, naming exactly what would open it.
  ///
  /// In en, this message translates to:
  /// **'A trend needs {need} nights across {days} days. You have {have}.'**
  String sleepTrendNeedMore(int have, int need, int days);

  /// The value of a day row on the history page for a day with no sleep record.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded'**
  String get sleepNightRowNoData;

  /// Bed and wake clock times on one day row of the history page.
  ///
  /// In en, this message translates to:
  /// **'{start} → {end}'**
  String sleepNightRowRange(String start, String end);

  /// Ends a workout that still has sets left, keeping what was logged.
  ///
  /// In en, this message translates to:
  /// **'Finish now'**
  String get liveFinishNow;

  /// Title of the finish-early dialog.
  ///
  /// In en, this message translates to:
  /// **'Finish here?'**
  String get liveFinishNowTitle;

  /// Body of the finish-early dialog. Promises that nothing is invented.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 set is still unlogged. It stays unlogged — nothing is recorded as done.} other{{count} sets are still unlogged. They stay unlogged — nothing is recorded as done.}}'**
  String liveFinishNowBody(int count);

  /// The streak rule, stated on the drill-down.
  ///
  /// In en, this message translates to:
  /// **'Train at least every {days} days'**
  String workoutStreakRule(int days);

  /// A day inside the streak with no training.
  ///
  /// In en, this message translates to:
  /// **'Rest day'**
  String get workoutStreakRestDay;

  /// A gap day kept alive by a spent streak restore.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get workoutStreakRestored;

  /// How long is left before the current streak breaks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Train today to keep it} =1{1 day left to train} other{{count} days left to train}}'**
  String workoutStreakDaysLeft(int count);

  /// Shown when the allowance has run out.
  ///
  /// In en, this message translates to:
  /// **'No active streak'**
  String get workoutStreakBroken;

  /// Action that spends a streak restore on a missed day.
  ///
  /// In en, this message translates to:
  /// **'Restore this day'**
  String get workoutStreakRestore;

  /// Title of the restore confirmation.
  ///
  /// In en, this message translates to:
  /// **'Restore this day?'**
  String get workoutStreakRestoreTitle;

  /// Body of the restore confirmation — states exactly what a restore does and does not do.
  ///
  /// In en, this message translates to:
  /// **'It bridges the gap so your streak survives. It does not add a workout, and it never counts as one.'**
  String get workoutStreakRestoreBody;

  /// Why the restore action is unavailable.
  ///
  /// In en, this message translates to:
  /// **'One restore every {days} days'**
  String workoutStreakRestoreUnavailable(int days);

  /// Opens the missed-day reason picker.
  ///
  /// In en, this message translates to:
  /// **'Why no training?'**
  String get workoutStreakWhyMissed;

  /// Footnote on the missed-day reason sheet.
  ///
  /// In en, this message translates to:
  /// **'Context only — it never changes your streak.'**
  String get workoutStreakReasonSaved;

  /// Missed-day reason.
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get missedDayRest;

  /// Missed-day reason.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get missedDayRecovery;

  /// Missed-day reason.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get missedDayTravel;

  /// Missed-day reason.
  ///
  /// In en, this message translates to:
  /// **'Illness'**
  String get missedDayIllness;

  /// Missed-day reason.
  ///
  /// In en, this message translates to:
  /// **'Too busy'**
  String get missedDayBusy;

  /// Missed-day reason.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get missedDayOther;

  /// Shown on a rest day with no recorded reason.
  ///
  /// In en, this message translates to:
  /// **'No reason given'**
  String get missedDayNone;

  /// How a session duration was produced.
  ///
  /// In en, this message translates to:
  /// **'Timed by ZIVO'**
  String get sessionDurationMeasured;

  /// How a session duration was produced.
  ///
  /// In en, this message translates to:
  /// **'Closed at your last set'**
  String get sessionDurationAutoClosed;

  /// How a session duration was produced.
  ///
  /// In en, this message translates to:
  /// **'You set this'**
  String get sessionDurationCorrected;

  /// How a session duration was produced.
  ///
  /// In en, this message translates to:
  /// **'Duration unknown'**
  String get sessionDurationUnknown;

  /// Chip on a session held out of the averages.
  ///
  /// In en, this message translates to:
  /// **'Needs a duration'**
  String get sessionNeedsDuration;

  /// Explains why a session is excluded from averages.
  ///
  /// In en, this message translates to:
  /// **'This session ran longer than a workout plausibly does, so it is left out of your averages until you set its length. Everything you logged is kept.'**
  String get sessionNeedsDurationBody;

  /// Opens the duration-correction sheet.
  ///
  /// In en, this message translates to:
  /// **'Set duration'**
  String get sessionSetDuration;

  /// Field label on the duration-correction sheet.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get sessionDurationMinutes;

  /// Clears a duration correction.
  ///
  /// In en, this message translates to:
  /// **'Use the measured time'**
  String get sessionDurationUseMeasured;

  /// Withdraws a session from the statistics.
  ///
  /// In en, this message translates to:
  /// **'Void this session'**
  String get sessionVoid;

  /// Title of the void dialog.
  ///
  /// In en, this message translates to:
  /// **'Void this session?'**
  String get sessionVoidTitle;

  /// Body of the void dialog.
  ///
  /// In en, this message translates to:
  /// **'It stays in your history exactly as logged, and stops counting toward your streak, averages and analysis.'**
  String get sessionVoidBody;

  /// Status label on a voided session.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get sessionVoided;

  /// Undoes a void.
  ///
  /// In en, this message translates to:
  /// **'Count this session again'**
  String get sessionUnvoid;

  /// Prompt for the void reason.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get sessionVoidReason;

  /// Void reason.
  ///
  /// In en, this message translates to:
  /// **'The time is wrong'**
  String get voidReasonBadDuration;

  /// Void reason.
  ///
  /// In en, this message translates to:
  /// **'Logged by mistake'**
  String get voidReasonLoggedByMistake;

  /// Void reason.
  ///
  /// In en, this message translates to:
  /// **'Wasn\'t me'**
  String get voidReasonNotMine;

  /// Void reason.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get voidReasonOther;

  /// Explains why delete is no longer offered on a logged session.
  ///
  /// In en, this message translates to:
  /// **'A session that recorded work is voided, not deleted — so your history stays trustworthy.'**
  String get sessionCannotDelete;

  /// Says how many sessions an average duration covers.
  ///
  /// In en, this message translates to:
  /// **'over {counted} of {total}'**
  String statDurationOver(int counted, int total);

  /// Shown when every session duration was held out of the average.
  ///
  /// In en, this message translates to:
  /// **'no usable session lengths yet'**
  String get statDurationAllExcluded;

  /// Title of the workout settings page.
  ///
  /// In en, this message translates to:
  /// **'Training settings'**
  String get workoutSettings;

  /// Setting label.
  ///
  /// In en, this message translates to:
  /// **'Maximum session length'**
  String get workoutMaxSessionTitle;

  /// Explains the maximum-session-length setting.
  ///
  /// In en, this message translates to:
  /// **'A workout still running past this, with nothing logged for a while, is treated as one you forgot to close. It is ended at your last logged set — never padded out, and never filled in with sets you did not do.'**
  String get workoutMaxSessionBody;

  /// Toast when a missed-day reason or restore fails to save.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that day.'**
  String get trainingDayMarkSaveFailed;

  /// Toast when a duration correction or void fails to save.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update that session.'**
  String get sessionUpdateFailed;

  /// Toast when a workout setting fails to save.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that setting.'**
  String get workoutSettingsSaveFailed;

  /// Title of the reminders page and its row on the Settings page.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get remindersTitle;

  /// One-line explanation under the reminders page header.
  ///
  /// In en, this message translates to:
  /// **'Get a notification when it\'s time to eat, train, or anything else you schedule.'**
  String get remindersIntro;

  /// Empty-state title when the user has no reminders.
  ///
  /// In en, this message translates to:
  /// **'No reminders yet'**
  String get remindersEmpty;

  /// Empty-state body under remindersEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add one to be reminded at the same time on the days you choose.'**
  String get remindersEmptyBody;

  /// Button that opens the sheet to create a new reminder.
  ///
  /// In en, this message translates to:
  /// **'Add reminder'**
  String get remindersAdd;

  /// Title of the reminder sheet when creating a new one.
  ///
  /// In en, this message translates to:
  /// **'New reminder'**
  String get remindersNewTitle;

  /// Title of the reminder sheet when editing an existing one.
  ///
  /// In en, this message translates to:
  /// **'Edit reminder'**
  String get remindersEditTitle;

  /// Hint text for the reminder name field.
  ///
  /// In en, this message translates to:
  /// **'Name (e.g. Breakfast, Leg day)'**
  String get remindersLabelHint;

  /// Reminder kind label: a meal reminder.
  ///
  /// In en, this message translates to:
  /// **'Meal'**
  String get remindersKindMeal;

  /// Reminder kind label: a workout reminder.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get remindersKindWorkout;

  /// Reminder kind label: a general reminder the user names themselves.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get remindersKindGeneral;

  /// Label for the time picker in the reminder sheet.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get remindersTimeLabel;

  /// Label for the day-of-week chooser in the reminder sheet.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get remindersRepeatLabel;

  /// Repeat value shown when a reminder fires on all seven days.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get remindersEveryDay;

  /// Confirms and saves the reminder in the sheet.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get remindersSave;

  /// Deletes the reminder being edited.
  ///
  /// In en, this message translates to:
  /// **'Delete reminder'**
  String get remindersDelete;

  /// Confirmation prompt before deleting a reminder.
  ///
  /// In en, this message translates to:
  /// **'Delete this reminder?'**
  String get remindersDeleteConfirm;

  /// Toast when saving a reminder fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that reminder.'**
  String get remindersSaveFailed;

  /// Note shown when the OS notification permission was denied.
  ///
  /// In en, this message translates to:
  /// **'Turn on notifications for ZIVO in your phone\'s settings to get reminders.'**
  String get remindersPermissionDenied;

  /// Button on a meal reminder that loads the meal scheduled in the active diet plan.
  ///
  /// In en, this message translates to:
  /// **'Sync from your plan'**
  String get remindersSyncFromPlan;

  /// Toggle on a workout reminder that links it to the active workout plan so it shows the next scheduled workout.
  ///
  /// In en, this message translates to:
  /// **'Sync with my plan'**
  String get remindersSyncWorkout;

  /// Explanation under the workout-sync toggle.
  ///
  /// In en, this message translates to:
  /// **'Shows your next scheduled workout, and keeps it up to date.'**
  String get remindersSyncWorkoutHint;

  /// Toggle on a synced workout reminder that shows a short line of encouragement instead of the list of exercises.
  ///
  /// In en, this message translates to:
  /// **'Motivational message'**
  String get remindersMotivational;

  /// Explanation under the motivational-message toggle on a workout reminder.
  ///
  /// In en, this message translates to:
  /// **'Names today\'s workout and adds a line to keep you going, instead of the exercise list.'**
  String get remindersMotivationalHint;

  /// Title of the sheet that lists the meals in the plan to pick one for a reminder.
  ///
  /// In en, this message translates to:
  /// **'Which meal?'**
  String get remindersPickMeal;

  /// Section label above the editable list of food items on a synced meal reminder.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get remindersMealItems;

  /// Hint on the field for adding a custom food item to a synced meal reminder.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get remindersAddItem;

  /// Shown when a meal reminder is asked to sync but there is no active diet plan.
  ///
  /// In en, this message translates to:
  /// **'No active meal plan to sync from.'**
  String get remindersNoMealPlan;

  /// Shown when a workout reminder is asked to sync but there is no active workout plan.
  ///
  /// In en, this message translates to:
  /// **'No active workout plan to sync from.'**
  String get remindersNoWorkoutPlan;

  /// Small badge on a reminder row indicating it is linked to a plan.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get remindersSyncedBadge;
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
