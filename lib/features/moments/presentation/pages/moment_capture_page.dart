import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/domain/media_kind.dart';
import '../../../../core/media/domain/media_object.dart';
import '../../../../core/media/media_service.dart';
import '../../../../core/media/presentation/media_image.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/moment.dart';
import '../../../../core/theme/train_tokens.dart';

/// Moment capture — a photo, a line, or both (either alone is enough to save).
/// Off-by-default privacy: no
/// location is captured unless the user adds it. Pass [initial] to edit an
/// existing moment in place instead of creating a new one; its capture time and
/// any location are preserved untouched.
class MomentCapturePage extends StatefulWidget {
  const MomentCapturePage({super.key, this.initial});

  final Moment? initial;

  @override
  State<MomentCapturePage> createState() => _MomentCapturePageState();
}

class _MomentCapturePageState extends State<MomentCapturePage> {
  late final TextEditingController _caption;

  /// The stored media reference persisted on the moment (relative store path).
  /// For an edited moment this starts as its existing ref.
  String? _imageRef;

  /// A freshly-picked file not yet imported into the media store. Held only
  /// until save, when [MediaService.capture] copies it into durable storage.
  String? _pickedTempPath;

  /// How the freshly-picked photo was obtained (camera vs library), recorded
  /// as media metadata.
  CaptureSource _pickedSource = CaptureSource.unknown;

  bool _canSave = false;

  bool get _editing => widget.initial != null;

  /// A moment is saveable with *either* a caption or a photo — a photo on its
  /// own is a complete moment, so we never force the user to type a line.
  bool get _hasPhoto => _pickedTempPath != null || _imageRef != null;

