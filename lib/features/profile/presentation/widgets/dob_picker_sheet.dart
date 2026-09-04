import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../core/util/date_format.dart';
import '../../../../l10n/l10n.dart';

/// Opens the shared ZIVO date-of-birth wheel and resolves to the picked date
/// (or null if dismissed). Used by both first-run onboarding and profile-edit
/// so the two surfaces present the identical warm picker — no stock Material
/// calendar anywhere.
Future<DateTime?> showDobPicker(BuildContext context, {DateTime? initial}) {
  return showZivoSheet<DateTime>(
    context: context,
    builder: (_) => DobPickerSheet(initial: initial),
  );
}

/// A native-feeling wheel date picker for date of birth — three synced
/// scrolling columns (month / day / year): dark [TrainColors.raisedStrong]
/// track, a hairline selection band, and a scroll-tick haptic on every settled
/// value. Changing month or year clamps an out-of-range day (e.g. leaving 31
/// when moving off a 31-day month) rather than allowing an invalid date.
///
/// Bounds enforce a 13+ minimum and a 120-year maximum age. [initial] may be
/// null (first-run onboarding has no prior value) — it then starts at a
/// sensible mid-range default instead of the newest allowed year.
class DobPickerSheet extends StatefulWidget {
  const DobPickerSheet({this.initial, super.key});

  final DateTime? initial;

  @override
  State<DobPickerSheet> createState() => _DobPickerSheetState();
}

class _DobPickerSheetState extends State<DobPickerSheet> {

  late final int _minYear = DateTime.now().year - 120;
  late final int _maxYear = DateTime.now().year - 13;

  /// The starting date: the provided [DobPickerSheet.initial] when present,
  /// otherwise a mid-range default (~25 years old) so the wheels don't open
  /// pinned to the 13-year-old edge.
  late final DateTime _start =
      widget.initial ?? DateTime(DateTime.now().year - 25, 1, 1);

  late int _year = _start.year.clamp(_minYear, _maxYear);
  late int _month = _start.month;
  late int _day = _start.day;

  late final _dayController = FixedExtentScrollController(
    initialItem: _day - 1,
  );

  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;

  void _tick() => HapticFeedback.selectionClick();

  void _clampDay() {
    final max = _daysInMonth;
    if (_day > max) {
      _day = max;
      _dayController.jumpToItem(_day - 1);
    }
  }

  @override
  void dispose() {
    _dayController.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(DateTime(_year, _month, _day));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 22,
        right: 22,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: const ZivoSheetHandle()),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              l(context).profileDateOfBirth,
              style: AppText.cardTitle,
            ),
          ),
          Container(
            height: 190,
            decoration: BoxDecoration(
              color: TrainColors.raisedStrong,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: CupertinoPicker(
                    key: const Key('dob-picker-month'),
                    scrollController: FixedExtentScrollController(
                      initialItem: _month - 1,
                    ),
                    itemExtent: 40,
                    diameterRatio: 1.3,
                    backgroundColor: Colors.transparent,
                    selectionOverlay: _selectionBand(edge: false),
                    onSelectedItemChanged: (index) {
                      _tick();
                      setState(() {
                        _month = index + 1;
                        _clampDay();
                      });
                    },
                    children: [
                      for (final m in monthNames(context))
                        Center(
                          child: Text(
                            m,
                            style: AppText.rowTitle.copyWith(
                              color: TrainColors.ink,
                              fontSize: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: CupertinoPicker(
                    key: const Key('dob-picker-day'),
                    scrollController: _dayController,
                    itemExtent: 40,
                    diameterRatio: 1.3,
                    backgroundColor: Colors.transparent,
                    selectionOverlay: _selectionBand(edge: false),
                    onSelectedItemChanged: (index) {
                      _tick();
                      setState(() => _day = index + 1);
                    },
                    children: [
                      for (var d = 1; d <= 31; d++)
                        Center(
                          child: Text(
                            '$d',
                            style: AppText.rowTitle.copyWith(
                              color: TrainColors.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: CupertinoPicker(
                    key: const Key('dob-picker-year'),
                    scrollController: FixedExtentScrollController(
                      initialItem: _year - _minYear,
                    ),
                    itemExtent: 40,
                    diameterRatio: 1.3,
                    backgroundColor: Colors.transparent,
                    selectionOverlay: _selectionBand(edge: true),
                    onSelectedItemChanged: (index) {
                      _tick();
                      setState(() {
                        _year = _minYear + index;
                        _clampDay();
                      });
                    },
                    children: [
                      for (var y = _minYear; y <= _maxYear; y++)
                        Center(
                          child: Text(
                            '$y',
                            style: AppText.rowTitle.copyWith(
                              color: TrainColors.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Material(
            color: TrainColors.ember,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: _submit,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l(context).actionSave,
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
        ],
      ),
    );
  }

  /// The dark, rounded "current selection" band, right-inset on the last
  /// (rightmost) column so it doesn't visually bleed past the sheet's edge.
  Widget _selectionBand({required bool edge}) {
    return Container(
      margin: EdgeInsets.only(left: 2, right: edge ? 6 : 2),
      decoration: BoxDecoration(
        color: TrainColors.hairlineStrong,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
