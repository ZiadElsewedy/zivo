import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/domain/media_kind.dart';
import '../../../../core/media/presentation/media_image.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/auth_user.dart';
import '../../domain/user_profile.dart';
import '../../../../core/widgets/settings_row.dart';
import 'settings_page.dart';

/// The "You" surface: identity at a glance, an editable about-me + account
/// section, and a way into [SettingsPage]. Reads the live [UserProfile]
/// (name, date of birth, bio, photo) alongside the [AuthUser] auth identity
/// (email + sign-in provider) so every real piece of data ZIVO holds about
/// the signed-in person has a home here.
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

  Future<void> _editBio(BuildContext context, UserProfile profile) async {
    final bio = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditTextSheet(
        title: 'About you',
        hint: 'A few words about yourself…',
        maxLength: 160,
        initial: profile.bio ?? '',
        multiline: true,
      ),
    );
    if (bio == null || !context.mounted) return;
    await AppScope.of(context).profiles.saveProfile(
          uid: profile.uid,
          name: profile.name,
          dateOfBirth: profile.dateOfBirth,
          photoPath: profile.photoPath,
          bio: bio.isEmpty ? null : bio,
        );
  }

  Future<void> _editDob(BuildContext context, UserProfile profile) async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DobPickerSheet(initial: profile.dateOfBirth),
    );
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
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (picked == null || !context.mounted) return;
      // Route the avatar through the media pipeline: durable local copy +
      // registry entry + any enabled backup targets. Returns the store
      // reference persisted on the profile (relative, so it survives reinstalls
      // that would strand an absolute path on iOS).
      final media = AppScope.of(context).requireMedia;
      final savedPath = await media.capture(
        sourcePath: picked.path,
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

  void _copyUid(BuildContext context, String uid) {
    Clipboard.setData(ClipboardData(text: uid));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceRaised,
          content: Text('User ID copied', style: AppText.button.copyWith(color: AppColors.ink, fontSize: 14)),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final AuthUser? user = scope.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: scope.profiles.watchProfile(user.uid),
          initialData: null,
          builder: (context, snapshot) {
            final profile = snapshot.data;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RiseIn(
                    child: Row(
                      children: [
                        Text('You', style: AppText.greeting),
                        const Spacer(),
                        _IconButton(
                          icon: Icons.settings_outlined,
                          semanticLabel: 'Settings',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SettingsPage()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  RiseIn(
                    delay: const Duration(milliseconds: 50),
                    child: _ProfileHeader(
                      user: user,
                      profile: profile,
                      onTapAvatar: profile == null ? null : () => _changePhoto(context, profile),
                    ),
                  ),
                  const SizedBox(height: 24),
                  RiseIn(
                    delay: const Duration(milliseconds: 90),
                    child: _AboutCard(
                      bio: profile?.bio,
                      onTap: profile == null ? null : () => _editBio(context, profile),
                    ),
                  ),
                  const SizedBox(height: 20),
                  RiseIn(
                    delay: const Duration(milliseconds: 130),
                    child: SettingsSectionCard(
                      label: 'ACCOUNT',
                      children: [
                        SettingsRow(
                          icon: Icons.badge_outlined,
                          title: 'Name',
                          value: profile?.name ?? '—',
                          onTap: profile == null ? null : () => _editName(context, profile),
                        ),
                        SettingsRow(
                          icon: Icons.cake_outlined,
                          title: 'Date of birth',
                          value: profile == null ? '—' : _formatDob(profile.dateOfBirth),
                          onTap: profile == null ? null : () => _editDob(context, profile),
                        ),
                        SettingsRow(
                          icon: Icons.mail_outline_rounded,
                          title: 'Email',
                          value: user.email ?? 'Hidden by provider',
                          trailing: user.email == null
                              ? null
                              : (user.isEmailVerified
                                  ? const Icon(Icons.verified_rounded, size: 17, color: AppColors.pulse)
                                  : const Icon(Icons.error_outline_rounded, size: 17, color: AppColors.solar)),
                        ),
                        SettingsRow(
                          icon: Icons.fingerprint_rounded,
                          title: 'User ID',
                          value: user.uid,
                          monospace: true,
                          trailing: const Icon(Icons.copy_rounded, size: 16, color: AppColors.ink3),
                          onTap: () => _copyUid(context, user.uid),
                          last: true,
                        ),
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
                            title: _providerLabel(user.providerIds[i]),
                            value: 'Connected',
                            last: i == user.providerIds.length - 1,
                          ),
                        if (user.providerIds.isEmpty)
                          const SettingsRow(
                            icon: Icons.password_rounded,
                            title: 'Email',
                            value: 'Connected',
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
    );
  }

  static String _providerLabel(String id) => switch (id) {
        'password' => 'Email & password',
        'google.com' => 'Google',
        'apple.com' => 'Apple',
        _ => id,
      };

  static IconData _providerIcon(String id) => switch (id) {
        'password' => Icons.password_rounded,
        'google.com' => Icons.g_mobiledata_rounded,
        'apple.com' => Icons.apple_rounded,
        _ => Icons.link_rounded,
      };

  static String _formatDob(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return '${d.day} ${months[d.month - 1]} ${d.year} · $age yrs';
  }
}

enum _PhotoAction { choose, remove }

/// A small circular icon button — the same 34px chip language as
/// `CaptureIconButton`, kept local since this page's chip is neutral
/// (surfaceRaised) rather than capture-flow-branded.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.semanticLabel, required this.onTap});

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
            decoration: const BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: AppColors.ink2),
          ),
        ),
      ),
    );
  }
}

