import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/task.dart';

enum _Due { today, tomorrow, custom }

/// Task quick-create — title is enough; due and priority are one-tap and
/// optional. Lightweight by design (a personal OS, not Jira).
class TaskCapturePage extends StatefulWidget {
  const TaskCapturePage({super.key});

  @override
  State<TaskCapturePage> createState() => _TaskCapturePageState();
}

class _TaskCapturePageState extends State<TaskCapturePage> {
  final TextEditingController _title = TextEditingController();
  _Due _due = _Due.today;
  DateTime? _customDate;
  bool _priority = false;
  bool _canAdd = false;

  @override
  void initState() {
    super.initState();
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

  DateTime? _resolveDue() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_due) {
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

  Future<void> _add() async {
    if (!_canAdd) return;
    final task = Task(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: _title.text.trim(),
      createdAt: DateTime.now(),
      due: _resolveDue(),
      priority: _priority,
    );
    await AppScope.of(context).tasks.add(task);
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
            _TopBar(onClose: () => Navigator.of(context).maybePop()),
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
              child: _AddButton(enabled: _canAdd, onTap: _add),
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
  const _TopBar({required this.onClose});

  final VoidCallback onClose;

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
                color: Color(0xFFEFEBE3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 18, color: AppColors.ink2),
            ),
          ),
          Expanded(
            child: Center(
              child: Text('New task',
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
      fg = Colors.white;
      border = AppColors.flare;
    } else if (selected) {
      bg = AppColors.ink;
      fg = Colors.white;
      border = AppColors.ink;
    } else {
      bg = Colors.transparent;
      fg = tone == _ChipTone.flare ? AppColors.flareText : AppColors.ink2;
      border = tone == _ChipTone.flare
          ? const Color(0x59DE2C56)
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
  const _AddButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

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
                const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Add task',
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
