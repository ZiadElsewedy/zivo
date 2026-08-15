import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/university_item.dart';
import '../../domain/university_item_type.dart';

enum _Due { none, today, tomorrow, custom }

/// University quick-create — title, assignment/exam, an optional due date,
/// and an optional free-text course label. Iris themed.
class UniversityCapturePage extends StatefulWidget {
  const UniversityCapturePage({super.key});

  @override
  State<UniversityCapturePage> createState() => _UniversityCapturePageState();
}

class _UniversityCapturePageState extends State<UniversityCapturePage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _course = TextEditingController();
  UniversityItemType _type = UniversityItemType.assignment;
  _Due _due = _Due.none;
  DateTime? _customDate;
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
    _course.dispose();
    super.dispose();
  }

  DateTime? _resolveDue() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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

  Future<void> _add() async {
    if (!_canAdd) return;
    final courseName = _course.text.trim();
    final item = UniversityItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: _title.text.trim(),
      type: _type,
      createdAt: DateTime.now(),
      due: _resolveDue(),
      courseName: courseName.isEmpty ? null : courseName,
    );
    final university = AppScope.of(context).university;
    await university.add(item);
    if (mounted) Navigator.of(context).pop(item);
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
                onSubmitted: (_) => _add(),
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
              child: _AddButton(enabled: _canAdd, onTap: _add),
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
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.ink2,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'New university item',
                style: AppText.button.copyWith(color: AppColors.ink2),
              ),
            ),
          ),
          const SizedBox(width: 34),
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
  const _AddButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

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
                const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Add',
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