/// Avatar + name + verified email — the identity summary above the account
/// details.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.profile, required this.onTapAvatar});

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
        _Avatar(seed: user.uid, name: _name, photoPath: profile?.photoPath, onTap: onTapAvatar),
        const SizedBox(height: 16),
        Text(_name, style: AppText.cardTitle.copyWith(fontSize: 22), textAlign: TextAlign.center),
        if (user.email != null) ...[
          const SizedBox(height: 5),
          Text(user.email!, style: AppText.body, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

/// The identity avatar. Shows the saved photo when one exists; otherwise a
/// deterministic monogram (hue derived from [seed], so it's stable across
/// sessions and distinct enough between accounts to feel personal). A small
/// camera badge signals it's tappable — standard iOS "edit photo" affordance.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.seed, required this.name, required this.photoPath, required this.onTap});

  final String seed;
  final String name;
  final String? photoPath;
  final VoidCallback? onTap;

  static const _hues = [AppColors.ember, AppColors.pulse, AppColors.iris, AppColors.flare, AppColors.solar];
  static const double _size = 92;

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words.first.substring(0, 1) + words.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    final hue = _hues[seed.hashCode.abs() % _hues.length];
    final fg = hue == AppColors.solar ? const Color(0xFF2A2205) : Colors.white;

    // The monogram is the base layer; when a stored photo resolves it covers
    // the circle. Resolution is async (the media store maps the ref to a file),
    // so we can't decide sync — the gradient stays behind and the photo, when
    // present, paints over it. A missing/stale ref falls back to the monogram.
    final monogram = Text(_initials, style: AppText.cardTitle.copyWith(fontSize: 30, color: fg));
    final circle = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [hue, hue.withValues(alpha: 0.75)],
        ),
        boxShadow: [
          BoxShadow(color: hue.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: -6, offset: const Offset(0, 12)),
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
                  ),
                  child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The "About" card — a short bio the person writes about themselves, tap
/// anywhere to edit. Shows a muted prompt until one is set.
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.bio, required this.onTap});

  final String? bio;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final trimmed = bio?.trim();
    final hasBio = trimmed != null && trimmed.isNotEmpty;
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ABOUT', style: AppText.sectionLabel),
              const Spacer(),
              if (onTap != null)
                Icon(hasBio ? Icons.edit_outlined : Icons.add_rounded, size: 16, color: AppColors.ink3),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasBio ? trimmed : 'Add a few words about yourself.',
            style: AppText.body.copyWith(color: hasBio ? AppColors.ink2 : AppColors.ink3, fontSize: 14.5),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return PressableScale(
      child: InkWell(borderRadius: BorderRadius.circular(AppRadius.card), onTap: onTap, child: card),
    );
  }
}

/// A bottom sheet with one text field — single-line (name) or multiline
/// (bio) — capped at [maxLength] with a live counter. `.withInitial(...)`
/// supplies the starting text (kept out of the const constructor since a
/// [TextEditingController] can't be const).
class _EditTextSheet extends StatefulWidget {
  const _EditTextSheet({
    required this.title,
    required this.hint,
    required this.maxLength,
    required this.initial,
    this.multiline = false,
    this.capitalizeWords = false,
  });

  final String title;
  final String hint;
  final int maxLength;
  final String initial;
  final bool multiline;
  final bool capitalizeWords;

  @override
  State<_EditTextSheet> createState() => _EditTextSheetState();
}

