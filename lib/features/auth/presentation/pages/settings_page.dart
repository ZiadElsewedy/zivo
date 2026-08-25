import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/env/app_environment.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../music/domain/music_connection.dart';
import '../../../music/domain/music_controller.dart';
import '../../../music/domain/now_playing.dart';
import '../../../music/music_config.dart';
import '../../../music/presentation/music_player_page.dart';
import '../widgets/media_backup_section.dart';
import '../../../../core/widgets/settings_row.dart';

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
    // Capture the navigator before the async gap (context may be unsafe after).
    final navigator = Navigator.of(context);
    setState(() => _signingOut = true);
    await auth.signOut();
    // The auth gate swaps the shell for the sign-in screen *underneath* this
    // pushed Settings route. Pop back to the gate so the user actually lands on
    // sign-in instead of a Settings page floating over it.
    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
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
        title: Text(
          'Settings',
          style: AppText.cardTitle.copyWith(fontSize: 20),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const RiseIn(child: MediaBackupSection()),
              const SizedBox(height: 20),
              if (kMusicEnabled) ...[
                RiseIn(
                  delay: const Duration(milliseconds: 50),
                  child: _MusicSection(controller: AppScope.of(context).requireMusic),
                ),
                const SizedBox(height: 20),
              ],
              RiseIn(
                delay: const Duration(milliseconds: 90),
                child: SettingsSectionCard(
                  label: 'ABOUT',
                  children: [
                    const SettingsRow(
                      icon: AppIcons.theme,
                      title: 'Theme',
                      value: 'Dark',
                    ),
                    SettingsRow(
                      icon: AppIcons.version,
                      title: 'Version',
                      value: info == null
                          ? '…'
                          : '${info.version} (${info.buildNumber})',
                      last: AppEnvironment.isRelease,
                    ),
                    if (!AppEnvironment.isRelease)
                      SettingsRow(
                        icon: AppIcons.build,
                        title: 'Build',
                        value: AppEnvironment.name,
                        last: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              RiseIn(
                delay: const Duration(milliseconds: 130),
                child: _SignOutButton(loading: _signingOut, onTap: _signOut),
              ),
              const SizedBox(height: 44),
              RiseIn(
                delay: const Duration(milliseconds: 180),
                child: _BrandFooter(
                  version: info == null
                      ? null
                      : 'Version ${info.version} (${info.buildNumber})',
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet brand signature at the foot of Settings — the ZIVO mark in the
/// light "paper" tone, the wordmark, and the build. Gives the screen identity
/// without competing with the controls above it.
class _BrandFooter extends StatelessWidget {
  const _BrandFooter({this.version});

  final String? version;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: Column(
        children: [
          Image.asset(
            'assets/transparent/zivo-mark-paper-256.png',
            width: 42,
            height: 42,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(height: 12),
          Text(
            'ZIVO',
            style: AppText.button.copyWith(
              fontSize: 12,
              letterSpacing: 5,
              color: AppColors.ink2,
            ),
          ),
          if (version != null) ...[
            const SizedBox(height: 5),
            Text(
              version!,
              style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// Settings' always-reachable entry point into the music feature — visible
/// in every connection state (before connecting there's no mini-bar or
/// in-session card yet, so this would otherwise be the one dead end with no
/// way in). Tapping always opens [MusicPlayerPage]; the connect/retry
/// affordance and per-state copy live there, not duplicated here — this row
/// is purely a destination link, its trailing value just previewing status.
class _MusicSection extends StatelessWidget {
  const _MusicSection({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MusicConnection>(
      stream: controller.connection,
      initialData: controller.currentConnection,
      builder: (context, connSnap) {
        final state = connSnap.data ?? MusicConnection.disconnected;
        return StreamBuilder<NowPlaying?>(
          stream: controller.nowPlaying,
          initialData: controller.currentNowPlaying,
          builder: (context, nowSnap) {
            final playing = nowSnap.data;
            final value = switch (state) {
              MusicConnection.connected => playing != null ? 'Playing' : 'Connected',
              MusicConnection.connecting => 'Connecting…',
              MusicConnection.authFailed => "Couldn't connect",
              MusicConnection.needsPremium => 'Premium required',
              MusicConnection.noSpotifyApp => 'Install Spotify',
              MusicConnection.disconnected => 'Not connected',
            };
            return SettingsSectionCard(
              label: 'MUSIC',
              children: [
                SettingsRow(
                  icon: AppIcons.music,
                  // TODO(spotify-icon): this is a neutral placeholder swatch
                  // (flat color, no mark) at assets/spotify/spotify-icon.png
                  // — swap in the official Spotify logo once sourced. Do
                  // NOT recreate/recolor the mark; follow Spotify's brand
                  // guidelines. Referenced here and nowhere else in the
                  // app — the in-session card/chip stay logo-free.
                  iconWidget: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset(
                      'assets/spotify/spotify-icon.png',
                      width: 18,
                      height: 18,
                    ),
                  ),
                  title: 'Spotify',
                  value: value,
                  last: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MusicPlayerPage(controller: controller),
                        fullscreenDialog: true,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.flareText,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        AppIcons.signOut,
                        size: 18,
                        color: AppColors.flareText,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Sign out',
                        style: AppText.button.copyWith(
                          fontSize: 15,
                          color: AppColors.flareText,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
