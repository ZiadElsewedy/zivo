import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/nutrition/custom_food.dart';
import '../../domain/nutrition/food_log_entry.dart';
import '../../domain/nutrition/food_reference.dart';
import '../../domain/nutrition/nutrition_calculator.dart';
import '../../../../l10n/l10n.dart';

/// "What did you eat?" — search the catalog, pick a food, give an amount.
///
/// The interaction is ordinary; what matters is what it refuses to do. The
/// user names a food, the catalog resolves it, and the deterministic
/// calculator turns the amount into calories. **Nothing here estimates.** If
/// the catalog has no match, the sheet offers to let the user define the food
/// rather than producing a plausible number — the bundled catalog is USDA, so
/// a miss on regional cooking is expected, not exceptional.
///
/// Returns the entries to log, or null if the user backed out. It performs no
/// write itself: the caller persists through `DietRepository.logFood`.
Future<List<FoodLogEntry>?> showLogFoodSheet(
  BuildContext context, {
  required DateTime day,
}) {
  return showModalBottomSheet<List<FoodLogEntry>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LogFoodSheet(day: day),
  );
}

class _LogFoodSheet extends StatefulWidget {
  const _LogFoodSheet({required this.day});

  final DateTime day;

  @override
  State<_LogFoodSheet> createState() => _LogFoodSheetState();
}

