import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../widgets/capture_widgets.dart';

/// The phase screens a plan import moves through — select → analyze →
/// rejected/error — shared by the workout and diet import flows.
///
/// These used to be a private `_PhaseIcon`/`_SelectingState`/… set copy-pasted
/// into each importer, and they had already drifted: the workout copies were
/// written with raw `TrainType.ui(...)` literals while the diet copies used the
/// named [AppText] ladder, so the two flows rendered the same screen at
/// different sizes and weights. They are one implementation now, on the named
/// ladder (ADR-009), and each caller passes only its own copy and accent — the
/// review/preview step, which only the workout flow has, stays in that page.

/// The looping-Lottie single-line "working" screen — for a step that does NOT
/// stream real progress and so has no honest stage checklist to show.
///
/// Used by diet **generation** (`aiGenerateDietPlan` is not streamed), whose
/// [statusLine] is a cycled written line, not a live extraction. Import uses
/// [ImportAnalyzingState] instead, which shows the real pipeline.
/// A large tinted rounded-square icon above a headline/subcopy pair — the
/// "premium empty/status state" language the capture flows share.
class ImportPhaseIcon extends StatelessWidget {
  const ImportPhaseIcon({required this.icon, required this.color, super.key});

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

/// The idle screen the import lands on behind the file picker — a cancel or a
/// retry falls back to this.
class ImportSelectingState extends StatelessWidget {
  const ImportSelectingState({
    required this.title,
    required this.subtitle,
    Color? accent,
    super.key,
    // `this._x`, which the lint asks for here, is not a thing Dart will
    // accept: a named parameter cannot be private. The field is private
    // so that the public name can be the *resolved* getter below, which
    // is what keeps this constructor `const` (ADR-011).
    // ignore: prefer_initializing_formals
  }) : _accent = accent;

  final String title;
  final String subtitle;
  final Color? _accent;

