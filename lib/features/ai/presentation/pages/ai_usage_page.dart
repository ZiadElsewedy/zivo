import 'package:flutter/material.dart';

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

/// Every AI request ZIVO has made for this user — what it was for, which model
/// did the work, the tokens it used and what it cost — read from the
/// owner-readable `aiUsage` log that every AI callable now writes
/// (`functions/ai/shared/usage_log.js`).
///
/// Top to bottom: the all-time total, totals per provider, totals per feature
/// (chat, plan import, plan builder, food search, voice), then the latest
/// requests one by one — with a "backup model" badge where Auto fell back and
/// a "failed" badge where nothing could answer. Costs are the backend's
/// estimates from list prices, and the footnote says so.
class AiUsagePage extends StatefulWidget {
  const AiUsagePage({super.key});

  @override
  State<AiUsagePage> createState() => _AiUsagePageState();
}

class _AiUsagePageState extends State<AiUsagePage> {
  Future<List<AiUsageRecord>>? _records;

  /// How many individual requests the "Recent" list shows. The totals above
  /// it are computed over everything loaded, not just these.
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
              const SizedBox(height: 22),
              if (snapshot.hasError)
                _Quiet(text: l(context).aiErrorGeneric)
              else if (records == null)
                // Loading — reserve a little height, no spinner (a settings
                // page shouldn't feel busy).
                const SizedBox(height: 120)
              else if (records.isEmpty)
                _Quiet(text: l(context).aiUsageEmpty)
              else
                ..._sections(context, records),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _sections(BuildContext context, List<AiUsageRecord> records) {
    final total = aiUsageGrandTotal(records);
    final byProvider = aiUsageTotalsBy(records, (r) => r.provider);
    final byFeature = aiUsageTotalsBy(records, (r) => r.feature);
    final recent = records.take(_recentShown).toList();
    return [
      RiseIn(
        delay: const Duration(milliseconds: 40),
        child: _TotalCard(total: total),
      ),
      const SizedBox(height: 22),
      RiseIn(
        delay: const Duration(milliseconds: 80),
        child: SettingsSectionCard(
          label: l(context).aiUsageByProvider,
          children: [
            for (var i = 0; i < byProvider.length; i++)
              AiDetailRow(
                leading: ProviderMark(provider: byProvider[i].key),
                title: aiProviderDisplayName(context, byProvider[i].key),
                subtitle: _groupSubtitle(context, byProvider[i]),
                last: i == byProvider.length - 1,
                trailing: _Cost(byProvider[i].costUsd),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      RiseIn(
        delay: const Duration(milliseconds: 120),
        child: SettingsSectionCard(
          label: l(context).aiUsageByFeature,
          children: [
            for (var i = 0; i < byFeature.length; i++)
              AiDetailRow(
                leading: _FeatureIcon(byFeature[i].key),
                title: aiFeatureText(context, byFeature[i].key),
                subtitle: _groupSubtitle(context, byFeature[i]),
                last: i == byFeature.length - 1,
                trailing: _Cost(byFeature[i].costUsd),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      RiseIn(
        delay: const Duration(milliseconds: 160),
        child: SettingsSectionCard(
          label: l(context).aiUsageRecent,
          children: [
            for (var i = 0; i < recent.length; i++)
              _RequestRow(record: recent[i], last: i == recent.length - 1),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          l(context).aiUsageCostNote,
          style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
        ),
      ),
    ];
  }

  String _groupSubtitle(BuildContext context, AiUsageTotals t) =>
      _requestsAndTokens(context, t);
}

/// "12 requests · 40.1K in · 2.2K out". Only the figures are LTR-isolated —
/// wrapping the whole line would reverse the Arabic words around them.
String _requestsAndTokens(BuildContext context, AiUsageTotals t) =>
    '${l(context).askUsageRequests(t.requests)} · ${_inOut(context, t.tokensIn, t.tokensOut)}';

String _inOut(BuildContext context, int tokensIn, int tokensOut) =>
    l(context).aiUsageInOut(
      ltrFor(context, compactTokens(tokensIn)),
      ltrFor(context, compactTokens(tokensOut)),
    );

/// The headline: all-time estimated cost, with requests and tokens under it.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total});

  final AiUsageTotals total;

  @override
  Widget build(BuildContext context) {
    return TrainCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l(context).aiUsageTotal.toUpperCase(),
            style: TrainType.caption(size: 9, tracking: 0.16),
          ),
          const SizedBox(height: 8),
          Text(
            l(
              context,
            ).askUsageEstCost(ltrFor(context, formatUsd(total.costUsd))),
            key: const Key('ai-usage-total-cost'),
            style: TrainType.mono(
              size: 30,
              color: TrainColors.inkPlain,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _requestsAndTokens(context, total),
            style: AppText.meta.copyWith(color: TrainColors.ink2),
          ),
        ],
      ),
    );
  }
}

/// One logged request: what it was for, the model that answered, tokens,
/// when — and a badge if it fell back to a backup model or failed.
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
        _inOut(context, record.tokensIn, record.tokensOut),
      if (record.createdAt != null) _when(context, record.createdAt!),
    ];
    final badge = record.failed
        ? _Badge(text: l(context).aiUsageFailed, color: TrainColors.ember)
        : record.cancelled
        ? _Badge(text: l(context).aiUsageCancelled, color: TrainColors.ink3)
        : record.fellBack
        ? _Badge(text: l(context).aiUsageFellBack, color: TrainColors.violet)
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
          _Cost(record.costUsd),
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

class _Cost extends StatelessWidget {
  const _Cost(this.usd);

  final double usd;

  @override
  Widget build(BuildContext context) => Text(
    ltrFor(context, formatUsd(usd)),
    style: TrainType.mono(size: 13.5, color: TrainColors.inkPlain, height: 1.1),
  );
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
