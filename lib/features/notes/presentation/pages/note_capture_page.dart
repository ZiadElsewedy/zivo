import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/note.dart';

/// Note capture — body-first; title optional. Speed over structure. Pass
/// [initial] to edit an existing note in place instead of creating a new one.
class NoteCapturePage extends StatefulWidget {
  const NoteCapturePage({super.key, this.initial});

  final Note? initial;

  @override
  State<NoteCapturePage> createState() => _NoteCapturePageState();
}

class _NoteCapturePageState extends State<NoteCapturePage> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  bool _canSave = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _body = TextEditingController(text: initial?.body ?? '');
    _canSave = _body.text.trim().isNotEmpty;
    _body.addListener(() {
      final canSave = _body.text.trim().isNotEmpty;
      if (canSave != _canSave) setState(() => _canSave = canSave);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final notes = AppScope.of(context).notes;
    final initial = widget.initial;
    final note = Note(
      id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      body: _body.text.trim(),
      updatedAt: DateTime.now(),
    );
    if (initial == null) {
      await notes.add(note);
    } else {
      await notes.update(note);
    }
    if (mounted) Navigator.of(context).pop(note);
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    final notes = AppScope.of(context).notes;
    await notes.remove(initial.id);
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
              title: _editing ? 'Edit note' : 'New note',
              onClose: () => Navigator.of(context).maybePop(),
              trailing: _editing
                  ? CaptureIconButton(
                      key: const Key('note-delete'),
                      icon: Icons.delete_outline_rounded,
                      onTap: _delete,
                      semanticLabel: 'Delete note',
                      iconColor: AppColors.flareText,
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                cursorColor: AppColors.ember,
                style: AppText.cardTitle.copyWith(fontSize: 23),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Title (optional)',
                  hintStyle: AppText.cardTitle.copyWith(fontSize: 23, color: AppColors.ink3),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _body,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  cursorColor: AppColors.ember,
                  style: AppText.body.copyWith(fontSize: 16, color: AppColors.ink),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Catch a thought…',
                    hintStyle: AppText.body.copyWith(fontSize: 16, color: AppColors.ink3),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                8,
                18,
                MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 8,
              ),
              child: PillButton(
                label: _editing ? 'Save note' : 'Add note',
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
