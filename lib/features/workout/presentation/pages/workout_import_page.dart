import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../ai/domain/import_progress.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../capture/presentation/import/import_flow_states.dart';
import '../../../capture/presentation/import/plan_import_file.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_import_input.dart';
import '../../domain/workout_import_outcome.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';
import '../../domain/workout_plan_from_import.dart';
import '../../domain/workout_plan_source.dart';
import 'workout_plan_edit_page.dart';

/// The workout-import flow (WORKOUT_SYSTEM.md §3.4, Phase 6), as a deliberate
/// sequence rather than a spinner bolted onto an upload button: get the
/// material → AI Analyzing → Review/Preview → Confirm Import → Done. The AI
/// never hallucinates a plan to have something to show — material that isn't a
/// usable workout plan surfaces a distinct, explained decline (see
/// [WorkoutImportRejected]) instead of an empty or fabricated split.
///
/// **Every capture route lands here** — a PDF, a photo, and (via [input]) a
/// dictated or typed description — the same shape diet's importer takes. With
/// no [input] it opens straight into the file picker (no idle "tap to start"
/// screen), since the entry action that pushed it already expressed that
/// intent; with an [input] the material was gathered before the push and the
/// work starts immediately.
///
/// The file picker, the backend-error copy and the select/analyze/reject/error
/// screens are shared with the diet importer (`capture/presentation/import/`);
/// the preview + done screens below are workout-only, because only this flow
/// reviews in place rather than dropping into the plan editor.
///
/// The preview IS the review gate (ADR-002's "human confirms before it
/// becomes real"): "Import this split" saves directly from what's shown,
/// with the full manual editor available as an optional deeper-edit step,
/// not a mandatory detour.
class WorkoutImportPage extends StatefulWidget {
  const WorkoutImportPage({
    super.key,
    this.input,
    Future<PickedImportFile?> Function()? pickFile,
  }) : pickFile = pickFile ?? pickImportFile;

  /// Material gathered before this page was pushed — a dictated or typed
  /// description. Null means "pick a file", the only route that can be
  /// restarted from inside this screen; with an [input] a retry goes back to
  /// the screen that produced it (mirrors `DietImportPage`).
  final WorkoutImportInput? input;

  /// Overridable for tests — defaults to the real file picker.
  final Future<PickedImportFile?> Function() pickFile;

  @override
  State<WorkoutImportPage> createState() => _WorkoutImportPageState();
}

enum _ImportPhase { selecting, analyzing, preview, done, rejected, error }

class _WorkoutImportPageState extends State<WorkoutImportPage> {
  _ImportPhase _phase = _ImportPhase.selecting;
  String? _errorMessage;
  // The raw failure text, shown only in debug builds so a real backend cause
  // (App Check, network) is visible on-device instead of hidden behind the
  // friendly line. Never surfaced in release.
  String? _errorDetail;
  String? _rejectionReason;
  WorkoutPlan? _draft;
  bool _saving = false;

  /// The newest extraction snapshot from the model, or null before the first
  /// one lands.
  ImportProgress? _progress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  /// What the analysing screen says right now: the live extraction if one has
  /// arrived, else the opening line.
  String get _statusLine =>
      importProgressLine(_progress, itemNoun: 'exercise');

  /// The entry point for both routes: an [input] gathered before the push goes
  /// straight to extraction; otherwise a file is picked first.
  Future<void> _run() async {
    setState(() {
      _phase = _ImportPhase.selecting;
      _errorMessage = null;
      _errorDetail = null;
      _rejectionReason = null;
      _draft = null;
      _saving = false;
      _progress = null;
    });

    final passed = widget.input;
    if (passed != null) {
      await _extract(passed);
      return;
    }

    PickedImportFile? file;
    try {
      file = await widget.pickFile();
    } catch (error, stack) {
      debugPrint('WorkoutImport: could not read the picked file: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _phase = _ImportPhase.error;
        _errorMessage = "Couldn't read that file.";
        _errorDetail = kDebugMode ? error.toString() : null;
      });
      return;
    }

