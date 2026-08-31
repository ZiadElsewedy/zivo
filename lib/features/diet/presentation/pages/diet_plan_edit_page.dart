import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/diet_day.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_plan.dart';
import '../../domain/diet_plan_status.dart';
import '../../domain/diet_source.dart';
import '../../domain/food_item.dart';
import '../../domain/meal.dart';
import '../../domain/nutrition/plausibility.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _weekdayLabel(int? weekday) =>
    weekday == null ? 'Every day' : _weekdayNames[weekday - 1];

class _MealDraft {
  _MealDraft({
    required this.id,
    required this.label,
    required this.order,
    List<FoodItem>? items,
  }) : items = items ?? <FoodItem>[];

  final String id;
  final String label;
  final int order;
  final List<FoodItem> items;
}

class _DayDraft {
  _DayDraft({this.weekday, required this.label, List<_MealDraft>? meals})
    : meals = meals ?? <_MealDraft>[];

  final int? weekday;
  final String label;
  final List<_MealDraft> meals;
}

/// Create or edit the diet plan — name, days (weekday chips or "every day" +
/// a label), meals within a day, and food items within a meal (via a bottom
/// sheet, mirroring Workout's exercise sheet). Saving persists the whole
/// plan, reusing its id when editing so it overwrites idempotently.
class DietPlanEditPage extends StatefulWidget {
  const DietPlanEditPage({super.key, this.initialPlan});

  final DietPlan? initialPlan;

  @override
  State<DietPlanEditPage> createState() => _DietPlanEditPageState();
}

class _DietPlanEditPageState extends State<DietPlanEditPage> {
  late final TextEditingController _name;
  late final String _planId;
  late final DateTime _createdAt;
  final List<_DayDraft> _days = [];
  bool _canSave = false;

  bool get _editing => widget.initialPlan != null;

  @override
  void initState() {
    super.initState();
    final plan = widget.initialPlan;
    _name = TextEditingController(text: plan?.name ?? '');
    _planId = plan?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    _createdAt = plan?.createdAt ?? DateTime.now();
    if (plan != null) {
      _days.addAll(
        plan.days.map(
          (d) => _DayDraft(
            weekday: d.weekday,
            label: d.label,
            meals: d.meals
                .map(
                  (m) => _MealDraft(
                    id: m.id,
                    label: m.label,
                    order: m.order,
                    items: List.of(m.items),
                  ),
                )
                .toList(),
          ),
        ),
      );
    }
    _name.addListener(_recompute);
    _recompute();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _recompute() {
    final canSave = _name.text.trim().isNotEmpty && _days.isNotEmpty;
    if (canSave != _canSave) setState(() => _canSave = canSave);
  }

  Future<void> _addDay() async {
    final result = await showModalBottomSheet<_DayDraft>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _DaySheet(),
    );
    if (result == null) return;
    setState(() => _days.add(result));
    _recompute();
  }

  void _removeDay(int index) {
    setState(() => _days.removeAt(index));
    _recompute();
  }

