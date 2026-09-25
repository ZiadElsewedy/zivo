import 'package:flutter/material.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../capture/presentation/widgets/capture_widgets.dart';
import 'plan_edit_chrome.dart';
import '../../controllers/plan_edit_controller.dart';
import '../../../../../l10n/l10n.dart';

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
      title: l(context).planAddDay,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: LabeledField(
                label: l(context).planDaySlot,
                controller: _slot,
                hint: l(context).planDaySlotHint,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                fieldKey: const Key('day-label-field'),
                label: l(context).planDayLabel,
                controller: _label,
                hint: l(context).planDayLabelHint,
                autofocus: true,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LabeledField(
          label: l(context).planDayNotesOptional,
          controller: _notes,
          hint: '—',
        ),
        const SizedBox(height: 22),
        PillButton(
          label: l(context).planAddDay,
          icon: Icons.add_rounded,
          color: TrainColors.green,
          enabled: _canAdd,
          onTap: _submit,
        ),
      ],
    );
  }
}
