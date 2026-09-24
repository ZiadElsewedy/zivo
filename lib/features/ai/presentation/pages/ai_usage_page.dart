import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/settings_row.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/ai_usage_summary.dart';
import '../ai_labels.dart';
import '../widgets/ask/ai_detail_row.dart';
import '../widgets/ask/provider_mark.dart';

/// The providers the usage page can be switched between, in display order.
const _kUsageProviders = ['anthropic', 'gemini'];

/// Where the AI money goes, one provider at a time.
///
/// Pick **Claude** or **Gemini** at the top and everything below is that
/// provider only: its estimated cost and the average cost of a request, how
/// many requests of each type it served (chat · generate · import · other,
/// plus how many failed), the tokens in and out, and its latest requests one
/// by one. Read from the owner-readable `aiUsage` log, which every AI request
/// writes with its provider, type, tokens and cost
/// (`functions/ai/shared/usage_log.js`). Costs are the backend's estimates
/// from list prices, and the footnote says so.
class AiUsagePage extends StatefulWidget {
  const AiUsagePage({this.initialProvider = 'anthropic', super.key});

  /// The provider selected on open ('anthropic' | 'gemini').
  final String initialProvider;

  @override
  State<AiUsagePage> createState() => _AiUsagePageState();
}

class _AiUsagePageState extends State<AiUsagePage> {
  Future<List<AiUsageRecord>>? _records;
  late String _provider = _kUsageProviders.contains(widget.initialProvider)
      ? widget.initialProvider
      : _kUsageProviders.first;

