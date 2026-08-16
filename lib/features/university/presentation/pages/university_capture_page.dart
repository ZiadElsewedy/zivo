import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/university_item.dart';
import '../../domain/university_item_type.dart';

enum _Due { none, today, tomorrow, custom }

/// University create-or-edit — title, assignment/exam, an optional due date,
/// and an optional free-text course label. Iris themed. Pass [initial] to
/// edit an existing item in place instead of creating a new one.
class UniversityCapturePage extends StatefulWidget {
  const UniversityCapturePage({super.key, this.initial});

  final UniversityItem? initial;

  @override
  State<UniversityCapturePage> createState() => _UniversityCapturePageState();
}

class _UniversityCapturePageState extends State<UniversityCapturePage> {
  late final TextEditingController _title;
  late final TextEditingController _course;
  late UniversityItemType _type;
  late _Due _due;
  DateTime? _customDate;
  bool _canAdd = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _course = TextEditingController(text: initial?.courseName ?? '');
    _type = initial?.type ?? UniversityItemType.assignment;
    final today = _today();
    final due = initial?.due;
    if (due == null) {
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
    _course.dispose();
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
    final university = AppScope.of(context).university;
    final initial = widget.initial;
    final courseName = _course.text.trim();
    final due = _resolveDue();
    final item = initial == null
        ? UniversityItem(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: _title.text.trim(),
            type: _type,
            createdAt: DateTime.now(),
            due: due,
            courseName: courseName.isEmpty ? null : courseName,
          )
        : initial.copyWith(
            title: _title.text.trim(),
            type: _type,
            due: due,
            clearDue: due == null,
            courseName: courseName.isEmpty ? null : courseName,
            clearCourseName: courseName.isEmpty,
          );
    if (initial == null) {
      await university.add(item);
    } else {
      await university.update(item);
    }
    if (mounted) Navigator.of(context).pop(item);
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    final university = AppScope.of(context).university;
    await university.remove(initial.id);
    if (mounted) Navigator.of(context).pop();
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
              onDelete: _editing ? _delete : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 6),
              child: TextField(
                controller: _title,
                autofocus: true,
                textInputAction: TextInputAction.next,
                cursorColor: AppColors.iris,
                style: AppText.cardTitle.copyWith(fontSize: 27),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: "What's due?",
                  hintStyle: AppText.cardTitle.copyWith(
                    fontSize: 27,
                    color: AppColors.ink3,
                  ),
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
                    label: UniversityItemType.assignment.label,
                    selected: _type == UniversityItemType.assignment,
                    onTap: () =>
                        setState(() => _type = UniversityItemType.assignment),
                  ),
                  _Chip(
                    label: UniversityItemType.exam.label,
                    selected: _type == UniversityItemType.exam,
                    onTap: () =>
                        setState(() => _type = UniversityItemType.exam),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
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
                    label: 'None',
                    selected: _due == _Due.none,
                    onTap: () => setState(() => _due = _Due.none),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
              child: TextField(
                controller: _course,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                cursorColor: AppColors.iris,
                style: AppText.rowTitle,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Course (optional)',
                  hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
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
              child: _AddButton(enabled: _canAdd, editing: _editing, onTap: _save),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onClose,
    required this.editing,
    this.onDelete,
  });

  final VoidCallback onClose;
  final bool editing;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 2),
      child: Row(
        children: [
          CaptureIconButton(
            icon: Icons.close_rounded,
            onTap: onClose,
            semanticLabel: 'Close',
          ),
          Expanded(
            child: Center(
              child: Text(
                editing ? 'Edit university item' : 'New university item',
                style: AppText.button.copyWith(color: AppColors.ink2),
              ),
            ),
          ),
          if (onDelete != null)
            CaptureIconButton(
              key: const Key('university-delete'),
              icon: Icons.delete_outline_rounded,
              onTap: onDelete!,
              semanticLabel: 'Delete item',
              iconColor: AppColors.flareText,
            )
          else
            const SizedBox(width: CaptureIconButton.targetSize),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    if (selected) {
      bg = AppColors.iris;
      fg = Colors.white;
      border = AppColors.iris;
    } else {
      bg = Colors.transparent;
      fg = AppColors.ink2;
      border = AppColors.hairline2;
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
        color: AppColors.iris,
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
                  editing ? 'Save' : 'Add',
                  style: AppText.button.copyWith(
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
