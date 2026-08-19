import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  String? _imagePath;
  bool _canSave = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _caption = TextEditingController(text: initial?.caption ?? '');
    _imagePath = initial?.imagePath;
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
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _imagePath = picked.path);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final moments = AppScope.of(context).moments;
    final initial = widget.initial;
    final moment = Moment(
      id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      caption: _caption.text.trim(),
      // Preserve the original capture time on edit; only stamp `now` when new.
      takenAt: initial?.takenAt ?? DateTime.now(),
      imagePath: _imagePath,
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
              child: _PhotoTile(imagePath: _imagePath, onTap: _pickPhoto),
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
  const _PhotoTile({required this.imagePath, required this.onTap});

  final String? imagePath;
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
          child: imagePath == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_a_photo_outlined, size: 28, color: AppColors.ink3),
                      const SizedBox(height: 8),
                      Text('Add a photo', style: AppText.body.copyWith(color: AppColors.ink3)),
                    ],
                  ),
                )
              : Image.file(File(imagePath!), fit: BoxFit.cover),
        ),
      ),
    );
  }
}
