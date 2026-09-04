import 'package:flutter/material.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../domain/ai_pending_action.dart';
import '../../../../../l10n/l10n.dart';

/// The ADR-003 confirmation card: an assistant proposal the user confirms or
/// cancels. Nothing has been written while it shows Confirm/Cancel.
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
    final resolved = status != AiActionStatus.pending;
    final meta = _kindMeta(context, action.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      // The card grows/settles smoothly as it swaps between the proposal and
      // the confirmed/declined receipt.
      child: AnimatedSize(
        duration: AppMotion.enter,
        curve: AppMotion.ease,
        alignment: Alignment.topCenter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          decoration: BoxDecoration(
            color: TrainColors.raised,
            borderRadius: BorderRadius.circular(20),
            // While it's awaiting a decision the card wears a faint wash of its
            // own hue and a soft lift, so it reads as a live, tappable object;
            // once resolved it settles back to a quiet history receipt.
            border: Border.all(
              color: resolved
                  ? TrainColors.hairline
                  : meta.tintFg.withValues(alpha: 0.22),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(resolved),
              child: resolved
                  ? _resolved(context, meta)
                  : _pending(context, meta),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pending(
    BuildContext context,
    ({IconData icon, String label, Color tintBg, Color tintFg}) meta,
  ) {
    final chips = _chips(context);
    final confirm = _confirmSpec(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerRow(meta),
        const SizedBox(height: 13),
        Text(
          _primaryLine(context),
          style: AppText.cardTitle.copyWith(fontSize: 20, letterSpacing: -0.3),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 7, runSpacing: 7, children: chips),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Material(
                color: confirm.color,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  key: const Key('proposal-confirm'),
                  onTap: onConfirm,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    child: Text(
                      confirm.label,
                      style: AppText.button.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              key: const Key('proposal-cancel'),
              onTap: onCancel,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                child: Text(
                  l(context).actionCancel,
                  style: AppText.button.copyWith(color: TrainColors.ink2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The resolved receipt: keeps the WHAT (kind, headline, detail chips) so a
  /// confirmation read days later still says exactly what was added, changed,
  /// or removed — with a small status pill instead of the action buttons.
  Widget _resolved(
    BuildContext context,
    ({IconData icon, String label, Color tintBg, Color tintFg}) meta,
  ) {
    final s = _statusSpec(context);
    final chips = _chips(context);
    final applied = status == AiActionStatus.applied;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerRow(meta, trailing: _statusPill(s)),
        const SizedBox(height: 12),
        Text(
          _primaryLine(context),
          style: AppText.cardTitle.copyWith(
            fontSize: 19,
            letterSpacing: -0.3,
            color: applied ? TrainColors.ink : TrainColors.ink3,
            // A struck-through headline reads instantly as "this did not
            // happen" for a cancelled or expired proposal.
            decoration: applied ? null : TextDecoration.lineThrough,
            decorationColor: TrainColors.ink3,
          ),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 11),
          Opacity(
            opacity: applied ? 1 : 0.6,
            child: Wrap(spacing: 7, runSpacing: 7, children: chips),
          ),
        ],
      ],
    );
  }

  Widget _headerRow(
    ({IconData icon, String label, Color tintBg, Color tintFg}) meta, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: meta.tintBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(meta.icon, size: 18, color: meta.tintFg),
        ),
        const SizedBox(width: 10),
        Text(
          meta.label,
          style: AppText.meta.copyWith(
            color: meta.tintFg,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );
  }

  Widget _statusPill(({IconData icon, String label, Color fg, Color bg}) s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 13, color: s.fg),
          const SizedBox(width: 5),
          Text(
            s.label,
            style: AppText.meta.copyWith(
              fontSize: 12,
              color: s.fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String label, Color fg, Color bg}) _statusSpec(
    BuildContext context,
  ) {
    switch (status) {
      case AiActionStatus.applied:
        return (
          icon: AppIcons.check,
          label: l(context).askProposalConfirmed,
          fg: TrainColors.green,
          bg: TrainColors.greenWash,
        );
      case AiActionStatus.cancelled:
        return (
          icon: AppIcons.close,
          label: l(context).askProposalCancelled,
          fg: TrainColors.ink3,
          bg: TrainColors.hairline,
        );
      default:
        return (
          icon: AppIcons.clock,
          label: l(context).askProposalExpired,
          fg: TrainColors.ink3,
          bg: TrainColors.hairline,
        );
    }
  }

  /// The confirm button's verb + colour. A delete is destructive, so it wears
  /// the alert hue and says "Delete" rather than a neutral "Confirm".
  ({String label, Color color}) _confirmSpec(BuildContext context) {
    if (action.kind == 'delete_expense') {
      return (label: l(context).actionDelete, color: TrainColors.ember);
    }
    return (label: l(context).askProposalConfirm, color: TrainColors.violet);
  }

  String _primaryLine(BuildContext context) {
    final f = action.fields;
    switch (action.kind) {
      case 'create_expense':
        return '${f['amount'] ?? ''} ${f['currency'] ?? ''}'.trim();
      case 'edit_expense':
      case 'delete_expense':
        final target = f['target'];
        return (target is String && target.trim().isNotEmpty)
            ? target
            : action.summary;
      case 'mark_meal_eaten':
        return '${f['meal'] ?? ''}'.trim();
      case 'log_food':
        final items = f['items'];
        if (items is List && items.length == 1 && items.first is Map) {
          final name = (items.first as Map)['name'];
          if (name is String && name.trim().isNotEmpty) return name.trim();
        }
        final count = f['count'];
        if (count is int && count > 0) return l(context).askFoodCount(count);
        return action.summary;
      default:
        return action.summary;
    }
  }

  /// A quantity like 2.0 → "2", 1.5 → "1.5" — plan/log amounts arrive as JSON
  /// numbers and read badly with a trailing ".0".
  String _qty(Object? value) {
    if (value is! num) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  List<Widget> _chips(BuildContext context) {
    final f = action.fields;
    final chips = <Widget>[];
    switch (action.kind) {
      case 'create_expense':
        if (f['category'] != null) {
          chips.add(_chip(AppIcons.tag, f['category'].toString()));
        }
        if (f['note'] != null) {
          chips.add(_chip(AppIcons.caption, f['note'].toString()));
        }
      case 'edit_expense':
        // Each field being changed, shown as its NEW value ("→ 60.00 EGP").
        final amount = f['amount'];
        if (amount != null) {
          chips.add(
            _chip(AppIcons.expenses, '→ $amount ${f['currency'] ?? ''}'.trim()),
          );
        }
        if (f['category'] != null) {
          chips.add(_chip(AppIcons.tag, '→ ${f['category']}'));
        }
        if (f['note'] != null) {
          chips.add(_chip(AppIcons.caption, '→ ${f['note']}'));
        }
      case 'delete_expense':
        final amount = f['amount'];
        if (amount != null) {
          chips.add(
            _chip(AppIcons.expenses, '$amount ${f['currency'] ?? ''}'.trim()),
          );
        }
        if (f['category'] != null) {
          chips.add(_chip(AppIcons.tag, f['category'].toString()));
        }
      case 'mark_meal_eaten':
        chips.add(
          _chip(
            f['state'] == 'eaten' ? AppIcons.success : AppIcons.close,
            f['state']?.toString() ?? 'eaten',
          ),
        );
      case 'log_food':
        final items = f['items'];
        if (items is List) {
          for (final raw in items) {
            if (raw is! Map) continue;
            final name = raw['name']?.toString() ?? '';
            final amount = '${_qty(raw['quantity'])} ${raw['unit'] ?? ''}'
                .trim();
            final label = amount.isEmpty ? name : '$name · $amount';
            if (label.isNotEmpty) chips.add(_chip(AppIcons.diet, label));
          }
        }
        // A total, only when it adds something over a single item's own chip.
        final total = f['totalKcal'];
        if (total != null && items is List && items.length > 1) {
          chips.add(_chip(AppIcons.diet, l(context).askKcalTotal('$total')));
        }
    }
    return chips;
  }

  Widget _chip(IconData icon, String label, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg ?? TrainColors.raisedStrong,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg ?? TrainColors.ink2),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.meta.copyWith(color: fg ?? TrainColors.ink2),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String label, Color tintBg, Color tintFg}) _kindMeta(
    BuildContext context,
    String kind,
  ) {
    switch (kind) {
      case 'create_expense':
        return (
          icon: AppIcons.expenses,
          label: l(context).askActionNewExpense,
          tintBg: TrainColors.amberWash,
          tintFg: TrainColors.amber,
        );
      case 'edit_expense':
        return (
          icon: AppIcons.edit,
          label: l(context).askActionEditExpense,
          tintBg: TrainColors.amberWash,
          tintFg: TrainColors.amber,
        );
      case 'delete_expense':
        return (
          icon: AppIcons.trash,
          label: l(context).askActionDeleteExpense,
          tintBg: TrainColors.emberWash,
          tintFg: TrainColors.ember,
        );
      case 'mark_meal_eaten':
        return (
          icon: AppIcons.diet,
          label: l(context).askActionDietPlan,
          tintBg: TrainColors.greenWash,
          tintFg: TrainColors.green,
        );
      case 'log_food':
        return (
          icon: AppIcons.diet,
          label: l(context).askActionLogFood,
          tintBg: TrainColors.greenWash,
          tintFg: TrainColors.green,
        );
      default:
        return (
          icon: AppIcons.ask,
          label: l(context).askActionSuggestion,
          tintBg: TrainColors.hairline,
          tintFg: TrainColors.ink2,
        );
    }
  }
}
