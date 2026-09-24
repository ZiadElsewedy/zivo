import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../capture/presentation/import/import_flow_states.dart';
import '../../../ai/domain/ai_failure.dart';
import '../../../ai/presentation/ai_labels.dart';
import '../../../ai/presentation/widgets/ai_model_sheet.dart';
import '../../../capture/presentation/import/plan_import_file.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../ai/domain/import_cancellation.dart';
import '../../domain/diet_import_input.dart';
import '../../domain/plan_preferences.dart';
import '../../domain/diet_import_outcome.dart';
import '../../domain/diet_source.dart';
import '../../domain/diet_plan.dart';
import '../../domain/diet_plan_from_import.dart';
import '../../domain/nutrition_targets.dart';
import 'diet_plan_edit_page.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';

/// The Diet import flow — a deliberately shorter mirror of
/// `WorkoutImportPage`: get the material → AI Analyzing → straight into
/// `DietPlanEditPage(initialPlan: ...)`, which IS the review-and-save gate
/// (it already carries full calorie/macro fields for every food item, so
/// there's no separate preview step here the way Workout's flow has one).
/// Material that isn't a usable diet plan surfaces a distinct, explained
/// decline instead of an empty or fabricated plan.
///
/// The file picker, the backend-error copy and the select/analyze/reject/error
/// screens are shared with the workout importer (`capture/presentation/import/`)
/// — the two flows read the same document types the same way and can no longer
/// drift on how a failure reads.
///
/// **Every route that produces a plan proposal lands here** — extraction from
/// a document, from a photo, from dictated or typed words, and generation from
/// preferences. With no [input] and no [generateFrom] it opens straight into
/// the file picker — no idle "tap to start" screen, since the entry action
/// that pushed this page already expressed that intent. Otherwise the material
/// was gathered before the push and the work starts immediately.
///
/// One analysis screen, one decline screen, one review gate, whatever the
/// route. A second copy of this flow for generated plans would be a second
/// place for "the AI couldn't do it" to be phrased differently.
class DietImportPage extends StatefulWidget {
  const DietImportPage({
    super.key,
    this.input,
    this.generateFrom,
    this.targetOverride,
    this.reviewBuilder,
    Future<PickedImportFile?> Function()? pickFile,
  }) : assert(
         input == null || generateFrom == null,
         'A run either reads material or designs a plan — never both.',
       ),
       pickFile = pickFile ?? pickImportFile;

  /// Preferences to build a plan FROM, rather than material to read. Mutually
  /// exclusive with [input].
  final PlanPreferences? generateFrom;

  /// The target the generated day is sized to, when the caller has computed one
  /// it does not want saved yet (the Diet Builder wizard's case). When null,
  /// generation falls back to the user's saved target. Ignored for imports.
  final NutritionTargets? targetOverride;

  /// Where an accepted proposal is reviewed. Defaults to the plan editor
  /// (`DietPlanEditPage`), the shared review-and-save gate; the wizard passes a
  /// builder for its own reveal screen, which also saves the target and body
  /// data alongside the plan. It is handed the freshly-built draft and returns
  /// once its own route is done — this page then pops itself, as before.
  final Widget Function(DietPlan draft)? reviewBuilder;

  /// Material gathered before this page was pushed. Null means "pick a file",
  /// which is the only route that can be restarted from inside this screen —
  /// with an [input] there is nothing here to re-gather, so a retry goes back
  /// to the screen that produced it.
  final DietImportInput? input;

  /// Overridable for tests — defaults to the real file picker.
  final Future<PickedImportFile?> Function() pickFile;

  @override
  State<DietImportPage> createState() => _DietImportPageState();
}

enum _ImportPhase { selecting, analyzing, rejected, error }

/// Generation's own lines, still cycled on a timer — and honestly so.
///
/// **`aiGenerateDietPlan` was not converted to streaming**, so unlike import
/// there is genuinely no live extraction to report here; these three lines
/// describe the work but do not track it. Deliberately naming the catalog
/// step, because "looking up real calories" is the part that makes this
/// trustworthy rather than a guess.
List<String> _generatingStatusLines(BuildContext context) => [
  l(context).dietGeneratingFoods,
  l(context).dietGeneratingCalories,
  l(context).dietGeneratingPortions,
];

