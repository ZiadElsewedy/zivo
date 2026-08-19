import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/domain/media_kind.dart';
import '../../../../core/media/media_service.dart';
import '../../../../core/media/presentation/media_image.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/moment.dart';

/// Moment capture — an optional photo plus a line. Off-by-default privacy: no
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

  bool _canSave = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _caption = TextEditingController(text: initial?.caption ?? '');
    _imageRef = initial?.imagePath;
    _canSave = _caption.text.trim().isNotEmpty;
    _caption.addListener(() {
      final canSave = _caption.text.trim().isNotEmpty;
      if (canSave != _canSave) setState(() => _canSave = canSave);
    });
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
    if (picked != null && mounted) setState(() => _pickedTempPath = picked.path);
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
        capturedAt: takenAt,
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
    final moments = AppScope.of(context).moments;
    await moments.remove(initial.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
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
                      iconColor: AppColors.flareText,
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
              child: _PhotoTile(
                service: AppScope.of(context).requireMedia,
                imageRef: _imageRef,
                pickedTempPath: _pickedTempPath,
                onTap: _pickPhoto,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
              child: TextField(
                controller: _caption,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                cursorColor: AppColors.ember,
                style: AppText.cardTitle.copyWith(fontSize: 22),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Say something…',
                  hintStyle: AppText.cardTitle.copyWith(fontSize: 22, color: AppColors.ink3),
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

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.service,
    required this.imageRef,
    required this.pickedTempPath,
    required this.onTap,
  });

  final MediaService service;

  /// The stored (durable) reference for an existing photo.
  final String? imageRef;

  /// A just-picked, not-yet-stored temp file (takes precedence for preview).
  final String? pickedTempPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 3 / 2,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.card, AppColors.surfaceRaised],
            ),
          ),
          child: _preview(),
        ),
      ),
    );
  }

  Widget _preview() {
    if (pickedTempPath != null) {
      return Image.file(File(pickedTempPath!), fit: BoxFit.cover);
    }
    if (imageRef != null) {
      return MediaImage(service: service, ref: imageRef, fit: BoxFit.cover);
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_a_photo_outlined, size: 28, color: AppColors.ink3),
          const SizedBox(height: 8),
          Text('Add a photo', style: AppText.body.copyWith(color: AppColors.ink3)),
        ],
      ),
    );
  }
}
