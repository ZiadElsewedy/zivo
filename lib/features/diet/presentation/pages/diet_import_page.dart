import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../capture/presentation/import/import_flow_states.dart';
import '../../../capture/presentation/import/plan_import_file.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../ai/domain/import_progress.dart';
import '../../domain/diet_import_input.dart';
import '../../domain/plan_preferences.dart';
import '../../domain/diet_import_outcome.dart';
import '../../domain/diet_source.dart';
import '../../domain/diet_plan.dart';
import '../../domain/diet_plan_from_import.dart';
import 'diet_plan_edit_page.dart';
import '../../../../core/theme/train_tokens.dart';

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
    Future<PickedImportFile?> Function()? pickFile,
  }) : assert(
         input == null || generateFrom == null,
         'A run either reads material or designs a plan — never both.',
       ),
       pickFile = pickFile ?? pickImportFile;

  /// Preferences to build a plan FROM, rather than material to read. Mutually
  /// exclusive with [input].
  final PlanPreferences? generateFrom;

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
const _generatingStatusLines = [
  'Choosing foods you like…',
  'Looking up real calories for each one…',
  'Sizing the portions to your target…',
];

class _DietImportPageState extends State<DietImportPage> {
  _ImportPhase _phase = _ImportPhase.selecting;
  String? _errorMessage;
  // The raw failure text, shown only in debug builds so a real backend cause
  // (App Check, network) is visible on-device instead of hidden behind the
  // friendly line. Never surfaced in release.
  String? _errorDetail;
  String? _rejectionReason;

  Timer? _analyzingTimer;
  int _analyzingStatusIndex = 0;

  /// The newest extraction snapshot — import only; generation never sets it.
  ImportProgress? _progress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _analyzingTimer?.cancel();
    super.dispose();
  }

  /// What the analysing screen says right now.
  ///
  /// Import reports real extraction (via [importProgressLine]); generation
  /// still cycles its written lines, because that callable does not stream.
  String get _statusLine {
    if (widget.generateFrom != null) {
      return _generatingStatusLines[_analyzingStatusIndex %
          _generatingStatusLines.length];
    }
    return importProgressLine(_progress, itemNoun: 'item');
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
            (_analyzingStatusIndex + 1) % _generatingStatusLines.length,
      );
    });
  }

  Future<void> _run() async {
    _analyzingTimer?.cancel();
    setState(() {
      _phase = _ImportPhase.selecting;
      _errorMessage = null;
      _errorDetail = null;
      _rejectionReason = null;
    });

    final generateFrom = widget.generateFrom;
    if (generateFrom != null) {
      await _propose(
        () => AppScope.of(context).ai.generateDietPlan(
          preferences: generateFrom,
          // The plan is sized to whatever objective the user has approved.
          // Null is fine and honest: the plan is built, just not fitted.
          targets: AppScope.of(context).diet.currentTargets,
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
      input = DietImportDocument(bytes: file.bytes, mimeType: file.mimeType);
    }

    await _propose(
      () => AppScope.of(context).ai.importDietPlan(
        input!,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      ),
      // The plan remembers which route it arrived by, so the library can say
      // so months later.
      source: _sourceFor(input),
    );
  }

  /// Runs one proposal — an extraction or a generation — and takes its
  /// outcome to the same three places: the review editor, the honest decline,
  /// or a real error. Shared so a generated plan cannot end up with its own
  /// wording for "that didn't work".
  Future<void> _propose(
    Future<DietImportOutcome> Function() run, {
    required DietSource source,
  }) async {
    if (!mounted) return;
    setState(() {
      _phase = _ImportPhase.analyzing;
      _progress = null;
    });
    _startAnalyzingCycle();

    try {
      final outcome = await run();
      _analyzingTimer?.cancel();
      if (!mounted) return;
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
    } catch (error, stack) {
      // Surface the real failure instead of swallowing it — an App Check /
      // network rejection shouldn't read as "your PDF is bad".
      _analyzingTimer?.cancel();
      debugPrint('DietImport: proposal failed: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _phase = _ImportPhase.error;
        _errorMessage = importErrorMessage(
          error,
          manualFallback: 'build the plan manually.',
        );
        _errorDetail = kDebugMode ? error.toString() : null;
      });
    }
  }

  /// Pushes the extracted draft straight into the plan editor — the one
  /// review-and-save gate for this flow (no separate preview step). Whether
  /// the editor ends in Save or just closing, the import flow itself is done
  /// either way, so this pops itself once that route returns.
  Future<void> _reviewDraft(DietPlan draft) async {
    await Navigator.of(context).push<DietPlan>(
      MaterialPageRoute(builder: (_) => DietPlanEditPage(initialPlan: draft)),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _buildManually() async {
    await Navigator.of(context).push<DietPlan>(
      MaterialPageRoute(builder: (_) => const DietPlanEditPage()),
    );
    if (mounted) Navigator.of(context).pop();
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
                (null, null) => 'Import Plan',
                (_, final PlanPreferences _) => 'Building your plan',
                _ => 'Reading your plan',
              },
              onClose: () => Navigator.of(context).maybePop(),
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
        return const ImportSelectingState(
          title: 'Select your diet plan',
          subtitle:
              "Choose a PDF or a photo of your plan and I'll map it into a "
              'real, editable plan — estimating calories and macros wherever '
              "the document doesn't state them.",
        );
      case _ImportPhase.analyzing:
        return ImportAnalyzingState(
          statusLine: _statusLine,
          chipColor: TrainColors.raisedStrong,
        );
      case _ImportPhase.rejected:
        return ImportRejectedState(
          title: generating
              ? "ZIVO couldn't build that plan"
              : "This doesn't look like a diet plan",
          reason: _rejectionReason!,
          retryLabel: generating
              ? 'Try again'
              : (fromFile ? 'Choose a different file' : 'Go back and edit'),
          onRetry: _retry,
          onBuildManually: _buildManually,
          retryColor: TrainColors.green,
        );
      case _ImportPhase.error:
        return ImportErrorState(
          message: _errorMessage!,
          detail: _errorDetail,
          onRetry: _retry,
          retryColor: TrainColors.green,
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
