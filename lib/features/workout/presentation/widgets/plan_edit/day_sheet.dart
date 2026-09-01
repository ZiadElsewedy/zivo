import 'package:flutter/material.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../capture/presentation/widgets/capture_widgets.dart';
import 'plan_edit_chrome.dart';
import '../../controllers/plan_edit_controller.dart';

/// A sheet to add one day: a slot letter, a label, and optional notes.
class DaySheet extends StatefulWidget {
  const DaySheet({required this.suggestedSlot, super.key});

  final String suggestedSlot;

  @override
  State<DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<DaySheet> {
  late final TextEditingController _slot = TextEditingController(
    text: widget.suggestedSlot,
  );
  final TextEditingController _label = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  bool _canAdd = false;

  @override
  void initState() {
    super.initState();
    _label.addListener(() {
      final canAdd = _label.text.trim().isNotEmpty;
      if (canAdd != _canAdd) setState(() => _canAdd = canAdd);
    });
  }

  @override
  void dispose() {
    _slot.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canAdd) return;
    final slot = _slot.text.trim().isEmpty
        ? widget.suggestedSlot
        : _slot.text.trim();
    final notes = _notes.text.trim();
    Navigator.of(context).pop(
      DayDraft(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        slot: slot,
        label: _label.text.trim(),
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: 'Add day',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: LabeledField(label: 'Slot', controller: _slot, hint: 'A'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                fieldKey: const Key('day-label-field'),
                label: 'Label',
                controller: _label,
                hint: 'Push / Pull / Legs',
                autofocus: true,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LabeledField(label: 'Notes (optional)', controller: _notes, hint: '—'),
        const SizedBox(height: 22),
        PillButton(
          label: 'Add day',
          icon: Icons.add_rounded,
          color: TrainColors.green,
          enabled: _canAdd,
          onTap: _submit,
        ),
      ],
    );
  }
}
