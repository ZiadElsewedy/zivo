import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/env/app_environment.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../music/domain/music_connection.dart';
import '../../../music/domain/music_controller.dart';
import '../../../music/domain/now_playing.dart';
import '../../../music/music_config.dart';
import '../../../music/presentation/equalizer_glyph.dart';
import '../../../music/presentation/music_player_page.dart';
import 'change_password_page.dart';
import 'privacy_page.dart';
import '../widgets/media_backup_section.dart';
import '../widgets/delete_account_sheet.dart';
import '../../../../core/widgets/settings_row.dart';

/// Settings — appearance, music, about (with the privacy policy), and sign
/// out. Split from [ProfilePage] the way most apps separate "who you are"
/// from "how the app behaves" — deliberately small: only sections backed by
/// something real.
///
/// Dressed to the design handoff's **Settings** screen (4e): the cool screen
/// wash, a 36px back circle beside the Manrope 800/27 title, then MEDIA /
/// MUSIC / APP / ACCOUNT as mono-labelled inset lists, and a ghost `Sign out`
/// at the foot.
///
/// Two things the handoff is specific about. The Spotify card carries a live
/// equalizer and the **actual track** on its second line — a row that says
/// only "Connected" makes a claim without evidence. And sign-out is a ghost,
/// not a red button: it is reversible, so it doesn't get to look like the
/// account deletion two rows above it.
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
    // Password accounts can change their password in-app; social accounts have
    // no ZIVO password, so that row is hidden for them. Deletion is offered to
    // everyone.
    final user = AppScope.of(context).auth.currentUser;
    final isPasswordUser = user?.providerIds.contains('password') ?? false;
    return TrainScreen(
      tint: TrainColors.settingsTint,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 44),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RiseIn(child: TrainPageHeader(title: 'Settings')),
            const SizedBox(height: 26),
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
                label: 'App',
                children: [
                  const SettingsRow(
                    icon: AppIcons.theme,
                    title: 'Theme',
                    value: 'Dark',
                    accent: TrainColors.violetGlyph,
                  ),
                  SettingsRow(
                    icon: AppIcons.version,
                    title: 'Version',
                    value: info == null
                        ? '…'
                        : '${info.version} (${info.buildNumber})',
                  ),
                  if (!AppEnvironment.isRelease)
                    SettingsRow(
                      icon: AppIcons.build,
                      title: 'Build',
                      value: AppEnvironment.name,
                    ),
                  SettingsRow(
                    icon: AppIcons.privacy,
                    title: 'Privacy policy',
                    // No value: the row's own name already says what
                    // it is, and a restated explanation in the value
                    // column is filler, not information.
                    value: '',
                    accent: TrainColors.green,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPage(),
                          fullscreenDialog: true,
                        ),
                      );
                    },
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            RiseIn(
              delay: const Duration(milliseconds: 150),
              child: SettingsSectionCard(
                label: 'Account',
                children: [
                  if (isPasswordUser)
                    SettingsRow(
                      icon: AppIcons.key,
                      title: 'Change password',
                      value: '',
                      accent: TrainColors.violetGlyph,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ChangePasswordPage(),
                          ),
                        );
                      },
                    ),
                  SettingsRow(
                    icon: AppIcons.trash,
                    title: 'Delete account',
                    // The one row on this page that states its own
                    // consequence — permanence is the fact worth
                    // knowing before the tap, not after.
                    value: 'PERMANENT',
                    accent: TrainColors.ember,
                    onTap: () => DeleteAccountSheet.show(context),
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            RiseIn(
              delay: const Duration(milliseconds: 170),
              child: _SignOutButton(loading: _signingOut, onTap: _signOut),
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
              color: TrainColors.ink2,
            ),
          ),
          if (version != null) ...[
            const SizedBox(height: 5),
            Text(
              version!,
              style: AppText.meta.copyWith(
                color: TrainColors.ink3,
                fontSize: 11,
              ),
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
/// affordance and per-state copy live there, not duplicated here.
///
/// Built to the handoff's Settings card rather than a plain row: a live
/// equalizer tile, `CONNECTED · PLAYING` as a green state caption, and — the
/// point of the whole thing — a second line carrying **the actual track and
/// how much of it is left**. The handoff's note is that "the row's claim must
/// be informative": a row that says only "Connected" asks you to take its
/// word for it. When nothing is playing there's no second line at all, rather
/// than an empty one.
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
            final connected = state == MusicConnection.connected;
            final live = connected && playing != null;
            final caption = switch (state) {
              MusicConnection.connected =>
                playing == null
                    ? 'CONNECTED'
                    : playing.isPaused
                    ? 'CONNECTED · PAUSED'
                    : 'CONNECTED · PLAYING',
              MusicConnection.connecting => 'CONNECTING…',
              MusicConnection.authFailed => "COULDN'T CONNECT",
              MusicConnection.needsPremium => 'PREMIUM REQUIRED',
              MusicConnection.noSpotifyApp => 'INSTALL SPOTIFY',
              MusicConnection.disconnected => 'NOT CONNECTED',
            };
            final accent = connected ? TrainColors.green : TrainColors.ink4;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 11),
                  child: TrainSectionLabel('Music'),
                ),
                PressableScale(
                  scale: 0.99,
                  child: Material(
                    color: connected
                        ? TrainColors.green.withValues(alpha: 0.05)
                        : const Color(0x08FFFFFF),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                MusicPlayerPage(controller: controller),
                            fullscreenDialog: true,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(17, 15, 17, 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: connected
                                ? TrainColors.green.withValues(alpha: 0.20)
                                : TrainColors.hairline,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.24),
                                    ),
                                  ),
                                  child: EqualizerGlyph(
                                    width: 14,
                                    height: 13,
                                    color: accent,
                                    playing: live && !playing.isPaused,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Spotify',
                                        style: TrainType.ui(
                                          size: 15,
                                          weight: FontWeight.w700,
                                          color: TrainColors.inkPlain,
                                          height: 1,
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Text(
                                        caption,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TrainType.mono(
                                          size: 10,
                                          tracking: 0.06,
                                          color: accent.withValues(
                                            alpha: connected ? 0.75 : 1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: Color(0x4DF4F4F0),
                                ),
                              ],
                            ),
                            // The evidence line. Absent entirely when there
                            // is no track — never an empty slot.
                            if (live) ...[
                              const Padding(
                                padding: EdgeInsets.only(top: 13, bottom: 11),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: TrainColors.hairline,
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      playing.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TrainType.ui(
                                        size: 12,
                                        weight: FontWeight.w600,
                                        color: const Color(0xB2F4F4F0),
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _remaining(playing),
                                    style: TrainType.mono(
                                      size: 10,
                                      color: const Color(0x59F4F4F0),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// `-2:37` — how much of the loaded track is left, from the snapshot's own
/// playhead. Not ticked live here: this is a status line, not a transport.
String _remaining(NowPlaying playing) {
  final left = playing.duration - playing.position;
  final seconds = left.isNegative ? 0 : left.inSeconds;
  return '-${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Sign out — a **ghost pill**, deliberately not a red button.
///
/// The handoff's own hierarchy: ember/red is for the single committing (or
/// irreversible) action on a screen, and on Settings that is "Delete account"
/// two sections above. Signing out is reversible — you sign back in — so it
/// takes the quietest shape on the page and stops competing with the one
/// thing here you genuinely can't undo.
class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: !loading,
      scale: 0.985,
      child: Material(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: TrainColors.ink2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        AppIcons.signOut,
                        size: 16,
                        color: Color(0xBFF4F4F0),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Sign out',
                        style: TrainType.ui(
                          size: 15,
                          weight: FontWeight.w700,
                          color: const Color(0xCCF4F4F0),
                          height: 1,
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
