import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../../ai/domain/import_progress.dart';
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

/// Shown while importing, until the model has extracted anything at all. It is
/// true copy: before the first day/meal arrives, reading is all that happens.
const String kImportOpeningLine = 'Reading the document…';

/// What the analysing screen says right now: the live extraction if one has
/// arrived, else the opening line.
///
/// Deliberately never claims a total — the model doesn't know how many
/// [itemNoun]s a document holds until it has read them, so "Day 2 of 5" would
/// be a number nobody has. A rising count is the honest shape.
String importProgressLine(ImportProgress? progress, {required String itemNoun}) {
  final p = progress;
  if (p == null || p.isEmpty) return kImportOpeningLine;
  final section = p.latestSection;
  if (section == null) {
    return p.planName != null ? 'Found "${p.planName}"…' : kImportOpeningLine;
  }
  final items = p.items == 1 ? '1 $itemNoun' : '${p.items} ${itemNoun}s';
  return '$section · $items';
}

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
    this.accent = TrainColors.green,
    super.key,
  });

  final String title;
  final String subtitle;
  final Color accent;

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

/// The looping-Lottie "analysing" screen. [statusLine] is the one live line;
/// build it with [importProgressLine].
class ImportAnalyzingState extends StatelessWidget {
  const ImportAnalyzingState({
    required this.statusLine,
    this.accent = TrainColors.green,
    this.chipColor = TrainColors.glassStrong,
    super.key,
  });

  final String statusLine;
  final Color accent;
  final Color chipColor;

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
    this.retryColor = TrainColors.ember,
    super.key,
  });

  final String title;
  final String reason;
  final String retryLabel;
  final VoidCallback onRetry;
  final VoidCallback onBuildManually;
  final Color retryColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ImportPhaseIcon(
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

/// A real technical failure (network, App Check, server error) — never a
/// verdict on the document. [detail] is the raw failure text, shown small and
/// dim in debug builds only.
class ImportErrorState extends StatelessWidget {
  const ImportErrorState({
    required this.message,
    required this.onRetry,
    this.detail,
    this.retryColor = TrainColors.ember,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;
  final String? detail;
  final Color retryColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ImportPhaseIcon(
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
                color: retryColor,
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