    if (file == null) {
      // The user backed out of the picker — nothing went wrong, just leave.
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Fail fast on oversized files — the callable's transport rejects them
    // anyway, but with an error this screen can't explain.
    if (file.bytes.length > kMaxImportFileBytes) {
      if (!mounted) return;
      setState(() {
        _phase = _ImportPhase.error;
        _errorMessage =
            'That file is too large — please choose one under '
            '7 MB.';
      });
      return;
    }

    await _extract(
      WorkoutImportDocument(bytes: file.bytes, mimeType: file.mimeType),
    );
  }

  /// Runs the extraction for [input] and takes its outcome to the review
  /// preview, the honest decline, or a real error — the same three places
  /// whatever route the material arrived by.
  Future<void> _extract(WorkoutImportInput input) async {
    if (!mounted) return;
    setState(() {
      _phase = _ImportPhase.analyzing;
      _progress = null;
    });

    try {
      final outcome = await AppScope.of(context).ai.importWorkoutPlan(
        input,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      switch (outcome) {
        case WorkoutImportAccepted(:final plan):
          setState(() {
            _draft = workoutPlanFromImport(
              plan,
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              now: DateTime.now(),
              // The saved split remembers which route it arrived by.
              source: _sourceFor(input),
            );
            _phase = _ImportPhase.preview;
          });
        case WorkoutImportRejected(:final reason):
          setState(() {
            _rejectionReason = reason;
            _phase = _ImportPhase.rejected;
          });
      }
    } catch (error, stack) {
      // Surface the real failure instead of swallowing it. The old blanket
      // "couldn't read that plan" hid App Check / network rejections and
      // sent people deleting data to chase a backend problem.
      debugPrint('WorkoutImport: aiImportWorkoutPlan failed: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _phase = _ImportPhase.error;
        _errorMessage = importErrorMessage(
          error,
          manualFallback: 'build the split manually.',
        );
        _errorDetail = kDebugMode ? error.toString() : null;
      });
    }
  }

