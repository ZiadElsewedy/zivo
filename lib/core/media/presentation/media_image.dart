import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_typography.dart';
import '../media_service.dart';

/// Displays a stored media reference. Resolves the (relative or legacy
/// absolute) [ref] to a file via the [MediaService] and renders it, with
/// three distinct states:
///
/// - **resolving** — [placeholder] (a quiet spinner when the caller doesn't
///   supply one); on another device the file may be mid-download from Drive.
/// - **resolved** — the image itself.
/// - **unavailable** — resolution finished without a file (never backed up,
///   Drive unreachable, or no session). Shows an explicit cloud-off mark
///   with a tap-to-retry affordance instead of sitting silently empty, so a
///   synced-metadata-but-missing-bytes moment is honest about its state and
///   one tap away from recovery (e.g. after the user connects Drive).
///
/// This is the read-side counterpart to [MediaService.capture]: features hold
/// an opaque string ref and never build a [File] themselves, so the store owns
/// how a ref maps to bytes on disk.
class MediaImage extends StatefulWidget {
  const MediaImage({
    required this.service,
    required this.ref,
    this.fit = BoxFit.cover,
    this.placeholder,
    super.key,
  });

  final MediaService service;
  final String? ref;
  final BoxFit fit;

  /// Shown while the reference is resolving (local read or cloud fetch).
  /// Defaults to a small centered spinner.
  final Widget? placeholder;

  @override
  State<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<MediaImage> {
  late Future<File?> _resolved;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _resolved = widget.service.resolveOrFetch(widget.ref);
  }

  @override
  void didUpdateWidget(MediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref != widget.ref || oldWidget.service != widget.service) {
      _retry();
    }
  }

  void _retry() {
    setState(() {
      _attempt++;
      _resolved = widget.service.resolveOrFetch(widget.ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      key: ValueKey('$widget.ref#$_attempt'),
      future: _resolved,
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.waiting || ConnectionState.active:
            return widget.placeholder ?? _spinner;
          case ConnectionState.none || ConnectionState.done:
            final file = snapshot.data;
            if (file != null && file.existsSync()) {
              return Image.file(file, fit: widget.fit);
            }
            return _Unavailable(onRetry: _retry);
        }
      },
    );
  }

  static const _spinner = Center(
    child: SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink3),
    ),
  );
}

/// The explicit "bytes aren't here (yet)" state — tappable to retry, so a
/// photo that becomes fetchable later (Drive connected, network back) is one
/// tap away without leaving the screen.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: AppColors.surfaceRaised,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.driveCloud, size: 20, color: AppColors.ink3),
              const SizedBox(height: 6),
              Text(
                'Tap to retry',
                style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
