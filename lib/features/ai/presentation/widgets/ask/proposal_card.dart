import 'package:flutter/material.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../domain/ai_pending_action.dart';
import '../../../../../core/util/bidi.dart';
import '../../../../../l10n/l10n.dart';

/// The ADR-003 confirmation card: a change ZIVO proposes and the user confirms
/// or cancels. Nothing has been written while it shows Confirm/Cancel.
///
/// Drawn as a slip, not a tile: a spine down the leading edge in the hue that
/// owns the change (amber money, green training and food, ember a deletion),
/// what kind of change it is, the one thing it's about set large — an amount
/// in the numbers face, a food or a workout in the text face — and then the
/// particulars as plain receipt rows ("Category  Food"). The decision sits
/// under a hairline; once made, it folds away and the slip stays in the thread
/// as the record, with its outcome where the buttons were decided.
class ProposalCard extends StatelessWidget {
  const ProposalCard({
    required this.action,
    required this.status,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final AiPendingAction action;
  final AiActionStatus status;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final pending = status == AiActionStatus.pending;
    final applied = status == AiActionStatus.applied;
    final kind = _kindOf(context, action);
    final rows = _rowsOf(context, action);
    final headline = _headlineOf(context, action);
    final still = MediaQuery.of(context).disableAnimations;
    // A change that didn't happen stays legible but steps back.
    final settledInk = applied || pending ? TrainColors.ink : TrainColors.ink3;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(kind.icon, size: 15, color: kind.hue),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                kind.label,
                style: TrainType.ui(
                  size: 13,
                  weight: FontWeight.w600,
                  color: kind.hue,
                ),
              ),
            ),
            if (!pending) _Outcome(status: status),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          headline.text,
          style:
              (headline.numeric
                      ? TrainType.mono(
                          size: 26,
                          weight: FontWeight.w500,
                          tracking: -0.02,
                          height: 1.15,
                        )
                      : TrainType.ui(
                          size: 20,
                          weight: FontWeight.w700,
                          tracking: -0.015,
                          height: 1.25,
                        ))
                  .copyWith(
                    color: settledInk,
                    // A struck headline reads at once as "this did not
                    // happen" on a cancelled or expired slip.
                    decoration: applied || pending
                        ? null
                        : TextDecoration.lineThrough,
                    decorationColor: TrainColors.ink3,
                  ),
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: 6),
            _ReceiptRow(
              label: row.$1,
              value: row.$2,
              muted: !applied && !pending,
            ),
          ],
        ],
        AnimatedSwitcher(
          duration: still ? Duration.zero : const Duration(milliseconds: 220),
          child: pending
              ? _Decision(
                  key: const ValueKey('decision'),
                  destructive: action.kind == 'delete_expense',
                  onConfirm: onConfirm,
                  onCancel: onCancel,
                )
              : const SizedBox(
                  key: ValueKey('settled'),
                  width: double.infinity,
                ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AnimatedSize(
        duration: still ? const Duration(milliseconds: 1) : AppMotion.enter,
        curve: AppMotion.ease,
        alignment: Alignment.topCenter,
        child: Container(
          decoration: BoxDecoration(
            color: TrainColors.raised,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: pending
                  ? TrainColors.hairlineStrong
                  : TrainColors.hairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The spine: the one spot of colour, full strength while the
                // change waits on the user, quieter once it's settled.
                AnimatedContainer(
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  width: 3,
                  color: kind.hue.withValues(
                    alpha: pending ? 1 : (applied ? 0.55 : 0.2),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      15,
                      14,
                      16,
                      15,
                    ),
                    child: body,
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

/// The decision: a hairline, then Confirm (the committing action, in ember —
/// the one hue the design system gives it) and a quiet Cancel.
class _Decision extends StatelessWidget {
  const _Decision({
    required this.destructive,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final bool destructive;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: TrainColors.hairline),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: TrainColors.ember,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    key: const Key('proposal-confirm'),
                    onTap: onConfirm,
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(
                          destructive ? s.actionDelete : s.askProposalConfirm,
                          style: TrainType.ui(
                            size: 15,
                            weight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                key: const Key('proposal-cancel'),
                onTap: onCancel,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Text(
                    s.actionCancel,
                    style: TrainType.ui(
                      size: 15,
                      weight: FontWeight.w600,
                      color: TrainColors.ink2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How the change ended, where the decision used to be asked.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.status});

  final AiActionStatus status;

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final (IconData icon, String label, Color color) = switch (status) {
      AiActionStatus.applied => (
        AppIcons.check,
        s.askProposalConfirmed,
        TrainColors.green,
      ),
      AiActionStatus.cancelled => (
        AppIcons.close,
        s.askProposalCancelled,
        TrainColors.ink3,
      ),
      _ => (AppIcons.clock, s.askProposalExpired, TrainColors.ink3),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TrainType.ui(
            size: 12.5,
            weight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// One particular of the change: a quiet label in a fixed column, its value
/// beside it — how a receipt lists things.
class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
    required this.muted,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: TrainType.ui(
              size: 13,
              weight: FontWeight.w500,
              color: TrainColors.ink3,
              height: 1.35,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TrainType.ui(
              size: 13.5,
              weight: FontWeight.w600,
              color: muted ? TrainColors.ink3 : TrainColors.ink2,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

typedef _Kind = ({IconData icon, String label, Color hue});

_Kind _kindOf(BuildContext context, AiPendingAction action) {
  final s = l(context);
  switch (action.kind) {
    case 'create_expense':
      return (
        icon: AppIcons.expenses,
        label: s.askActionNewExpense,
        hue: TrainColors.amber,
      );
    case 'edit_expense':
      return (
        icon: AppIcons.edit,
        label: s.askActionEditExpense,
        hue: TrainColors.amber,
      );
    case 'delete_expense':
      return (
        icon: AppIcons.trash,
        label: s.askActionDeleteExpense,
        hue: TrainColors.ember,
      );
    case 'mark_meal_eaten':
      return (
        icon: AppIcons.diet,
        label: s.askActionDietPlan,
        hue: TrainColors.green,
      );
    case 'log_food':
      return (
        icon: AppIcons.diet,
        label: s.askActionLogFood,
        hue: TrainColors.green,
      );
    case 'replace_meal_item':
      return (
        icon: AppIcons.diet,
        label: s.askActionReplaceFood,
        hue: TrainColors.green,
      );
    case 'change_workout_day':
      final swap = action.fields['mode'] == 'swap';
      return (
        icon: AppIcons.workout,
        label: swap ? s.askActionWorkoutSwap : s.askActionWorkoutSkip,
        hue: TrainColors.green,
      );
    default:
      return (
        icon: AppIcons.ask,
        label: s.askActionSuggestion,
        hue: TrainColors.ink2,
      );
  }
}

/// The one thing the change is about, and whether it's a figure (set in the
/// numbers face) or words.
({String text, bool numeric}) _headlineOf(
  BuildContext context,
  AiPendingAction action,
) {
  final f = action.fields;
  String? text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
  switch (action.kind) {
    case 'create_expense':
      return (
        text: ltrFor(
          context,
          '${f['amount'] ?? ''} ${f['currency'] ?? ''}'.trim(),
        ),
        numeric: true,
      );
    case 'edit_expense':
    case 'delete_expense':
      final target = text(f['target']);
      return (
        text: target == null ? action.summary : isolate(target),
        numeric: false,
      );
    case 'mark_meal_eaten':
      return (text: isolate(text(f['meal']) ?? action.summary), numeric: false);
    case 'log_food':
      final items = f['items'];
      if (items is List && items.length == 1 && items.first is Map) {
        final name = text((items.first as Map)['name']);
        if (name != null) return (text: isolate(name), numeric: false);
      }
      final count = f['count'];
      if (count is int && count > 0) {
        return (text: l(context).askFoodCount(count), numeric: false);
      }
      return (text: action.summary, numeric: false);
    case 'replace_meal_item':
      final to = text(f['to']);
      return (text: to == null ? action.summary : isolate(to), numeric: false);
    case 'change_workout_day':
      final to = text(f['to']);
      return (
        text: to == null
            ? action.summary
            : l(context).askWorkoutToday(isolate(to)),
        numeric: false,
      );
    default:
      return (text: action.summary, numeric: false);
  }
}

/// A quantity like 2.0 → "2", 1.5 → "1.5" — plan/log amounts arrive as JSON
/// numbers and read badly with a trailing ".0".
String _qty(Object? value) {
  if (value is! num) return '';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

/// The particulars, as (label, value) receipt rows.
List<(String, String)> _rowsOf(BuildContext context, AiPendingAction action) {
  final s = l(context);
  final f = action.fields;
  String? text(Object? v) =>
      v != null && '$v'.trim().isNotEmpty ? '$v'.trim() : null;
  String money(Object? amount) =>
      ltrFor(context, '$amount ${f['currency'] ?? ''}'.trim());
  String kcal(Object? v) => ltrFor(context, s.askKcalTotal('$v'));
  final rows = <(String, String)>[];
  switch (action.kind) {
    case 'create_expense':
      if (text(f['category']) case final c?) {
        rows.add((s.askRowCategory, _categoryName(context, c)));
      }
      if (text(f['note']) case final n?) rows.add((s.askRowNote, isolate(n)));
    case 'edit_expense':
      // Each field being changed, as its NEW value.
      if (f['amount'] != null) rows.add((s.askRowAmount, money(f['amount'])));
      if (text(f['category']) case final c?) {
        rows.add((s.askRowCategory, _categoryName(context, c)));
      }
      if (text(f['note']) case final n?) rows.add((s.askRowNote, isolate(n)));
    case 'delete_expense':
      if (f['amount'] != null) rows.add((s.askRowAmount, money(f['amount'])));
      if (text(f['category']) case final c?) {
        rows.add((s.askRowCategory, _categoryName(context, c)));
      }
    case 'mark_meal_eaten':
      // `state` arrives as the English "eaten"/"not eaten" — a server-side
      // value, read as a flag; the WORD is the app's own.
      final eaten = f['state'] != 'not eaten';
      rows.add((s.askRowStatus, eaten ? s.dietEaten : s.dietNotEaten));
    case 'log_food':
      final items = f['items'];
      if (items is List && items.length > 1) {
        for (final raw in items) {
          if (raw is! Map) continue;
          // A food name is text ZIVO did not write, so it decides its own
          // direction; the quantity is a composed run and is pinned.
          final amount = '${_qty(raw['quantity'])} ${raw['unit'] ?? ''}'.trim();
          rows.add((isolate('${raw['name'] ?? ''}'), ltrFor(context, amount)));
        }
        if (f['totalKcal'] != null) {
          rows.add((s.askRowTotal, kcal(f['totalKcal'])));
        }
      } else if (items is List && items.length == 1 && items.first is Map) {
        final raw = items.first as Map;
        final amount = '${_qty(raw['quantity'])} ${raw['unit'] ?? ''}'.trim();
        if (amount.isNotEmpty) {
          rows.add((s.askRowAmount, ltrFor(context, amount)));
        }
        if (f['totalKcal'] != null) {
          rows.add((s.askRowCalories, kcal(f['totalKcal'])));
        }
      }
    case 'replace_meal_item':
      if (text(f['meal']) case final m?) rows.add((s.askRowMeal, isolate(m)));
      if (text(f['from']) case final from?) {
        rows.add((s.askRowInsteadOf, isolate(from)));
      }
      if (f['toCalories'] != null) {
        final was = f['fromCalories'] != null
            ? ', ${s.askRowWas(kcal(f['fromCalories']))}'
            : '';
        rows.add((s.askRowCalories, '${kcal(f['toCalories'])}$was'));
      }
    case 'change_workout_day':
      final from = text(f['from']);
      final then = text(f['then']);
      if (f['mode'] == 'swap') {
        if (from != null) rows.add((s.askRowInsteadOf, isolate(from)));
        if (then != null) rows.add((s.askRowNext, isolate(then)));
      } else {
        if (from != null) {
          rows.add((
            s.askRowSkipped,
            s.askSkippedUntilNextRound(isolate(from)),
          ));
        }
        if (then != null) rows.add((s.askRowThen, isolate(then)));
      }
  }
  return rows;
}

/// A stored category id in the reader's words — the built-in ones through the
/// same strings the Expenses screens use, a user's own category as they wrote
/// it (capitalised: the id is stored lower-case).
String _categoryName(BuildContext context, String id) {
  final s = l(context);
  return switch (id.toLowerCase()) {
    'food' => s.categoryFood,
    'coffee' => s.categoryCoffee,
    'transport' => s.categoryTransport,
    'groceries' => s.categoryGroceries,
    'shopping' => s.categoryShopping,
    'other' => s.categoryOther,
    _ => isolate('${id[0].toUpperCase()}${id.substring(1)}'),
  };
}
