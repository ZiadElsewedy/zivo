import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../capture/presentation/widgets/capture_widgets.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'music_artwork.dart';
import 'music_scrubber.dart';

/// The full-screen player — pushed from [NowPlayingBar]. Enter/exit is a
/// plain fullscreen-dialog `MaterialPageRoute` (see wherever this is
/// pushed) rather than a custom transition: the platform's own slide-up/
/// down is already symmetric (spatial consistency — it leaves the way it
/// arrived), so nothing bespoke is added here.
class MusicPlayerPage extends StatelessWidget {
  const MusicPlayerPage({required this.controller, super.key});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: PressableScale(
          child: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
            color: AppColors.ink2,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<MusicConnection>(
          stream: controller.connection,
          initialData: controller.currentConnection,
          builder: (context, connSnap) {
            final state = connSnap.data ?? MusicConnection.disconnected;
            if (state != MusicConnection.connected) {
              return _ConnectionState(state: state, onConnect: controller.connect);
            }
            return StreamBuilder<NowPlaying?>(
              stream: controller.nowPlaying,
              initialData: controller.currentNowPlaying,
              builder: (context, snap) {
                final playing = snap.data;
                if (playing == null) return const _NothingPlaying();
                return _Player(controller: controller, playing: playing);
              },
            );
          },
        ),
      ),
    );
  }
}

class _Player extends StatelessWidget {
  const _Player({required this.controller, required this.playing});

  final MusicController controller;
  final NowPlaying playing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        0,
        AppSpacing.l,
        AppSpacing.l,
      ),
      child: Column(
        children: [
          const Spacer(),
          _BigArtwork(bytes: playing.artworkBytes, url: playing.artworkUrl),
          const SizedBox(height: AppSpacing.section),
          Text(
            playing.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.cardTitle.copyWith(fontSize: 22, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            playing.artist,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body.copyWith(color: AppColors.ink2),
          ),
          const SizedBox(height: AppSpacing.l),
          MusicScrubber(
            controller: controller,
            duration: playing.duration,
            position: playing.position,
            isPaused: playing.isPaused,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_format(playing.position), style: AppText.meta.copyWith(color: AppColors.ink3)),
              Text(_format(playing.duration), style: AppText.meta.copyWith(color: AppColors.ink3)),
            ],
          ),
          const SizedBox(height: AppSpacing.l),
          if (!playing.hasControl)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: Text(
                'Playing on another device — controls are read-only here.',
                textAlign: TextAlign.center,
                style: AppText.meta.copyWith(color: AppColors.ink3),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Control(
                icon: Icons.replay_rounded,
                size: 26,
                enabled: playing.hasControl,
                onTap: controller.replay,
              ),
              const SizedBox(width: AppSpacing.l),
              _Control(
                icon: Icons.skip_previous_rounded,
                size: 32,
                enabled: playing.hasControl,
                onTap: controller.previous,
              ),
              const SizedBox(width: AppSpacing.l),
              _PlayPauseControl(playing: playing, controller: controller),
              const SizedBox(width: AppSpacing.l),
              _Control(
                icon: Icons.skip_next_rounded,
                size: 32,
                enabled: playing.hasControl,
                onTap: controller.next,
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }

  static String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _BigArtwork extends StatelessWidget {
  const _BigArtwork({required this.bytes, required this.url});

  final Uint8List? bytes;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) => MusicArtwork(
          bytes: bytes,
          url: url,
          size: constraints.maxWidth,
          iconSize: 64,
          borderRadius: 20,
        ),
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.size,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: enabled,
      child: IconButton(
        iconSize: size,
        color: enabled ? AppColors.ink : AppColors.ink3,
        onPressed: !enabled
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap();
              },
        icon: Icon(icon),
      ),
    );
  }
}

/// The primary play/pause control — a filled circle rather than a bare
/// icon, matching this app's other primary actions ([PillButton]).
class _PlayPauseControl extends StatelessWidget {
  const _PlayPauseControl({required this.playing, required this.controller});

  final NowPlaying playing;
  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: playing.hasControl,
      child: Material(
        color: playing.hasControl ? AppColors.ember : AppColors.surfaceRaised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: !playing.hasControl
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  playing.isPaused ? controller.play() : controller.pause();
                },
          child: SizedBox(
            width: 64,
            height: 64,
            child: Icon(
              playing.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: playing.hasControl ? Colors.white : AppColors.ink3,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}

/// The three non-`connected` states — each with copy specific to what's
/// actually wrong, rather than one generic "can't connect" message.
class _ConnectionState extends StatelessWidget {
  const _ConnectionState({required this.state, required this.onConnect});

  final MusicConnection state;
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    final (icon, message, showConnect) = switch (state) {
      MusicConnection.needsPremium => (
        Icons.workspace_premium_outlined,
        'Spotify Premium is required to control playback here.',
        false,
      ),
      MusicConnection.noSpotifyApp => (
        Icons.error_outline_rounded,
        'Install Spotify to connect.',
        false,
      ),
      MusicConnection.connecting => (Icons.sync_rounded, 'Connecting…', false),
      MusicConnection.disconnected ||
      MusicConnection.connected => (
        Icons.music_note_rounded,
        "Connect Spotify to see what's playing.",
        true,
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppColors.ink3),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.aside.copyWith(color: AppColors.ink2),
            ),
            if (showConnect) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 200,
                child: PillButton(
                  label: 'Connect Spotify',
                  icon: Icons.link_rounded,
                  color: AppColors.pulse,
                  enabled: true,
                  onTap: onConnect,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Nothing playing right now.',
        style: AppText.aside.copyWith(color: AppColors.ink2),
      ),
    );
  }
}
