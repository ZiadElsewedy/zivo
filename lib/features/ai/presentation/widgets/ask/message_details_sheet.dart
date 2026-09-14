import 'package:flutter/material.dart';

import '../../../../../core/theme/train_tokens.dart';
import '../../../../../l10n/l10n.dart';
import '../../../domain/ai_message.dart';
import '../../../domain/ai_repository.dart';
import '../../../domain/ai_turn_usage.dart';
import '../../ai_labels.dart';

/// Long-press an assistant reply → this sheet, showing which model answered and
/// that turn's token/cost telemetry (the `aiUsage` doc, matched by
/// [AiMessage.clientTurnId]). Read-only; there is nothing to confirm.
Future<void> showAskTurnDetails(
  BuildContext context, {
  required AiRepository repo,
  required AiMessage message,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: TrainColors.sheetSurface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: _TurnDetails(
          future: repo.usageForTurn(message.clientTurnId ?? ''),
        ),
      ),
    ),
  );
}

class _TurnDetails extends StatelessWidget {
  const _TurnDetails({required this.future});

  final Future<AiTurnUsage?> future;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l(context).askTurnDetailsTitle,
          style: TrainType.ui(
            size: 17,
            weight: FontWeight.w700,
            color: TrainColors.ink,
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<AiTurnUsage?>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final usage = snap.data;
            if (usage == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l(context).askTurnUnavailable,
                  style: TrainType.ui(
                    size: 14,
                    weight: FontWeight.w400,
                    color: TrainColors.ink.withValues(alpha: 0.6),
                    height: 1.4,
                  ),
                ),
              );
            }
            return _rows(context, usage);
          },
        ),
      ],
    );
  }

  Widget _rows(BuildContext context, AiTurnUsage u) {
    final s = l(context);
    final provider = aiProviderDisplayName(context, u.provider);
    final answeredBy = u.model.isEmpty ? provider : '$provider · ${u.model}';
    final tools = u.tools.isEmpty ? s.askTurnNone : u.tools.join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(label: s.askTurnAnsweredBy, value: answeredBy),
        const _Divider(),
        _Row(
          label: s.askTurnInputTokens,
          value: _int(u.tokensIn),
          // Cache split reads under the input total.
          sub:
              '${s.askTurnCached} ${_int(u.cacheReadTokens)}'
              ' · ${s.askTurnUncached} ${_int(u.uncachedTokensIn)}',
        ),
        _Row(label: s.askTurnOutputTokens, value: _int(u.tokensOut)),
        _Row(label: s.askTurnToolResults, value: _int(u.toolResultTokens)),
        _Row(label: s.askTurnTools, value: tools),
        _Row(label: s.askTurnIterations, value: _int(u.iterations)),
        _Row(label: s.askTurnLatency, value: _latency(u.latencyMs)),
        _Row(label: s.askTurnCost, value: _cost(u.costUsd)),
      ],
    );
  }

  /// Thousands-grouped integer (locale-neutral, ASCII digits) — the numbers are
  /// diagnostic, so a plain grouped form reads the same in every locale.
  static String _int(int v) {
    final digits = v.abs().toString();
    final buf = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  static String _latency(int ms) =>
      ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)} s' : '$ms ms';

  static String _cost(double usd) {
    // Small turns are fractions of a cent — keep enough digits to be non-zero.
    final digits = usd < 0.01 ? 5 : 4;
    return '\$${usd.toStringAsFixed(digits)}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TrainType.ui(
                    size: 14,
                    weight: FontWeight.w500,
                    color: TrainColors.ink.withValues(alpha: 0.6),
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    sub!,
                    style: TrainType.mono(
                      size: 11.5,
                      color: TrainColors.ink.withValues(alpha: 0.45),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TrainType.mono(
              size: 14,
              weight: FontWeight.w500,
              color: TrainColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: TrainColors.hairline);
}
