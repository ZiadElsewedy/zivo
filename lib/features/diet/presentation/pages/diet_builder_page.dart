import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../capture/presentation/widgets/voice_capture_field.dart';
import '../../../workout/domain/body_weight_entry.dart';
import '../../domain/common_foods.dart';
import '../../domain/diet_goal.dart';
import '../../domain/nutrition_targets.dart';
import '../../domain/target_calculator.dart';
import '../controllers/diet_builder_controller.dart';
import '../diet_labels.dart';
import '../widgets/diet_number_field.dart';
import '../widgets/food_chip_picker.dart';
import 'diet_import_page.dart';
import 'diet_plan_reveal_page.dart';

/// The guided Diet Builder — one number-free flow that asks what someone is
/// trying to do and how they live, then does the arithmetic and the generation
/// behind the scenes.
///
/// Goal → About you → How you eat → What you avoid → How many meals → **Build**,
/// then the plan reveal. The steps only *gather*: the deterministic target
/// (`calculateTargets`), the AI generation and the review-and-save all happen
/// after Build, so the user never sees a calorie figure until it's useful
/// context on the finished plan.
///
/// Everything downstream is the existing engine — `DietImportPage` runs the
/// generation and its analysing/decline UI, `DietPlanRevealPage` is the review
/// gate. This screen is only the intake, held together by a
/// [DietBuilderController].
class DietBuilderPage extends StatefulWidget {
  const DietBuilderPage({super.key});

  @override
  State<DietBuilderPage> createState() => _DietBuilderPageState();
}

class _DietBuilderPageState extends State<DietBuilderPage> {
  final DietBuilderController _c = DietBuilderController();
  final PageController _pages = PageController();
  int _step = 0;

  static const int _stepCount = 5;

  @override
  void initState() {
    super.initState();
    // Rebuild the whole screen on any answer — the footer's Continue/Build
    // enablement lives outside the steps and has to track the controller too.
    _c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    _pages.dispose();
    super.dispose();
  }

  /// Fills About-you from what ZIVO already knows, so the user confirms rather
  /// than re-enters. Read-only here — nothing is written until the reveal's
  /// Save.
  Future<void> _prefill() async {
    if (!mounted) return;
    final scope = AppScope.of(context);
    final weights = scope.bodyWeight?.current ?? const <BodyWeightEntry>[];
    final latest = weights.isEmpty ? null : weights.first;

    int? dobAge;
    final uid = scope.auth.currentUser?.uid;
    if (uid != null) {
      try {
        final profile = await scope.profiles.fetchProfile(uid);
        if (profile != null) {
          dobAge = ageFrom(profile.dateOfBirth, DateTime.now());
        }
      } catch (_) {
        // Offline or unreadable — the user just types their age.
      }
    }
    if (!mounted) return;
    _c.seedBody(
      profile: scope.diet.currentBodyProfile,
      latestWeightKg: latest?.weightKg,
      dobAge: dobAge,
    );
  }

  bool get _canAdvance => switch (_step) {
        0 => _c.goalComplete,
        1 => _c.bodyComplete,
        _ => true,
      };

  void _next() {
    if (_step >= _stepCount - 1) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    _pages.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    FocusScope.of(context).unfocus();
    _pages.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _build() async {
    final result = _c.finalize(DateTime.now());
    if (result == null) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DietImportPage(
          generateFrom: result.preferences,
          // Size the plan to the computed-but-unsaved target. It becomes the
          // user's only when they Save on the reveal (ADR-007).
          targetOverride: result.proposal.targets,
          reviewBuilder: (draft) =>
              DietPlanRevealPage(plan: draft, result: result),
        ),
      ),
    );
    // The generate → reveal flow pops itself when it's done, so landing back
    // here means it finished either way — leave with it.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return TrainScreen(
      tint: TrainColors.dietTint,
      child: Column(
        children: [
          CaptureTopBar(
            title: l(context).prefsBuildTitle,
            onClose: () => Navigator.of(context).maybePop(),
          ),
          _StepBar(step: _step, total: _stepCount),
          Expanded(
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _step = i),
              children: [
                _GoalStep(controller: _c),
                _AboutStep(controller: _c),
                _EatStep(controller: _c),
                _AvoidStep(controller: _c),
                _MealsStep(controller: _c),
              ],
            ),
          ),
          _Footer(
            step: _step,
            total: _stepCount,
            controller: _c,
            onBack: _back,
            onNext: _next,
            onBuild: _build,
            canAdvance: _canAdvance,
          ),
        ],
      ),
    );
  }
}

/// A thin progress rail — dots, no copy, so it reads in any language.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step
                      ? TrainColors.green
                      : TrainColors.hairlineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < total - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// The shared scaffold for a step: a title, a prompt, and the step's body.
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.listKey,
    required this.title,
    required this.prompt,
    required this.children,
  });

  final Key listKey;
  final String title;
  final String prompt;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: listKey,
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      children: [
        Text(
          title,
          style: TrainType.serifVoice(context, size: 27, height: 1.1),
        ),
        const SizedBox(height: 8),
        Text(
          prompt,
          style: AppText.body.copyWith(color: TrainColors.ink2, height: 1.45),
        ),
        const SizedBox(height: 22),
        ...children,
      ],
    );
  }
}

