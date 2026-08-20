import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/workout_plan.dart';
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

/// The PDF-import entry flow (WORKOUT_SYSTEM.md §3.4, Phase 6): pick a PDF →
/// call `aiImportWorkoutPlan` → hand the parsed draft to `WorkoutPlanEditPage`
/// (in `asSplit` mode) for the user to review/fix before saving. That review
/// screen IS the "human confirms before it becomes real" gate — this page
/// itself never saves anything, and pops back to split management once the
/// review is done (saved or not).
///
/// Opens straight into the file picker (no idle "tap to start" screen) since
/// the entry action that pushed this page already expressed that intent.
class WorkoutPdfImportPage extends StatefulWidget {
  const WorkoutPdfImportPage({super.key, Future<Uint8List?> Function()? pickPdfBytes})
    : pickPdfBytes = pickPdfBytes ?? _defaultPickPdfBytes;

  /// Overridable for tests — defaults to the real file picker.
  final Future<Uint8List?> Function() pickPdfBytes;

  @override
  State<WorkoutPdfImportPage> createState() => _WorkoutPdfImportPageState();
}

enum _ImportPhase { picking, importing, error }

class _WorkoutPdfImportPageState extends State<WorkoutPdfImportPage> {
  _ImportPhase _phase = _ImportPhase.picking;
  String? _errorMessage;
  // The raw failure text, shown only in debug builds so a real backend cause
  // (App Check, auth, network) is visible on-device instead of hidden behind
  // the friendly line. Never surfaced in release.
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickAndImport());
  }

  Future<void> _pickAndImport() async {
    setState(() {
      _phase = _ImportPhase.picking;
      _errorMessage = null;
      _errorDetail = null;
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
    setState(() => _phase = _ImportPhase.importing);

    try {
      final result = await AppScope.of(context).ai.importWorkoutPlan(pdfBytes: bytes);
      if (!mounted) return;
      final draft = workoutPlanFromImport(
        result,
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        now: DateTime.now(),
      );
      await Navigator.of(context).push<WorkoutPlan>(
        MaterialPageRoute(builder: (_) => WorkoutPlanEditPage(initialPlan: draft, asSplit: true)),
      );
      // Whether the review ended in Save, Delete, or just closing — the
      // import flow itself is done either way.
      if (mounted) Navigator.of(context).pop();
    } catch (error, stack) {
      // Surface the real failure instead of swallowing it. The old blanket
      // "couldn't read that plan" hid App Check / auth / network rejections
      // and sent people deleting data to chase a backend problem.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureTopBar(
              title: 'Import PDF',
              onClose: () => Navigator.of(context).maybePop(),
              titleColor: AppColors.ink2,
              iconColor: AppColors.ink2,
              chipColor: AppColors.surfaceRaised,
            ),
            Expanded(child: Center(child: _body())),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _ImportPhase.picking:
        return const _StatusMessage(label: 'Choose a PDF…');
      case _ImportPhase.importing:
        return const _StatusMessage(label: 'Reading your plan…', showSpinner: true);
      case _ImportPhase.error:
        return _ErrorMessage(
          message: _errorMessage!,
          detail: _errorDetail,
          onRetry: _pickAndImport,
        );
    }
  }
}

/// Maps a raw import failure to a user-facing line, recognising the common
/// backend rejections so the message points at the real cause instead of
/// blaming the PDF. Classifies from the error's string form deliberately — this
/// presentation layer must not import the `cloud_functions` SDK (its exception
/// types are confined to the data layer), and callable failures render their
/// code/message into `toString()` (e.g. `[firebase_functions/unauthenticated]`).
String _importErrorMessage(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('app-check') ||
      text.contains('app check') ||
      text.contains('appcheck')) {
    return "The app couldn't verify itself (App Check). Register this "
        "build's debug token in the Firebase console, then try again.";
  }
  if (text.contains('unauthenticated') ||
      text.contains('permission-denied') ||
      text.contains('permission denied')) {
    return 'You need to be signed in to import a plan.';
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

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.label, this.showSpinner = false});

  final String label;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSpinner) ...[
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.pulse),
          ),
          const SizedBox(height: 16),
        ],
        Text(label, style: AppText.body.copyWith(color: AppColors.ink2)),
      ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.picture_as_pdf_outlined, size: 30, color: AppColors.ink3),
          const SizedBox(height: 12),
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
    );
  }
}
