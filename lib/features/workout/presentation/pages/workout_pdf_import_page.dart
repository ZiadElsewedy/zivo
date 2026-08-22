import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_import_outcome.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';
import '../../domain/workout_plan_from_import.dart';
import 'workout_plan_edit_page.dart';

/// Picks a PDF and returns its bytes — null means the user backed out of the
/// picker (not an error); a picked file with no readable bytes throws, same
/// as any other read failure, so callers only need two branches.
Future<Uint8List?> _defaultPickPdfBytes() async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final bytes = picked.files.single.bytes;
  if (bytes == null || bytes.isEmpty) {
    throw StateError("Couldn't read that file.");
  }
  return bytes;
}

/// The PDF-import flow (WORKOUT_SYSTEM.md §3.4, Phase 6), as a deliberate
/// sequence rather than a spinner bolted onto an upload button: Select File →
/// AI Analyzing → Review/Preview → Confirm Import → Done. The AI never
/// hallucinates a plan to have something to show — a document that isn't a
/// usable workout plan surfaces a distinct, explained decline (see
/// [WorkoutImportRejected]) instead of an empty or fabricated split.
///
/// The preview IS the review gate (ADR-002's "human confirms before it
/// becomes real"): "Import this split" saves directly from what's shown,
/// with the full manual editor available as an optional deeper-edit step,
/// not a mandatory detour.
///
/// Opens straight into the file picker (no idle "tap to start" screen) since
/// the entry action that pushed this page already expressed that intent —
/// the [_ImportPhase.selecting] screen behind it is what a cancel or a retry
/// lands back on.
class WorkoutPdfImportPage extends StatefulWidget {
  const WorkoutPdfImportPage({super.key, Future<Uint8List?> Function()? pickPdfBytes})
    : pickPdfBytes = pickPdfBytes ?? _defaultPickPdfBytes;

  /// Overridable for tests — defaults to the real file picker.
  final Future<Uint8List?> Function() pickPdfBytes;

  @override
  State<WorkoutPdfImportPage> createState() => _WorkoutPdfImportPageState();
}

enum _ImportPhase { selecting, analyzing, preview, done, rejected, error }

/// Cycled while [_ImportPhase.analyzing] is showing — an honest sense of
/// progress on a single opaque model call, not a fake percentage.
const _analyzingStatusLines = [
  'Reading the document…',
  'Identifying training days…',
  'Mapping exercises and sets…',
];

class _WorkoutPdfImportPageState extends State<WorkoutPdfImportPage> {
  _ImportPhase _phase = _ImportPhase.selecting;
  String? _errorMessage;
  // The raw failure text, shown only in debug builds so a real backend cause
  // (App Check, network) is visible on-device instead of hidden behind the
  // friendly line. Never surfaced in release.
  String? _errorDetail;
  String? _rejectionReason;
  WorkoutPlan? _draft;
  bool _saving = false;

