import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/schedule_event.dart';

enum _DateChoice { today, tomorrow, custom }

/// Event create-or-edit — title, a date + start time, optional location.
/// Pass [initial] to edit an existing event in place instead of creating a
/// new one; editing preserves the event's original duration.
class EventCapturePage extends StatefulWidget {
  const EventCapturePage({super.key, this.initial});

  final ScheduleEvent? initial;

  @override
  State<EventCapturePage> createState() => _EventCapturePageState();
}

class _EventCapturePageState extends State<EventCapturePage> {
  final TextEditingController _title = TextEditingController();
  late _DateChoice _dateChoice;
  DateTime? _customDate;
  late TimeOfDay _time;
  String? _location;
  bool _canAdd = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title.text = initial?.title ?? '';
    _location = initial?.location;

    final today = _today();
    if (initial == null) {
      _dateChoice = _DateChoice.today;
      final now = TimeOfDay.now();
      _time = now.replacing(hour: (now.hour + 1) % 24, minute: 0);
    } else {
      final start = initial.start;
      final startDay = DateTime(start.year, start.month, start.day);
      if (startDay == today) {
        _dateChoice = _DateChoice.today;
      } else if (startDay == today.add(const Duration(days: 1))) {
        _dateChoice = _DateChoice.tomorrow;
      } else {
        _dateChoice = _DateChoice.custom;
        _customDate = startDay;
      }
      _time = TimeOfDay(hour: start.hour, minute: start.minute);
    }

    _canAdd = _title.text.trim().isNotEmpty;
    _title.addListener(() {
      final canAdd = _title.text.trim().isNotEmpty;
      if (canAdd != _canAdd) setState(() => _canAdd = canAdd);
    });
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime _resolveDate() {
    final today = _today();
    return switch (_dateChoice) {
      _DateChoice.today => today,
      _DateChoice.tomorrow => today.add(const Duration(days: 1)),
      _DateChoice.custom => _customDate ?? today,
    };
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() {
        _customDate = DateTime(picked.year, picked.month, picked.day);
        _dateChoice = _DateChoice.custom;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _editLocation() async {
    final controller = TextEditingController(text: _location);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Location', style: AppText.cardTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.rowTitle,
          decoration: const InputDecoration(hintText: 'Where?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppText.button.copyWith(color: AppColors.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Done', style: AppText.button.copyWith(color: AppColors.emberText)),
          ),
        ],
      ),
    );
    if (result != null) setState(() => _location = result.isEmpty ? null : result);
  }

  Future<void> _save() async {
    if (!_canAdd) return;
    final schedule = AppScope.of(context).schedule;
    final initial = widget.initial;
    final date = _resolveDate();
    final start = DateTime(date.year, date.month, date.day, _time.hour, _time.minute);
    final duration = initial == null
        ? const Duration(hours: 1)
        : (initial.end != null
              ? initial.end!.difference(initial.start)
              : const Duration(hours: 1));
    final event = ScheduleEvent(
      id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: _title.text.trim(),
      start: start,
      end: start.add(duration),
      location: _location,
      label: initial?.label,
    );
    if (initial == null) {
      await schedule.add(event);
    } else {
      await schedule.update(event);
    }
    if (mounted) Navigator.of(context).pop(event);
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    final schedule = AppScope.of(context).schedule;
    await schedule.remove(initial.id);
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
              title: _editing ? 'Edit event' : 'New event',
              onClose: () => Navigator.of(context).maybePop(),
              trailing: _editing
                  ? InkWell(
                      key: const Key('event-delete'),
                      onTap: _delete,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFEBE3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.flareText,
                        ),
                      ),
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 6),
              child: TextField(
                controller: _title,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                cursorColor: AppColors.ember,
                style: AppText.cardTitle.copyWith(fontSize: 27),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: "What's happening?",
                  hintStyle: AppText.cardTitle.copyWith(fontSize: 27, color: AppColors.ink3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
              child: Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  SelectChip(
                    label: 'Today',
                    selected: _dateChoice == _DateChoice.today,
                    onTap: () => setState(() => _dateChoice = _DateChoice.today),
                  ),
                  SelectChip(
                    label: 'Tomorrow',
                    selected: _dateChoice == _DateChoice.tomorrow,
                    onTap: () => setState(() => _dateChoice = _DateChoice.tomorrow),
                  ),
                  SelectChip(
                    label: _dateChoice == _DateChoice.custom && _customDate != null
                        ? _formatDate(_customDate!)
                        : 'Date',
                    icon: Icons.calendar_today_rounded,
                    selected: _dateChoice == _DateChoice.custom,
                    onTap: _pickDate,
                  ),
                  SelectChip(
                    label: _time.format(context),
                    icon: Icons.schedule_rounded,
                    selected: true,
                    onTap: _pickTime,
                  ),
                  SelectChip(
                    label: _location ?? 'Location',
                    icon: Icons.place_outlined,
                    selected: _location != null,
                    onTap: _editLocation,
                  ),
                ],
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
                label: _editing ? 'Save event' : 'Add event',
                icon: _editing ? Icons.check_rounded : Icons.add_rounded,
                enabled: _canAdd,
                onTap: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
