import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_typography.dart';
import '../domain/media_resolution.dart';
import '../media_service.dart';

/// Displays a stored media reference honestly. Resolves the [ref] through
/// [MediaService.resolveWithStatus] and renders exactly what that answer
/// means:
///
/// - **onDevice** — the image itself.
/// - **cloudOnly** — bytes exist in Drive and are being fetched (or briefly
///   backing off after a failed attempt). A quiet pulsing cloud state, never
///   an error — the fetch self-heals.
/// - **nowhere** — the photo isn't on this device AND was never backed up
///   (typically captured on another device). Rendered as a calm "lives
///   elsewhere" tile with NO tappable retry — a retry cannot succeed until
///   another device uploads it, so pretending otherwise would be a lie.
///
/// Optional [onRetry] gives surfaces that want an explicit escape hatch
/// (e.g. the full-screen viewer, where the user is looking straight at the
/// gap) a manual re-resolve; grids omit it and rely on automatic recovery.
///
/// [decodeWidth] downsamples the decode to ~[decodeWidth]px — grid tiles must
/// NOT decode a 1600px capture for a 120dp cell, or scrolling stutters.
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
    this.decodeWidth,
    this.onRetry,
    super.key,
  });

  final MediaService service;
  final String? ref;
  final BoxFit fit;

  /// Shown while the reference resolves (local check or cloud fetch).
  /// Defaults to a soft pulsing surface.
  final Widget? placeholder;

  /// Decode target width in pixels (grid tiles pass their layout width ×
  /// devicePixelRatio; full-screen viewers leave it null for full fidelity).
  final int? decodeWidth;

  /// Called by the "nowhere" state's retry affordance when set; without it
  /// that state renders purely informational.
  final VoidCallback? onRetry;

  @override
  State<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<MediaImage>
    with SingleTickerProviderStateMixin {
  late Future<MediaResolution> _resolved;
  int _attempt = 0;
  Timer? _selfRetry;

  /// Drives the cloudOnly pulse — a slow breathing opacity, calmer than any
  /// spinner: nothing is wrong, bytes are merely on their way.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    lowerBound: 0.35,
    upperBound: 0.85,
  );

  @override
  void initState() {
    super.initState();
    _resolved = widget.service.resolveWithStatus(widget.ref);
  }

  @override
  void didUpdateWidget(MediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref != widget.ref || oldWidget.service != widget.service) {
      _reresolve();
    }
  }

  @override
  void dispose() {
    _selfRetry?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _reresolve() {
    _selfRetry?.cancel();
    setState(() {
      _attempt++;
      _resolved = widget.service.resolveWithStatus(widget.ref);
    });
  }

  /// One scheduled self-heal per failed fetch, aligned with the service's
  /// own backoff window — a photo whose network blipped recovers on its own
  /// without any user interaction.
  void _scheduleSelfRetry() {
    _selfRetry?.cancel();
    _selfRetry = Timer(
      MediaService.fetchFailureBackoff + const Duration(milliseconds: 500),
      _reresolve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MediaResolution>(
      key: ValueKey('${widget.ref}#$_attempt'),
      future: _resolved,
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.waiting || ConnectionState.active:
            _pulse.repeat(reverse: true);
            return widget.placeholder ?? _PulsingSurface(pulse: _pulse);
          case ConnectionState.none || ConnectionState.done:
            final resolution = snapshot.data;
            final file = resolution?.file;
            if (resolution != null && file != null && file.existsSync()) {
              _selfRetry?.cancel();
              _pulse.stop();
              return Image.file(
              file,
              fit: widget.fit,
              cacheWidth: widget.decodeWidth,
            );
            }
            switch (resolution?.availability) {
              case MediaAvailability.cloudOnly || null:
                _scheduleSelfRetry();
                _pulse.repeat(reverse: true);
                return _PulsingSurface(pulse: _pulse, icon: AppIcons.driveCloud);
              case MediaAvailability.nowhere:
                _pulse.stop();
                return _LivesElsewhere(onRetry: widget.onRetry);
              case MediaAvailability.onDevice:
                // The file existed at resolution time but evaporated before
                // this frame (deleted underneath us) — quietly re-resolve.
                _scheduleSelfRetry();
                _pulse.repeat(reverse: true);
                return _PulsingSurface(pulse: _pulse);
            }
        }
      },
    );
  }
}

/// A quiet breathing surface used for both resolving and cloud-fetching —
/// one visual language for "bytes are coming".
class _PulsingSurface extends StatelessWidget {
  const _PulsingSurface({required this.pulse, this.icon});

  final Animation<double> pulse;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceRaised,
      child: Center(
        child: FadeTransition(
          opacity: pulse,
          child: Icon(
            icon ?? AppIcons.image,
            size: 22,
            color: AppColors.ink3,
          ),
        ),
      ),
    );
  }
}

/// The honest "these bytes live somewhere else right now" state. Deliberately
/// NOT styled as an error and — unless [onRetry] is provided — deliberately
/// NOT tappable: nothing this device can do will fetch them until another
/// device backs them up.
class _LivesElsewhere extends StatelessWidget {
  const _LivesElsewhere({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.driveCloud, size: 20, color: AppColors.ink3),
        const SizedBox(height: 6),
        Text(
          'Captured on another device',
          style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
    final content = ColoredBox(
      color: AppColors.surfaceRaised,
      child: Center(child: body),
    );
    if (onRetry == null) return content;
    return GestureDetector(
      onTap: onRetry,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}