// --- Step 1: goal -----------------------------------------------------------

class _GoalStep extends StatelessWidget {
  const _GoalStep({required this.controller});

  final DietBuilderController controller;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      listKey: const Key('builder-goal'),
      title: l(context).dietBuilderGoalTitle,
      prompt: l(context).dietBuilderGoalPrompt,
      children: [
        for (final goal in DietGoal.values) ...[
          _GoalCard(
            goal: goal,
            selected: controller.goal == goal,
            onTap: () => controller.goal = goal,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.onTap,
  });

  final DietGoal goal;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (goal) {
        DietGoal.fatLoss => Icons.trending_down_rounded,
        DietGoal.muscleGain => Icons.fitness_center_rounded,
        DietGoal.maintain => Icons.balance_rounded,
        DietGoal.recomp => Icons.sync_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('builder-goal-${goal.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        decoration: BoxDecoration(
          color: selected ? TrainColors.green.withValues(alpha: 0.12)
              : TrainColors.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? TrainColors.green : TrainColors.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _icon,
              size: 22,
              color: selected ? TrainColors.green : TrainColors.ink2,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dietGoalText(context, goal), style: AppText.rowTitle),
                  const SizedBox(height: 3),
                  Text(
                    dietGoalDetailText(context, goal),
                    style: AppText.meta.copyWith(color: TrainColors.ink3),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  size: 20, color: TrainColors.green),
          ],
        ),
      ),
    );
  }
}

// --- Step 2: about you ------------------------------------------------------

class _AboutStep extends StatelessWidget {
  const _AboutStep({required this.controller});

  final DietBuilderController controller;

  @override
  Widget build(BuildContext context) {
    final maintenance = controller.previewMaintenance;
    return _StepScaffold(
      listKey: const Key('builder-about'),
      title: l(context).dietBuilderAboutTitle,
      prompt: l(context).dietBuilderAboutPrompt,
      children: [
        Row(
          children: [
            DietNumberField(
              label: l(context).unitKg,
              controller: controller.weightField,
              hint: '81',
              fieldKey: const Key('builder-weight'),
            ),
            const SizedBox(width: 12),
            DietNumberField(
              label: l(context).unitCm,
              controller: controller.heightField,
              hint: '178',
              fieldKey: const Key('builder-height'),
            ),
          ],
        ),
        if (controller.heightCm != null && !controller.heightInRange) ...[
          const SizedBox(height: 9),
          Text(
            l(context).bodyHeightRange,
            key: const Key('builder-height-range'),
            style: AppText.meta.copyWith(color: TrainColors.ember),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            DietNumberField(
              label: l(context).bodyAgeLabel,
              controller: controller.ageField,
              hint: '30',
              decimal: false,
              fieldKey: const Key('builder-age'),
            ),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
        if (controller.ageFromDob) ...[
          const SizedBox(height: 9),
          Text(
            l(context).dietBuilderAgeFromProfile,
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
        ],
        const SizedBox(height: 20),
        Text(l(context).bodySexQuestion, style: AppText.rowTitle),
        const SizedBox(height: 11),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final sex in TargetSex.values)
              SelectChip(
                key: Key('builder-sex-${sex.name}'),
                label: sex == TargetSex.male
                    ? l(context).bodySexMale
                    : l(context).bodySexFemale,
                selected: controller.sex == sex,
                onTap: () => controller.sex = sex,
              ),
          ],
        ),
        const SizedBox(height: 22),
        Text(l(context).bodyActivityQuestion, style: AppText.rowTitle),
        const SizedBox(height: 11),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final level in ActivityLevel.values)
              SelectChip(
                key: Key('builder-activity-${level.name}'),
                label: activityText(context, level),
                selected: controller.activity == level,
                onTap: () => controller.activity = level,
              ),
          ],
        ),
        if (controller.activity != null) ...[
          const SizedBox(height: 9),
          Text(
            activityDetailText(context, controller.activity!),
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
        ],
        if (maintenance != null) ...[
          const SizedBox(height: 20),
          _MaintenancePreview(kcal: maintenance),
        ],
      ],
    );
  }
}

/// Shown live so the user sees what "moderate" vs "high" means — but ZIVO's
/// working, not the target itself, which stays hidden until the reveal.
class _MaintenancePreview extends StatelessWidget {
  const _MaintenancePreview({required this.kcal});

  final int kcal;

  @override
  Widget build(BuildContext context) {
    return TrainCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l(context).dietMaintenanceCaps,
            style: TrainType.caption(size: 9, tracking: 0.16),
          ),
          const SizedBox(height: 6),
          Text(
            ltrFor(context, l(context).dietKcalPerDay(kcal)),
            key: const Key('builder-maintenance'),
            style: AppText.rowTitle,
          ),
          const SizedBox(height: 4),
          Text(
            l(context).dietMaintenanceEstimated,
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
        ],
      ),
    );
  }
}