  Timer? _analyzingTimer;
  int _analyzingStatusIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickAndImport());
  }

  @override
  void dispose() {
    _analyzingTimer?.cancel();
    super.dispose();
  }

  void _startAnalyzingCycle() {
    _analyzingStatusIndex = 0;
    _analyzingTimer?.cancel();
    _analyzingTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted) return;
      setState(() => _analyzingStatusIndex = (_analyzingStatusIndex + 1) % _analyzingStatusLines.length);
    });
  }

  Future<void> _pickAndImport() async {
    _analyzingTimer?.cancel();
    setState(() {
      _phase = _ImportPhase.selecting;
      _errorMessage = null;
      _errorDetail = null;
      _rejectionReason = null;
      _draft = null;
      _saving = false;
    });

    Uint8List? bytes;
    try {
      bytes = await widget.pickPdfBytes();
    } catch (error, stack) {
      debugPrint('WorkoutPdfImport: could not read the picked file: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _phase = _ImportPhase.error;
        _errorMessage = "Couldn't read that file.";
        _errorDetail = kDebugMode ? error.toString() : null;
      });
      return;
    }

    if (bytes == null) {
      // The user backed out of the picker — nothing went wrong, just leave.
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (!mounted) return;
    setState(() => _phase = _ImportPhase.analyzing);
    _startAnalyzingCycle();

    try {
      final outcome = await AppScope.of(context).ai.importWorkoutPlan(pdfBytes: bytes);
      _analyzingTimer?.cancel();
      if (!mounted) return;
      switch (outcome) {
        case WorkoutImportAccepted(:final plan):
          setState(() {
            _draft = workoutPlanFromImport(
              plan,
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              now: DateTime.now(),
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
      _analyzingTimer?.cancel();
      debugPrint('WorkoutPdfImport: aiImportWorkoutPlan failed: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _phase = _ImportPhase.error;
        _errorMessage = _importErrorMessage(error);
        _errorDetail = kDebugMode ? error.toString() : null;
      });
    }
  }

  Future<void> _confirmImport() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).workoutPlans.saveSplit(draft);
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

  Future<void> _editBeforeImporting() async {
    final draft = _draft;
    if (draft == null) return;
    await Navigator.of(context).push<WorkoutPlan>(
      MaterialPageRoute(builder: (_) => WorkoutPlanEditPage(initialPlan: draft, asSplit: true)),
    );
    // Whether the review ended in Save, Delete, or just closing — the import
    // flow itself is done either way.
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _buildManually() async {
    await Navigator.of(context).push<WorkoutPlan>(
      MaterialPageRoute(builder: (_) => const WorkoutPlanEditPage(asSplit: true)),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureTopBar(
              title: _phase == _ImportPhase.preview ? 'Review import' : 'Import PDF',
              onClose: () => Navigator.of(context).maybePop(),
              titleColor: AppColors.ink2,
              iconColor: AppColors.ink2,
              chipColor: AppColors.surfaceRaised,
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

  Widget _body() {
    switch (_phase) {
      case _ImportPhase.selecting:
        return const _SelectingState();
      case _ImportPhase.analyzing:
        return _AnalyzingState(statusLine: _analyzingStatusLines[_analyzingStatusIndex]);
      case _ImportPhase.preview:
        return _PreviewState(
          plan: _draft!,
          saving: _saving,
          onImport: _confirmImport,
          onEdit: _editBeforeImporting,
          onChooseDifferentFile: _pickAndImport,
        );
      case _ImportPhase.done:
        return _DoneState(plan: _draft!, onDone: () => Navigator.of(context).pop());
      case _ImportPhase.rejected:
        return _RejectedState(
          reason: _rejectionReason!,
          onChooseDifferentFile: _pickAndImport,
          onBuildManually: _buildManually,
        );
      case _ImportPhase.error:
        return _ErrorMessage(message: _errorMessage!, detail: _errorDetail, onRetry: _pickAndImport);
    }
  }
}

/// Maps a raw import failure to a user-facing line, recognising the common
/// backend rejections so the message points at the real cause instead of
/// blaming the PDF. Classifies from the error's string form deliberately —
/// this presentation layer must not import the `cloud_functions` SDK (its
/// exception types are confined to the data layer), and callable failures
/// render their code/message into `toString()` (e.g.
/// `[firebase_functions/unauthenticated]`).
///
/// `aiImportWorkoutPlan` deliberately never requires sign-in (it reads and
/// extracts a PDF, nothing more — see the callable's own doc comment in
/// `functions/index.js`), so an `unauthenticated`/`permission-denied`
/// rejection from THIS call can only be Firebase App Check declining the
/// request, never a real "you need to sign in" case — Firebase's own App
/// Check enforcement message doesn't reliably say "app check" at all, so
/// treating those codes as a separate, lower-priority branch (as this used
/// to) left the real cause misreported as a sign-in problem.
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
  if (text.contains('deadline') ||
      text.contains('timeout') ||
      text.contains('unavailable') ||
      text.contains('network')) {
    return 'Network problem reaching the import service — check your '
        'connection and try again.';
  }
  return "Couldn't read that plan — try a clearer PDF, or build the split manually.";
}

/// The icon-chip look shared by every non-preview phase of this flow — a
/// large tinted rounded-square icon above a headline/subcopy pair, the same
/// "premium empty/status state" language the rest of the Workout feature
/// already uses (see `workout_plan_page.dart`'s own empty/error states).
class _PhaseIcon extends StatelessWidget {
  const _PhaseIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(22)),
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
            const _PhaseIcon(icon: Icons.upload_file_rounded, color: AppColors.pulse),
            const SizedBox(height: 18),
            Text(
              'Select your training plan',
              style: AppText.cardTitle.copyWith(color: AppColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Choose a PDF and I'll map it into a real, editable split.",
              style: AppText.body.copyWith(color: AppColors.ink3),
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
            decoration: const BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle),
            padding: const EdgeInsets.all(10),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(AppColors.pulse, BlendMode.srcIn),
              child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 20),
          Text('Analyzing your plan', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              statusLine,
              key: ValueKey(statusLine),
              style: AppText.body.copyWith(color: AppColors.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewState extends StatelessWidget {
  const _PreviewState({
    required this.plan,
    required this.saving,
    required this.onImport,
    required this.onEdit,
    required this.onChooseDifferentFile,
  });

  final WorkoutPlan plan;
  final bool saving;
  final VoidCallback onImport;
  final VoidCallback onEdit;
  final VoidCallback onChooseDifferentFile;

  @override
  Widget build(BuildContext context) {
    final exerciseCount = plan.days.fold<int>(0, (sum, d) => sum + d.exercises.length);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.pulse),
                  const SizedBox(width: 6),
                  Text(
                    "HERE'S WHAT I FOUND",
                    style: AppText.meta.copyWith(
                      color: AppColors.pulse,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(plan.name, style: AppText.heroNumber.copyWith(fontSize: 26, color: AppColors.ink)),
              const SizedBox(height: 4),
              Text(
                '${plan.days.length} day${plan.days.length == 1 ? '' : 's'} · '
                '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'} total',
                style: AppText.meta.copyWith(color: AppColors.ink3),
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
            color: AppColors.ground,
            border: Border(top: BorderSide(color: AppColors.hairline2)),
          ),
          child: Column(
            children: [
              PillButton(
                label: saving ? 'Importing…' : 'Import this split',
                icon: Icons.check_rounded,
                color: AppColors.pulse,
                enabled: !saving,
                onTap: onImport,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: saving ? null : onEdit,
                    child: Text('Edit before importing', style: AppText.meta.copyWith(color: AppColors.ink2)),
                  ),
                  Text('·', style: AppText.meta.copyWith(color: AppColors.ink3)),
                  TextButton(
                    onPressed: saving ? null : onChooseDifferentFile,
                    child: Text('Choose a different file', style: AppText.meta.copyWith(color: AppColors.ink2)),
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
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Day ${day.slot} · ${day.label}',
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
              ),
              Text(workoutDayMeta(day), style: AppText.meta.copyWith(color: AppColors.ink3)),
            ],
          ),
          if (day.exercises.isEmpty) ...[
            const SizedBox(height: 8),
            Text('No exercises found for this day.', style: AppText.meta.copyWith(color: AppColors.ink3)),
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
                        style: AppText.body.copyWith(fontSize: 14, color: AppColors.ink2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      collapsedSetSummaries(exercise.sets).join(' · '),
                      style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 12),
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
    final exerciseCount = plan.days.fold<int>(0, (sum, d) => sum + d.exercises.length);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PhaseIcon(icon: Icons.check_rounded, color: AppColors.pulse),
            const SizedBox(height: 18),
            Text('Import complete', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(
              '"${plan.name}" added to your splits — ${plan.days.length} day'
              '${plan.days.length == 1 ? '' : 's'}, $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}.',
              style: AppText.body.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 160,
              child: PillButton(
                label: 'Done',
                icon: Icons.arrow_forward_rounded,
                color: AppColors.pulse,
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

class _RejectedState extends StatelessWidget {
  const _RejectedState({
    required this.reason,
    required this.onChooseDifferentFile,
    required this.onBuildManually,
  });

  final String reason;
  final VoidCallback onChooseDifferentFile;
  final VoidCallback onBuildManually;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PhaseIcon(icon: Icons.picture_as_pdf_outlined, color: AppColors.flare),
            const SizedBox(height: 18),
            Text(
              "This doesn't look like a workout plan",
              style: AppText.cardTitle.copyWith(color: AppColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(reason, style: AppText.body.copyWith(color: AppColors.ink3), textAlign: TextAlign.center),
            const SizedBox(height: 22),
            SizedBox(
              width: 220,
              child: PillButton(
                label: 'Choose a different file',
                icon: Icons.upload_file_rounded,
                color: AppColors.pulse,
                enabled: true,
                onTap: onChooseDifferentFile,
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onBuildManually,
              child: Text('Build manually instead', style: AppText.meta.copyWith(color: AppColors.ink2)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message, required this.onRetry, this.detail});

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
            const _PhaseIcon(icon: Icons.cloud_off_rounded, color: AppColors.ink3),
            const SizedBox(height: 18),
            Text(message, style: AppText.aside.copyWith(color: AppColors.ink2), textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: 10),
              Text(
                detail!,
                style: AppText.aside.copyWith(color: AppColors.ink3, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              child: PillButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                color: AppColors.pulse,
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