/// How many lines the generating cycle rotates through. A count, not copy —
/// the timer needs it without a [BuildContext].
const _kGeneratingStatusCount = 3;

class _DietImportPageState extends State<DietImportPage> {
  _ImportPhase _phase = _ImportPhase.selecting;
  String? _errorMessage;
  // Set when the failure was the active AI model's provider and switching
  // model could fix it — the error screen then offers "Switch model".
  bool _canSwitchModel = false;
  String? _rejectionReason;

  // Bumped on every [_run]/[_propose] dispatch. A stale attempt's completion
  // (one whose model was switched out from under it) checks this before
  // touching state, so it can't clobber the attempt that superseded it.
  int _attempt = 0;

  // The active model's display name, shown on the analyzing/generating
  // screen so switching model (in Settings, or via "Switch model" on a
  // failure) is visibly in effect, not just a setting taken on faith.
  String? _modelLabel;

  Timer? _analyzingTimer;
  int _analyzingStatusIndex = 0;

  /// The live cancel handle for the in-flight import, or null. Cancelling it
  /// calls `aiCancelImport`, which aborts the backend model call.
  ImportCancellation? _cancellation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshModelLabel();
      _run();
    });
  }

  /// Reads the user's saved model selection for the badge on the analyzing/
  /// generating screen. Best-effort and silent on failure — the badge is
  /// just absent, never a reason to fail the import itself.
  Future<void> _refreshModelLabel() async {
    try {
      final selection = await AppScope.of(context).ai.getModelSelection();
      if (!mounted) return;
      setState(() => _modelLabel = aiModelSelectionText(context, selection));
    } catch (_) {
      // Badge stays absent — not worth surfacing to the user.
    }
  }

  @override
  void dispose() {
    _analyzingTimer?.cancel();
    super.dispose();
  }

  /// Closing the flow — cancels an in-flight import first (propagating to the
  /// backend via `aiCancelImport`), then pops.
  void _closeFlow() {
    _cancellation?.cancel();
    Navigator.of(context).maybePop();
  }

  /// The cycled line the **generation** screen shows — that callable does not
  /// stream, so there is no live extraction to report. Import instead renders
  /// the real pipeline via [ImportAnalyzingState].
  String _generatingLine(BuildContext context) {
    final lines = _generatingStatusLines(context);
    return lines[_analyzingStatusIndex % lines.length];
  }

  /// Only generation cycles now. Import's line moves when the model does.
  void _startAnalyzingCycle() {
    _analyzingStatusIndex = 0;
    _analyzingTimer?.cancel();
    if (widget.generateFrom == null) return;
    _analyzingTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted) return;
      setState(
        () => _analyzingStatusIndex =
            (_analyzingStatusIndex + 1) % _kGeneratingStatusCount,
      );
    });
  }

  Future<void> _run() async {
    // Read before the awaits below — a BuildContext must not cross an async
    // gap; an AppLocalizations value may.
    final strings = l(context);
    _analyzingTimer?.cancel();
    setState(() {
      _phase = _ImportPhase.selecting;
      _errorMessage = null;
      _rejectionReason = null;
    });

    final generateFrom = widget.generateFrom;
    if (generateFrom != null) {
      await _propose(
        () => AppScope.of(context).ai.generateDietPlan(
          preferences: generateFrom,
          // The plan is sized to whatever objective the user has approved — or
          // to the wizard's computed-but-unsaved target when one is passed.
          // Null is fine and honest: the plan is built, just not fitted.
          targets:
              widget.targetOverride ?? AppScope.of(context).diet.currentTargets,
        ),
        source: DietSource.generated,
      );
      return;
    }

    var input = widget.input;
    if (input == null) {
      PickedImportFile? file;
      try {
        file = await widget.pickFile();
      } catch (error, stack) {
        debugPrint('DietImport: could not read the picked file: $error');
        debugPrintStack(stackTrace: stack);
        if (!mounted) return;
        setState(() {
          _phase = _ImportPhase.error;
          _errorMessage = strings.dietFileReadFailed;
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
          _errorMessage = strings.dietFileTooLarge(
            kMaxImportFileBytes ~/ (1024 * 1024),
          );
        });
        return;
      }
      input = DietImportDocument(bytes: file.bytes, mimeType: file.mimeType);
    }

    final cancellation = ImportCancellation();
    await _propose(
      () => AppScope.of(context).ai.importDietPlan(
        input!,
        cancellation: cancellation,
      ),
      // The plan remembers which route it arrived by, so the library can say
      // so months later.
      source: _sourceFor(input),
      cancellation: cancellation,
    );
  }

  /// Runs one proposal — an extraction or a generation — and takes its
  /// outcome to the same three places: the review editor, the honest decline,
  /// or a real error. Shared so a generated plan cannot end up with its own
  /// wording for "that didn't work".
  Future<void> _propose(
    Future<DietImportOutcome> Function() run, {
    required DietSource source,
    ImportCancellation? cancellation,
  }) async {
    if (!mounted) return;
    // Read before the awaits below, for the same reason as in [_run].
    final strings = l(context);
    final attempt = ++_attempt;
    setState(() {
      _phase = _ImportPhase.analyzing;
      _cancellation = cancellation;
    });
    _startAnalyzingCycle();

    try {
      final outcome = await run();
      _analyzingTimer?.cancel();
      // A switch made mid-flight cancels this attempt and starts a fresh one
      // (see [_switchModelDuringAnalysis]) — if this one still lands, it's
      // been superseded, and touching state now would clobber the new one.
      if (!mounted || attempt != _attempt) return;
      switch (outcome) {
        case DietImportAccepted(:final plan):
          final draft = dietPlanFromImport(
            plan,
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            now: DateTime.now(),
            source: source,
          );
          await _reviewDraft(draft);
        case DietImportRejected(:final reason):
          setState(() {
            _rejectionReason = reason;
            _phase = _ImportPhase.rejected;
          });
      }
    } on ImportCancelledException {
      // Either the user pressed X/Cancel — the page is popping, nothing to
      // show — or a model switch mid-flight cancelled this attempt on
      // purpose to start a fresh one. Either way, nothing to show here.
      _analyzingTimer?.cancel();
      return;
    } catch (error, stack) {
      // Surface the real failure instead of swallowing it — an App Check /
      // network rejection shouldn't read as "your PDF is bad".
      _analyzingTimer?.cancel();
      debugPrint('DietImport: proposal failed: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _phase = _ImportPhase.error;
        _canSwitchModel = error is AiFailure && aiFailureSuggestsSwitch(error);
        _errorMessage = importErrorMessage(
          context,
          error,
          manualFallback: strings.dietBuildManually,
          // Generation reads no document — "couldn't read that plan" would
          // blame one that doesn't exist.
          unknownMessage: widget.generateFrom != null
              ? strings.aiErrorGeneric
              : null,
        );
      });
    } finally {
      // Guarded the same way: a stale attempt settling after a newer one has
      // already set its own [_cancellation] must not null that one out.
      if (attempt == _attempt) _cancellation = null;
    }
  }

  /// Pushes the extracted draft straight into the plan editor — the one
  /// review-and-save gate for this flow (no separate preview step). Whether
  /// the editor ends in Save or just closing, the import flow itself is done
  /// either way, so this pops itself once that route returns.
  Future<void> _reviewDraft(DietPlan draft) async {
    final reviewBuilder = widget.reviewBuilder;
    await Navigator.of(context).push<DietPlan>(
      MaterialPageRoute(
        builder: (_) => reviewBuilder != null
            ? reviewBuilder(draft)
            : DietPlanEditPage(initialPlan: draft),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _buildManually() async {
    await Navigator.of(context).push<DietPlan>(
      MaterialPageRoute(builder: (_) => const DietPlanEditPage()),
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// Opens the active-model picker; a new pick retries straight away — the
  /// callable reads the saved choice server-side, so the retry uses it.
  Future<void> _switchModel() async {
    final picked = await showAiModelSheet(context);
    if (picked != null && mounted) {
      await _refreshModelLabel();
      _retry();
    }
  }

  /// Tapping the "Using `<model>`" badge **while the request is still
  /// running** — the point of showing it at all is to let a bad pick be
  /// fixed without waiting out a failure first. Only cancels and restarts
  /// on an actual change ([showAiModelSheet] returns null for "closed
  /// without picking" or "re-tapped the model already active"), so backing
  /// out of the sheet leaves the current attempt running untouched.
  Future<void> _switchModelDuringAnalysis() async {
    final picked = await showAiModelSheet(context);
    if (!mounted || picked == null) return;
    await _refreshModelLabel();
    // Aborts the backend call (`aiCancelImport`) rather than leaving it to
    // finish and bill for an answer nobody will see — [_propose]'s attempt
    // guard means it would be ignored anyway, but this also stops paying
    // for it.
    _cancellation?.cancel();
    _retry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureTopBar(
              title: switch ((widget.input, widget.generateFrom)) {
                (null, null) => l(context).dietImportPlanTitle,
                (_, final PlanPreferences _) => l(context).dietBuildingYourPlan,
                _ => l(context).dietReadingYourPlan,
              },
              onClose: _closeFlow,
              titleColor: TrainColors.ink2,
              iconColor: TrainColors.ink2,
              chipColor: TrainColors.raisedStrong,
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
    );
  }

  /// What "try again" means depends on where the material came from: a
  /// picked file can be re-picked right here, but a dictated description
  /// lives on the screen behind this one — retrying it in place would offer
  /// the user a second run of the identical text.
  void _retry() {
    if (widget.input == null && widget.generateFrom == null) {
      _run();
    } else if (widget.generateFrom != null) {
      // Generation is not deterministic: running it again on the same
      // preferences is a genuine second attempt, not a repeat of the same
      // failure — so this one retries in place.
      _run();
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _body() {
    final generating = widget.generateFrom != null;
    final fromFile = widget.input == null && !generating;
    switch (_phase) {
      case _ImportPhase.selecting:
        return ImportSelectingState(
          title: l(context).dietSelectYourPlan,
          subtitle: l(context).dietSelectYourPlanBody,
        );
      case _ImportPhase.analyzing:
        // Both are one buffered AI call with no observable sub-steps: import
        // shows an honest wait line with a working Cancel; generation keeps its
        // cycled description lines (no cancel). The model badge is tappable
        // for import too — never generation, which has nothing to cancel
        // server-side, so switching mid-flight would just orphan a second
        // billed call rather than replace the first.
        return ImportAnalyzingState(
          statusLine: generating
              ? _generatingLine(context)
              : l(context).importAnalyzingWait,
          onCancel: generating ? null : _closeFlow,
          chipColor: TrainColors.raisedStrong,
          modelLabel: _modelLabel,
          onTapModel: generating ? null : _switchModelDuringAnalysis,
        );
      case _ImportPhase.rejected:
        return ImportRejectedState(
          title: generating
              ? l(context).dietCouldntBuildPlan
              : l(context).dietNotADietPlan,
          reason: _rejectionReason!,
          retryLabel: generating
              ? l(context).actionRetry
              : (fromFile
                    ? l(context).dietChooseDifferentFile
                    : l(context).dietGoBackAndEdit),
          onRetry: _retry,
          onBuildManually: _buildManually,
          retryColor: TrainColors.green,
        );
      case _ImportPhase.error:
        return ImportErrorState(
          message: _errorMessage!,
          onRetry: _retry,
          retryColor: TrainColors.green,
          secondaryLabel: _canSwitchModel ? l(context).aiSwitchModel : null,
          onSecondary: _switchModel,
        );
    }
  }

  /// The provenance each capture route records on the saved plan.
  static DietSource _sourceFor(DietImportInput input) => switch (input) {
    DietImportDocument(:final mimeType) =>
      mimeType == 'application/pdf' ? DietSource.pdf : DietSource.photo,
    // Typed-out text is the user's own words too, but they wrote them: that
    // is a hand-written plan an extractor happened to structure, and calling
    // it "dictated" would be a small lie in a field whose whole job is
    // provenance.
    DietImportDescription(:final dictated) =>
      dictated ? DietSource.dictated : DietSource.manual,
  };
}