  Future<void> _addMeal(int dayIndex) async {
    final label = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _MealSheet(),
    );
    if (label == null) return;
    setState(() {
      final day = _days[dayIndex];
      day.meals.add(
        _MealDraft(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          label: label,
          order: day.meals.length,
        ),
      );
    });
  }

  void _removeMeal(int dayIndex, int mealIndex) {
    setState(() => _days[dayIndex].meals.removeAt(mealIndex));
  }

  Future<void> _addItem(int dayIndex, int mealIndex) async {
    final item = await showModalBottomSheet<FoodItem>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _FoodItemSheet(),
    );
    if (item == null) return;
    setState(() => _days[dayIndex].meals[mealIndex].items.add(item));
  }

  void _removeItem(int dayIndex, int mealIndex, int itemIndex) {
    setState(() => _days[dayIndex].meals[mealIndex].items.removeAt(itemIndex));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final now = DateTime.now();
    final plan = DietPlan(
      id: _planId,
      name: _name.text.trim(),
      status: DietPlanStatus.active,
      source: widget.initialPlan?.source ?? DietSource.manual,
      createdAt: _createdAt,
      updatedAt: now,
      days: _days
          .map(
            (d) => DietDay(
              weekday: d.weekday,
              label: d.label,
              meals: d.meals
                  .map(
                    (m) => Meal(
                      id: m.id,
                      label: m.label,
                      order: m.order,
                      items: List.unmodifiable(m.items),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
    await AppScope.of(context).diet.savePlan(plan);
    if (mounted) Navigator.of(context).pop(plan);
  }

  Future<void> _delete() async {
    final plan = widget.initialPlan;
    if (plan == null) return;
    final diet = AppScope.of(context).diet;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TrainColors.raised,
        title: Text(l(context).planDeleteTitle, style: AppText.cardTitle),
        content: Text(
          'This removes "${plan.name}" and all its days and meals. This can\'t be undone.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppText.button.copyWith(color: TrainColors.ink3),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: AppText.button.copyWith(color: TrainColors.ember),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await diet.deletePlan(plan.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureTopBar(
              title: l(context).planEditTitle,
              onClose: () => Navigator.of(context).maybePop(),
              trailing: _editing
                  ? CaptureIconButton(
                      key: const Key('diet-plan-delete'),
                      icon: Icons.delete_outline_rounded,
                      onTap: _delete,
                      semanticLabel: l(context).planDelete,
                      iconColor: TrainColors.ember,
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 6),
              child: TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                cursorColor: TrainColors.green,
                style: AppText.cardTitle.copyWith(fontSize: 24),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: l(context).planNameHint,
                  hintStyle: AppText.cardTitle.copyWith(
                    fontSize: 24,
                    color: TrainColors.ink3,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _days.isEmpty
                  ? _EmptyDays(onAdd: _addDay)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
                      itemCount: _days.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i == _days.length) {
                          return _AddButton(label: l(context).planAddDay, onTap: _addDay);
                        }
                        return _DayCard(
                          day: _days[i],
                          onRemoveDay: () => _removeDay(i),
                          onAddMeal: () => _addMeal(i),
                          onRemoveMeal: (mi) => _removeMeal(i, mi),
                          onAddItem: (mi) => _addItem(i, mi),
                          onRemoveItem: (mi, ii) => _removeItem(i, mi, ii),
                        );
                      },
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                8,
                18,
                MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 8,
              ),
              child: PillButton(
                label: l(context).planSave,
                icon: Icons.check_rounded,
                color: TrainColors.green,
                enabled: _canSave,
                onTap: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDays extends StatelessWidget {
  const _EmptyDays({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.restaurant_rounded,
            size: 30,
            color: TrainColors.ink3,
          ),
          const SizedBox(height: 12),
          Text(l(context).planNoDays, style: AppText.aside),
          const SizedBox(height: 14),
          _AddButton(label: l(context).planAddDay, onTap: onAdd),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 18,
          vertical: compact ? 8 : 12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: TrainColors.hairlineStrong, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              size: compact ? 14 : 17,
              color: TrainColors.green,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.button.copyWith(
                fontSize: compact ? 12.5 : 14,
                color: TrainColors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.onRemoveDay,
    required this.onAddMeal,
    required this.onRemoveMeal,
    required this.onAddItem,
    required this.onRemoveItem,
  });

  final _DayDraft day;
  final VoidCallback onRemoveDay;
  final VoidCallback onAddMeal;
  final void Function(int mealIndex) onRemoveMeal;
  final void Function(int mealIndex) onAddItem;
  final void Function(int mealIndex, int itemIndex) onRemoveItem;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  day.label,
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: onRemoveDay,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: TrainColors.ink3,
                ),
                splashRadius: 20,
                tooltip: 'Remove day',
              ),
            ],
          ),
          for (var mi = 0; mi < day.meals.length; mi++)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _MealBlock(
                meal: day.meals[mi],
                onRemoveMeal: () => onRemoveMeal(mi),
                onAddItem: () => onAddItem(mi),
                onRemoveItem: (ii) => onRemoveItem(mi, ii),
              ),
            ),
          const SizedBox(height: 10),
          _AddButton(label: l(context).planAddMeal, onTap: onAddMeal, compact: true),
        ],
      ),
    );
  }
}

