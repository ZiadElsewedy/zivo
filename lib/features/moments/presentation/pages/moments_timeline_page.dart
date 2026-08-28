import 'package:flutter/material.dart';

import '../../../../core/media/domain/media_object.dart';
import '../../../../core/media/presentation/media_image.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../domain/moment.dart';
import 'moment_capture_page.dart';
import 'photo_viewer_page.dart';
import '../../../../core/media/presentation/storage_sync_page.dart';

/// How the gallery grid is filtered. Camera/Library read the media record's
/// capture source; Photos filters to moments that actually have an image.
enum MomentFilter { all, photos, notes, camera, library }

extension on MomentFilter {
  String get label => switch (this) {
    MomentFilter.all => 'All',
    MomentFilter.photos => 'Photos',
    MomentFilter.notes => 'Notes',
    MomentFilter.camera => 'Camera',
    MomentFilter.library => 'Library',
  };
}

/// Moments as a real gallery: a clean, scrollable grid of photos (newest
/// first), a filter bar, and a full-screen zoomable viewer with per-photo
/// metadata behind each tile. Caption-only moments open straight into edit.
///
/// Dressed to the design handoff's **Moments** screen (4d): the warm screen
/// wash, the 36px back circle beside the Manrope 800/27 title, ember-selected
/// filter pills, the dashed empty state, and the ember camera FAB.
///
/// The handoff draws this screen in its FIRST-ENTRY state — one note card and
/// an empty rest — and explicitly leaves the photo grid for a later pass
/// ("Moments with a real photo grid"), so the grid here keeps its existing
/// shape and takes the handoff's material rather than being redrawn to a
/// layout the handoff never specified.
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
      case MomentFilter.notes:
        return moment.imagePath == null;
      case MomentFilter.camera:
        return _media[moment.id]?.source == CaptureSource.camera;
      case MomentFilter.library:
        return _media[moment.id]?.source == CaptureSource.library;
    }
  }

  Future<void> _newMoment() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MomentCapturePage()));
    await _loadMedia();
  }

  Future<void> _openEdit(Moment moment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MomentCapturePage(initial: moment)),
    );
    await _loadMedia();
  }

  Future<void> _openPhoto(List<Moment> photos, int index) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerPage(
          service: AppScope.of(context).requireMedia,
          photos: photos,
          mediaById: _media,
          initialIndex: index,
          onDelete: _deleteMomentCompletely,
        ),
      ),
    );
    await _loadMedia();
  }

  /// Deletes a moment AND its media everywhere it lives — the local file,
  /// the registry record, and the Google Drive copy (best-effort, when one
  /// exists). Deleting only the Firestore doc would orphan the bytes on
  /// every device and in the cloud, and leave a ghost tile for any moment
  /// whose caption was empty.
  Future<void> _deleteMomentCompletely(Moment moment) async {
    final scope = AppScope.of(context);
    await scope.moments.remove(moment.id);
    await scope.requireMedia.deleteMedia(id: moment.id, ref: moment.imagePath);
    await _loadMedia();
  }

  @override
  Widget build(BuildContext context) {
    final moments = AppScope.of(context).moments;
    return TrainScreen(
      tint: TrainColors.momentsTint,
      floatingActionButton: TrainFab(
        icon: AppIcons.camera,
        semanticLabel: 'New moment',
        onTap: _newMoment,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: TrainPageHeader(
              title: 'Moments',
              action: TrainHeaderAction(
                icon: AppIcons.backupNow,
                semanticLabel: 'Storage & Sync',
                accent: TrainColors.green,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StorageSyncPage()),
                  );
                  await _loadMedia();
                },
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Moment>>(
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
                  return const _MomentsEmptyState(title: 'Nothing logged yet');
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
                          ? _MomentsEmptyState(title: _emptyLabel())
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                6,
                                14,
                                100,
                              ),
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
                                      _openPhoto(
                                        photos,
                                        photos.indexOf(moment),
                                      );
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
          ),
        ],
      ),
    );
  }

  String _emptyLabel() => switch (_filter) {
    MomentFilter.camera => 'No camera photos yet.',
    MomentFilter.library => 'Nothing from your library yet.',
    MomentFilter.photos => 'No photos yet.',
    MomentFilter.notes => 'No notes yet.',
    MomentFilter.all => 'Nothing else logged yet',
  };
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelect});

  final MomentFilter selected;
  final ValueChanged<MomentFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 6),
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
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      TrainFilterPill(label: label, selected: active, onTap: onTap);
}

/// The handoff's empty state: a 52px dashed camera tile, a Manrope headline,
/// and one line saying what a moment is for. Dashed, because there is nothing
/// behind it yet — a filled card here would be a container waiting on data.
class _MomentsEmptyState extends StatelessWidget {
  const _MomentsEmptyState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrainDashedCard(
              radius: 18,
              padding: EdgeInsets.zero,
              child: const SizedBox(
                width: 52,
                height: 52,
                child: Icon(
                  AppIcons.camera,
                  size: 22,
                  color: Color(0x59F4F4F0),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TrainType.ui(
                size: 16,
                weight: FontWeight.w700,
                color: const Color(0x99F4F4F0),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'Snap a lift, a meal, or a scale reading — moments attach to '
              'the session you were in.',
              textAlign: TextAlign.center,
              style: TrainType.ui(
                size: 12.5,
                weight: FontWeight.w400,
                color: const Color(0x61F4F4F0),
                height: 1.55,
              ),
            ),
          ],
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
            color: const Color(0x0BFFFFFF),
            child: hasPhoto ? _photo(context) : _captionTile(),
          ),
        ),
      ),
    );
  }

  /// Tile width × devicePixelRatio — the decode target that keeps a
  /// three-across grid from decoding full 1600px captures per cell.
  int _decodeWidth(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final tileWidth =
        (MediaQuery.of(context).size.width - 28 - 12) /
        3; // 14px gutters + gaps
    return (tileWidth * dpr).round().clamp(120, 800);
  }

  Widget _photo(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Hero-tagged so opening the viewer reads as THE tile expanding to
        // fill the screen — not a new screen appearing over the grid.
        Hero(
          tag: 'moment-photo-${moment.id}',
          child: MediaImage(
            service: AppScope.of(context).requireMedia,
            ref: moment.imagePath,
            fit: BoxFit.cover,
            decodeWidth: _decodeWidth(context),
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
          const Icon(AppIcons.caption, size: 17, color: Color(0x59F4F4F0)),
          // Flexible so the caption YIELDS when the square tile is tight
          // (narrow widths / larger text scale) instead of forcing its full
          // 3-line height and overflowing the cell by a few px — the
          // "Bottom overflowed by N pixels" on this grid. Still ellipsizes.
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                moment.caption.isEmpty ? 'Untitled' : moment.caption,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TrainType.ui(
                  size: 12.5,
                  weight: FontWeight.w400,
                  color: TrainColors.ink2,
                  height: 1.4,
                ),
              ),
            ),
          ),
          Text(
            timeAgo(moment.takenAt, now).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TrainType.caption(
              size: 8.5,
              tracking: 0.14,
              color: TrainColors.ink4,
            ),
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