// --- Step 3: how you eat ----------------------------------------------------

class _EatStep extends StatelessWidget {
  const _EatStep({required this.controller});

  final DietBuilderController controller;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      listKey: const Key('builder-eat'),
      title: l(context).dietBuilderEatTitle,
      prompt: l(context).dietBuilderEatPrompt,
      children: [
        VoiceCaptureField(
          controller: controller.eatingHabits,
          keyPrefix: 'builder-eat',
          hint: l(context).dietBuilderEatHint,
          minLines: 5,
        ),
        const SizedBox(height: 10),
        Text(
          l(context).dietBuilderOptionalNote,
          style: AppText.meta.copyWith(color: TrainColors.ink3),
        ),
      ],
    );
  }
}

// --- Step 4: what you avoid -------------------------------------------------

class _AvoidStep extends StatelessWidget {
  const _AvoidStep({required this.controller});

  final DietBuilderController controller;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      listKey: const Key('builder-avoid'),
      title: l(context).dietBuilderAvoidTitle,
      prompt: l(context).dietBuilderAvoidPrompt,
      children: [
        VoiceCaptureField(
          controller: controller.dislikes,
          keyPrefix: 'builder-dislikes',
          hint: l(context).dietBuilderAvoidHint,
        ),
        const SizedBox(height: 26),
        Text(l(context).dietBuilderAllergiesTitle, style: AppText.rowTitle),
        const SizedBox(height: 5),
        Text(
          l(context).dietBuilderAllergiesPrompt,
          style: AppText.meta.copyWith(color: TrainColors.ember, height: 1.4),
        ),
        const SizedBox(height: 12),
        VoiceCaptureField(
          controller: controller.allergies,
          keyPrefix: 'builder-allergies',
          hint: l(context).dietBuilderAllergiesHint,
          minLines: 2,
          accent: TrainColors.ember,
        ),
        const SizedBox(height: 16),
        FoodChipPicker(
          keyPrefix: 'builder-allergen',
          heading: l(context).dietBuilderAllergyChips,
          note: l(context).dietBuilderAllergyChipsNote,
          optionIds: kCommonAllergenIds,
          labelFor: commonAllergenLabel,
          selected: controller.allergenChips,
          onChanged: controller.setAllergenChips,
        ),
      ],
    );
  }
}

// --- Step 5: how many meals -------------------------------------------------

class _MealsStep extends StatelessWidget {
  const _MealsStep({required this.controller});

  final DietBuilderController controller;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      listKey: const Key('builder-meals'),
      title: l(context).dietBuilderMealsTitle,
      prompt: l(context).dietBuilderMealsPrompt,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var n = 2; n <= 5; n++)
              SelectChip(
                key: Key('builder-meals-$n'),
                label: '$n',
                selected: controller.mealsPerDay == n,
                onTap: () => controller.mealsPerDay = n,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l(context).dietMealsADayNote,
          style: AppText.meta.copyWith(color: TrainColors.ink3),
        ),
        const SizedBox(height: 26),
        Text(l(context).dietBuilderScheduleTitle, style: AppText.rowTitle),
        const SizedBox(height: 5),
        Text(
          l(context).dietBuilderSchedulePrompt,
          style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
        ),
        const SizedBox(height: 12),
        VoiceCaptureField(
          controller: controller.schedule,
          keyPrefix: 'builder-schedule',
          hint: l(context).dietBuilderScheduleHint,
          minLines: 2,
        ),
      ],
    );
  }
}

// --- Footer -----------------------------------------------------------------

class _Footer extends StatelessWidget {
  const _Footer({
    required this.step,
    required this.total,
    required this.controller,
    required this.onBack,
    required this.onNext,
    required this.onBuild,
    required this.canAdvance,
  });

  final int step;
  final int total;
  final DietBuilderController controller;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onBuild;
  final bool canAdvance;

  @override
  Widget build(BuildContext context) {
    final isLast = step == total - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 16),
      child: Row(
        children: [
          TextButton(
            key: const Key('builder-back'),
            onPressed: onBack,
            child: Text(
              step == 0 ? l(context).actionClose : l(context).dietBuilderBack,
              style: AppText.meta.copyWith(color: TrainColors.ink2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isLast
                ? PillButton(
                    key: const Key('builder-build'),
                    label: l(context).prefsBuild,
                    icon: Icons.auto_awesome_rounded,
                    enabled: controller.canBuild,
                    onTap: onBuild,
                  )
                : PillButton(
                    key: const Key('builder-next'),
                    label: l(context).dietBuilderContinue,
                    icon: Icons.arrow_forward_rounded,
                    color: TrainColors.ink,
                    textColor: TrainColors.base,
                    enabled: canAdvance,
                    onTap: onNext,
                  ),
          ),
        ],
      ),
    );
  }
}
