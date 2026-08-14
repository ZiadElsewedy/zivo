import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../data/today_demo_data.dart';
import '../../domain/today_snapshot.dart';
import '../widgets/common.dart';
import '../widgets/focus_list.dart';
import '../widgets/now_next_card.dart';
import '../widgets/spending_glance.dart';
import '../widgets/training_card.dart';

/// The Today command centre — the adaptive surface that reads like a sentence
/// about the day. Currently rendered from demo data.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    const s = todayDemoSnapshot;
    final media = MediaQuery.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.1),
          radius: 1.1,
          colors: [Color(0xFFFFFDF8), AppColors.ground, Color(0xFFF0EDE6)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: media.padding.top + 6),
          const _AskHint(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.s,
                AppSpacing.screen,
                media.padding.bottom + 150,
              ),
              children: [
                RiseIn(delay: Duration.zero, child: _Header(s)),
                RiseIn(
                  delay: const Duration(milliseconds: 90),
                  child: _NowNextSection(s.nowNext),
                ),
                RiseIn(
                  delay: const Duration(milliseconds: 170),
                  child: _FocusSection(s.focus),
                ),
                RiseIn(
                  delay: const Duration(milliseconds: 250),
                  child: _TrainingSection(s.training),
                ),
                RiseIn(
                  delay: const Duration(milliseconds: 330),
                  child: _SpendingSection(s.spending),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AskHint extends StatelessWidget {
  const _AskHint();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.hairline2,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'PULL TO ASK',
          style: AppText.tabLabel.copyWith(
            color: AppColors.ink3,
            letterSpacing: 1.9,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.s);

  final TodaySnapshot s;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(s.dateLabel.toUpperCase(), style: AppText.dateLabel),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(child: Text(s.greeting, style: AppText.greeting)),
            const SizedBox(width: 8),
            const Icon(Icons.wb_sunny_rounded, color: AppColors.ember, size: 25),
          ],
        ),
        const SizedBox(height: 11),
        Text(s.aside, style: AppText.aside),
      ],
    );
  }
}

class _NowNextSection extends StatelessWidget {
  const _NowNextSection(this.data);

  final NowNext? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Now · Next', top: AppSpacing.section - 4),
        NowNextCard(data!),
      ],
    );
  }
}

class _FocusSection extends StatelessWidget {
  const _FocusSection(this.items);

  final List<FocusItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Today'),
        FocusList(items),
      ],
    );
  }
}

class _TrainingSection extends StatelessWidget {
  const _TrainingSection(this.data);

  final TrainingToday? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Training'),
        TrainingCard(data!),
      ],
    );
  }
}

class _SpendingSection extends StatelessWidget {
  const _SpendingSection(this.data);

  final SpendingGlance? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Spending'),
        SpendingGlanceRow(data!),
      ],
    );
  }
}
