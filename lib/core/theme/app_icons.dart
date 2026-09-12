import 'package:phosphor_icons/phosphor_icons.dart';

/// The app's single icon vocabulary — Phosphor Icons mapped to semantic names,
/// so every surface uses one consistent, premium set instead of ad-hoc
/// `Icons.*`. Nothing outside this file names a glyph: the rest of the app
/// says `AppIcons.streak`, never `PhosphorIconsRegular.flame`. That seam is what
/// made swapping the whole set from Lucide a one-file change, and it is worth
/// keeping intact.
///
/// **Regular, and drawn larger to carry it.** This set ran Bold for one
/// revision, chosen to stop small glyphs reading soft: a 2.5px stroke on a 24
/// grid lands near 1.8 logical px at 17, where Regular's 1.5px lands near one.
/// That fixed crispness and cost the thing crispness was standing in for.
/// Heavy rounded strokes read friendly and consumer; the restrained line-icon
/// sets this app is measured against — Linear, Things, Arc, Apple's own — all
/// run thin and buy their sharpness with **size and space instead of weight**.
///
/// So: Regular, with the glyph drawn bigger wherever it was too small to hold
/// a thin stroke — 20px bare in a settings row, 24px in the bottom bar. If a
/// glyph ever looks soft again, the answer is a larger mark or a brighter ink,
/// never a heavier cut.
///
/// **Fill is a real weight here, not a duplicate.** Under Lucide the `*Fill`
/// names were the same glyph as their stroked twin and the active state was
/// carried by colour alone. Phosphor ships a true solid cut, so the bottom
/// bar's active tab and the photo viewer's open info panel now use it.
///
/// Values are `IconData`, so they drop into the standard `Icon(...)` widget
/// and stay `const` at the call site.
///
/// > **RTL note.** Every Phosphor glyph is declared with
/// > `matchTextDirection: true`, so all of them mirror under Arabic. That is
/// > right for [chevron], [back] and [send], and harmless for the symmetric
/// > majority; [trendUp] / [trendDown] / [analysis] are the ones to eyeball if
/// > the Arabic build ever looks off, since a mirrored slope beside an
/// > unmirrored chart is the one case that actively misreads.
class AppIcons {
  AppIcons._();

  // Bottom navigation. The `*Fill` twin is the solid cut, cross-faded in as
  // the ember capsule arrives (see `zivo_bottom_bar`), not a colour swap.
  static const today = PhosphorIconsRegular.house;
  static const todayFill = PhosphorIconsFill.house;
  static const hub = PhosphorIconsRegular.squaresFour;
  static const hubFill = PhosphorIconsFill.squaresFour;
  static const ask = PhosphorIconsRegular.sparkle;
  static const askFill = PhosphorIconsFill.sparkle;
  static const you = PhosphorIconsRegular.user;
  static const youFill = PhosphorIconsFill.user;

  // Hub modules.
  static const workout = PhosphorIconsRegular.barbell;
  static const diet = PhosphorIconsRegular.forkKnife;
  static const expenses = PhosphorIconsRegular.wallet;
  static const moments = PhosphorIconsRegular.images;
  static const sleep = PhosphorIconsRegular.moon;

  // Sleep. The moon above is the module's mark; these are the Sleep screen's
  // own vocabulary — the header's two actions and the how-it-works sheet.
  static const sleepTargets = PhosphorIconsRegular.target;
  static const sleepSync = PhosphorIconsRegular.arrowsClockwise;
  static const sleepSources = PhosphorIconsRegular.sealCheck;
  static const sleepWeek = PhosphorIconsRegular.calendarBlank;
  static const sleepNoGrade = PhosphorIconsRegular.prohibit;
  static const sleepWoke = PhosphorIconsRegular.sunHorizon;

