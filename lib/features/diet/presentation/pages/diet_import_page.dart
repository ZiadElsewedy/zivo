import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/diet_import_input.dart';
import '../../domain/plan_preferences.dart';
import '../../domain/diet_import_outcome.dart';
import '../../domain/diet_source.dart';
import '../../domain/diet_plan.dart';
import '../../domain/diet_plan_from_import.dart';
import 'diet_plan_edit_page.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';

/// The largest file the import flow will upload. Cloud Functions callables
/// reject requests past ~10 MiB at the transport layer — before the server's
/// own size check ever runs — and base64 inflates bytes by ~4/3, so anything
/// bigger than this dies with a cryptic platform error instead of a clear
/// one.
const _maxFileBytes = 7 * 1024 * 1024;

/// The file types the import flow accepts, mapped to the media type sent to
/// the backend — PDFs are read natively; photos ride as image blocks.
const _allowedExtensions = <String, String>{
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
};

/// Picks a plan document (PDF or photo) and returns its bytes plus media type
/// — null means the user backed out of the picker (not an error); a picked
/// file with no readable bytes throws, same as any other read failure, so
/// callers only need two branches.
Future<({Uint8List bytes, String mimeType})?> _defaultPickFile() async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: List.unmodifiable(_allowedExtensions.keys),
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.single;
  final mimeType = _allowedExtensions[file.extension?.toLowerCase()];
  if (mimeType == null) {
    throw StateError('Unsupported file type: ${file.extension}');
  }
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    throw StateError("Couldn't read that file.");
  }
  return (bytes: bytes, mimeType: mimeType);
}

/// The Diet import flow — a deliberately shorter mirror of
/// `WorkoutPdfImportPage`: get the material → AI Analyzing → straight into
/// `DietPlanEditPage(initialPlan: ...)`, which IS the review-and-save gate
/// (it already carries full calorie/macro fields for every food item, so
/// there's no separate preview step here the way Workout's flow has one).
/// Material that isn't a usable diet plan surfaces a distinct, explained
/// decline instead of an empty or fabricated plan.
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
    Future<({Uint8List bytes, String mimeType})?> Function()? pickFile,
  }) : assert(
         input == null || generateFrom == null,
         'A run either reads material or designs a plan — never both.',
       ),
       pickFile = pickFile ?? _defaultPickFile;

  /// Preferences to build a plan FROM, rather than material to read. Mutually
  /// exclusive with [input].
  final PlanPreferences? generateFrom;

  /// Material gathered before this page was pushed. Null means "pick a file",
  /// which is the only route that can be restarted from inside this screen —
  /// with an [input] there is nothing here to re-gather, so a retry goes back
  /// to the screen that produced it.
  final DietImportInput? input;

  /// Overridable for tests — defaults to the real file picker.
  final Future<({Uint8List bytes, String mimeType})?> Function() pickFile;

  @override
  State<DietImportPage> createState() => _DietImportPageState();
}

enum _ImportPhase { selecting, analyzing, rejected, error }

/// Cycled while [_ImportPhase.analyzing] is showing — an honest sense of
/// progress on a single opaque model call, not a fake percentage.
const _analyzingStatusLines = [
  'Reading the document…',
  'Identifying meals…',
  'Estimating calories and macros…',
];

