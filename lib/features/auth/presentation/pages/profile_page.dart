
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/domain/media_kind.dart';
import '../../../../core/media/presentation/media_image.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/auth_user.dart';
import '../../domain/user_profile.dart';
import '../widgets/dob_picker_sheet.dart';
import '../../../../core/widgets/settings_row.dart';
import 'settings_page.dart';

/// The "You" surface: identity at a glance, an editable about-me + account
/// section, and a way into [SettingsPage]. Reads the live [UserProfile]
/// (name, date of birth, bio, photo) alongside the [AuthUser] auth identity
/// (email + sign-in provider) so every real piece of data ZIVO holds about
/// the signed-in person has a home here.
///
/// Shares Today & Hub's atmospheric backdrop (radial ground gradient + soft
/// aura blobs) so all the app's dashboard-grade surfaces read as one world,
/// and presents the identity as a hero: a gradient-ringed avatar glowing in
/// its own hue over the name it belongs to.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _editName(BuildContext context, UserProfile profile) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
          toolbarColor: AppColors.ground,
          toolbarWidgetColor: AppColors.ink,
          backgroundColor: AppColors.ground,
          activeControlsWidgetColor: AppColors.ember,
          cropFrameColor: AppColors.ground,
          cropGridColor: AppColors.hairline2,
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

    return Scaffold(
      backgroundColor: AppColors.ground,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.15,
            colors: [Color(0xFF231B14), AppColors.ground, Color(0xFF0E0B08)],
            stops: [0.0, 0.52, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Ambient depth — a warm glow behind the identity hero, a cool
            // counterweight lower down. Purely decorative.
            const Positioned(
              top: -50,
              right: -70,
              child: _AuraBlob(color: AppColors.ember, size: 230),
            ),
            const Positioned(
              top: 340,
              left: -90,
              child: _AuraBlob(color: AppColors.iris, size: 190),
            ),
            SafeArea(
              child: StreamBuilder<UserProfile?>(
                stream: scope.profiles.watchProfile(user.uid),
                initialData: null,
                builder: (context, snapshot) {
                  final profile = snapshot.data;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 44),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RiseIn(
                          child: Row(
                            children: [
                              Text('You', style: AppText.greeting),
                              const Spacer(),
                              _IconButton(
                                icon: AppIcons.settings,
                                semanticLabel: 'Settings',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const SettingsPage(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
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
                        const SizedBox(height: 28),
                        RiseIn(
                          delay: const Duration(milliseconds: 90),
                          child: _AboutSection(
                            bio: profile?.bio,
                            onSave: profile == null
                                ? null
                                : (bio) => AppScope.of(context)
                                      .profiles
                                      .saveProfile(
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
                                accent: AppColors.ember,
                                onTap: profile == null
                                    ? null
                                    : () => _editName(context, profile),
                              ),
                              SettingsRow(
                                icon: AppIcons.cake,
                                title: 'Date of birth',
                                value: profile == null
                                    ? '—'
                                    : _formatDob(profile.dateOfBirth),
                                accent: AppColors.flare,
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
                                  value: 'Connected',
                                  // The gold key is the one sign-in mark that
                                  // owns a hue of its own; brand marks stay on
                                  // the neutral chip so no fake branding.
                                  accent: user.providerIds[i] == 'password'
                                      ? AppColors.solar
                                      : null,
                                  last: i == user.providerIds.length - 1,
                                ),
                              if (user.providerIds.isEmpty)
                                const SettingsRow(
                                  icon: AppIcons.key,
                                  title: 'Email',
                                  value: 'Connected',
                                  accent: AppColors.solar,
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
            ),
          ],
        ),
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

  static String _formatDob(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return '${d.day} ${months[d.month - 1]} ${d.year} · $age yrs';
  }
}

enum _PhotoAction { choose, remove }

/// A soft, blurred wash of color floating behind the content — the quiet
/// "energy" glow shared with Today and Hub. Purely decorative.
class _AuraBlob extends StatelessWidget {
  const _AuraBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // A radial gradient, not an ImageFiltered blur — visually the
          // same soft glow at a fraction of the GPU cost, which matters
          // during page transitions (blur layers repaint per frame).
          gradient: RadialGradient(
            colors: [
              // Softened so the ambient glow never competes with content.
              color.withValues(alpha: 0.10),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small circular icon button — the same 34px chip language as
/// `CaptureIconButton`, kept local since this page's chip is neutral
/// (surfaceRaised + hairline edge) rather than capture-flow-branded.
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Tooltip(
        message: semanticLabel,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Icon(icon, size: 19, color: AppColors.ink2),
          ),
        ),
      ),
    );
  }
}

/// Avatar + name + verified email — the identity hero above the account
/// details. The email carries its verification state as a small meaningful
/// badge (pulse check when verified, solar alert when not).
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
    return Column(
      children: [
        _Avatar(
          name: _name,
          photoPath: profile?.photoPath,
          onTap: onTapAvatar,
        ),
        const SizedBox(height: 18),
        Text(
          _name,
          style: AppText.cardTitle.copyWith(fontSize: 24),
          textAlign: TextAlign.center,
        ),
        if (user.email != null) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  user.email!,
                  style: AppText.body.copyWith(fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                user.isEmailVerified ? AppIcons.success : AppIcons.warning,
                size: 15,
                color: user.isEmailVerified ? AppColors.pulse : AppColors.solar,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The identity avatar. Shows the saved photo when one exists; otherwise a
/// monogram over a calm, warm-charcoal disc — no colored ring, no glow, so
/// the person (not a hue) is the hero. A single hairline edge and a soft
/// neutral shadow give it just enough lift. A small ember camera badge marks
/// it tappable — the standard iOS "edit photo" affordance.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.photoPath,
    required this.onTap,
  });

  final String name;
  final String? photoPath;
  final VoidCallback? onTap;

  static const double _size = 96;

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
      style: AppText.cardTitle.copyWith(fontSize: 34, color: AppColors.ink),
    );
    final circle = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // A calm warm-charcoal disc (surface step lighter at the top-left),
        // a single hairline edge, and a soft *neutral* lift — no hue, no glow.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceRaised, AppColors.card],
        ),
        border: Border.all(color: AppColors.hairline2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 28,
            spreadRadius: -10,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: path == null
          ? monogram
          : SizedBox(
              width: _size,
              height: _size,
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            circle,
            if (onTap != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.ember,
                    border: Border.all(color: AppColors.ground, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: -2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    AppIcons.camera,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
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

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: _editing
              ? AppColors.ember.withValues(alpha: 0.55)
              : AppColors.hairline,
        ),
        boxShadow: AppShadows.card,
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('ABOUT', style: AppText.sectionLabel),
                const Spacer(),
                if (editable && !_editing)
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.hairline2),
                    ),
                    child: Icon(
                      hasBio ? AppIcons.edit : AppIcons.add,
                      size: 13,
                      color: AppColors.ink3,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_editing)
              _buildEditor()
            else
              Text(
                hasBio ? trimmed : 'Add a few words about yourself.',
                style: AppText.body.copyWith(
                  color: hasBio ? AppColors.ink2 : AppColors.ink3,
                  fontSize: 14.5,
                  height: 1.55,
                ),
              ),
          ],
        ),
      ),
    );

    // In edit mode the card is a live field, so it isn't a button; likewise
    // while the profile is still loading (no save handler).
    if (!editable || _editing) return card;
    return PressableScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: _startEditing,
        child: card,
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
          cursorColor: AppColors.ember,
          onChanged: (_) => setState(() {}),
          style: AppText.body.copyWith(
            color: AppColors.ink,
            fontSize: 14.5,
            height: 1.55,
          ),
          decoration: InputDecoration(
            isCollapsed: true,
            counterText: '',
            border: InputBorder.none,
            hintText: 'A few words about yourself…',
            hintStyle: AppText.body.copyWith(
              color: AppColors.ink3,
              fontSize: 14.5,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '${_controller.text.length} / $_maxLength',
              style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 11),
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
                colors: [Color(0xFFFF7038), AppColors.ember],
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: AppShadows.ember,
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
                color: primary ? Colors.white : AppColors.ink3,
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
            color: AppColors.card.withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: AppColors.hairline2),
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
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
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
                cursorColor: AppColors.ember,
                style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  counterStyle: AppText.meta.copyWith(
                    color: AppColors.ink3,
                    fontSize: 11,
                  ),
                  border: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.hairline),
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.hairline),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.ember, width: 1.6),
                  ),
                  hintText: widget.hint,
                  hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
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
                        colors: [const Color(0xFFFF7038), AppColors.ember],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: AppShadows.ember,
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
