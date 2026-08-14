import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/schedule_event.dart';

/// Event capture — a time-anchored commitment. Title, a start time, optional
/// location. Lightweight; date defaults to today.
class EventCapturePage extends StatefulWidget {
  const EventCapturePage({super.key});

  @override
  State<EventCapturePage> createState() => _EventCapturePageState();
}

class _EventCapturePageState extends State<EventCapturePage> {
  final TextEditingController _title = TextEditingController();
  late TimeOfDay _time;
  String? _location;
  bool _canAdd = false;

  @override
  void initState() {
    super.initState();
    final now = TimeOfDay.now();
    _time = now.replacing(hour: (now.hour + 1) % 24, minute: 0);
    _title.addListener(() {
      final canAdd = _title.text.trim().isNotEmpty;
      if (canAdd != _canAdd) setState(() => _canAdd = canAdd);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
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

  Future<void> _add() async {
    if (!_canAdd) return;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, _time.hour, _time.minute);
    final event = ScheduleEvent(
      id: now.microsecondsSinceEpoch.toString(),
      title: _title.text.trim(),
      start: start,
      end: start.add(const Duration(hours: 1)),
      location: _location,
    );
    await AppScope.of(context).schedule.add(event);
    if (mounted) Navigator.of(context).pop(event);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureTopBar(title: 'New event', onClose: () => Navigator.of(context).maybePop()),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 6),
              child: TextField(
                controller: _title,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
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
                    selected: true,
                    onTap: () {},
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
                label: 'Add event',
                icon: Icons.add_rounded,
                enabled: _canAdd,
                onTap: _add,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