class _LogFoodSheetState extends State<_LogFoodSheet> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _quantity = TextEditingController(text: '100');

  Timer? _debounce;
  List<FoodReference> _results = const [];
  bool _searching = false;

  /// The food being measured. Null while still searching.
  FoodReference? _picked;
  String _unit = 'g';

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _search(value));
    setState(() {});
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _searching = true);
    final resolver = AppScope.of(context).requireFoods;
    final results = await resolver.search(trimmed, limit: 25);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  /// The units offered for the picked food: grams always, plus exactly the
  /// measures the source recorded for THIS food. Never a generic list —
  /// offering "cup" for a food whose source never measured one would invite
  /// the density guess the calculator refuses to make.
  List<String> get _units {
    final food = _picked;
    if (food == null) return const ['g'];
    return ['g', ...food.portions.map((p) => p.label)];
  }

  double? get _quantityValue {
    final parsed = double.tryParse(_quantity.text.trim().replaceAll(',', '.'));
    return (parsed == null || parsed <= 0) ? null : parsed;
  }

  /// The live preview of what this will log. Null when the amount can't be
  /// resolved — the sheet then shows the reason instead of a number.
  Object? get _preview {
    final food = _picked;
    final quantity = _quantityValue;
    if (food == null || quantity == null) return null;
    return nutritionFor(food: food, quantity: quantity, unit: _unit);
  }

  Future<void> _defineCustomFood() async {
    final created = await showModalBottomSheet<CustomFood>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomFoodSheet(initialName: _query.text.trim()),
    );
    if (created == null || !mounted) return;
    await AppScope.of(context).diet.saveCustomFood(created);
    if (!mounted) return;
    setState(() {
      _picked = created.toReference();
      _unit = 'g';
    });
  }

  void _commit() {
    final preview = _preview;
    if (preview is! ResolvedNutrition) return;
    final now = DateTime.now();
    HapticFeedback.lightImpact();
    Navigator.of(context).pop([
      FoodLogEntry(
        id: 'log-${now.microsecondsSinceEpoch}',
        day: DateTime(widget.day.year, widget.day.month, widget.day.day),
        loggedAt: now,
        foodId: preview.food.id,
        foodName: preview.food.name,
        quantity: preview.quantity,
        unit: preview.unit,
        grams: preview.grams,
        kcal: preview.kcal,
        proteinG: preview.proteinG,
        carbsG: preview.carbsG,
        fatG: preview.fatG,
        source: preview.source,
        sourceRef: preview.sourceRef,
        origin: FoodLogOrigin.logged,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return Container(
      decoration: const BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 22,
        right: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: picked == null ? _buildSearch() : _buildMeasure(picked),
      ),
    );
  }

  Widget _buildSearch() {
    final query = _query.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l(context).logWhatDidYouEat, style: AppText.rowTitle),
        const SizedBox(height: 4),
        Text(
          'Searching ${nutritionSourceLabel(NutritionSource.usdaFdc)}.',
          style: AppText.meta.copyWith(color: TrainColors.ink3),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('food-search'),
          controller: _query,
          autofocus: true,
          onChanged: _onQueryChanged,
          cursorColor: TrainColors.green,
          style: AppText.rowTitle,
          decoration: InputDecoration(
            hintText: 'chicken breast, rice, olive oil…',
            hintStyle: AppText.rowTitle.copyWith(color: TrainColors.ink3),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: TrainColors.ink3,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 12,
            ),
            filled: true,
            fillColor: TrainColors.base,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _searching
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: TrainColors.green,
                    ),
                  ),
                )
              : _results.isEmpty
              ? _EmptyResults(
                  query: query,
                  onDefine: query.length >= 2 ? _defineCustomFood : null,
                )
              : ListView.builder(
                  key: const Key('food-results'),
                  itemCount: _results.length,
                  itemBuilder: (context, i) => _FoodRow(
                    food: _results[i],
                    onTap: () => setState(() {
                      _picked = _results[i];
                      _unit = 'g';
                    }),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMeasure(FoodReference food) {
    final preview = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CaptureIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => setState(() => _picked = null),
              semanticLabel: l(context).logBackToSearch,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                food.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowTitle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _ProvenanceLine(food: food),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 110,
              child: TextField(
                key: const Key('log-quantity'),
                controller: _quantity,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                cursorColor: TrainColors.green,
                style: AppText.rowTitle,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  filled: true,
                  fillColor: TrainColors.base,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final unit in _units)
                    SelectChip(
                      key: Key('unit-$unit'),
                      label: unit,
                      selected: _unit == unit,
                      onTap: () => setState(() => _unit = unit),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (preview is ResolvedNutrition)
          _NutritionPreview(nutrition: preview)
        else if (preview is QuantityUnresolved)
          _UnresolvedNote(problem: preview)
        else
          Text(
            'Enter an amount.',
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
        const Spacer(),
        PillButton(
          key: const Key('log-food-confirm'),
          label: l(context).logIt,
          icon: Icons.check_rounded,
          enabled: preview is ResolvedNutrition,
          onTap: _commit,
        ),
      ],
    );
  }
}

/// Where a food's figures come from, said on the screen where they're chosen.
class _ProvenanceLine extends StatelessWidget {
  const _ProvenanceLine({required this.food});

  final FoodReference food;

  @override
  Widget build(BuildContext context) {
    final preparation = switch (food.preparation) {
      FoodPreparation.raw => 'raw',
      FoodPreparation.cooked => 'cooked',
      FoodPreparation.dry => 'dry',
      FoodPreparation.unknown => null,
    };
    return Text(
      [
        nutritionSourceLabel(food.source),
        ?preparation,
        '${food.kcalPer100g.round()} kcal / 100g',
      ].join(' · '),
      style: AppText.meta.copyWith(color: TrainColors.ink3),
    );
  }
}

/// One search result: the source's own name, its state, and its energy density
/// — enough for the user to tell raw from cooked before they pick.
class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.food, required this.onTap});

  final FoodReference food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCustom = food.source == NutritionSource.userCustom;
    return PressableScale(
      scale: 0.99,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (isCustom) 'Your own food',
                        if (food.preparation != FoodPreparation.unknown)
                          food.preparation.name,
                        '${food.kcalPer100g.round()} kcal/100g',
                      ].join(' · '),
                      style: AppText.meta.copyWith(
                        color: isCustom ? TrainColors.green : TrainColors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: TrainColors.ink3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The honest empty state. The bundled catalog is USDA, so a miss on regional
/// cooking is normal — and the answer is to let the user say what it is, never
/// to approximate it with something close.
class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.query, this.onDefine});

  final String query;
  final VoidCallback? onDefine;

  @override
  Widget build(BuildContext context) {
    if (query.length < 2) {
      return Center(
        child: Text(
          'Type a food to search.',
          style: AppText.meta.copyWith(color: TrainColors.ink3),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nothing in the catalog matches "$query".',
            textAlign: TextAlign.center,
            style: AppText.rowTitle.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            "It's a USDA catalog, so it's thin on regional and home cooking. "
            "Rather than guess, tell ZIVO what this food is once and it'll "
            'remember.',
            textAlign: TextAlign.center,
            style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.45),
          ),
          const SizedBox(height: 18),
          if (onDefine != null)
            PillButton(
              key: const Key('define-custom-food'),
              label: l(context).logAddOwnFood(query),
              icon: Icons.add_rounded,
              color: TrainColors.green,
              textColor: const Color(0xFF04140D),
              enabled: true,
              onTap: onDefine!,
            ),
        ],
      ),
    );
  }
}

