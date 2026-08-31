import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../workout/domain/body_weight_entry.dart';
import '../../domain/body_measures.dart';
import '../../domain/body_profile.dart';
import '../../domain/nutrition_targets.dart';
import '../../domain/target_calculator.dart';
import '../widgets/diet_number_field.dart';

/// Where the user gives ZIVO the body data every energy figure rests on.
///
/// **This screen buys one thing: the ability to answer "what is this plan
/// doing to me".** It does not set a target and it never will — saving here
/// writes body data and nothing else, and the target flow keeps its own
/// review-then-save gate (see `diet_targets_page.dart`). The two are next to
/// each other in the UI and deliberately separate in the data.
///
/// Weight is asked for here but **stored in the workout feature's weigh-in
/// log**, not on the profile: it is the one figure here that legitimately
/// changes week to week, and the user already keeps it there. A second copy
/// would be a second answer to "what do you weigh".
class BodyProfilePage extends StatefulWidget {
  const BodyProfilePage({super.key});

  @override
  State<BodyProfilePage> createState() => _BodyProfilePageState();
}

class _BodyProfilePageState extends State<BodyProfilePage> {
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _height = TextEditingController();
  final TextEditingController _maintenance = TextEditingController();

  TargetSex? _sex;
  ActivityLevel? _activity;

  /// The weigh-in the weight field was prefilled from, so Save can tell an
  /// untouched prefill from a new reading and not log a duplicate weigh-in
  /// every time this screen is opened.
  double? _prefilledWeightKg;
  DateTime? _weighedAt;

  /// Age from the account profile's date of birth, read once on load — the
  /// profile repository is async, and the preview below can't block on it.
  /// Null just means no maintenance preview, never a guessed age.
  int? _age;

  bool _loaded = false;

  /// Whether the optional "I already know my daily calories" field is open.
  /// Starts open when there IS a stored figure — hiding a value the user
  /// previously entered is how it gets silently lost on the next save.
  bool _showMaintenance = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _weight.dispose();
    _height.dispose();
    _maintenance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final scope = AppScope.of(context);
    final profile = scope.diet.currentBodyProfile;
    final weights = scope.bodyWeight?.current ?? const <BodyWeightEntry>[];
    final latest = weights.isEmpty ? null : weights.first;

    setState(() {
      if (profile != null) {
        _height.text = _trim(profile.heightCm);
        _sex = profile.sex;
        _activity = profile.activity;
        _maintenance.text = profile.statedMaintenanceKcal?.toString() ?? '';
        // Open when there's already a figure: a stored value hidden behind a
        // collapsed row is a value the user can't see they still have.
        _showMaintenance = profile.statedMaintenanceKcal != null;
      }
      if (latest != null) {
        _prefilledWeightKg = latest.weightKg;
        _weighedAt = latest.loggedAt;
        _weight.text = _trim(latest.weightKg);
      }
      _loaded = true;
    });

