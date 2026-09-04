import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/domain/media_kind.dart';
import '../../../../core/media/presentation/media_image.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/session_status.dart';
import '../../../workout/domain/training_volume.dart';
import '../../../auth/domain/auth_user.dart';
import '../../../shell/presentation/widgets/bottom_chrome.dart';
import '../../domain/user_profile.dart';
import '../widgets/dob_picker_sheet.dart';
import '../../../../core/widgets/settings_row.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../auth/presentation/pages/settings_page.dart';
import '../../../../core/util/date_format.dart';

/// The "You" surface: identity at a glance, an editable about-me + account
/// section, and a way into [SettingsPage]. Reads the live [UserProfile]
/// (name, date of birth, bio, photo) alongside the [AuthUser] auth identity
/// (email + sign-in provider) so every real piece of data ZIVO holds about
/// the signed-in person has a home here.
///
/// Dressed to the design handoff's **You** screen (2b): the warm screen wash,
/// a centred 96px avatar inside an ember progress ring with its camera badge,
/// the name, the verified email line, then a 3-up mono stat card, the dashed
/// About prompt, and the ACCOUNT / SIGN-IN lists.
///
/// The ring is not decoration — it reads how complete this profile is (see
/// [_profileCompleteness]), which is exactly what the sections beneath it
/// invite you to finish. Ember, because filling it in IS the one committing
/// action this screen offers.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _editName(BuildContext context, UserProfile profile) async {
    final name = await showZivoSheet<String>(
      context: context,
      builder: (_) => _EditTextSheet(
        title: 'Edit name',
        hint: 'Your name',
        maxLength: 60,
        initial: profile.name,
        capitalizeWords: true,
      ),
    );
    if (name == null || !context.mounted) return;
    await AppScope.of(context).profiles.saveProfile(
      uid: profile.uid,
      name: name,
      dateOfBirth: profile.dateOfBirth,
      photoPath: profile.photoPath,
      bio: profile.bio,
    );
  }

  Future<void> _editDob(BuildContext context, UserProfile profile) async {
    final picked = await showDobPicker(context, initial: profile.dateOfBirth);
    if (picked == null || !context.mounted) return;
    await AppScope.of(context).profiles.saveProfile(
      uid: profile.uid,
      name: profile.name,
      dateOfBirth: picked,
      photoPath: profile.photoPath,
      bio: profile.bio,
    );
  }

  Future<void> _changePhoto(BuildContext context, UserProfile profile) async {
    final action = await showCupertinoModalPopup<_PhotoAction>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Profile Photo'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, _PhotoAction.choose),
            child: const Text('Choose Photo'),
          ),
          if (profile.photoPath != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(sheetContext, _PhotoAction.remove),
              child: const Text('Remove Photo'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    if (action == _PhotoAction.choose) {
      // Pick at a generous size so the crop editor has real pixels to work
      // with; the circular crop below produces the final square avatar.
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
      if (picked == null || !context.mounted) return;
      // Guide the crop to the avatar's own shape: a locked 1:1 circular frame,
      // so what the person positions is exactly what lands in the circle — no
      // blind cover-cropping of a rectangle. Backing out cancels the change.
      final cropped = await _cropAvatar(picked.path);
      if (cropped == null || !context.mounted) return;
      // Route the avatar through the media pipeline: durable local copy +
      // registry entry + any enabled backup targets. Returns the store
      // reference persisted on the profile (relative, so it survives reinstalls
      // that would strand an absolute path on iOS).
      final media = AppScope.of(context).requireMedia;
      final savedPath = await media.capture(
        sourcePath: cropped.path,
        kind: MediaKind.avatar,
        id: profile.uid,
        ownerUid: profile.uid,
      );
      if (!context.mounted) return;
      await AppScope.of(context).profiles.saveProfile(
        uid: profile.uid,
        name: profile.name,
        dateOfBirth: profile.dateOfBirth,
        photoPath: savedPath,
        bio: profile.bio,
      );
    } else {
      final scope = AppScope.of(context);
      final oldPath = profile.photoPath;
      await scope.profiles.saveProfile(
        uid: profile.uid,
        name: profile.name,
        dateOfBirth: profile.dateOfBirth,
        photoPath: null,
        bio: profile.bio,
      );
      if (oldPath != null) {
        // Best-effort: remove the local file and its registry entry.
        await scope.requireMedia.deleteMedia(id: profile.uid, ref: oldPath);
      }
    }
  }

  /// The premium avatar editor — the same native cropper the moments capture
  /// flow uses (`image_cropper`), here locked to a 1:1 **circular** frame and
  /// themed to ZIVO. Returns the cropped file, or null if the person backs
  /// out. "Move & Scale" so the circle previews exactly what will be saved.
  Future<CroppedFile?> _cropAvatar(String sourcePath) {
    return ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 92,
      uiSettings: [
        IOSUiSettings(
          title: 'Move & Scale',
          doneButtonTitle: 'Choose',
          cancelButtonTitle: 'Cancel',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          aspectRatioPickerButtonHidden: true,
          resetAspectRatioEnabled: false,
        ),
        AndroidUiSettings(
          toolbarTitle: 'Edit Photo',
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
          hideBottomControls: false,
          toolbarColor: TrainColors.base,
          toolbarWidgetColor: TrainColors.ink,
          backgroundColor: TrainColors.base,
          activeControlsWidgetColor: TrainColors.ember,
          cropFrameColor: TrainColors.base,
          cropGridColor: TrainColors.hairlineStrong,
          statusBarLight: false,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final AuthUser? user = scope.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return TrainScreen(
      tint: TrainColors.youTint,
      child: StreamBuilder<UserProfile?>(
        stream: scope.profiles.watchProfile(user.uid),
        initialData: null,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          return SingleChildScrollView(
            // A downward drag puts the keyboard away. The About card is
            // edited in place with a multi-line field, whose Return key
            // inserts a newline rather than closing anything — so without
            // this (and the field's own tap-outside) the only exits were the
            // Cancel/Save pair the keyboard was sitting on top of.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            // The page scrolls UNDER the bottom object — the floating tab bar
            // plus the now-playing strip fused to it (the shell runs
            // `extendBody: true`). [BottomChrome] is that object's live
            // measured height, so the SIGN-IN card clears it whether or not
            // music is playing.
            padding: EdgeInsets.fromLTRB(
              22,
              12,
              22,
              BottomChrome.of(context) + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // No screen title here: on this one surface the
                // avatar IS the header, so the row above it carries
                // nothing but the single way out to Settings.
                RiseIn(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TrainCircleButton(
                      semanticLabel: 'Settings',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      ),
                      child: const Icon(
                        AppIcons.settings,
                        size: 16,
                        color: Color(0xB2F4F4F0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                RiseIn(
                  delay: const Duration(milliseconds: 50),
                  child: _ProfileHeader(
                    user: user,
                    profile: profile,
                    onTapAvatar: profile == null
                        ? null
                        : () => _changePhoto(context, profile),
                  ),
                ),
                const SizedBox(height: 26),
                RiseIn(
                  delay: const Duration(milliseconds: 70),
                  child: _LifetimeStats(user: user),
                ),
                const SizedBox(height: 26),
                RiseIn(
                  delay: const Duration(milliseconds: 90),
                  child: _AboutSection(
                    bio: profile?.bio,
                    onSave: profile == null
                        ? null
                        : (bio) => AppScope.of(context).profiles.saveProfile(
                            uid: profile.uid,
                            name: profile.name,
                            dateOfBirth: profile.dateOfBirth,
                            photoPath: profile.photoPath,
                            bio: bio,
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                RiseIn(
                  delay: const Duration(milliseconds: 130),
                  child: SettingsSectionCard(
                    label: 'ACCOUNT',
                    children: [
                      SettingsRow(
                        icon: AppIcons.idCard,
                        title: 'Name',
                        value: profile?.name ?? '—',
                        accent: TrainColors.violetGlyph,
                        onTap: profile == null
                            ? null
                            : () => _editName(context, profile),
                      ),
                      SettingsRow(
                        icon: AppIcons.cake,
                        title: 'Date of birth',
                        value: profile == null
                            ? '—'
                            : _formatDob(context, profile.dateOfBirth),
                        accent: TrainColors.violetGlyph,
                        last: true,
                        onTap: profile == null
                            ? null
                            : () => _editDob(context, profile),
                      ),
                      // Email intentionally NOT repeated here — it's
                      // the hero line under the name (with its
                      // verification badge); a second copy below read
                      // as filler, not information.
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                RiseIn(
                  delay: const Duration(milliseconds: 170),
                  child: SettingsSectionCard(
                    label: 'SIGN-IN',
                    children: [
                      for (var i = 0; i < user.providerIds.length; i++)
                        SettingsRow(
                          icon: _providerIcon(user.providerIds[i]),
                          iconWidget: _providerLogo(user.providerIds[i]),
                          title: _providerLabel(user.providerIds[i]),
                          // The state badge replaces the value
                          // column outright: "connected" is a state,
                          // and green is what state looks like here.
                          value: '',
                          trailing: const _ConnectedBadge(),
                          // The amber key is the one sign-in mark
                          // that owns a hue of its own; brand marks
                          // stay on the neutral tile so no fake
                          // branding.
                          accent: user.providerIds[i] == 'password'
                              ? TrainColors.amber
                              : null,
                          last: i == user.providerIds.length - 1,
                        ),
                      if (user.providerIds.isEmpty)
                        const SettingsRow(
                          icon: AppIcons.key,
                          title: 'Email',
                          value: '',
                          trailing: _ConnectedBadge(),
                          accent: TrainColors.violetGlyph,
                          last: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _providerLabel(String id) => switch (id) {
    'password' => 'Email & password',
    'google.com' => 'Google',
    'apple.com' => 'Apple',
    _ => id,
  };

  static IconData _providerIcon(String id) => switch (id) {
    'password' => AppIcons.key,
    'apple.com' => AppIcons.apple,
    // Google renders its real mark via [_providerLogo]; this neutral glyph is
    // only a fallback should the bundled logo ever fail to load.
    _ => AppIcons.link,
  };

  /// The official brand mark for a provider, shown inside the row's leading
  /// chip instead of a glyph. Google ships the genuine four-color "G"
  /// (bundled from Google's brand assets, never recolored) — the same pattern
  /// as the Spotify mark in Settings. Others fall back to [_providerIcon].
  static Widget? _providerLogo(String id) => switch (id) {
    'google.com' => Image.asset(
      'assets/google/google-icon.png',
      width: 18,
      height: 18,
      filterQuality: FilterQuality.medium,
    ),
    _ => null,
  };

  static String _formatDob(BuildContext context, DateTime d) {
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return '${formatDayMonthYear(context, d).toUpperCase()} · $age';
  }
}

enum _PhotoAction { choose, remove }

/// Avatar + name + verified email — the identity hero. The email carries its
/// verification state as a small green check and a `VERIFIED` caption; an
/// unverified address says so in amber instead, because "unverified" is
/// something to act on, not a neutral fact.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.profile,
    required this.onTapAvatar,
  });

  final AuthUser user;
  final UserProfile? profile;
  final VoidCallback? onTapAvatar;

  String get _name {
    final profileName = profile?.name.trim();
    if (profileName != null && profileName.isNotEmpty) return profileName;
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return 'Signed in';
  }

  @override
  Widget build(BuildContext context) {
    final verified = user.isEmailVerified;
    return Column(
      children: [
        _Avatar(
          name: _name,
          photoPath: profile?.photoPath,
          onTap: onTapAvatar,
          completeness: _profileCompleteness(user, profile),
        ),
        const SizedBox(height: 16),
        Text(
          _name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TrainType.ui(
            size: 26,
            weight: FontWeight.w800,
            tracking: -0.025,
            color: TrainColors.ink,
            height: 1,
          ),
        ),
        if (user.email != null) ...[
          const SizedBox(height: 9),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  user.email!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TrainType.mono(size: 12, color: TrainColors.ink2),
                ),
              ),
              const SizedBox(width: 7),
              Icon(
                verified ? AppIcons.success : AppIcons.warning,
                size: 13,
                color: verified ? TrainColors.green : TrainColors.amber,
              ),
              const SizedBox(width: 6),
              Text(
                verified ? 'VERIFIED' : 'UNVERIFIED',
                style: TrainType.caption(
                  size: 8.5,
                  tracking: 0.14,
                  weight: FontWeight.w600,
                  color: (verified ? TrainColors.green : TrainColors.amber)
                      .withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// How much of this profile is actually filled in, 0..1 — what the avatar's
/// ember ring reports. Five equal parts: a name, a date of birth, a photo, a
/// bio, and a verified email. Every one of them is something a section
/// further down this same screen can complete, so the ring always points at
/// work the screen itself can finish.
double _profileCompleteness(AuthUser user, UserProfile? profile) {
  var filled = user.isEmailVerified ? 1 : 0;
  if (profile != null) {
    if (profile.name.trim().isNotEmpty) filled++;
    if (profile.photoPath != null) filled++;
    if ((profile.bio ?? '').trim().isNotEmpty) filled++;
    // A default-constructed profile carries today's date; treat a DOB that
    // isn't plausibly a birthday as unset rather than claiming credit for it.
    if (DateTime.now().difference(profile.dateOfBirth).inDays > 366) filled++;
  }
  return filled / 5;
}

/// The green `CONNECTED` state badge on a sign-in row — a dot plus a mono
/// caption, which is what "state" looks like everywhere else in this system.
class _ConnectedBadge extends StatelessWidget {
  const _ConnectedBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: TrainColors.green,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'CONNECTED',
          style: TrainType.caption(
            size: 9,
            tracking: 0.14,
            weight: FontWeight.w600,
            color: TrainColors.green.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

/// The 3-up lifetime readout under the identity: sessions trained, months
/// since the account was created, and every kilogram ever moved.
///
/// Reads the sessions stream directly rather than taking a snapshot — this
/// card sits on a tab that stays mounted, so a session finished elsewhere in
/// the app should be reflected here without a remount.
class _LifetimeStats extends StatelessWidget {
  const _LifetimeStats({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <LiveSession>[];
        final completed = sessions
            .where((s) => s.status == SessionStatus.completed)
            .length;
        final volume = formatVolume(lifetimeVolumeKg(sessions));
        final months = _monthsSince(user.createdAt);

        return TrainCard(
          radius: 20,
          padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 4),
          child: TrainStatStrip(
            items: [
              TrainStat('$completed', 'Sessions'),
              TrainStat(months == null ? '—' : '$months', 'Months in'),
              // The one figure here that means progress rather than
              // description, so it gets the green.
              TrainStat(
                '${volume.value}${volume.unit.toLowerCase()}',
                'Lifetime',
                color: TrainColors.green,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Whole months between [since] and now, or null when the account's creation
/// date isn't known (some providers withhold it) — a dash beats a zero that
/// looks like a real reading.
int? _monthsSince(DateTime? since) {
  if (since == null) return null;
  final now = DateTime.now();
  final months = (now.year - since.year) * 12 + (now.month - since.month);
  return months < 0 ? 0 : months;
}

/// The identity avatar, inside its own ember progress ring.
///
/// The photo (or a monogram disc) fills the ring's inside; the ring itself
/// reports [completeness] — how much of the profile is filled in — and the
/// ember camera badge marks the whole thing tappable, the standard iOS
/// "edit photo" affordance.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.photoPath,
    required this.onTap,
    required this.completeness,
  });

  final String name;
  final String? photoPath;
  final VoidCallback? onTap;

  /// 0..1 — the fraction of the ember ring that is drawn.
  final double completeness;

  static const double _size = 96;

  /// The disc inside the ring, inset so the stroke never touches the photo.
  static const double _inset = 8;

  String get _initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words.first.substring(0, 1) + words.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final path = photoPath;

    // The monogram is the base layer; when a stored photo resolves it covers
    // the circle. Resolution is async (the media store maps the ref to a file),
    // so we can't decide sync — the disc stays behind and the photo, when
    // present, paints over it. A missing/stale ref falls back to the monogram.
    final monogram = Text(
      _initials,
      style: TrainType.ui(
        size: 32,
        weight: FontWeight.w700,
        color: TrainColors.ink,
        height: 1,
      ),
    );
    final disc = Container(
      width: _size - _inset * 2,
      height: _size - _inset * 2,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: TrainColors.glassStrong,
      ),
      child: path == null
          ? monogram
          : SizedBox.expand(
              child: MediaImage(
                service: AppScope.of(context).requireMedia,
                ref: path,
                fit: BoxFit.cover,
                placeholder: Center(child: monogram),
              ),
            ),
    );

    return PressableScale(
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: completeness.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) =>
                      CustomPaint(painter: _AvatarRingPainter(t)),
                ),
              ),
              disc,
              if (onTap != null)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TrainColors.ember,
                      // The badge punches a hole in the ring rather than
                      // floating over it — the border is the page's own
                      // ground colour, not a shadow.
                      border: Border.all(
                        color: const Color(0xFF0B0A09),
                        width: 2.5,
                      ),
                    ),
                    child: const Icon(
                      AppIcons.camera,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 2px ember arc around the avatar: a hairline track with the completed
/// fraction drawn over it, round-capped, starting at 12 o'clock.
class _AvatarRingPainter extends CustomPainter {
  const _AvatarRingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 3;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = TrainColors.hairline,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = TrainColors.ember,
    );
  }

  @override
  bool shouldRepaint(_AvatarRingPainter old) => old.progress != progress;
}

/// The "About" section — a short bio the person writes about themselves,
/// edited **in place**. Tapping the card (or its pencil) turns the card
/// itself into the editor: an inline field, a live counter, and Cancel /
/// Save — the card grows to fit what's typed, so nothing ever leaves the
/// page or looks cramped. A muted prompt stands in until a bio is set.
class _AboutSection extends StatefulWidget {
  const _AboutSection({required this.bio, required this.onSave});

  final String? bio;

  /// Persists the new bio (null clears it). When null the section is
  /// read-only — the brief loading state before the profile resolves.
  final Future<void> Function(String? bio)? onSave;

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  static const int _maxLength = 160;

  late final TextEditingController _controller = TextEditingController(
    text: widget.bio ?? '',
  );
  final FocusNode _focus = FocusNode();
  bool _editing = false;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _AboutSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Track live profile updates while we're not actively editing.
    if (!_editing && widget.bio != oldWidget.bio) {
      _controller.text = widget.bio ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (widget.onSave == null) return;
    _controller.text = widget.bio ?? '';
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      // Put the WHOLE card - field, counter and the Cancel/Save pair - above
      // the keyboard, not just the caret. `alignment: 1.0` parks its bottom
      // edge at the bottom of the (already keyboard-shortened) viewport;
      // without it the field scrolled itself just far enough to show the
      // cursor and left the two buttons under the keyboard, with no way to
      // reach them and - on a multi-line field, whose Return key inserts a
      // newline - no way to put the keyboard down either.
      Scrollable.ensureVisible(
        context,
        alignment: 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _cancel() {
    _focus.unfocus();
    setState(() {
      _controller.text = widget.bio ?? '';
      _editing = false;
    });
  }

  Future<void> _save() async {
    final onSave = widget.onSave;
    if (onSave == null || _saving) return;
    final text = _controller.text.trim();
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    await onSave(text.isEmpty ? null : text);
    if (!mounted) return;
    _focus.unfocus();
    setState(() {
      _saving = false;
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.onSave != null;
    final trimmed = widget.bio?.trim();
    final hasBio = trimmed != null && trimmed.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 11),
          child: TrainSectionLabel('About'),
        ),
        // Empty and unfilled, the card is DASHED — an outline, not a surface.
        // A solid card with a prompt inside reads as a real container waiting
        // on data, which the identity doc rules out (§8).
        if (!hasBio && !_editing)
          TrainDashedCard(
            onTap: editable ? _startEditing : null,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add a few words about yourself.',
                    style: TrainType.ui(
                      size: 13.5,
                      weight: FontWeight.w400,
                      color: TrainColors.ink4,
                      height: 1.4,
                    ),
                  ),
                ),
                if (editable) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x24FFFFFF)),
                    ),
                    child: const Icon(
                      AppIcons.add,
                      size: 12,
                      color: Color(0x99F4F4F0),
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          _buildFilledCard(editable: editable, bio: trimmed ?? ''),
      ],
    );
  }

  /// The written (or being-written) state: a real card, because now there IS
  /// something in it. Editing tints the edge ember — the one moment on this
  /// screen with an action waiting to be committed.
  Widget _buildFilledCard({required bool editable, required String bio}) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: TrainColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _editing
              ? TrainColors.ember.withValues(alpha: 0.45)
              : TrainColors.hairline,
        ),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _editing
            ? _buildEditor()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      bio,
                      style: TrainType.ui(
                        size: 13.5,
                        weight: FontWeight.w400,
                        color: TrainColors.ink2,
                        height: 1.55,
                      ),
                    ),
                  ),
                  if (editable) ...[
                    const SizedBox(width: 12),
                    const Icon(
                      AppIcons.edit,
                      size: 13,
                      color: Color(0x66F4F4F0),
                    ),
                  ],
                ],
              ),
      ),
    );

    // In edit mode the card is a live field, so it isn't a button; likewise
    // while the profile is still loading (no save handler).
    if (!editable || _editing) return card;
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _startEditing,
          child: card,
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          maxLines: null,
          minLines: 2,
          maxLength: _maxLength,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: TrainColors.ember,
          // A tap anywhere off the card puts the keyboard down. A multi-line
          // field's Return key makes a newline, so it cannot close its own
          // keyboard - and Flutter only dismisses on tap-outside by default
          // on desktop.
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onChanged: (_) => setState(() {}),
          style: TrainType.ui(
            size: 13.5,
            weight: FontWeight.w400,
            color: TrainColors.ink,
            height: 1.55,
          ),
          decoration: InputDecoration(
            isCollapsed: true,
            counterText: '',
            border: InputBorder.none,
            hintText: 'A few words about yourself…',
            hintStyle: TrainType.ui(
              size: 13.5,
              weight: FontWeight.w400,
              color: TrainColors.ink4,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '${_controller.text.length} / $_maxLength',
              style: TrainType.mono(size: 10.5, color: TrainColors.ink4),
            ),
            const Spacer(),
            _AboutButton(label: 'Cancel', onTap: _saving ? null : _cancel),
            const SizedBox(width: 6),
            _AboutButton(
              label: 'Save',
              primary: true,
              busy: _saving,
              onTap: _saving ? null : _save,
            ),
          ],
        ),
      ],
    );
  }
}

/// A small pill action for the inline About editor — a ghost text button
/// (Cancel) or the ember primary (Save), which shows a spinner while saving.
class _AboutButton extends StatelessWidget {
  const _AboutButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: EdgeInsets.symmetric(horizontal: primary ? 18 : 14, vertical: 9),
      decoration: primary
          ? BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFF7038), TrainColors.ember],
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: TrainColors.actionGlow(TrainColors.ember),
            )
          : null,
      child: busy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : Text(
              label,
              style: AppText.button.copyWith(
                fontSize: 14,
                color: primary ? Colors.white : TrainColors.ink3,
              ),
            ),
    );
    return PressableScale(
      enabled: onTap != null,
      child: Opacity(
        opacity: (onTap == null && !busy) ? 0.5 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet with one single-line text field (the Name editor), capped
/// at [maxLength] with a live counter. `initial` supplies the starting text
/// (kept out of the const constructor since a [TextEditingController] can't
/// be const). The About bio is edited inline on the page — see
/// [_AboutSection] — not here.
class _EditTextSheet extends StatefulWidget {
  const _EditTextSheet({
    required this.title,
    required this.hint,
    required this.maxLength,
    required this.initial,
    this.capitalizeWords = false,
  });

  final String title;
  final String hint;
  final int maxLength;
  final String initial;
  final bool capitalizeWords;

  @override
  State<_EditTextSheet> createState() => _EditTextSheetState();
}

class _EditTextSheetState extends State<_EditTextSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  bool get _canSave => _text.text.trim().isNotEmpty;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSave) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    // Premium edit surface: the sheet material is a translucent, blurred
    // glass card (the backdrop dims + blurs behind it) rather than a flat
    // opaque strip — the same material language as the workout start
    // confirm. Keyboard insets ride the padding so the field stays visible
    // while typing.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: TrainColors.raised.withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: TrainColors.hairlineStrong),
          ),
          padding: EdgeInsets.only(
            top: 12,
            left: 22,
            right: 22,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: const ZivoSheetHandle()),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 12),
                child: Text(widget.title, style: AppText.cardTitle),
              ),
              TextField(
                controller: _text,
                autofocus: true,
                maxLength: widget.maxLength,
                maxLines: 1,
                textCapitalization: widget.capitalizeWords
                    ? TextCapitalization.words
                    : TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (_) => setState(() {}),
                cursorColor: TrainColors.ember,
                style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  counterStyle: AppText.meta.copyWith(
                    color: TrainColors.ink3,
                    fontSize: 11,
                  ),
                  border: const UnderlineInputBorder(
                    borderSide: BorderSide(color: TrainColors.hairline),
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: TrainColors.hairline),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: TrainColors.ember,
                      width: 1.6,
                    ),
                  ),
                  hintText: widget.hint,
                  hintStyle: AppText.rowTitle.copyWith(color: TrainColors.ink3),
                ),
              ),
              const SizedBox(height: 22),
              Opacity(
                opacity: _canSave ? 1 : 0.45,
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [const Color(0xFFFF7038), TrainColors.ember],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: TrainColors.actionGlow(TrainColors.ember),
                    ),
                    child: InkWell(
                      onTap: _canSave ? _submit : null,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              AppIcons.check,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Save',
                              style: AppText.button.copyWith(
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// The date-of-birth wheel now lives in the shared `DobPickerSheet`
// (widgets/dob_picker_sheet.dart) so first-run onboarding and this edit
// surface present the identical picker — see `_editDob`.