/// What will be logged, computed — never estimated.
class _NutritionPreview extends StatelessWidget {
  const _NutritionPreview({required this.nutrition});

  final ResolvedNutrition nutrition;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('log-preview'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: TrainColors.base,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${nutrition.kcal} kcal',
            style: TrainType.mono(size: 22, weight: FontWeight.w300),
          ),
          const SizedBox(height: 6),
          Text(
            'P ${nutrition.proteinG}g · C ${nutrition.carbsG}g · '
            'F ${nutrition.fatG}g · ${nutrition.grams}g',
            style: AppText.meta.copyWith(color: TrainColors.ink2),
          ),
        ],
      ),
    );
  }
}

/// Why an amount couldn't be turned into a figure — and what would work.
class _UnresolvedNote extends StatelessWidget {
  const _UnresolvedNote({required this.problem});

  final QuantityUnresolved problem;

  @override
  Widget build(BuildContext context) {
    final measures = problem.availableMeasures;
    final text = switch (problem.problem) {
      QuantityProblem.invalidQuantity => 'Enter an amount above zero.',
      QuantityProblem.unknownMeasure =>
        measures.isEmpty
            ? 'ZIVO only has this food by weight — enter it in grams. '
                  'Converting ${problem.unit} would mean guessing a density.'
            : "ZIVO doesn't have ${problem.unit} for this food. Use grams, or: "
                  '${measures.join(', ')}.',
    };
    return Container(
      key: const Key('log-unresolved'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: TrainColors.base,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: AppText.meta.copyWith(color: TrainColors.ink2, height: 1.45),
      ),
    );
  }
}

/// Defines a food the catalog doesn't have. The values are the user's, stored
/// as theirs — see [CustomFood].
class _CustomFoodSheet extends StatefulWidget {
  const _CustomFoodSheet({required this.initialName});

  final String initialName;

  @override
  State<_CustomFoodSheet> createState() => _CustomFoodSheetState();
}

class _CustomFoodSheetState extends State<_CustomFoodSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  final TextEditingController _kcal = TextEditingController();
  final TextEditingController _protein = TextEditingController();
  final TextEditingController _carbs = TextEditingController();
  final TextEditingController _fat = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _value(TextEditingController c) {
    final parsed = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return (parsed == null || parsed < 0) ? null : parsed;
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty && (_value(_kcal) ?? -1) >= 0;

  void _save() {
    if (!_canSave) return;
    final now = DateTime.now();
    Navigator.of(context).pop(
      CustomFood(
        id: 'cf-${now.microsecondsSinceEpoch}',
        name: _name.text.trim(),
        kcalPer100g: _value(_kcal) ?? 0,
        proteinPer100g: _value(_protein) ?? 0,
        carbsPer100g: _value(_carbs) ?? 0,
        fatPer100g: _value(_fat) ?? 0,
        createdAt: now,
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
        top: 16,
        left: 22,
        right: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        key: const Key('custom-food-scroll'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l(context).logYourOwnFood, style: AppText.rowTitle),
            const SizedBox(height: 4),
            Text(
              'Per 100g, from the label or your own measure. ZIVO stores these '
              'as yours and never overwrites them.',
              style: AppText.meta.copyWith(
                color: TrainColors.ink3,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            _Field(
              label: l(context).logFoodName,
              controller: _name,
              fieldKey: const Key('custom-name'),
              numeric: false,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: l(context).nutritionCaloriesPer100g,
                    controller: _kcal,
                    fieldKey: const Key('custom-kcal'),
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: l(context).nutritionProtein,
                    controller: _protein,
                    fieldKey: const Key('custom-protein'),
                    onChanged: () => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: l(context).nutritionCarbs,
                    controller: _carbs,
                    fieldKey: const Key('custom-carbs'),
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: l(context).nutritionFat,
                    controller: _fat,
                    fieldKey: const Key('custom-fat'),
                    onChanged: () => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            PillButton(
              key: const Key('save-custom-food'),
              label: l(context).logSaveFood,
              icon: Icons.check_rounded,
              enabled: _canSave,
              onTap: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.fieldKey,
    required this.onChanged,
    this.numeric = true,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final VoidCallback onChanged;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          key: fieldKey,
          controller: controller,
          onChanged: (_) => onChanged(),
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
              : null,
          cursorColor: TrainColors.green,
          style: AppText.rowTitle,
          decoration: InputDecoration(
            isDense: true,
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
          ),
        ),
      ],
    );
  }
}