    final uid = scope.auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final profile = await scope.profiles.fetchProfile(uid);
      if (!mounted || profile == null) return;
      setState(() => _age = ageFrom(profile.dateOfBirth, DateTime.now()));
    } catch (_) {
      // Offline or unreadable: no preview, and Save still works — age is not
      // an input this screen collects.
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  double? get _weightKg => parsePositiveDecimal(_weight.text);
  double? get _heightCm => parsePositiveDecimal(_height.text);
  int? get _statedMaintenance => parsePositiveInt(_maintenance.text);

  bool get _heightOutOfRange {
    final cm = _heightCm;
    return cm != null && !heightIsPlausible(cm);
  }

  bool get _maintenanceOutOfRange {
    final kcal = _statedMaintenance;
    return kcal != null && !statedMaintenanceIsPlausible(kcal);
  }

  bool get _canSave =>
      !_saving &&
      _heightCm != null &&
      !_heightOutOfRange &&
      !_maintenanceOutOfRange &&
      _sex != null &&
      _activity != null;

  /// The maintenance figure the current inputs produce, shown live so the
  /// user can see what their answers actually mean before saving them. Null
  /// until every input the equation needs is present.
  int? get _previewMaintenance {
    final stated = _statedMaintenance;
    if (stated != null && statedMaintenanceIsPlausible(stated)) return stated;
    final weightKg = _weightKg;
    final heightCm = _heightCm;
    final sex = _sex;
    final activity = _activity;
    final age = _age;
    if (weightKg == null ||
        heightCm == null ||
        !heightIsPlausible(heightCm) ||
        sex == null ||
        activity == null ||
        age == null) {
      return null;
    }
    final bmr = basalMetabolicRate(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      sex: sex,
    );
    return (bmr * activityFactor(activity)).round();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);

    // A new weigh-in only when the number actually changed — reopening this
    // screen and tapping Save should not plant a duplicate reading in the
    // weight history the workout feature charts.
    final weightKg = _weightKg;
    if (weightKg != null && weightKg != _prefilledWeightKg) {
      final log = scope.bodyWeight;
      if (log != null) {
        await log.save(
          BodyWeightEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            weightKg: weightKg,
            loggedAt: DateTime.now(),
          ),
        );
      }
    }

    await scope.diet.saveBodyProfile(
      BodyProfile(
        heightCm: _heightCm!,
        sex: _sex!,
        activity: _activity!,
        statedMaintenanceKcal: _maintenanceOutOfRange
            ? null
            : _statedMaintenance,
        updatedAt: DateTime.now(),
      ),
    );

    if (!mounted) return;
    HapticFeedback.lightImpact();
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final staleDays = _weighedAt == null
        ? null
        : DateTime.now().difference(_weighedAt!).inDays;

    return TrainScreen(
      tint: TrainColors.dietTint,
      child: Column(
        children: [
          CaptureTopBar(
            title: l(context).bodyTitle,
            onClose: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: !_loaded
                ? const SizedBox.shrink()
                : ListView(
                    key: const Key('body-profile-list'),
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
                    children: [
                      // One line, not four. Why the screen exists is worth a
                      // sentence; how Mifflin-St Jeor works is not — that is
                      // the engine, and the user asked not to be shown it.
                      Text(
                        l(context).bodyIntro,
                        style: AppText.body.copyWith(
                          color: TrainColors.ink2,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Plain questions rather than labelled form fields:
                      // "What do you weigh?" needs no explanation, where
                      // "Weight (kg)" under a section header called "You"
                      // needs the header to make sense.
                      Text(
                        l(context).bodyWeightQuestion,
                        style: AppText.rowTitle,
                      ),
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          DietNumberField(
                            label: l(context).unitKg,
                            controller: _weight,
                            hint: '82',
                            fieldKey: const Key('body-weight'),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: SizedBox.shrink()),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        staleDays == null
                            ? l(context).bodyWeighInNote
                            : l(context).bodyLastWeighIn(_agoLabel(staleDays)),
                        key: const Key('weigh-in-note'),
                        style: AppText.meta.copyWith(color: TrainColors.ink3),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l(context).bodyHeightQuestion,
                        style: AppText.rowTitle,
                      ),
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          DietNumberField(
                            label: l(context).unitCm,
                            controller: _height,
                            hint: '178',
                            fieldKey: const Key('body-height'),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: SizedBox.shrink()),
                        ],
                      ),
                      if (_heightOutOfRange) ...[
                        const SizedBox(height: 9),
                        Text(
                          l(context).bodyHeightRange,
                          key: const Key('height-range-note'),
                          style: AppText.meta.copyWith(
                            color: TrainColors.ember,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(l(context).bodySexQuestion, style: AppText.rowTitle),
                      const SizedBox(height: 11),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final sex in TargetSex.values)
                            SelectChip(
                              key: Key('sex-${sex.name}'),
                              label: sex == TargetSex.male
                                  ? l(context).bodySexMale
                                  : l(context).bodySexFemale,
                              selected: _sex == sex,
                              onTap: () => setState(() => _sex = sex),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l(context).bodyActivityQuestion,
                        style: AppText.rowTitle,
                      ),
                      const SizedBox(height: 11),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final level in ActivityLevel.values)
                            SelectChip(
                              key: Key('activity-${level.name}'),
                              label: activityLabel(level),
                              selected: _activity == level,
                              onTap: () => setState(() => _activity = level),
                            ),
                        ],
                      ),
                      // Kept: this one line is what makes "moderate" mean
                      // something, and it describes the user's week rather
                      // than the equation.
                      if (_activity != null) ...[
                        const SizedBox(height: 9),
                        Text(
                          activityDescription(_activity!),
                          style: AppText.meta.copyWith(color: TrainColors.ink3),
                        ),
                      ],
                      const SizedBox(height: 20),
                      // Behind a tap. Almost nobody knows this number, and a
                      // labelled "Known maintenance (kcal)" box sitting open
                      // on the screen is the engine showing through — but the
                      // capability is load-bearing (a stated figure outranks
                      // the estimate), so it stays reachable.
                      _KnownCaloriesDisclosure(
                        expanded: _showMaintenance,
                        onToggle: () => setState(
                          () => _showMaintenance = !_showMaintenance,
                        ),
                        controller: _maintenance,
                        outOfRange: _maintenanceOutOfRange,
                      ),
                      if (_previewMaintenance != null) ...[
                        const SizedBox(height: 20),
                        _MaintenancePreview(
                          kcal: _previewMaintenance!,
                          source:
                              _statedMaintenance != null &&
                                  !_maintenanceOutOfRange
                              ? MaintenanceSource.stated
                              : MaintenanceSource.estimated,
                        ),
                      ],
                      const SizedBox(height: 26),
                      PillButton(
                        key: const Key('save-body-profile'),
                        label: l(context).actionSave,
                        icon: Icons.check_rounded,
                        enabled: _canSave,
                        onTap: _save,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _agoLabel(int days) => switch (days) {
    <= 0 => 'today',
    1 => 'yesterday',
    < 14 => '$days days ago',
    < 60 => '${(days / 7).round()} weeks ago',
    _ => '${(days / 30).round()} months ago',
  };
}

/// What the answers add up to, live. Shown before Save so the user sees the
/// consequence of "moderate" vs "high" rather than discovering it afterwards
/// in a verdict they can't trace.
class _MaintenancePreview extends StatelessWidget {
  const _MaintenancePreview({required this.kcal, required this.source});

  final int kcal;
  final MaintenanceSource source;

  @override
  Widget build(BuildContext context) {
    return TrainCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MAINTENANCE',
                  style: TrainType.caption(size: 9, tracking: 0.16),
                ),
                const SizedBox(height: 6),
                Text(
                  '$kcal kcal a day',
                  key: const Key('maintenance-preview'),
                  style: AppText.rowTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  source == MaintenanceSource.stated
                      ? 'The figure you gave. ZIVO uses it as-is.'
                      : 'Estimated from these numbers — a population average, '
                            'not a measurement of you.',
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one engine-facing input on this screen, kept off it until asked for.
///
/// A stated maintenance figure outranks the estimate (`MaintenanceSource`), so
/// removing it would cost real accuracy for the few people who have one. A
/// labelled kcal box sitting open on a screen otherwise made of plain
/// questions is what makes the app feel like a calculator, so it lives behind
/// a sentence about the user instead of a field about the formula.
class _KnownCaloriesDisclosure extends StatelessWidget {
  const _KnownCaloriesDisclosure({
    required this.expanded,
    required this.onToggle,
    required this.controller,
    required this.outOfRange,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final TextEditingController controller;
  final bool outOfRange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const Key('known-calories-toggle'),
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 20,
                  color: TrainColors.ink3,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l(context).bodyKnowMaintenance,
                    style: AppText.meta.copyWith(color: TrainColors.ink2),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              DietNumberField(
                label: l(context).unitKcal,
                controller: controller,
                hint: '—',
                decimal: false,
                fieldKey: const Key('body-maintenance'),
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            outOfRange
                ? l(context).bodyMaintenanceRange
                : l(context).bodyMaintenanceNote,
            key: const Key('maintenance-note'),
            style: AppText.meta.copyWith(
              color: outOfRange ? TrainColors.ember : TrainColors.ink3,
            ),
          ),
        ],
      ],
    );
  }
}