/// The item's stated calories measured against its own macros, as a line to
/// print — null when there is nothing to say (which is most items).
String? _crossCheckNote(FoodItem item) =>
    nutritionCrossCheckNote(crossCheckItem(item));

class _MealBlock extends StatelessWidget {
  const _MealBlock({
    required this.meal,
    required this.onRemoveMeal,
    required this.onAddItem,
    required this.onRemoveItem,
  });

  final _MealDraft meal;
  final VoidCallback onRemoveMeal;
  final VoidCallback onAddItem;
  final void Function(int itemIndex) onRemoveItem;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TrainColors.base,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meal.label,
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: TrainColors.ink,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemoveMeal,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: TrainColors.ink3,
                ),
                splashRadius: 18,
                tooltip: 'Remove meal',
              ),
            ],
          ),
          for (var ii = 0; ii < meal.items.length; ii++)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${meal.items[ii].name} · '
                          '${foodQtyLabel(meal.items[ii])}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.meta.copyWith(color: TrainColors.ink2),
                        ),
                        // The editor is the review gate for an imported plan,
                        // so it is where a figure that contradicts its own
                        // macros has to be visible. It states both numbers
                        // rather than a verdict, and it does not block Save:
                        // the user may know something the arithmetic doesn't,
                        // and refusing their plan over a guess the app made
                        // would be the wrong party paying for it.
                        if (_crossCheckNote(meal.items[ii]) case final note?)
                          Padding(
                            key: Key('item-crosscheck-${meal.id}-$ii'),
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              note,
                              maxLines: 2,
                              style: AppText.meta.copyWith(
                                color: TrainColors.ember,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => onRemoveItem(ii),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: TrainColors.ink3,
                    ),
                    splashRadius: 16,
                    tooltip: 'Remove item',
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          _AddButton(label: l(context).planAddItem, onTap: onAddItem, compact: true),
        ],
      ),
    );
  }
}

