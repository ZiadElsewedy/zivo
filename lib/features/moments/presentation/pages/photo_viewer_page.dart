import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/media/domain/media_object.dart';
import '../../../../core/media/media_service.dart';
import '../../../../core/media/presentation/media_image.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/async_action.dart';
import '../../domain/moment.dart';
import '../moment_metadata.dart';
import '../../../../core/widgets/zivo_confirm.dart';
import '../../../../l10n/l10n.dart';

/// A full-screen, swipeable, pinch-zoomable photo viewer — the "open a photo"
/// half of the gallery. Swipe left/right between photos, pinch or double-tap to
/// zoom, tap to toggle the chrome, and reveal a translucent metadata panel
/// (when/where/how the photo was taken) with the info button.
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    required this.service,
    required this.photos,
    required this.mediaById,
    required this.initialIndex,
    required this.onDelete,
    super.key,
  });

  final MediaService service;

  /// Photo-bearing moments, in the same order shown in the grid.
  final List<Moment> photos;
  final Map<String, MediaObject> mediaById;
  final int initialIndex;

  /// Deletes a moment in the backing repository.
  final Future<void> Function(Moment) onDelete;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage>
    with AsyncAction<PhotoViewerPage> {
  late final PageController _pageController;
  late List<Moment> _photos;
  late int _index;
  bool _chrome = true;
  bool _info = false;

  /// Whether the CURRENT photo's bytes are actually on this device — the
  /// metadata panel's Backup row is only honest when it knows this. On a
  /// second device a moment can be fully synced as data while its image
  /// lives solely in Drive.
  Future<bool>? _onDevice;

  @override
  void initState() {
    super.initState();
    _photos = List.of(widget.photos);
    _index = widget.initialIndex.clamp(0, _photos.length - 1);
    _pageController = PageController(initialPage: _index);
    _refreshOnDevice();
  }

  void _refreshOnDevice() {
    final ref = _current.imagePath;
    if (ref == null) {
      _onDevice = null;
      return;
    }
    _onDevice = widget.service
        .resolve(ref)
        .then((file) => file != null && file.existsSync())
        .catchError((_) => false);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Moment get _current => _photos[_index];

  void _confirmDelete() => runAction(#delete, _deleteCurrent);

  Future<void> _deleteCurrent() async {
    final moment = _current;
    final confirmed = await confirmDestructive(
      context,
      title: l(context).momentDeleteTitle,
      body: l(context).momentDeleteBody,
    );
    if (!confirmed) return;
    await widget.onDelete(moment);
    if (!mounted) return;
    setState(() {
      _photos.removeWhere((m) => m.id == moment.id);
      if (_photos.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      _index = _index.clamp(0, _photos.length - 1);
    });
    if (_photos.isNotEmpty && _pageController.hasClients) {
      _pageController.jumpToPage(_index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_photos.isEmpty) return const SizedBox.shrink();
    final moment = _current;
    final media = widget.mediaById[moment.id];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // The photos — tap toggles chrome.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _chrome = !_chrome),
              child: PageView.builder(
                controller: _pageController,
                itemCount: _photos.length,
                onPageChanged: (i) => setState(() {
                  _index = i;
                  _info = false;
                  _refreshOnDevice();
                }),
                itemBuilder: (context, i) => _ZoomablePhoto(
                  service: widget.service,
                  ref: _photos[i].imagePath,
                  heroTag: 'moment-photo-${_photos[i].id}',
                ),
              ),
            ),
          ),

          // Top chrome: close + counter + delete.
          _AnimatedChrome(
            visible: _chrome,
            top: true,
            child: _TopBar(
              index: _index,
              total: _photos.length,
              onClose: () => Navigator.of(context).pop(),
              onDelete: _confirmDelete,
            ),
          ),

          // Bottom chrome: caption + info toggle, expanding into the metadata.
          _AnimatedChrome(
            visible: _chrome,
            top: false,
            child: _BottomBar(
              moment: moment,
              media: media,
              onDevice: _onDevice,
              infoOpen: _info,
              onToggleInfo: () => setState(() => _info = !_info),
            ),
          ),
        ],
      ),
    );
  }
}

