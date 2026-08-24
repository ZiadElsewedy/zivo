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
  static const edit = LucideIcons.pencil;
  static const location = LucideIcons.mapPin;
  static const caption = LucideIcons.type;

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
}