/// A sheet to add one day: a weekday (or "Every day") + an optional label.
class _DaySheet extends StatefulWidget {
  const _DaySheet();

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  int? _weekday = 1;
  final TextEditingController _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _label.text.trim().isEmpty
        ? _weekdayLabel(_weekday)
        : _label.text.trim();
    Navigator.of(context).pop(_DayDraft(weekday: _weekday, label: label));
  }

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
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: TrainColors.hairlineStrong,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(l(context).planAddDay, style: AppText.cardTitle),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var wd = 1; wd <= 7; wd++)
                SelectChip(
                  label: _weekdayNames[wd - 1],
                  selected: _weekday == wd,
                  onTap: () => setState(() => _weekday = wd),
                ),
              SelectChip(
                label: l(context).planEveryDay,
                selected: _weekday == null,
                onTap: () => setState(() => _weekday = null),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            cursorColor: TrainColors.green,
            style: AppText.rowTitle,
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.hairline),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.hairline),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.green, width: 1.6),
              ),
              hintText: l(context).planDayLabelHint,
              hintStyle: AppText.rowTitle.copyWith(color: TrainColors.ink3),
            ),
          ),
          const SizedBox(height: 22),
          PillButton(
            label: l(context).planAddDay,
            icon: Icons.add_rounded,
            color: TrainColors.green,
            enabled: true,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

/// A sheet to add one meal: just its label.
class _MealSheet extends StatefulWidget {
  const _MealSheet();

  @override
  State<_MealSheet> createState() => _MealSheetState();
}

class _MealSheetState extends State<_MealSheet> {
  final TextEditingController _label = TextEditingController();
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
    _label.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canAdd) return;
    Navigator.of(context).pop(_label.text.trim());
  }

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
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: TrainColors.hairlineStrong,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(l(context).planAddMeal, style: AppText.cardTitle),
          ),
          TextField(
            controller: _label,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            cursorColor: TrainColors.green,
            style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.hairline),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.hairline),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.green, width: 1.6),
              ),
              hintText: l(context).planMealNameHint,
              hintStyle: AppText.rowTitle.copyWith(color: TrainColors.ink3),
            ),
          ),
          const SizedBox(height: 22),
          PillButton(
            label: l(context).planAddMeal,
            icon: Icons.add_rounded,
            color: TrainColors.green,
            enabled: _canAdd,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

/// A sheet to add one food item: name, quantity + unit, and optional
/// calories/macros.
class _FoodItemSheet extends StatefulWidget {
  const _FoodItemSheet();

  @override
  State<_FoodItemSheet> createState() => _FoodItemSheetState();
}

class _FoodItemSheetState extends State<_FoodItemSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _quantity = TextEditingController(text: '100');
  final TextEditingController _calories = TextEditingController();
  final TextEditingController _protein = TextEditingController();
  final TextEditingController _carbs = TextEditingController();
  final TextEditingController _fat = TextEditingController();
  String _unit = 'g';
  bool _canAdd = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      final canAdd = _name.text.trim().isNotEmpty;
      if (canAdd != _canAdd) setState(() => _canAdd = canAdd);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canAdd) return;
    final quantity =
        double.tryParse(_quantity.text.trim().replaceAll(',', '.')) ?? 0;
    final calories = int.tryParse(_calories.text.trim());
    final protein = double.tryParse(_protein.text.trim().replaceAll(',', '.'));
    final carbs = double.tryParse(_carbs.text.trim().replaceAll(',', '.'));
    final fat = double.tryParse(_fat.text.trim().replaceAll(',', '.'));
    Navigator.of(context).pop(
      FoodItem(
        name: _name.text.trim(),
        quantity: quantity <= 0 ? 1 : quantity,
        unit: _unit,
        calories: (calories == null || calories <= 0) ? null : calories,
        proteinG: (protein == null || protein <= 0) ? null : protein,
        carbsG: (carbs == null || carbs <= 0) ? null : carbs,
        fatG: (fat == null || fat <= 0) ? null : fat,
      ),
    );
  }

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
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: TrainColors.hairlineStrong,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(l(context).planAddFoodItem, style: AppText.cardTitle),
          ),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.next,
            cursorColor: TrainColors.green,
            style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.hairline),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.hairline),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.green, width: 1.6),
              ),
              hintText: l(context).planFoodNameHint,
              hintStyle: AppText.rowTitle.copyWith(color: TrainColors.ink3),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NumberField(label: l(context).planQty, controller: _quantity),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UNIT',
                      style: AppText.meta.copyWith(
                        color: TrainColors.ink3,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final u in const ['g', 'ml', 'pcs'])
                          SelectChip(
                            label: u,
                            selected: _unit == u,
                            onTap: () => setState(() => _unit = u),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _NumberField(label: l(context).nutritionCalories, controller: _calories, hint: '—'),
              const SizedBox(width: 12),
              _NumberField(
                label: l(context).nutritionProtein,
                controller: _protein,
                hint: '—',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _NumberField(label: l(context).nutritionCarbs, controller: _carbs, hint: '—'),
              const SizedBox(width: 12),
              _NumberField(label: l(context).nutritionFat, controller: _fat, hint: '—'),
            ],
          ),
          const SizedBox(height: 22),
          PillButton(
            label: l(context).planAddItem,
            icon: Icons.add_rounded,
            color: TrainColors.green,
            enabled: _canAdd,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppText.meta.copyWith(
              color: TrainColors.ink3,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            cursorColor: TrainColors.green,
            style: AppText.rowTitle,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: AppText.rowTitle.copyWith(color: TrainColors.ink3),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              filled: true,
              fillColor: TrainColors.base,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: TrainColors.green,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
