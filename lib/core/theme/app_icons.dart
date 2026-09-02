import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The app's single icon vocabulary — Lucide Icons mapped to semantic names, so
/// every surface uses one consistent, premium line-icon set instead of ad-hoc
/// `Icons.*`. Lucide is a single uniform weight; "active"/emphasis states use
/// the same glyph and lean on colour rather than a filled variant.
///
/// Values are `IconData`, so they drop into the standard `Icon(...)` widget.
class AppIcons {
  AppIcons._();

  // Bottom navigation (fill == same glyph; active state is a colour change).
  static const today = LucideIcons.house;
  static const todayFill = LucideIcons.house;
  static const hub = LucideIcons.layoutGrid;
  static const hubFill = LucideIcons.layoutGrid;
  static const ask = LucideIcons.sparkles;
  static const askFill = LucideIcons.sparkles;
  static const you = LucideIcons.user;
  static const youFill = LucideIcons.user;

  // Hub modules.
  static const workout = LucideIcons.dumbbell;
  static const diet = LucideIcons.utensilsCrossed;
  static const expenses = LucideIcons.wallet;
  static const moments = LucideIcons.images;

  // Training analytics & sessions.
  static const analysis = LucideIcons.chartNoAxesCombined;
  static const trendUp = LucideIcons.trendingUp;
  static const trendDown = LucideIcons.trendingDown;
  static const trophy = LucideIcons.trophy;
  static const history = LucideIcons.history;
  static const splits = LucideIcons.layers2;
  static const streak = LucideIcons.flame;
  static const timer = LucideIcons.timer;
  static const clock = LucideIcons.clock;
  static const scale = LucideIcons.scale;
  static const planDoc = LucideIcons.clipboardList;
  static const sessions = LucideIcons.activity;
  static const minus = LucideIcons.minus;
  static const calendarClock = LucideIcons.calendarClock;
  static const bolt = LucideIcons.zap;
  static const duplicate = LucideIcons.copy;
  static const pause = LucideIcons.pause;

  // Common actions / affordances.
  static const add = LucideIcons.plus;
  static const camera = LucideIcons.camera;
  static const image = LucideIcons.image;
  static const crop = LucideIcons.crop;
  static const retake = LucideIcons.refreshCw;
  static const trash = LucideIcons.trash2;
  static const check = LucideIcons.check;
  static const close = LucideIcons.x;
  static const back = LucideIcons.arrowLeft;
  static const info = LucideIcons.info;
  static const infoFill = LucideIcons.info;
  static const chevron = LucideIcons.chevronRight;
  static const chevronDown = LucideIcons.chevronDown;
  static const edit = LucideIcons.pencil;
  static const tag = LucideIcons.tag;
  static const location = LucideIcons.mapPin;
  static const caption = LucideIcons.type;

  // Profile & account.
  static const settings = LucideIcons.settings;
  static const idCard = LucideIcons.idCard;
  static const cake = LucideIcons.cake;
  static const mail = LucideIcons.mail;
  static const key = LucideIcons.keyRound;
  static const apple = LucideIcons.apple;
  static const link = LucideIcons.link;

  // Ask · chat & voice.
  static const chatNew = LucideIcons.messageSquarePlus;
  static const replyStyle = LucideIcons.slidersHorizontal;
  static const mic = LucideIcons.mic;
  static const stopCircle = LucideIcons.circleStop;
  static const waveform = LucideIcons.audioLines;
  static const send = LucideIcons.arrowUp;

  // Settings · about.
  static const privacy = LucideIcons.shieldCheck;

  // Music.
  static const music = LucideIcons.music;
  static const shuffle = LucideIcons.shuffle;
  static const repeat = LucideIcons.repeat;
  static const repeatOne = LucideIcons.repeat1;
  static const headphones = LucideIcons.headphones;
  static const bluetooth = LucideIcons.bluetooth;
  static const speaker = LucideIcons.volume2;

  // Settings · media & backup.
  static const theme = LucideIcons.moon;
  static const photos = LucideIcons.images;
  static const driveCloud = LucideIcons.cloud;
  static const driveConnected = LucideIcons.cloudCheck;
  static const backupNow = LucideIcons.cloudUpload;
  static const schedule3Day = LucideIcons.calendarDays;
  static const wifi = LucideIcons.wifi;
  static const disconnect = LucideIcons.unlink;
  static const version = LucideIcons.info;
  static const build = LucideIcons.wrench;
  static const signOut = LucideIcons.logOut;

  // Toast / status glyphs.
  static const success = LucideIcons.badgeCheck;
  static const warning = LucideIcons.circleAlert;

  // Expense categories — the vocabulary a category (built-in or user-created)
  // picks its mark from. These replaced literal emoji, which identity §4/§8
  // rule out twice: emoji render differently per-OS and instantly break the
  // otherwise-custom feel. Mapped from `CategoryIcon` in the expenses feature's
  // `category_icons.dart`, the same way hues map through `category_hue_colors`.
  static const catFood = LucideIcons.utensils;
  static const catCoffee = LucideIcons.coffee;
  static const catTransport = LucideIcons.carTaxiFront;
  static const catGroceries = LucideIcons.shoppingCart;
  static const catShopping = LucideIcons.shoppingBag;
  static const catEntertainment = LucideIcons.clapperboard;
  static const catHome = LucideIcons.house;
  static const catHealth = LucideIcons.pill;
  static const catEducation = LucideIcons.graduationCap;
  static const catTravel = LucideIcons.plane;
  static const catPets = LucideIcons.pawPrint;
  static const catGifts = LucideIcons.gift;
  static const catUtilities = LucideIcons.lightbulb;
  static const catPhone = LucideIcons.smartphone;
  static const catGames = LucideIcons.gamepad2;
  static const catDrinks = LucideIcons.beer;
  static const catCar = LucideIcons.car;
  static const catFitness = LucideIcons.dumbbell;
  static const catBooks = LucideIcons.bookOpen;
  static const catGrooming = LucideIcons.scissors;
  static const catMusic = LucideIcons.music;
  static const catParking = LucideIcons.circleParking;
  static const catBills = LucideIcons.receipt;
  static const catPersonalCare = LucideIcons.showerHead;
  static const catOther = LucideIcons.tag;
}