  // Training analytics & sessions.
  static const analysis = PhosphorIconsRegular.chartLineUp;
  static const trendUp = PhosphorIconsRegular.trendUp;
  static const trendDown = PhosphorIconsRegular.trendDown;
  static const trophy = PhosphorIconsRegular.trophy;
  static const history = PhosphorIconsRegular.clockCounterClockwise;
  static const splits = PhosphorIconsRegular.stack;
  static const streak = PhosphorIconsRegular.flame;
  static const timer = PhosphorIconsRegular.timer;
  static const clock = PhosphorIconsRegular.clock;
  static const scale = PhosphorIconsRegular.scales;
  static const planDoc = PhosphorIconsRegular.clipboardText;
  static const sessions = PhosphorIconsRegular.pulse;
  static const minus = PhosphorIconsRegular.minus;
  static const calendarClock = PhosphorIconsRegular.calendarDot;
  static const bolt = PhosphorIconsRegular.lightning;
  static const duplicate = PhosphorIconsRegular.copy;
  static const pause = PhosphorIconsRegular.pause;

  // Readiness — the recovery/"what to train today" call. `pulse` reads as a
  // vital sign, which is what readiness fuses; per-factor rows reuse the
  // sleep/workout/timer/scale glyphs of the input they cite.
  static const readiness = PhosphorIconsRegular.pulse;

  // Reminders (local notifications). `bell` is the feature's mark; meal/workout
  // reuse the diet/workout module glyphs, and `general` gets a plain clock.
  // `reminderSync` marks a reminder linked to a meal/workout plan.
  static const reminders = PhosphorIconsRegular.bell;
  static const reminderMeal = PhosphorIconsRegular.forkKnife;
  static const reminderWorkout = PhosphorIconsRegular.barbell;
  static const reminderGeneral = PhosphorIconsRegular.clock;
  static const reminderSync = PhosphorIconsRegular.arrowsClockwise;

  // Common actions / affordances.
  static const add = PhosphorIconsRegular.plus;
  static const search = PhosphorIconsRegular.magnifyingGlass;
  static const camera = PhosphorIconsRegular.camera;
  static const image = PhosphorIconsRegular.image;
  static const crop = PhosphorIconsRegular.crop;
  static const retake = PhosphorIconsRegular.arrowsClockwise;
  static const trash = PhosphorIconsRegular.trash;
  static const check = PhosphorIconsRegular.check;
  static const close = PhosphorIconsRegular.x;
  static const back = PhosphorIconsRegular.arrowLeft;
  static const info = PhosphorIconsRegular.info;
  static const infoFill = PhosphorIconsFill.info;

  /// Phosphor's caret, not its chevron: the chevron cut is a heavier, wider
  /// arrowhead built for large controls and reads as a shouted `>` at the
  /// size a list row draws it.
  ///
  /// **Regular, where the rest of the set is Bold — deliberately.** A chevron
  /// is a passive affordance: it says "this row opens", it is not information.
  /// At Bold it out-weighted the mono value sitting next to it, so the row
  /// read as an arrow with some text rather than a value you can drill into.
  /// The rule is the same one type uses — secondary things take a lighter
  /// weight, not a smaller size alone.
  static const chevron = PhosphorIconsRegular.caretRight;
  static const chevronDown = PhosphorIconsRegular.caretDown;
  static const edit = PhosphorIconsRegular.pencilSimple;
  static const tag = PhosphorIconsRegular.tag;
  static const location = PhosphorIconsRegular.mapPin;
  static const caption = PhosphorIconsRegular.textT;

  // Profile & account.
  static const settings = PhosphorIconsRegular.gear;
  static const idCard = PhosphorIconsRegular.identificationCard;
  static const cake = PhosphorIconsRegular.cake;
  static const mail = PhosphorIconsRegular.envelope;
  static const key = PhosphorIconsRegular.key;
  static const apple = PhosphorIconsRegular.appleLogo;
  static const link = PhosphorIconsRegular.link;

  // Ask · chat & voice.
  static const chatNew = PhosphorIconsRegular.notePencil;
  // Ask settings (model + reply style) — a "faders" glyph reads as adjustments.
  static const replyStyle = PhosphorIconsRegular.fadersHorizontal;
  static const mic = PhosphorIconsRegular.microphone;
  static const stopCircle = PhosphorIconsRegular.stopCircle;
  static const waveform = PhosphorIconsRegular.waveform;
  static const send = PhosphorIconsRegular.arrowUp;

  // Settings · about.
  static const privacy = PhosphorIconsRegular.shieldCheck;

