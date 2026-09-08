import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/deferred_write.dart';
import '../../../../core/util/parse.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/zivo_confirm.dart';
import '../../../../core/widgets/zivo_field.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/live_session.dart';
import '../../domain/session_status.dart';
import '../../domain/workout_session_repository.dart';
import '../workout_labels.dart';

/// Correct a session's duration.
///
/// The affordance that makes "exclude and flag" honest rather than merely
/// tidy: a session held out of the averages is not a dead end, it is one tap
/// from being right again. What it writes is an **amendment** —
/// `startedAt`/`completedAt` are left exactly as recorded, and the number the
/// user gives is stored beside them with [DurationSource.userCorrected] so
/// every screen can say where it came from.
///
/// It cannot touch a set. That is not a promise made in a comment; a duration
/// lives on the session and performance lives under `exercises`, and
/// [LiveSession.correctDuration] has no path to the latter.
Future<void> showDurationCorrectionSheet(
  BuildContext context, {
  required LiveSession session,
  required WorkoutSessionRepository repository,
}) {
  final controller = TextEditingController(
    text: session.correctedDurationMinutes?.toString() ??
        (session.hasUsableDuration(const Duration(hours: 24))
            ? session.elapsed.inMinutes.toString()
            : ''),
  );

  return showZivoSheet<void>(
    context: context,
    builder: (sheetContext) => ZivoSheetSurface(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          8,
          22,
          MediaQuery.of(sheetContext).viewInsets.bottom + 22,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ZivoSheetHandle(),
            const SizedBox(height: 6),
            Text(
              l(sheetContext).sessionSetDuration,
              style: TrainType.ui(
                size: 19,
                weight: FontWeight.w700,
                color: TrainColors.inkPlain,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l(sheetContext).sessionNeedsDurationBody,
              style: TrainType.ui(
                size: 12.5,
                color: TrainColors.ink3,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TrainType.mono(size: 22, color: TrainColors.inkPlain),
              decoration: zivoFieldDecoration(
                accent: TrainColors.green,
                hintText: l(sheetContext).sessionDurationMinutes,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (session.correctedDurationMinutes != null) ...[
                  Expanded(
                    child: TrainGhostButton(
                      label: l(sheetContext).sessionDurationUseMeasured,
                      mono: false,
                      onTap: () {
                        final failure = l(sheetContext).sessionUpdateFailed;
                        Navigator.of(sheetContext).pop();
                        deferWrite(
                          repository.saveSession(session.correctDuration(null)),
                          failureMessage: failure,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TrainPrimaryButton(
                    label: l(sheetContext).actionSave,
                    onTap: () {
                      final minutes = parseWhole(controller.text);
                      if (minutes == null || minutes <= 0) return;
                      final failure = l(sheetContext).sessionUpdateFailed;
                      Navigator.of(sheetContext).pop();
                      deferWrite(
                        repository.saveSession(
                          session.correctDuration(minutes),
                        ),
                        failureMessage: failure,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Void a session — the replacement for deleting one.
///
/// A tracker whose history can be curated is a tracker whose numbers mean
/// nothing, so a session that recorded real work is never erased: it is
/// withdrawn, with a reason, and it keeps its place in History showing exactly
/// what was lifted. Only the statistics stop counting it.
Future<bool> showVoidSessionSheet(
  BuildContext context, {
  required LiveSession session,
  required WorkoutSessionRepository repository,
  required DateTime now,
}) async {
  final reason = await showZivoSheet<VoidReason>(
    context: context,
    builder: (sheetContext) => ZivoSheetSurface(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ZivoSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l(sheetContext).sessionVoidTitle,
                    style: TrainType.ui(
                      size: 19,
                      weight: FontWeight.w700,
                      color: TrainColors.inkPlain,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l(sheetContext).sessionVoidBody,
                    style: TrainType.ui(
                      size: 12.5,
                      color: TrainColors.ink3,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            TrainListCard(
              rows: [
                for (final reason in VoidReason.values)
                  TrainListRow(
                    icon: AppIcons.minus,
                    accent: TrainColors.ink4,
                    label: voidReasonLabel(sheetContext, reason),
                    onTap: () => Navigator.of(sheetContext).pop(reason),
                  ),
              ],
            ),
            const SizedBox(height: 22),
          ],
        ),
      ),
    ),
  );
  if (reason == null || !context.mounted) return false;

  final confirmed = await confirmDestructive(
    context,
    title: l(context).sessionVoidTitle,
    body: l(context).sessionVoidBody,
    confirmLabel: l(context).sessionVoid,
  );
  if (!confirmed || !context.mounted) return false;

  deferWrite(
    repository.saveSession(session.voidSession(reason: reason, now: now)),
    failureMessage: l(context).sessionUpdateFailed,
  );
  return true;
}
