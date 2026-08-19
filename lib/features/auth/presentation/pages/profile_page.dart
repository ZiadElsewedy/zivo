import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/auth_user.dart';
import '../../domain/user_profile.dart';

/// The "You" surface: identity at a glance, an editable account section, and
/// sign-out. Reads the live [UserProfile] (name + date of birth) alongside
/// the [AuthUser] auth identity (email + sign-in provider) so every real
/// piece of data ZIVO holds about the signed-in person has a home here.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    final auth = AppScope.of(context).auth;
    setState(() => _signingOut = true);
    await auth.signOut();
    // The auth gate reacts to the stream and swaps this whole subtree out, so
    // there's nothing to navigate here; guard setState in case we're still up.
    if (mounted) setState(() => _signingOut = false);
  }

  Future<void> _editName(UserProfile profile) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditNameSheet(initial: profile.name),
    );
    if (name == null || !mounted) return;
    await AppScope.of(context).profiles.saveProfile(
          uid: profile.uid,
          name: name,
          dateOfBirth: profile.dateOfBirth,
        );
  }

  Future<void> _editDob(UserProfile profile) async {
    final now = DateTime.now();
    final lastDate = DateTime(now.year - 13, now.month, now.day);
    final firstDate = DateTime(now.year - 120, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: profile.dateOfBirth,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Date of birth',
    );
    if (picked == null || !mounted) return;
    await AppScope.of(context).profiles.saveProfile(
          uid: profile.uid,
          name: profile.name,
          dateOfBirth: picked,
        );
  }

  void _copyUid(String uid) {
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
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RiseIn(child: Text('You', style: AppText.greeting)),
                  const SizedBox(height: 22),
                  RiseIn(
                    delay: const Duration(milliseconds: 50),
                    child: _ProfileHeader(user: user, profile: profile),
                  ),
                  const SizedBox(height: 30),
                  RiseIn(
                    delay: const Duration(milliseconds: 100),
                    child: _SectionCard(
                      label: 'ACCOUNT',
                      children: [
                        _Row(
                          icon: Icons.badge_outlined,
                          title: 'Name',
                          value: profile?.name ?? '—',
                          onTap: profile == null ? null : () => _editName(profile),
                        ),
                        _Row(
                          icon: Icons.cake_outlined,
                          title: 'Date of birth',
                          value: profile == null ? '—' : _formatDob(profile.dateOfBirth),
                          onTap: profile == null ? null : () => _editDob(profile),
                        ),
                        _Row(
                          icon: Icons.mail_outline_rounded,
                          title: 'Email',
                          value: user.email ?? 'Hidden by provider',
                          trailing: user.email == null
                              ? null
                              : (user.isEmailVerified
                                  ? const Icon(Icons.verified_rounded, size: 17, color: AppColors.pulse)
                                  : const Icon(Icons.error_outline_rounded, size: 17, color: AppColors.solar)),
                        ),
                        _Row(
                          icon: Icons.fingerprint_rounded,
                          title: 'User ID',
                          value: user.uid,
                          monospace: true,
                          trailing: const Icon(Icons.copy_rounded, size: 16, color: AppColors.ink3),
                          onTap: () => _copyUid(user.uid),
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  RiseIn(
                    delay: const Duration(milliseconds: 140),
                    child: _SectionCard(
                      label: 'SIGN-IN',
                      children: [
                        for (var i = 0; i < user.providerIds.length; i++)
                          _Row(
                            icon: _providerIcon(user.providerIds[i]),
                            title: _providerLabel(user.providerIds[i]),
                            value: 'Connected',
                            last: i == user.providerIds.length - 1,
                          ),
                        if (user.providerIds.isEmpty)
                          const _Row(
                            icon: Icons.password_rounded,
                            title: 'Email',
                            value: 'Connected',
                            last: true,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  RiseIn(
                    delay: const Duration(milliseconds: 180),
                    child: _SignOutButton(loading: _signingOut, onTap: _signOut),
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

/// Avatar + name + verified email — the identity summary above the account
/// details. The avatar is a deterministic monogram (no photo storage exists
/// yet): its hue is derived from [AuthUser.uid] so it's stable across
/// sessions and distinct enough between accounts to feel personal.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.profile});

  final AuthUser user;
  final UserProfile? profile;

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
        _Avatar(seed: user.uid, name: _name),
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.seed, required this.name});

  final String seed;
  final String name;

  static const _hues = [AppColors.ember, AppColors.pulse, AppColors.iris, AppColors.flare, AppColors.solar];

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words.first.substring(0, 1) + words.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hue = _hues[seed.hashCode.abs() % _hues.length];
    final fg = hue == AppColors.solar ? const Color(0xFF2A2205) : Colors.white;
    return Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
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
      child: Text(
        _initials,
        style: AppText.cardTitle.copyWith(fontSize: 28, color: fg),
      ),
    );
  }
}

/// A grouped, hairline-divided list of [_Row]s under an uppercase [label] —
/// the iOS Settings "inset grouped" pattern, in ZIVO's dark material.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: AppText.sectionLabel),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: AppShadows.card,
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.value,
    this.trailing,
    this.onTap,
    this.monospace = false,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool monospace;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final editable = onTap != null;
    final row = Container(
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: AppColors.ink2),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(title, style: AppText.rowTitle.copyWith(fontSize: 15)),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppText.meta.copyWith(
                color: AppColors.ink3,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ] else if (editable) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink3),
          ],
        ],
      ),
    );
    if (!editable) return row;
    return PressableScale(
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

class _EditNameSheet extends StatefulWidget {
  const _EditNameSheet({required this.initial});

  final String initial;

  @override
  State<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<_EditNameSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.initial);

  bool get _canSave => _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop(_name.text.trim());
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
            child: Text('Edit name', style: AppText.cardTitle),
          ),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() {}),
            cursorColor: AppColors.ember,
            style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.hairline)),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.hairline)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.ember, width: 1.6)),
              hintText: 'Your name',
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

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: !loading,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.hairline2, width: 1.4),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.flareText),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.logout_rounded, size: 18, color: AppColors.flareText),
                      const SizedBox(width: 8),
                      Text('Sign out', style: AppText.button.copyWith(fontSize: 15, color: AppColors.flareText)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
