import 'package:flutter/material.dart';
import '../../../../l10n/l10n.dart';

import '../../../../core/media/domain/media_object.dart';
import '../../../../core/media/presentation/media_image.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/deferred_write.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../domain/moment.dart';
import 'moment_capture_page.dart';
import 'photo_viewer_page.dart';
import '../../../../core/media/presentation/storage_sync_page.dart';
import '../../../../core/util/bidi.dart';

/// How the gallery grid is filtered. Camera/Library read the media record's
/// capture source; Photos filters to moments that actually have an image.
enum MomentFilter { all, photos, notes, camera, library }

extension on MomentFilter {
  /// The filter's word on screen. Takes a context because it is copy — the
  /// five ARB keys already existed and this extension simply never read them,
  /// so the filter bar stayed English on an otherwise Arabic gallery.
  String label(BuildContext context) => switch (this) {
    MomentFilter.all => l(context).momentsFilterAll,
    MomentFilter.photos => l(context).momentsFilterPhotos,
    MomentFilter.notes => l(context).momentsFilterNotes,
    MomentFilter.camera => l(context).momentsFilterCamera,
    MomentFilter.library => l(context).momentsFilterLibrary,
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
/// The gallery's column count — shared by the grid delegate and the
/// sparse-row filler so they can't disagree.
const int _kGridColumns = 3;

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

  /// How many dashed "add" tiles to append so a sparse grid still fills its
  /// first row. Zero once there is a full row of real moments.
  static int _rowFillers(int count) =>
      count == 0 || count >= _kGridColumns ? 0 : _kGridColumns - count;

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
  /// Local-first: the grid drops the tile now (the Firestore delete reaches
  /// its own listeners off the cache), and the durable removal — the row, the
  /// local file, the registry entry, any Drive copy — finishes behind it.
  Future<void> _deleteMomentCompletely(Moment moment) async {
    final scope = AppScope.of(context);
    final media = scope.requireMedia;
    final moments = scope.moments;
    deferWrite(() async {
      await moments.remove(moment.id);
      await media.deleteMedia(id: moment.id, ref: moment.imagePath);
    }(), failureMessage: l(context).momentDeleteFailed);
    await _loadMedia();
  }

  @override
  Widget build(BuildContext context) {
    final moments = AppScope.of(context).moments;
    return TrainScreen(
      tint: TrainColors.momentsTint,
      floatingActionButton: TrainFab(
        icon: AppIcons.camera,
        semanticLabel: l(context).momentNewTitle,
        onTap: _newMoment,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: TrainPageHeader(
              title: l(context).momentsTitle,
              action: TrainHeaderAction(
                icon: AppIcons.backupNow,
                semanticLabel: l(context).storageTitle,
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
                  return _MomentsEmptyState(
                    title: l(context).momentsEmptyTitle,
                  );
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
                              padding: EdgeInsets.fromLTRB(
                                14,
                                6,
                                14,
                                TrainBottomInset.of(context),
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _kGridColumns,
                                    mainAxisSpacing: 6,
                                    crossAxisSpacing: 6,
                                  ),
                              // A 3-up grid with one moment in it left a
                              // single tile marooned in a screenful of black,
                              // which reads as a gallery that failed to load
                              // rather than as a life with one moment saved.
                              // Below a full row, the remaining slots are
                              // dashed "add" tiles: the row reads as a row,
                              // and the gap becomes an invitation. They stop
                              // appearing the moment there's real content.
                              itemCount:
                                  filtered.length +
                                  _rowFillers(filtered.length),
                              itemBuilder: (context, i) {
                                if (i >= filtered.length) {
                                  return _AddMomentTile(onTap: _newMoment);
                                }
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
    MomentFilter.camera => l(context).momentsEmptyCamera,
    MomentFilter.library => l(context).momentsEmptyLibrary,
    MomentFilter.photos => l(context).momentsEmptyPhotos,
    MomentFilter.notes => l(context).momentsEmptyNotes,
    MomentFilter.all => l(context).momentsEmptyOther,
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
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _FilterChip(
                label: filter.label(context),
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
              child: SizedBox(
                width: 52,
                height: 52,
                child: Icon(
                  AppIcons.camera,
                  size: 22,
                  color: TrainColors.inkAt(0.35),
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
                color: TrainColors.inkAt(0.6),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              l(context).momentsEmptyBody,
              textAlign: TextAlign.center,
              style: TrainType.ui(
                size: 12.5,
                weight: FontWeight.w400,
                color: TrainColors.inkAt(0.38),
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
            color: TrainColors.glass,
            child: hasPhoto ? _photo(context) : _captionTile(context),
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

  Widget _captionTile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(AppIcons.caption, size: 17, color: TrainColors.inkAt(0.35)),
          // Flexible so the caption YIELDS when the square tile is tight
          // (narrow widths / larger text scale) instead of forcing its full
          // 3-line height and overflowing the cell by a few px — the
          // "Bottom overflowed by N pixels" on this grid. Still ellipsizes.
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Builder(
                builder: (context) {
                  final caption = moment.caption.isEmpty
                      ? l(context).momentUntitled
                      : moment.caption;
                  return Text(
                    caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    // The user's own words pick their own direction — an
                    // English note in an Arabic gallery otherwise
                    // right-aligned with its full stop flung to the far end.
                    textDirection: directionOfFor(context, caption),
                    textAlign: TextAlign.start,
                    style: TrainType.ui(
                      size: 12.5,
                      weight: FontWeight.w400,
                      color: TrainColors.ink2,
                      height: 1.4,
                    ),
                  );
                },
              ),
            ),
          ),
          Text(
            timeAgo(context, moment.takenAt, now).toUpperCase(),
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

/// A dashed slot that completes a sparse first row and offers the next
/// moment. Uses the same dashed language as the empty state, so a
/// one-moment grid reads as the same designed surface, not a broken one.
class _AddMomentTile extends StatelessWidget {
  const _AddMomentTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TrainDashedCard(
      radius: 14,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Center(
        child: Icon(AppIcons.add, size: 20, color: TrainColors.ink4),
      ),
    );
  }
}
