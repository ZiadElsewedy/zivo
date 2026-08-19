import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
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
        _customDate = picked;
        _due = _Due.custom;
      });
    }
  }

  Future<void> _save() async {
    if (!_canAdd) return;
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
            _TopBar(
              editing: _editing,
              onClose: () => Navigator.of(context).maybePop(),
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
                  _Chip(
                    label: 'No date',
                    selected: _due == _Due.none,
                    onTap: () => setState(() => _due = _Due.none),
                  ),
                  _Chip(
                    label: 'Today',
                    selected: _due == _Due.today,
                    onTap: () => setState(() => _due = _Due.today),
                  ),
                  _Chip(
                    label: 'Tomorrow',
                    selected: _due == _Due.tomorrow,
                    onTap: () => setState(() => _due = _Due.tomorrow),
                  ),
                  _Chip(
                    label: _due == _Due.custom && _customDate != null
                        ? _formatDate(_customDate!)
                        : 'Date',
                    icon: Icons.calendar_today_rounded,
                    selected: _due == _Due.custom,
                    onTap: _pickDate,
                  ),
                  _Chip(
                    label: 'Priority',
                    icon: Icons.priority_high_rounded,
                    selected: _priority,
                    tone: _ChipTone.flare,
                    onTap: () => setState(() => _priority = !_priority),
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
              child: _AddButton(
                enabled: _canAdd,
                editing: _editing,
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose, required this.editing});

  final VoidCallback onClose;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 2),
      child: Row(
        children: [
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 18, color: AppColors.ink2),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(editing ? 'Edit task' : 'New task',
                  style: AppText.button.copyWith(color: AppColors.ink2)),
            ),
          ),
          const SizedBox(width: 34),
        ],
      ),
    );
  }
}

enum _ChipTone { neutral, flare }

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.tone = _ChipTone.neutral,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    if (selected && tone == _ChipTone.flare) {
      bg = AppColors.flare;
      fg = AppColors.ground;
      border = AppColors.flare;
    } else if (selected) {
      bg = AppColors.ink;
      fg = AppColors.ground;
      border = AppColors.ink;
    } else {
      bg = Colors.transparent;
      fg = tone == _ChipTone.flare ? AppColors.flareText : AppColors.ink2;
      border = tone == _ChipTone.flare
          ? const Color(0x59FF3D6E)
          : AppColors.hairline2;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppText.button.copyWith(fontSize: 13.5, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.enabled,
    required this.onTap,
    this.editing = false,
  });

  final bool enabled;
  final VoidCallback onTap;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: AppColors.ember,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  editing ? Icons.check_rounded : Icons.add_rounded,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  editing ? 'Save task' : 'Add task',
                  style: AppText.button.copyWith(fontSize: 16, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