  /// What "try again" means depends on where the material came from: a picked
  /// file can be re-picked right here, but a description lives on the screen
  /// behind this one — retrying it in place would just re-run the identical
  /// text, so it goes back instead (mirrors `DietImportPage._retry`).
  void _restart() {
    if (widget.input == null) {
      _run();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// The provenance the saved split records for each capture route.
  static WorkoutPlanSource _sourceFor(WorkoutImportInput input) =>
      switch (input) {
        WorkoutImportDocument(:final mimeType) =>
          mimeType == 'application/pdf'
              ? WorkoutPlanSource.pdf
              : WorkoutPlanSource.photo,
        // Typed text is the user's own words too, but they wrote them: that is
        // a hand-structured plan, not a transcript — same reasoning as diet.
        WorkoutImportDescription(:final dictated) =>
          dictated ? WorkoutPlanSource.dictated : WorkoutPlanSource.typed,
      };

  Future<void> _confirmImport() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).workoutPlans.saveSplit(draft);
      // saveSplit deliberately does NOT steal the active pointer (multi-split
      // semantics) — but an import is unambiguous intent: this IS the plan
      // the user wants training against. Without this, Today's Training card
      // kept reading "No training plan yet" after a successful import.
      await _activate(draft.id);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _phase = _ImportPhase.done;
      });
    } catch (error, stack) {
      debugPrint('WorkoutPdfImport: saveSplit failed: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      // A transient save failure keeps the reviewed draft in hand — no need
      // to re-read the PDF to try again, just tap Import once more.
      setState(() => _saving = false);
      showZivoToast(
        context,
        "Couldn't save that split — check your connection and try again.",
        kind: ToastKind.error,
      );
    }
  }

  /// Points the active-split pointer at [id]. Best-effort: the split was just
  /// saved, so a failure here would be extraordinary — and the import itself
  /// already succeeded either way.
  Future<void> _activate(String id) async {
    try {
      await AppScope.of(context).workoutPlans.setActiveSplit(id);
    } catch (error) {
      debugPrint('WorkoutPdfImport: setActiveSplit failed: $error');
    }
  }

  Future<void> _editBeforeImporting() async {
    final draft = _draft;
    if (draft == null) return;
    // The editor saves via saveSplit (asSplit mode) which never steals
    // active — so when it returns a SAVED plan, finish the job here. A null
    // return means deleted or closed: nothing to activate.
    final saved = await Navigator.of(context).push<WorkoutPlan>(
      MaterialPageRoute(
        builder: (_) => WorkoutPlanEditPage(initialPlan: draft, asSplit: true),
      ),
    );
    if (saved != null) await _activate(saved.id);
    // Whether the review ended in Save, Delete, or just closing — the import
    // flow itself is done either way.
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _buildManually() async {
    final saved = await Navigator.of(context).push<WorkoutPlan>(
      MaterialPageRoute(
        builder: (_) => const WorkoutPlanEditPage(asSplit: true),
      ),
    );
    if (saved != null) await _activate(saved.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: DecoratedBox(
        // The same wash the Workout hub carries — a capture flow belongs to
        // the surface that launched it, not to a flat void.
        decoration: const BoxDecoration(gradient: TrainColors.hubTint),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CaptureTopBar(
                title: _phase == _ImportPhase.preview
                    ? 'Review import'
                    : 'Import Plan',
                onClose: () => Navigator.of(context).maybePop(),
                titleColor: TrainColors.ink2,
                iconColor: TrainColors.ink2,
                chipColor: TrainColors.glassStrong,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: KeyedSubtree(key: ValueKey(_phase), child: _body()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _ImportPhase.selecting:
        return const ImportSelectingState(
          title: 'Select your training plan',
          subtitle:
              "Choose a PDF or a photo of your plan and I'll map it into a "
              'real, editable split.',
        );
      case _ImportPhase.analyzing:
        return ImportAnalyzingState(statusLine: _statusLine);
      case _ImportPhase.preview:
        return _PreviewState(
          plan: _draft!,
          saving: _saving,
          onImport: _confirmImport,
          onEdit: _editBeforeImporting,
          onRestart: _restart,
          restartLabel: widget.input == null
              ? 'Choose a different file'
              : 'Start over',
        );
      case _ImportPhase.done:
        return _DoneState(
          plan: _draft!,
          onDone: () => Navigator.of(context).pop(),
        );
      case _ImportPhase.rejected:
        return ImportRejectedState(
          title: "This doesn't look like a workout plan",
          reason: _rejectionReason!,
          retryLabel: widget.input == null
              ? 'Choose a different file'
              : 'Go back and edit',
          onRetry: _restart,
          onBuildManually: _buildManually,
        );
      case _ImportPhase.error:
        return ImportErrorState(
          message: _errorMessage!,
          detail: _errorDetail,
          onRetry: _restart,
        );
    }
  }
}

class _PreviewState extends StatelessWidget {
  const _PreviewState({
    required this.plan,
    required this.saving,
    required this.onImport,
    required this.onEdit,
    required this.onRestart,
    required this.restartLabel,
  });

  final WorkoutPlan plan;
  final bool saving;
  final VoidCallback onImport;
  final VoidCallback onEdit;

  /// Re-pick a file (file route) or go back to the description (typed/dictated
  /// route); [restartLabel] names which.
  final VoidCallback onRestart;
  final String restartLabel;

  @override
  Widget build(BuildContext context) {
    final exerciseCount = plan.days.fold<int>(
      0,
      (sum, d) => sum + d.exercises.length,
    );
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: TrainColors.green,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "HERE'S WHAT I FOUND",
                    style: TrainType.mono(
                      size: 10.5,
                      weight: FontWeight.w700,
                      tracking: 0.06,
                      color: TrainColors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                plan.name,
                style: TrainType.mono(
                  size: 26,
                  weight: FontWeight.w300,
                  tracking: -0.05,
                  color: TrainColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${plan.days.length} day${plan.days.length == 1 ? '' : 's'} · '
                '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'} total',
                style: TrainType.mono(
                  size: 10.5,
                  tracking: 0.06,
                  color: TrainColors.ink4,
                ),
              ),
              const SizedBox(height: 20),
              for (final day in plan.days)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PreviewDayCard(day: day),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
          decoration: const BoxDecoration(
            color: TrainColors.base,
            border: Border(top: BorderSide(color: TrainColors.hairline)),
          ),
          child: Column(
            children: [
              PillButton(
                label: saving ? 'Importing…' : 'Import this split',
                icon: Icons.check_rounded,
                color: TrainColors.ember,
                enabled: !saving,
                onTap: onImport,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: saving ? null : onEdit,
                    child: Text(
                      'Edit before importing',
                      style: TrainType.mono(
                        size: 10.5,
                        tracking: 0.06,
                        color: TrainColors.ink2,
                      ),
                    ),
                  ),
                  Text(
                    '·',
                    style: TrainType.mono(
                      size: 10.5,
                      tracking: 0.06,
                      color: TrainColors.ink4,
                    ),
                  ),
                  TextButton(
                    onPressed: saving ? null : onRestart,
                    child: Text(
                      restartLabel,
                      style: TrainType.mono(
                        size: 10.5,
                        tracking: 0.06,
                        color: TrainColors.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewDayCard extends StatelessWidget {
  const _PreviewDayCard({required this.day});

  final WorkoutDay day;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Day ${day.slot} · ${day.label}',
                  style: TrainType.ui(
                    size: 15,
                    weight: FontWeight.w600,
                    height: 1.1,
                    color: TrainColors.ink,
                  ),
                ),
              ),
              Text(
                workoutDayMeta(day),
                style: TrainType.mono(
                  size: 10.5,
                  tracking: 0.06,
                  color: TrainColors.ink4,
                ),
              ),
            ],
          ),
          if (day.exercises.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'No exercises found for this day.',
              style: TrainType.mono(
                size: 10.5,
                tracking: 0.06,
                color: TrainColors.ink4,
              ),
            ),
          ] else
            for (final exercise in day.exercises)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        exercise.name,
                        style: TrainType.ui(
                          size: 14,
                          weight: FontWeight.w400,
                          height: 1.5,
                          color: TrainColors.ink2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      collapsedSetSummaries(exercise.sets).join(' · '),
                      style: TrainType.mono(
                        size: 12,
                        tracking: 0.06,
                        color: TrainColors.ink4,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _DoneState extends StatelessWidget {
  const _DoneState({required this.plan, required this.onDone});

  final WorkoutPlan plan;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final exerciseCount = plan.days.fold<int>(
      0,
      (sum, d) => sum + d.exercises.length,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ImportPhaseIcon(
              icon: Icons.check_rounded,
              color: TrainColors.green,
            ),
            const SizedBox(height: 18),
            Text(
              'Import complete',
              style: TrainType.ui(
                size: 20,
                weight: FontWeight.w800,
                tracking: -0.025,
                height: 1.15,
                color: TrainColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '"${plan.name}" added to your splits — ${plan.days.length} day'
              '${plan.days.length == 1 ? '' : 's'}, $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}.',
              style: TrainType.ui(
                size: 13.5,
                weight: FontWeight.w400,
                height: 1.5,
                color: TrainColors.ink4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 160,
              child: PillButton(
                label: 'Done',
                icon: Icons.arrow_forward_rounded,
                color: TrainColors.ember,
                enabled: true,
                onTap: onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
