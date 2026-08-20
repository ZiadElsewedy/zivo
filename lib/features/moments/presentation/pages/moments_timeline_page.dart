import 'package:flutter/material.dart';

import '../../../../core/media/domain/media_object.dart';
import '../../../../core/media/presentation/media_image.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../domain/moment.dart';
import 'moment_capture_page.dart';
import 'photo_viewer_page.dart';
import '../../../../core/media/presentation/storage_sync_page.dart';

/// How the gallery grid is filtered. Camera/Library read the media record's
/// capture source; Photos filters to moments that actually have an image.
enum MomentFilter { all, photos, camera, library }

extension on MomentFilter {
  String get label => switch (this) {
        MomentFilter.all => 'All',
        MomentFilter.photos => 'Photos',
        MomentFilter.camera => 'Camera',
        MomentFilter.library => 'Library',
      };
}

/// Moments as a real gallery: a clean, scrollable grid of photos (newest
/// first), a filter bar, and a full-screen zoomable viewer with per-photo
/// metadata behind each tile. Caption-only moments open straight into edit.
class MomentsTimelinePage extends StatefulWidget {
  const MomentsTimelinePage({super.key});

  @override
  State<MomentsTimelinePage> createState() => _MomentsTimelinePageState();
}

class _MomentsTimelinePageState extends State<MomentsTimelinePage> {
  MomentFilter _filter = MomentFilter.all;
  Map<String, MediaObject> _media = const {};
  bool _mediaLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_mediaLoaded) {
      _mediaLoaded = true;
      _loadMedia();
    }
  }

  Future<void> _loadMedia() async {
    try {
      final all = await AppScope.of(context).requireMedia.registry.getAll();
      if (mounted) {
        setState(() => _media = {for (final m in all) m.id: m});
      }
    } catch (_) {
      // Metadata is best-effort; the grid still renders from the moments.
    }
  }

  bool _matches(Moment moment) {
    switch (_filter) {
      case MomentFilter.all:
        return true;
      case MomentFilter.photos:
        return moment.imagePath != null;
      case MomentFilter.camera:
        return _media[moment.id]?.source == CaptureSource.camera;
      case MomentFilter.library:
        return _media[moment.id]?.source == CaptureSource.library;
    }
  }

  Future<void> _newMoment() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MomentCapturePage()),
    );
    await _loadMedia();
  }

  Future<void> _openEdit(Moment moment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MomentCapturePage(initial: moment)),
    );
    await _loadMedia();
  }

  Future<void> _openPhoto(List<Moment> photos, int index) async {
    final moments = AppScope.of(context).moments;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerPage(
          service: AppScope.of(context).requireMedia,
          photos: photos,
          mediaById: _media,
          initialIndex: index,
          onDelete: (m) => moments.remove(m.id),
        ),
      ),
    );
    await _loadMedia();
  }

  @override
  Widget build(BuildContext context) {
    final moments = AppScope.of(context).moments;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Moments', style: AppText.cardTitle),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.backupNow, color: AppColors.ink2),
            tooltip: 'Storage & Sync',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StorageSyncPage()),
              );
              await _loadMedia();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.ember,
        elevation: 2,
        tooltip: 'New moment',
        onPressed: _newMoment,
        child: const Icon(AppIcons.camera, color: Colors.white),
      ),
      body: StreamBuilder<List<Moment>>(
        stream: moments.watchAll(),
        initialData: moments.current,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const ErrorStateView();
          final all = snapshot.data ?? const <Moment>[];
          if (all.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingStateView();
          }
          if (all.isEmpty) {
            return const EmptyStateView('No moments yet.');
          }
          final filtered = all.where(_matches).toList(growable: false);
          final photos = filtered
              .where((m) => m.imagePath != null)
              .toList(growable: false);
          final now = DateTime.now();
          return Column(
            children: [
              _FilterBar(
                selected: _filter,
                onSelect: (f) => setState(() => _filter = f),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? EmptyStateView(_emptyLabel())
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 100),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final moment = filtered[i];
                          return _GalleryTile(
                            moment: moment,
                            media: _media[moment.id],
                            now: now,
                            onTap: () {
                              if (moment.imagePath == null) {
                                _openEdit(moment);
                              } else {
                                _openPhoto(photos, photos.indexOf(moment));
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _emptyLabel() => switch (_filter) {
        MomentFilter.camera => 'No camera photos yet.',
        MomentFilter.library => 'Nothing from your library yet.',
        MomentFilter.photos => 'No photos yet.',
        MomentFilter.all => 'No moments yet.',
      };
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelect});

  final MomentFilter selected;
  final ValueChanged<MomentFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        children: [
          for (final filter in MomentFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterChip(
                label: filter.label,
                active: filter == selected,
                onTap: () => onSelect(filter),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: active ? AppColors.ember : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: active ? AppColors.ember : AppColors.hairline2,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: AppText.button.copyWith(
              fontSize: 13.5,
              color: active ? Colors.white : AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.moment,
    required this.media,
    required this.now,
    required this.onTap,
  });

  final Moment moment;
  final MediaObject? media;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = moment.imagePath != null;
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: AppColors.card,
            child: hasPhoto ? _photo(context) : _captionTile(),
          ),
        ),
      ),
    );
  }

  Widget _photo(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MediaImage(
          service: AppScope.of(context).requireMedia,
          ref: moment.imagePath,
          fit: BoxFit.cover,
          // Shown until the photo resolves — on another device it may live only
          // in Google Drive and is being fetched, or isn't backed up/reachable.
          placeholder: const ColoredBox(
            color: AppColors.surfaceRaised,
            child: Center(
              child: Icon(AppIcons.driveCloud, size: 22, color: AppColors.ink3),
            ),
          ),
        ),
        if (media?.source == CaptureSource.camera)
          const Positioned(
            right: 6,
            top: 6,
            child: _CornerGlyph(icon: AppIcons.camera),
          ),
      ],
    );
  }

  Widget _captionTile() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(AppIcons.caption, size: 18, color: AppColors.ink3),
          Text(
            moment.caption.isEmpty ? 'Untitled' : moment.caption,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppText.body.copyWith(fontSize: 12.5, color: AppColors.ink2),
          ),
          Text(
            timeAgo(moment.takenAt, now),
            style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _CornerGlyph extends StatelessWidget {
  const _CornerGlyph({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 13, color: Colors.white),
    );
  }
}