  void _recomputeCanSave() {
    final canSave = _caption.text.trim().isNotEmpty || _hasPhoto;
    if (canSave != _canSave) setState(() => _canSave = canSave);
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _caption = TextEditingController(text: initial?.caption ?? '');
    _imageRef = initial?.imagePath;
    _canSave = _caption.text.trim().isNotEmpty || _hasPhoto;
    _caption.addListener(_recomputeCanSave);
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    // Camera-first: a moment is usually something happening *now*, so "Take
    // Photo" is the primary action and opens the camera in one tap; the library
    // stays one tap away for existing shots.
    final source = await showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ImageSource.camera),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ImageSource.gallery),
            child: const Text('Choose from Library'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    // Hold the picker's temp path for preview; the durable copy is made on save.
    if (picked != null && mounted) {
      setState(() {
        _pickedTempPath = picked.path;
        _pickedSource = source == ImageSource.camera
            ? CaptureSource.camera
            : CaptureSource.library;
        _canSave = true; // a photo alone is enough to save
      });
    }
  }

  /// Opens the native crop/straighten/rotate editor on the current photo and
  /// keeps the edited result. Works for a freshly-picked photo or an existing
  /// moment's stored photo — resolving via [MediaService.resolveOrFetch], so
  /// a cloud-only photo (synced metadata, image still in Drive) downloads on
  /// demand and edits like any local one rather than silently doing nothing.
  Future<void> _editPhoto() async {
    var path = _pickedTempPath;
    if (path == null && _imageRef != null) {
      final file = await AppScope.of(
        context,
      ).requireMedia.resolveOrFetch(_imageRef);
      path = file?.path;
    }
    if (path == null || !mounted) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
      compressQuality: 92,
      uiSettings: [
        IOSUiSettings(
          title: 'Edit Photo',
          doneButtonTitle: 'Done',
          cancelButtonTitle: 'Cancel',
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
        ),
        AndroidUiSettings(
          toolbarTitle: 'Edit Photo',
          toolbarColor: TrainColors.base,
          toolbarWidgetColor: TrainColors.ink,
          backgroundColor: TrainColors.base,
          activeControlsWidgetColor: TrainColors.ember,
          cropFrameColor: TrainColors.ink,
          cropGridColor: TrainColors.hairlineStrong,
          statusBarLight: false,
          lockAspectRatio: false,
        ),
      ],
    );
    if (cropped != null && mounted) {
      setState(() => _pickedTempPath = cropped.path);
    }
  }

  /// Retake straight from the camera, replacing the current photo.
  Future<void> _retake() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() {
        _pickedTempPath = picked.path;
        _pickedSource = CaptureSource.camera;
        _canSave = true; // a photo alone is enough to save
      });
    }
  }

  void _removePhoto() {
    setState(() {
      _pickedTempPath = null;
      _imageRef = null;
      _pickedSource = CaptureSource.unknown;
      // No photo now ⇒ fall back to requiring a caption.
      _canSave = _caption.text.trim().isNotEmpty;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final scope = AppScope.of(context);
    final moments = scope.moments;
    final initial = widget.initial;
    final id = initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    // Preserve the original capture time on edit; only stamp `now` when new.
    final takenAt = initial?.takenAt ?? DateTime.now();

    // If a new photo was picked, import it into the durable media store now
    // (this also fans out to enabled backup targets, e.g. Save to Photos) and
    // persist the returned store reference instead of the ephemeral temp path.
    var imageRef = _imageRef;
    final tempPath = _pickedTempPath;
    if (tempPath != null) {
      imageRef = await scope.requireMedia.capture(
        sourcePath: tempPath,
        kind: MediaKind.moment,
        id: id,
        ownerUid: scope.auth.currentUser?.uid ?? 'local',
        source: _pickedSource,
        capturedAt: takenAt,
      );
    }

    // An edit that REMOVED the photo must remove its bytes too — the local
    // file, the registry record, and any Drive copy would otherwise outlive
    // the moment as orphans. (A REPLACED photo is handled inside capture():
    // same id → same store path overwritten in place.)
    if (initial != null && initial.imagePath != null && imageRef == null) {
      await scope.requireMedia.deleteMedia(
        id: initial.id,
        ref: initial.imagePath,
      );
    }

    final moment = Moment(
      id: id,
      caption: _caption.text.trim(),
      takenAt: takenAt,
      imagePath: imageRef,
      // Location has no capture UI yet; carry it through untouched on edit.
      location: initial?.location,
    );
    if (initial == null) {
      await moments.add(moment);
    } else {
      await moments.update(moment);
    }
    if (mounted) Navigator.of(context).pop(moment);
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    final scope = AppScope.of(context);
    await scope.moments.remove(initial.id);
    // The moment's photo dies with it — everywhere it lives (see
    // [MediaService.deleteMedia]).
    if (initial.imagePath != null) {
      await scope.requireMedia.deleteMedia(
        id: initial.id,
        ref: initial.imagePath,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureTopBar(
              title: _editing ? 'Edit moment' : 'New moment',
              onClose: () => Navigator.of(context).maybePop(),
              trailing: _editing
                  ? CaptureIconButton(
                      key: const Key('moment-delete'),
                      icon: Icons.delete_outline_rounded,
                      onTap: _delete,
                      semanticLabel: 'Delete moment',
                      iconColor: TrainColors.ember,
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
              child: _PhotoArea(
                service: AppScope.of(context).requireMedia,
                imageRef: _imageRef,
                pickedTempPath: _pickedTempPath,
                onAdd: _pickPhoto,
                onEdit: _editPhoto,
                onRetake: _retake,
                onRemove: _removePhoto,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
              child: TextField(
                controller: _caption,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                cursorColor: TrainColors.ember,
                style: AppText.cardTitle.copyWith(fontSize: 22),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Say something…',
                  hintStyle: AppText.cardTitle.copyWith(
                    fontSize: 22,
                    color: TrainColors.ink3,
                  ),
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                8,
                18,
                MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 8,
              ),
              child: PillButton(
                label: _editing ? 'Save moment' : 'Add moment',
                icon: _editing ? Icons.check_rounded : Icons.add_rounded,
                enabled: _canSave,
                onTap: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The capture page's photo block. Empty: a tap-to-add tile that opens the
/// camera-first sheet. With a photo: the image plus a polished action bar —
/// Edit (crop/straighten), Retake, Remove — so the whole take/edit/keep flow
/// lives in one place.
class _PhotoArea extends StatelessWidget {
  const _PhotoArea({
    required this.service,
    required this.imageRef,
    required this.pickedTempPath,
    required this.onAdd,
    required this.onEdit,
    required this.onRetake,
    required this.onRemove,
  });

  final MediaService service;
  final String? imageRef;
  final String? pickedTempPath;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback onRetake;
  final VoidCallback onRemove;

  bool get _hasPhoto => pickedTempPath != null || imageRef != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasPhoto) {
      return GestureDetector(
        onTap: onAdd,
        child: AspectRatio(
          aspectRatio: 3 / 2,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [TrainColors.raised, TrainColors.raisedStrong],
              ),
              border: Border.all(color: TrainColors.hairlineStrong),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    AppIcons.camera,
                    size: 30,
                    color: TrainColors.ink3,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Add a photo',
                    style: AppText.body.copyWith(color: TrainColors.ink3),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        GestureDetector(
          onTap: onEdit,
          child: AspectRatio(
            aspectRatio: 3 / 2,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
              ),
              child: pickedTempPath != null
                  ? Image.file(File(pickedTempPath!), fit: BoxFit.cover)
                  : MediaImage(
                      service: service,
                      ref: imageRef,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _PhotoAction(icon: AppIcons.crop, label: 'Edit', onTap: onEdit),
            const SizedBox(width: 10),
            _PhotoAction(
              icon: AppIcons.retake,
              label: 'Retake',
              onTap: onRetake,
            ),
            const SizedBox(width: 10),
            _PhotoAction(
              icon: AppIcons.trash,
              label: 'Remove',
              onTap: onRemove,
              tint: TrainColors.ember,
            ),
          ],
        ),
      ],
    );
  }
}

class _PhotoAction extends StatelessWidget {
  const _PhotoAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? TrainColors.ink;
    return Expanded(
      child: PressableScale(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TrainColors.raised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: TrainColors.hairlineStrong),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: AppText.button.copyWith(fontSize: 13.5, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