  /// Defaults to the active skin's `green` — resolved on read
  /// rather than as a parameter default, which is what lets this
  /// constructor stay `const` (ADR-011).
  Color get accent => _accent ?? TrainColors.green;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ImportPhaseIcon(icon: Icons.upload_file_rounded, color: accent),
            const SizedBox(height: 18),
            Text(
              title,
              style: AppText.cardTitle.copyWith(color: TrainColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppText.body.copyWith(color: TrainColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The "analysing" screen — a looping-Lottie mark, the title, one honest line,
/// and an optional Cancel.
///
/// An import is a single ~minute model call with no observable sub-steps, so
/// this deliberately does NOT pretend separate backend stages are running: it
/// says the app is analysing the plan and sets the wait expectation via
/// [statusLine]. [onCancel], when given, shows a Cancel that aborts the import
/// (backend-side, via `aiCancelImport`). Diet generation reuses this with its
/// own cycled [statusLine] and no cancel.
class ImportAnalyzingState extends StatelessWidget {
  const ImportAnalyzingState({
    required this.statusLine,
    this.onCancel,
    Color? accent,
    Color? chipColor,
    super.key,
    // A named parameter cannot be private; the field is private so the public
    // name can be the *resolved* getter below, which keeps this const (ADR-011).
    // ignore: prefer_initializing_formals
  }) : _accent = accent,
       // ignore: prefer_initializing_formals
       _chipColor = chipColor;

  final String statusLine;

  /// Aborts the import (backend-side, via `aiCancelImport`). Null hides Cancel
  /// (e.g. diet generation, or an offline fake that cannot cancel).
  final VoidCallback? onCancel;

  final Color? _accent;

  /// Defaults to the active skin's `green` — resolved on read (ADR-011).
  Color get accent => _accent ?? TrainColors.green;
  final Color? _chipColor;

  /// Defaults to the active skin's `glassStrong` — resolved on read (ADR-011).
  Color get chipColor => _chipColor ?? TrainColors.glassStrong;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(color: chipColor, shape: BoxShape.circle),
            padding: const EdgeInsets.all(10),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
              child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l(context).importAnalyzing,
            style: AppText.cardTitle.copyWith(color: TrainColors.ink),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              statusLine,
              key: ValueKey(statusLine),
              style: AppText.body.copyWith(color: TrainColors.ink3),
              textAlign: TextAlign.center,
            ),
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 24),
            TextButton(
              onPressed: onCancel,
              child: Text(
                l(context).actionCancel,
                style: AppText.meta.copyWith(color: TrainColors.ink2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The honest decline — the document isn't (or doesn't contain) a usable plan.
/// [retryLabel] names what retrying does on this route (re-pick a file, or go
/// back to the description that produced it); [retryColor] is the flow's own
/// action hue.
class ImportRejectedState extends StatelessWidget {
  const ImportRejectedState({
    required this.title,
    required this.reason,
    required this.retryLabel,
    required this.onRetry,
    required this.onBuildManually,
    Color? retryColor,
    super.key,
    // `this._x`, which the lint asks for here, is not a thing Dart will
    // accept: a named parameter cannot be private. The field is private
    // so that the public name can be the *resolved* getter below, which
    // is what keeps this constructor `const` (ADR-011).
    // ignore: prefer_initializing_formals
  }) : _retryColor = retryColor;

  final String title;
  final String reason;
  final String retryLabel;
  final VoidCallback onRetry;
  final VoidCallback onBuildManually;
  final Color? _retryColor;

  /// Defaults to the active skin's `ember` — resolved on read
  /// rather than as a parameter default, which is what lets this
  /// constructor stay `const` (ADR-011).
  Color get retryColor => _retryColor ?? TrainColors.ember;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ImportPhaseIcon(
              icon: Icons.description_outlined,
              color: TrainColors.ember,
            ),
            const SizedBox(height: 18),
            Text(
              title,
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
                color: retryColor,
                enabled: true,
                onTap: onRetry,
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onBuildManually,
              child: Text(
                l(context).importBuildManuallyInstead,
                style: AppText.meta.copyWith(color: TrainColors.ink2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A real technical failure (network, App Check, server error) — never a
/// verdict on the document. [detail] is the raw failure text, shown small and
/// dim in debug builds only.
class ImportErrorState extends StatelessWidget {
  const ImportErrorState({
    required this.message,
    required this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
    Color? retryColor,
    super.key,
    // `this._x`, which the lint asks for here, is not a thing Dart will
    // accept: a named parameter cannot be private. The field is private
    // so that the public name can be the *resolved* getter below, which
    // is what keeps this constructor `const` (ADR-011).
    // ignore: prefer_initializing_formals
  }) : _retryColor = retryColor;

  /// The one friendly line — already phrased for a person. There is
  /// deliberately no "technical detail" slot: this screen used to render the
  /// raw exception and its stack trace under the message in debug builds,
  /// which overflowed the screen and read as a crash. The cause is in the
  /// debug console (`debugPrint`) and the server log, where it belongs.
  final String message;
  final VoidCallback onRetry;

  /// An optional second action under Retry — "Switch model" when the active
  /// AI model is what failed, so it can be fixed without leaving the flow.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Color? _retryColor;

  /// Defaults to the active skin's `ember` — resolved on read
  /// rather than as a parameter default, which is what lets this
  /// constructor stay `const` (ADR-011).
  Color get retryColor => _retryColor ?? TrainColors.ember;

  @override
  Widget build(BuildContext context) {
    // Scrolls rather than overflows: a long localized message, a large text
    // scale or a short screen must never paint the overflow stripes.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ImportPhaseIcon(
                    icon: Icons.cloud_off_rounded,
                    color: TrainColors.ink3,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    message,
                    style: AppText.aside(context).copyWith(
                      color: TrainColors.ink,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: 180,
                    child: PillButton(
                      label: l(context).actionRetry,
                      icon: Icons.refresh_rounded,
                      color: retryColor,
                      enabled: true,
                      onTap: onRetry,
                    ),
                  ),
                  if (secondaryLabel != null && onSecondary != null) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      key: const Key('import-error-secondary'),
                      onPressed: onSecondary,
                      child: Text(
                        secondaryLabel!,
                        style: AppText.button.copyWith(color: TrainColors.ink),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
