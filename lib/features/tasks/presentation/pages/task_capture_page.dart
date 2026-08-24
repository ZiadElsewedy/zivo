import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/task.dart';

enum _Due { none, today, tomorrow, custom }

/// Task create-or-edit — title is enough; due and priority are one-tap and
/// optional. Lightweight by design (a personal OS, not Jira). Pass [initial]
/// to edit an existing task in place instead of creating a new one.
class TaskCapturePage extends StatefulWidget {
  const TaskCapturePage({super.key, this.initial});

  final Task? initial;

  @override
  State<TaskCapturePage> createState() => _TaskCapturePageState();
}

class _TaskCapturePageState extends State<TaskCapturePage> {
  late final TextEditingController _title;
  late _Due _due;
  DateTime? _customDate;
  late bool _priority;
  bool _canAdd = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _priority = initial?.priority ?? false;
    final today = _today();
    final due = initial?.due;
    if (initial == null) {
      _due = _Due.today;
    } else if (due == null) {
      _due = _Due.none;
    } else if (due == today) {
      _due = _Due.today;
    } else if (due == today.add(const Duration(days: 1))) {
      _due = _Due.tomorrow;
    } else {
      _due = _Due.custom;
      _customDate = due;
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

  DateTime? _resolveDue() {
    final today = _today();
    return switch (_due) {
      _Due.none => null,
      _Due.today => today,
      _Due.tomorrow => today.add(const Duration(days: 1)),
      _Due.custom => _customDate,
    };
  }

  void _selectDue(_Due due) {
    HapticFeedback.selectionClick();
    setState(() => _due = due);
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
      HapticFeedback.selectionClick();
      setState(() {
        _customDate = picked;
        _due = _Due.custom;
      });
    }
  }

  void _togglePriority() {
    HapticFeedback.selectionClick();
    setState(() => _priority = !_priority);
  }

  Future<void> _save() async {
    if (!_canAdd) return;
    HapticFeedback.lightImpact();
    final tasks = AppScope.of(context).tasks;
    final initial = widget.initial;
    final due = _resolveDue();
    final task = initial == null
        ? Task(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: _title.text.trim(),
            createdAt: DateTime.now(),
            due: due,
            priority: _priority,
          )
        : initial.copyWith(
            title: _title.text.trim(),
            due: due,
            clearDue: due == null,
            priority: _priority,
          );
    if (initial == null) {
      await tasks.add(task);
    } else {
      await tasks.update(task);
    }
    if (mounted) Navigator.of(context).pop(task);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureTopBar(
              title: _editing ? 'Edit task' : 'New task',
              onClose: () => Navigator.of(context).maybePop(),
              titleColor: AppColors.ink2,
              iconColor: AppColors.ink2,
              chipColor: AppColors.surfaceRaised,
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
                  hintText: 'What needs doing?',
                  hintStyle: AppText.cardTitle
                      .copyWith(fontSize: 27, color: AppColors.ink3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
              child: Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  PressableScale(
                    child: SelectChip(
                      label: 'No date',
                      selected: _due == _Due.none,
                      onTap: () => _selectDue(_Due.none),
                    ),
                  ),
                  PressableScale(
                    child: SelectChip(
                      label: 'Today',
                      selected: _due == _Due.today,
                      onTap: () => _selectDue(_Due.today),
                    ),
                  ),
                  PressableScale(
                    child: SelectChip(
                      label: 'Tomorrow',
                      selected: _due == _Due.tomorrow,
                      onTap: () => _selectDue(_Due.tomorrow),
                    ),
                  ),
                  PressableScale(
                    child: SelectChip(
                      label: _due == _Due.custom && _customDate != null
                          ? _formatDate(_customDate!)
                          : 'Date',
                      icon: Icons.calendar_today_rounded,
                      selected: _due == _Due.custom,
                      onTap: _pickDate,
                    ),
                  ),
                  PressableScale(
                    child: SelectChip(
                      label: 'Priority',
                      icon: Icons.priority_high_rounded,
                      selected: _priority,
                      tone: ChipTone.flare,
                      onTap: _togglePriority,
                    ),
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
                label: _editing ? 'Save task' : 'Add task',
                icon: _editing ? Icons.check_rounded : Icons.add_rounded,
                color: AppColors.ember,
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