class _EditTextSheetState extends State<_EditTextSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);

  bool get _canSave => widget.multiline ? true : _text.text.trim().isNotEmpty;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
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
              decoration: BoxDecoration(color: AppColors.hairline2, borderRadius: BorderRadius.circular(999)),
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
            maxLines: widget.multiline ? 4 : 1,
            minLines: widget.multiline ? 3 : 1,
            textCapitalization: widget.capitalizeWords ? TextCapitalization.words : TextCapitalization.sentences,
            textInputAction: widget.multiline ? TextInputAction.newline : TextInputAction.done,
            onSubmitted: widget.multiline ? null : (_) => _submit(),
            onChanged: (_) => setState(() {}),
            cursorColor: AppColors.ember,
            style: AppText.rowTitle.copyWith(fontWeight: widget.multiline ? FontWeight.w400 : FontWeight.w600),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              counterStyle: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 11),
              border: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.hairline)),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.hairline)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.ember, width: 1.6)),
              hintText: widget.hint,
              hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
            ),
          ),
          const SizedBox(height: 22),
          Opacity(
            opacity: _canSave ? 1 : 0.45,
            child: Material(
              color: AppColors.ember,
              borderRadius: BorderRadius.circular(999),
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
                      const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Text('Save', style: AppText.button.copyWith(fontSize: 16, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A native-feeling wheel date picker for date of birth — three synced
/// scrolling columns (month / day / year), matching the workout plan
/// editor's rest-duration wheel: dark [AppColors.surfaceRaised] track, a
/// hairline selection band, and a scroll-tick haptic on every settled value.
/// Changing month or year clamps an out-of-range day (e.g. leaving 31 when
/// moving off a 31-day month) rather than allowing an invalid date.
class _DobPickerSheet extends StatefulWidget {
  const _DobPickerSheet({required this.initial});

  final DateTime initial;

  @override
  State<_DobPickerSheet> createState() => _DobPickerSheetState();
}

class _DobPickerSheetState extends State<_DobPickerSheet> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late final int _minYear = DateTime.now().year - 120;
  late final int _maxYear = DateTime.now().year - 13;

  late int _year = widget.initial.year.clamp(_minYear, _maxYear);
  late int _month = widget.initial.month;
  late int _day = widget.initial.day;

  late final _dayController = FixedExtentScrollController(initialItem: _day - 1);

  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;

  void _tick() => HapticFeedback.selectionClick();

  void _clampDay() {
    final max = _daysInMonth;
    if (_day > max) {
      _day = max;
      _dayController.jumpToItem(_day - 1);
    }
  }

  @override
  void dispose() {
    _dayController.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(DateTime(_year, _month, _day));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(top: 12, left: 22, right: 22, bottom: MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(color: AppColors.hairline2, borderRadius: BorderRadius.circular(999)),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text('Date of birth', style: AppText.cardTitle),
          ),
          Container(
            height: 190,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: CupertinoPicker(
                    key: const Key('dob-picker-month'),
                    scrollController: FixedExtentScrollController(initialItem: _month - 1),
                    itemExtent: 40,
                    diameterRatio: 1.3,
                    backgroundColor: Colors.transparent,
                    selectionOverlay: _selectionBand(edge: false),
                    onSelectedItemChanged: (index) {
                      _tick();
                      setState(() {
                        _month = index + 1;
                        _clampDay();
                      });
                    },
                    children: [
                      for (final m in _months)
                        Center(child: Text(m, style: AppText.rowTitle.copyWith(color: AppColors.ink, fontSize: 16))),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: CupertinoPicker(
                    key: const Key('dob-picker-day'),
                    scrollController: _dayController,
                    itemExtent: 40,
                    diameterRatio: 1.3,
                    backgroundColor: Colors.transparent,
                    selectionOverlay: _selectionBand(edge: false),
                    onSelectedItemChanged: (index) {
                      _tick();
                      setState(() => _day = index + 1);
                    },
                    children: [
                      for (var d = 1; d <= 31; d++)
                        Center(child: Text('$d', style: AppText.rowTitle.copyWith(color: AppColors.ink))),
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: CupertinoPicker(
                    key: const Key('dob-picker-year'),
                    scrollController: FixedExtentScrollController(initialItem: _year - _minYear),
                    itemExtent: 40,
                    diameterRatio: 1.3,
                    backgroundColor: Colors.transparent,
                    selectionOverlay: _selectionBand(edge: true),
                    onSelectedItemChanged: (index) {
                      _tick();
                      setState(() {
                        _year = _minYear + index;
                        _clampDay();
                      });
                    },
                    children: [
                      for (var y = _minYear; y <= _maxYear; y++)
                        Center(child: Text('$y', style: AppText.rowTitle.copyWith(color: AppColors.ink))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Material(
            color: AppColors.ember,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: _submit,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text('Save', style: AppText.button.copyWith(fontSize: 16, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The dark, rounded "current selection" band, right-inset on the last
  /// (rightmost) column so it doesn't visually bleed past the sheet's edge.
  Widget _selectionBand({required bool edge}) {
    return Container(
      margin: EdgeInsets.only(left: 2, right: edge ? 6 : 2),
      decoration: BoxDecoration(color: AppColors.hairline2, borderRadius: BorderRadius.circular(10)),
    );
  }
}