/// One pinch/double-tap zoomable photo page.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    required this.service,
    required this.ref,
    required this.heroTag,
  });

  final MediaService service;
  final String? ref;

  /// Matches the gallery tile's Hero so opening reads as the tile expanding.
  final String heroTag;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  late final AnimationController _anim;
  Animation<Matrix4>? _zoomAnim;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _anim =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 260),
        )..addListener(() {
          final value = _zoomAnim?.value;
          if (value != null) _controller.value = value;
        });
  }

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _zoomAnim = Matrix4Tween(
      begin: _controller.value,
      end: target,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  void _handleDoubleTap() {
    final zoomedIn = _controller.value.getMaxScaleOnAxis() > 1.05;
    if (zoomedIn) {
      _animateTo(Matrix4.identity());
      return;
    }
    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;
    const scale = 2.6;
    final target = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (scale - 1),
        -position.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
    _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapDetails = d,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(
          // Same Hero tag as its gallery tile — opening a photo reads as that
          // tile expanding to full screen. Only the initially-open page
          // carries flight (PageView neighbors never participate).
          child: Hero(
            tag: widget.heroTag,
            child: MediaImage(
              service: widget.service,
              ref: widget.ref,
              fit: BoxFit.contain,
              placeholder: const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades + slides the chrome in/out from the matching edge.
class _AnimatedChrome extends StatelessWidget {
  const _AnimatedChrome({
    required this.visible,
    required this.top,
    required this.child,
  });

  final bool visible;
  final bool top;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      top: top ? (visible ? 0 : -140) : null,
      bottom: top ? null : (visible ? 0 : -260),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: visible ? 1 : 0,
        child: child,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.index,
    required this.total,
    required this.onClose,
    required this.onDelete,
  });

  final int index;
  final int total;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 14,
        left: 6,
        right: 6,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          _GlyphButton(icon: AppIcons.close, onTap: onClose, semantic: 'Close'),
          Expanded(
            child: Text(
              '${index + 1} of $total',
              textAlign: TextAlign.center,
              style: AppText.meta.copyWith(color: Colors.white),
            ),
          ),
          _GlyphButton(
            icon: AppIcons.trash,
            onTap: onDelete,
            semantic: 'Delete',
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.moment,
    required this.media,
    required this.onDevice,
    required this.infoOpen,
    required this.onToggleInfo,
  });

  final Moment moment;
  final MediaObject? media;

  /// Whether the photo's bytes are on this device right now (null while
  /// checking, or when the moment has no image) — keeps the Backup row honest.
  final Future<bool>? onDevice;
  final bool infoOpen;
  final VoidCallback onToggleInfo;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            12,
            MediaQuery.of(context).padding.bottom + 16,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xCC000000), Color(0x66000000)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      moment.caption.isEmpty
                          ? 'Untitled moment'
                          : moment.caption,
                      style: AppText.cardTitle.copyWith(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  _GlyphButton(
                    icon: infoOpen ? AppIcons.infoFill : AppIcons.info,
                    onTap: onToggleInfo,
                    semantic: 'Photo info',
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: infoOpen
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 14, right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<bool>(
                        future: onDevice,
                        initialData: true,
                        builder: (context, snap) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final row in buildMomentMetadata(
                              moment,
                              media,
                              photoOnDevice: snap.data ?? true,
                            ))
                              _MetaLine(row: row),
                          ],
                        ),
                      ),
                    ],
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

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.row});
  final MetadataRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              row.label,
              style: AppText.meta.copyWith(
                color: Colors.white54,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              row.value,
              style: AppText.body.copyWith(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.icon,
    required this.onTap,
    required this.semantic,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