  /// Settings' language row. Named here rather than reached for as
  /// `Icons.translate_rounded` at the call site: Material Rounded is a
  /// different design grid and a heavier optical weight than Phosphor, and one
  /// Material glyph in a Phosphor column is visible even when you can't name
  /// it.
  static const language = PhosphorIconsRegular.translate;

  // Music.
  static const music = PhosphorIconsRegular.musicNote;
  static const shuffle = PhosphorIconsRegular.shuffle;
  static const repeat = PhosphorIconsRegular.repeat;
  static const repeatOne = PhosphorIconsRegular.repeatOnce;
  static const headphones = PhosphorIconsRegular.headphones;
  static const bluetooth = PhosphorIconsRegular.bluetooth;
  static const speaker = PhosphorIconsRegular.speakerHigh;

  // Settings · media & backup.
  // `circleHalf` — Phosphor's appearance/contrast mark — rather than the bare
  // moon the Sleep module already owns: two rows in the app drawn with the
  // same glyph make the set read thin, and this row is an appearance readout
  // rather than anything to do with night.
  static const theme = PhosphorIconsRegular.circleHalf;
  static const photos = PhosphorIconsRegular.images;
  static const driveCloud = PhosphorIconsRegular.cloud;
  static const driveConnected = PhosphorIconsRegular.cloudCheck;
  static const backupNow = PhosphorIconsRegular.cloudArrowUp;
  static const schedule3Day = PhosphorIconsRegular.calendarDots;
  static const wifi = PhosphorIconsRegular.wifiHigh;
  static const disconnect = PhosphorIconsRegular.linkBreak;

  // Not the generic `info` — that mark belongs to [info], and Version sitting
  // under the same glyph as every explainer button flattens both. The package
  // is what a version names; the hammer is what built it.
  static const version = PhosphorIconsRegular.package;
  static const build = PhosphorIconsRegular.hammer;
  static const signOut = PhosphorIconsRegular.signOut;

  // Toast / status glyphs.
  static const success = PhosphorIconsRegular.sealCheck;
  static const warning = PhosphorIconsRegular.warningCircle;

  // Expense categories — the vocabulary a category (built-in or user-created)
  // picks its mark from. These replaced literal emoji, which identity §4/§8
  // rule out twice: emoji render differently per-OS and instantly break the
  // otherwise-custom feel. Mapped from `CategoryIcon` in the expenses feature's
  // `category_icons.dart`, the same way hues map through `category_hue_colors`.
  static const catFood = PhosphorIconsRegular.bowlFood;
  static const catCoffee = PhosphorIconsRegular.coffee;
  static const catTransport = PhosphorIconsRegular.taxi;
  static const catGroceries = PhosphorIconsRegular.shoppingCart;
  static const catShopping = PhosphorIconsRegular.shoppingBag;
  static const catEntertainment = PhosphorIconsRegular.filmSlate;
  static const catHome = PhosphorIconsRegular.house;
  static const catHealth = PhosphorIconsRegular.pill;
  static const catEducation = PhosphorIconsRegular.graduationCap;
  static const catTravel = PhosphorIconsRegular.airplaneTilt;
  static const catPets = PhosphorIconsRegular.pawPrint;
  static const catGifts = PhosphorIconsRegular.gift;
  static const catUtilities = PhosphorIconsRegular.lightbulb;
  static const catPhone = PhosphorIconsRegular.deviceMobile;
  static const catGames = PhosphorIconsRegular.gameController;
  static const catDrinks = PhosphorIconsRegular.beerStein;
  static const catCar = PhosphorIconsRegular.car;
  static const catFitness = PhosphorIconsRegular.barbell;
  static const catBooks = PhosphorIconsRegular.bookOpen;
  static const catGrooming = PhosphorIconsRegular.scissors;
  static const catMusic = PhosphorIconsRegular.musicNote;
  static const catParking = PhosphorIconsRegular.carProfile;
  static const catBills = PhosphorIconsRegular.receipt;
  static const catPersonalCare = PhosphorIconsRegular.shower;
  static const catOther = PhosphorIconsRegular.tag;
}
