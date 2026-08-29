import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../domain/diet_plan.dart';
import '../../domain/grocery_list.dart';
import '../../../../core/theme/train_tokens.dart';

/// The shopping view for the active diet plan — every food across every day
/// and meal, quantities summed into one list ("what one shop looks like").
/// Ticking lines is deliberately ephemeral session state, not persisted data;
/// the list itself is always derivable from the plan.
class GroceryListPage extends StatefulWidget {
  const GroceryListPage({super.key, required this.plan});

  final DietPlan plan;

  @override
  State<GroceryListPage> createState() => _GroceryListPageState();
}

class _GroceryListPageState extends State<GroceryListPage> {
  final _checked = <int>{};

  List<GroceryItem> get _items => buildGroceryList(widget.plan);

  String get _shareText {
    final items = _items;
    if (items.isEmpty) return '';
    return 'Groceries — ${widget.plan.name}\n'
        '${items.map((i) => '• ${_line(i)}').join('\n')}';
  }

  String _line(GroceryItem item) {
    final quantity = item.quantity == item.quantity.roundToDouble()
        ? item.quantity.toStringAsFixed(0)
        : item.quantity.toStringAsFixed(1);
    return '${item.name} — $quantity ${item.unit}';
  }

  void _copyList() {
    Clipboard.setData(ClipboardData(text: _shareText));
    showZivoToast(context, 'List copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: TrainColors.base,
      appBar: AppBar(
        backgroundColor: TrainColors.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Groceries', style: AppText.cardTitle),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Copy list',
              icon: const Icon(Icons.copy_rounded),
              onPressed: _copyList,
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  "This plan has no foods to shop for yet.",
                  style: AppText.body.copyWith(color: TrainColors.ink3),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.s,
                AppSpacing.screen,
                48,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final checked = _checked.contains(index);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: checked,
                        onChanged: (_) => setState(() {
                          checked
                              ? _checked.remove(index)
                              : _checked.add(index);
                        }),
                      ),
                      Expanded(
                        child: Text(
                          _line(item),
                          style: AppText.body.copyWith(
                            color: checked ? TrainColors.ink3 : TrainColors.ink,
                            decoration: checked
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