/// Generation's own lines. Different work, said differently — and deliberately
/// naming the catalog step, because "looking up real calories" is the part
/// that makes this trustworthy rather than a guess.
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

  List<String> get _statusLines => widget.generateFrom == null
      ? _analyzingStatusLines
      : _generatingStatusLines;

  void _startAnalyzingCycle() {
    _analyzingStatusIndex = 0;
    _analyzingTimer?.cancel();
    _analyzingTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted) return;
      setState(
        () => _analyzingStatusIndex =
            (_analyzingStatusIndex + 1) % _statusLines.length,
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
      ({Uint8List bytes, String mimeType})? file;
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
      if (file.bytes.length > _maxFileBytes) {
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
      () => AppScope.of(context).ai.importDietPlan(input!),
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
    setState(() => _phase = _ImportPhase.analyzing);
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
        _errorMessage = _importErrorMessage(error);
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
        return const _SelectingState();
      case _ImportPhase.analyzing:
        return _AnalyzingState(statusLine: _statusLines[_analyzingStatusIndex]);
      case _ImportPhase.rejected:
        return _RejectedState(
          reason: _rejectionReason!,
          retryLabel: generating
              ? 'Try again'
              : (fromFile ? 'Choose a different file' : 'Go back and edit'),
          declineTitle: generating
              ? "ZIVO couldn't build that plan"
              : "This doesn't look like a diet plan",
          onRetry: _retry,
          onBuildManually: _buildManually,
        );
      case _ImportPhase.error:
        return _ErrorMessage(
          message: _errorMessage!,
          detail: _errorDetail,
          onRetry: _retry,
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

/// Maps a raw import failure to a user-facing line — mirrors
/// `workout_pdf_import_page.dart`'s `_importErrorMessage` exactly (same
/// reasoning: `aiImportDietPlan` never requires sign-in beyond App Check, so
/// an unauthenticated/permission-denied rejection here can only be App
/// Check declining the request).
String _importErrorMessage(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('app-check') ||
      text.contains('app check') ||
      text.contains('appcheck') ||
      text.contains('unauthenticated') ||
      text.contains('permission-denied') ||
      text.contains('permission denied')) {
    return kDebugMode
        ? "The app couldn't verify itself (App Check). Register this "
              "build's debug token in the Firebase console, then try again."
        : "Couldn't verify this app install. Please try again in a moment.";
  }
  if (text.contains('not-found')) {
    // The callable itself is missing — an undeployed or renamed backend
    // function. Nothing about the picked file is wrong; blaming it sends
    // people re-scanning a perfectly good plan.
    return "The import service isn't available right now — please try "
        'again later.';
  }
  if (text.contains('deadline') ||
      text.contains('timeout') ||
      text.contains('unavailable') ||
      text.contains('network')) {
    return 'Network problem reaching the import service — check your '
        'connection and try again.';
  }
  return "Couldn't read that plan — try a clearer photo or PDF, or build the plan manually.";
}

/// The icon-chip look shared by every phase of this flow — the same
/// "premium empty/status state" language `WorkoutPdfImportPage` uses.
class _PhaseIcon extends StatelessWidget {
  const _PhaseIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(icon, size: 32, color: color),
    );
  }
}

class _SelectingState extends StatelessWidget {
  const _SelectingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PhaseIcon(
              icon: Icons.upload_file_rounded,
              color: TrainColors.green,
            ),
            const SizedBox(height: 18),
            Text(
              'Select your diet plan',
              style: AppText.cardTitle.copyWith(color: TrainColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a PDF or a photo of your plan and I\'ll map it into a '
              'real, editable plan — estimating calories and macros wherever '
              "the document doesn't state them.",
              style: AppText.body.copyWith(color: TrainColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyzingState extends StatelessWidget {
  const _AnalyzingState({required this.statusLine});

  final String statusLine;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              color: TrainColors.raisedStrong,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(10),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                TrainColors.green,
                BlendMode.srcIn,
              ),
              child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Analyzing your plan',
            style: AppText.cardTitle.copyWith(color: TrainColors.ink),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              statusLine,
              key: ValueKey(statusLine),
              style: AppText.body.copyWith(color: TrainColors.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectedState extends StatelessWidget {
  const _RejectedState({
    required this.reason,
    required this.retryLabel,
    required this.declineTitle,
    required this.onRetry,
    required this.onBuildManually,
  });

  final String reason;

  /// What went wrong, headlined for this route — an unreadable document and a
  /// request ZIVO couldn't design around are not the same failure.
  final String declineTitle;

  /// Names what retrying actually does on this route — re-pick a file, or go
  /// back to the description that produced this.
  final String retryLabel;
  final VoidCallback onRetry;
  final VoidCallback onBuildManually;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PhaseIcon(
              icon: Icons.description_outlined,
              color: TrainColors.ember,
            ),
            const SizedBox(height: 18),
            Text(
              declineTitle,
              style: AppText.cardTitle.copyWith(color: TrainColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              style: AppText.body.copyWith(color: TrainColors.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 220,
              child: PillButton(
                label: retryLabel,
                icon: Icons.upload_file_rounded,
                color: TrainColors.green,
                enabled: true,
                onTap: onRetry,
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onBuildManually,
              child: Text(
                'Build manually instead',
                style: AppText.meta.copyWith(color: TrainColors.ink2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({
    required this.message,
    required this.onRetry,
    this.detail,
  });

  final String message;
  final VoidCallback onRetry;

  /// Raw failure text (debug builds only) — the real backend cause, shown
  /// small and dim under the friendly line.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PhaseIcon(
              icon: Icons.cloud_off_rounded,
              color: TrainColors.ink3,
            ),
            const SizedBox(height: 18),
            Text(
              message,
              style: AppText.aside.copyWith(color: TrainColors.ink2),
              textAlign: TextAlign.center,
            ),
            if (detail != null) ...[
              const SizedBox(height: 10),
              Text(
                detail!,
                style: AppText.aside.copyWith(
                  color: TrainColors.ink3,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              child: PillButton(
                label: l(context).actionRetry,
                icon: Icons.refresh_rounded,
                color: TrainColors.green,
                enabled: true,
                onTap: onRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
