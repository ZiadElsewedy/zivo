import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/diet_import_outcome.dart';
import '../../domain/diet_plan.dart';
import '../../domain/diet_plan_from_import.dart';
import 'diet_plan_edit_page.dart';

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

/// The Diet PDF-import flow (Chunk B+C) — a deliberately shorter mirror of
/// `WorkoutPdfImportPage`: Select File → AI Analyzing → straight into
/// `DietPlanEditPage(initialPlan: ...)`, which IS the review-and-save gate
/// (it already carries full calorie/macro fields for every food item, so
/// there's no separate preview step here the way Workout's flow has one).
/// A document that isn't a usable diet plan surfaces a distinct, explained
/// decline instead of an empty or fabricated plan.
///
/// Opens straight into the file picker (no idle "tap to start" screen) since
/// the entry action that pushed this page already expressed that intent —
/// the [_ImportPhase.selecting] screen behind it is what a cancel or a retry
/// lands back on.
class DietPdfImportPage extends StatefulWidget {
  const DietPdfImportPage({
    super.key,
    Future<({Uint8List bytes, String mimeType})?> Function()? pickFile,
  }) : pickFile = pickFile ?? _defaultPickFile;

  /// Overridable for tests — defaults to the real file picker.
  final Future<({Uint8List bytes, String mimeType})?> Function() pickFile;

  @override
  State<DietPdfImportPage> createState() => _DietPdfImportPageState();
}

enum _ImportPhase { selecting, analyzing, rejected, error }

/// Cycled while [_ImportPhase.analyzing] is showing — an honest sense of
/// progress on a single opaque model call, not a fake percentage.
const _analyzingStatusLines = [
  'Reading the document…',
  'Identifying meals…',
  'Estimating calories and macros…',
];

class _DietPdfImportPageState extends State<DietPdfImportPage> {
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
      setState(
        () => _analyzingStatusIndex =
            (_analyzingStatusIndex + 1) % _analyzingStatusLines.length,
      );
    });
  }

  Future<void> _pickAndImport() async {
    _analyzingTimer?.cancel();
    setState(() {
      _phase = _ImportPhase.selecting;
      _errorMessage = null;
      _errorDetail = null;
      _rejectionReason = null;
    });

    ({Uint8List bytes, String mimeType})? file;
    try {
      file = await widget.pickFile();
    } catch (error, stack) {
      debugPrint('DietPdfImport: could not read the picked file: $error');
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
        _errorMessage = 'That file is too large — please choose one under '
            '7 MB.';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _phase = _ImportPhase.analyzing);
    _startAnalyzingCycle();

    try {
      final outcome = await AppScope.of(
        context,
      ).ai.importDietPlan(fileBytes: file.bytes, mimeType: file.mimeType);
      _analyzingTimer?.cancel();
      if (!mounted) return;
      switch (outcome) {
        case DietImportAccepted(:final plan):
          final draft = dietPlanFromImport(
            plan,
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            now: DateTime.now(),
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
      debugPrint('DietPdfImport: aiImportDietPlan failed: $error');
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
      backgroundColor: AppColors.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureTopBar(
              title: 'Import Plan',
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
        return _AnalyzingState(
          statusLine: _analyzingStatusLines[_analyzingStatusIndex],
        );
      case _ImportPhase.rejected:
        return _RejectedState(
          reason: _rejectionReason!,
          onChooseDifferentFile: _pickAndImport,
          onBuildManually: _buildManually,
        );
      case _ImportPhase.error:
        return _ErrorMessage(
          message: _errorMessage!,
          detail: _errorDetail,
          onRetry: _pickAndImport,
        );
    }
  }
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
              color: AppColors.pulse,
            ),
            const SizedBox(height: 18),
            Text(
              'Select your diet plan',
              style: AppText.cardTitle.copyWith(color: AppColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a PDF or a photo of your plan and I\'ll map it into a '
              'real, editable plan — estimating calories and macros wherever '
              "the document doesn't state them.",
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
            decoration: const BoxDecoration(
              color: AppColors.surfaceRaised,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(10),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                AppColors.pulse,
                BlendMode.srcIn,
              ),
              child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Analyzing your plan',
            style: AppText.cardTitle.copyWith(color: AppColors.ink),
          ),
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
            const _PhaseIcon(
              icon: Icons.description_outlined,
              color: AppColors.flare,
            ),
            const SizedBox(height: 18),
            Text(
              "This doesn't look like a diet plan",
              style: AppText.cardTitle.copyWith(color: AppColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              style: AppText.body.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
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
              child: Text(
                'Build manually instead',
                style: AppText.meta.copyWith(color: AppColors.ink2),
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
              color: AppColors.ink3,
            ),
            const SizedBox(height: 18),
            Text(
              message,
              style: AppText.aside.copyWith(color: AppColors.ink2),
              textAlign: TextAlign.center,
            ),
            if (detail != null) ...[
              const SizedBox(height: 10),
              Text(
                detail!,
                style: AppText.aside.copyWith(
                  color: AppColors.ink3,
                  fontSize: 11,
                ),
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
