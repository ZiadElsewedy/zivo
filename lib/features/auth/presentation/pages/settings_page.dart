import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/env/app_environment.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../widgets/settings_row.dart';

/// Settings — appearance and about, plus sign out. Split from [ProfilePage]
/// the way most apps separate "who you are" from "how the app behaves" —
/// deliberately small: only sections backed by something real (no
/// notification/privacy toggles that don't do anything yet).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _signingOut = false;
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    final auth = AppScope.of(context).auth;
    setState(() => _signingOut = true);
    await auth.signOut();
    // The auth gate reacts to the stream and swaps the whole shell out from
    // under this page, so there's nothing to navigate here; guard setState
    // in case this page is somehow still up.
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final info = _packageInfo;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Settings', style: AppText.cardTitle.copyWith(fontSize: 20)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsSectionCard(
                label: 'APPEARANCE',
                children: [
                  SettingsRow(
                    icon: Icons.dark_mode_rounded,
                    title: 'Theme',
                    value: 'Dark',
                    last: true,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SettingsSectionCard(
                label: 'ABOUT',
                children: [
                  SettingsRow(
                    icon: Icons.info_outline_rounded,
                    title: 'Version',
                    value: info == null ? '…' : '${info.version} (${info.buildNumber})',
                    last: AppEnvironment.isRelease,
                  ),
                  if (!AppEnvironment.isRelease)
                    SettingsRow(
                      icon: Icons.build_outlined,
                      title: 'Build',
                      value: AppEnvironment.name,
                      last: true,
                    ),
                ],
              ),
              const SizedBox(height: 30),
              _SignOutButton(loading: _signingOut, onTap: _signOut),
            ],
          ),
        ),
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
