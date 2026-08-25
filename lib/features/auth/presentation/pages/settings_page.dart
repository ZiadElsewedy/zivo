import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/env/app_environment.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
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
///
/// Presented in the app's dashboard language — atmospheric backdrop, editorial
/// title, staggered entrance — with iOS-Settings colored marks giving each
/// row's icon its own identity.
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
            const Positioned(
              top: -60,
              right: -70,
              child: _AuraBlob(color: AppColors.iris, size: 200),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 44),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RiseIn(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BackButton(),
                          const SizedBox(height: 20),
                          Text('Settings', style: AppText.greeting),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const RiseIn(
                      delay: Duration(milliseconds: 50),
                      child: MediaBackupSection(),
                    ),
                    const SizedBox(height: 20),
                    if (kMusicEnabled) ...[
                      RiseIn(
                        delay: const Duration(milliseconds: 90),
                        child: _MusicSection(
                          controller: AppScope.of(context).requireMusic,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    RiseIn(
                      delay: const Duration(milliseconds: 130),
                      child: SettingsSectionCard(
                        label: 'ABOUT',
                        children: [
                          const SettingsRow(
                            icon: AppIcons.theme,
                            title: 'Theme',
                            value: 'Dark',
                            accent: AppColors.iris,
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
                      delay: const Duration(milliseconds: 170),
                      child: _SignOutButton(
                        loading: _signingOut,
                        onTap: _signOut,
                      ),
                    ),
                    const SizedBox(height: 44),
                    RiseIn(
                      delay: const Duration(milliseconds: 220),
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
          ],
        ),
      ),
    );
  }
}

/// A soft, blurred wash of color floating behind the content — the quiet
/// "energy" glow shared with Today, Hub and Profile. Purely decorative.
class _AuraBlob extends StatelessWidget {
  const _AuraBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.14),
          ),
        ),
      ),
    );
  }
}

/// The pushed-page back affordance — the same 38px chip language as Profile's
/// settings button, pointing home.
class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Tooltip(
        message: 'Back',
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
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
            child: const Icon(AppIcons.back, size: 18, color: AppColors.ink2),
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
              MusicConnection.connected =>
                playing != null ? 'Playing' : 'Connected',
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
                  accent: AppColors.pulse,
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

/// The sign-out action — the page's one destructive moment, styled as tinted
/// glass: a flare wash inside a flare-tinted edge, lifted on a soft red glow.
class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: !loading,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.flare.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.flare.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: AppColors.flare.withValues(alpha: 0.16),
                blurRadius: 26,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: InkWell(
            onTap: loading ? null : onTap,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              alignment: Alignment.center,
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
      ),
    );
  }
}