  /// How many individual requests the "Recent" list shows. The stats above it
  /// are computed over everything loaded, not just these.
  static const int _recentShown = 60;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load once — AppScope isn't safe to read in initState.
    _records ??= AppScope.of(context).ai.usageRecords();
  }

  @override
  Widget build(BuildContext context) {
    return TrainScreen(
      tint: TrainColors.settingsTint,
      child: FutureBuilder<List<AiUsageRecord>>(
        future: _records,
        builder: (context, snapshot) {
          final records = snapshot.data;
          return ListView(
            key: const Key('ai-usage-page'),
            padding: EdgeInsets.fromLTRB(
              22,
              12,
              22,
              TrainBottomInset.of(context),
            ),
            children: [
              RiseIn(child: TrainPageHeader(title: l(context).aiUsageTitle)),
              const SizedBox(height: 20),
              _ProviderSwitch(
                selected: _provider,
                onSelect: (p) {
                  if (p == _provider) return;
                  HapticFeedback.selectionClick();
                  setState(() => _provider = p);
                },
              ),
              const SizedBox(height: 18),
              if (snapshot.hasError)
                _Quiet(text: l(context).aiErrorUnknownBody)
              else if (records == null)
                // Loading — reserve a little height, no spinner (a settings
                // page shouldn't feel busy).
                const SizedBox(height: 120)
              else
                ..._providerSections(context, records),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _providerSections(
    BuildContext context,
    List<AiUsageRecord> records,
  ) {
    final name = aiProviderDisplayName(context, _provider);
    final stats = aiProviderStats(records, _provider);
    if (stats.totalRequests == 0) {
      return [_Quiet(text: l(context).aiUsageProviderEmpty(name))];
    }
    final recent = records
        .where((r) => r.provider == _provider)
        .take(_recentShown)
        .toList();
    final requestRows = <(String, int)>[
      (l(context).aiUsageTotalRequests, stats.totalRequests),
      (l(context).aiUsageChatRequests, stats.chatRequests),
      (l(context).aiUsageGenerateRequests, stats.generateRequests),
      (l(context).aiUsageImportRequests, stats.importRequests),
      (l(context).aiUsageOtherRequests, stats.otherRequests),
      if (stats.failedRequests > 0)
        (l(context).aiUsageFailedRequests, stats.failedRequests),
    ];
    final tokenRows = <(String, int)>[
      (l(context).aiUsageTokensUsed, stats.tokensTotal),
      (l(context).aiUsageInputTokens, stats.tokensIn),
      (l(context).aiUsageOutputTokens, stats.tokensOut),
    ];
    return [
      _CostCard(stats: stats),
      const SizedBox(height: 20),
      SettingsSectionCard(
        label: l(context).aiUsageRequestsSection,
        children: [
          for (var i = 0; i < requestRows.length; i++)
            _StatRow(
              key: Key('stat-requests-$i'),
              label: requestRows[i].$1,
              value: ltrFor(context, _grouped(requestRows[i].$2)),
              emphasis: i == 0,
              last: i == requestRows.length - 1,
            ),
        ],
      ),
      const SizedBox(height: 20),
      SettingsSectionCard(
        label: l(context).aiUsageTokensSection,
        children: [
          for (var i = 0; i < tokenRows.length; i++)
            _StatRow(
              key: Key('stat-tokens-$i'),
              label: tokenRows[i].$1,
              value: ltrFor(context, _grouped(tokenRows[i].$2)),
              emphasis: i == 0,
              last: i == tokenRows.length - 1,
            ),
        ],
      ),
      const SizedBox(height: 20),
      SettingsSectionCard(
        label: l(context).aiUsageRecent,
        children: [
          for (var i = 0; i < recent.length; i++)
            _RequestRow(record: recent[i], last: i == recent.length - 1),
        ],
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          l(context).aiUsageCostNote,
          style: AppText.meta.copyWith(color: TrainColors.ink2, height: 1.4),
        ),
      ),
    ];
  }
}

/// 1234567 → "1,234,567" — exact counts, not the compact "1.2M", because this
/// page is where the precise number is wanted.
String _grouped(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// The Claude | Gemini switch — two pills with the provider marks.
class _ProviderSwitch extends StatelessWidget {
  const _ProviderSwitch({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TrainColors.sectionFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          for (final p in _kUsageProviders)
            Expanded(
              child: GestureDetector(
                key: Key('usage-provider-$p'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: p == selected
                        ? TrainColors.raisedStrong
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ProviderMark(provider: p),
                      const SizedBox(width: 8),
                      Text(
                        aiProviderDisplayName(context, p),
                        style: TrainType.ui(
                          size: 15,
                          weight: p == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: p == selected
                              ? TrainColors.inkPlain
                              : TrainColors.ink2,
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
}

/// The headline: this provider's estimated cost, and what a completed request
/// costs on average.
class _CostCard extends StatelessWidget {
  const _CostCard({required this.stats});

  final AiProviderStats stats;

  @override
  Widget build(BuildContext context) {
    return TrainCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l(context).aiUsageEstimatedCost.toUpperCase(),
                  style: TrainType.caption(size: 9, tracking: 0.16),
                ),
                const SizedBox(height: 8),
                Text(
                  ltrFor(context, formatUsd(stats.costUsd)),
                  key: const Key('ai-usage-total-cost'),
                  style: TrainType.mono(
                    size: 30,
                    color: TrainColors.inkPlain,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                l(context).aiUsageCostPerRequest.toUpperCase(),
                style: TrainType.caption(size: 9, tracking: 0.16),
              ),
              const SizedBox(height: 8),
              Text(
                ltrFor(context, formatUsd(stats.costPerRequestUsd)),
                key: const Key('ai-usage-cost-per-request'),
                style: TrainType.mono(
                  size: 17,
                  color: TrainColors.ink,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A label on the left, an exact figure on the right.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.last,
    this.emphasis = false,
    super.key,
  });

  final String label;
  final String value;
  final bool last;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 17),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TrainType.ui(
                    size: 15,
                    weight: emphasis ? FontWeight.w700 : FontWeight.w500,
                    color: emphasis ? TrainColors.inkPlain : TrainColors.ink,
                  ),
                ),
              ),
              Text(
                value,
                style: TrainType.mono(
                  size: 15,
                  color: TrainColors.inkPlain,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        if (!last)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 17),
            child: Divider(height: 1, thickness: 1, color: TrainColors.hairline),
          ),
      ],
    );
  }
}

/// One logged request: what it was for, the model that answered, tokens,
/// when — and a badge if it failed or was cancelled.
class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.record, required this.last});

  final AiUsageRecord record;
  final bool last;

  String _when(BuildContext context, DateTime at) {
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay
        ? formatClockTime(context, at)
        : '${formatMonthDay(context, at)}, ${formatClockTime(context, at)}';
  }

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (record.model.isNotEmpty) aiModelIdText(context, record.model),
      if (record.tokensTotal > 0)
        l(context).aiUsageInOut(
          ltrFor(context, compactTokens(record.tokensIn)),
          ltrFor(context, compactTokens(record.tokensOut)),
        ),
      // The router's automatic fallback made this request succeed on a
      // different provider than the one the user has active — said plainly,
      // not left for the model name alone to imply.
      if (record.fallbackOccurred && record.requestedProvider != null)
        l(context).aiUsageSwitchedFrom(
          aiProviderDisplayName(context, record.requestedProvider!),
        ),
      if (record.createdAt != null) _when(context, record.createdAt!),
    ];
    final badge = record.failed
        ? _Badge(text: l(context).aiUsageFailed, color: TrainColors.ember)
        : record.cancelled
        ? _Badge(text: l(context).aiUsageCancelled, color: TrainColors.ink3)
        : null;
    return AiDetailRow(
      leading: _FeatureIcon(record.feature),
      title: aiFeatureText(context, record.feature),
      subtitle: parts.join(' · '),
      last: last,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            ltrFor(context, formatUsd(record.costUsd)),
            style: TrainType.mono(
              size: 13.5,
              color: TrainColors.inkPlain,
              height: 1.1,
            ),
          ),
          if (badge != null) ...[const SizedBox(height: 4), badge],
        ],
      ),
    );
  }
}

class _FeatureIcon extends StatelessWidget {
  const _FeatureIcon(this.feature);

  final String feature;

  IconData get _icon => switch (feature) {
    'chat' => AppIcons.ask,
    'workout_import' => AppIcons.workout,
    'diet_import' => AppIcons.planDoc,
    'diet_generate' => AppIcons.diet,
    'food_search' => AppIcons.search,
    'transcribe' => AppIcons.mic,
    _ => AppIcons.bolt,
  };

  @override
  Widget build(BuildContext context) =>
      Icon(_icon, size: 19, color: TrainColors.ink2);
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: AppText.meta.copyWith(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 6),
    child: Text(text, style: AppText.body.copyWith(color: TrainColors.ink2)),
  );
}
