import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/ai_model_selection.dart';
import '../ai_labels.dart';
import 'ask/provider_mark.dart';

/// Picks the **active AI model** from anywhere — the plan import/generation
/// error screens use it so "Claude isn't available" can be fixed on the spot
/// instead of sending the user to Ask settings. Reads and writes the same
/// `users/{uid}/settings/ai` field the Ask settings page does; the plan
/// callables read it server-side on the next attempt, and the chat re-reads
/// it before each send (`AskController.runSend`), so everything agrees.
///
/// Resolves to the newly active model id, or null when the sheet was closed
/// without a change.
Future<String?> showAiModelSheet(BuildContext context) {
  // Scroll-controlled so the sheet sizes to its content — three described
  // rows don't fit the half-screen cap on a short phone.
  return showZivoSheet<String>(
    context: context,
    builder: (_) => const _AiModelSheet(),
  );
}

class _AiModelSheet extends StatefulWidget {
  const _AiModelSheet();

  @override
  State<_AiModelSheet> createState() => _AiModelSheetState();
}

class _AiModelSheetState extends State<_AiModelSheet> {
  String? _active;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_active != null) return;
    AppScope.of(context).ai.getModelSelection().then(
      (m) {
        if (mounted) setState(() => _active = validAiModelSelection(m));
      },
      onError: (Object _) {
        if (mounted) setState(() => _active = kDefaultAiModelSelection);
      },
    );
  }

  Future<void> _pick(String model) async {
    if (_saving || model == _active) {
      Navigator.of(context).pop();
      return;
    }
    HapticFeedback.selectionClick();
    final ai = AppScope.of(context).ai;
    final navigator = Navigator.of(context);
    final strings = l(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _saving = true;
      _active = model;
    });
    try {
      await ai.setModelSelection(model);
      navigator.pop(model);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(SnackBar(content: Text(strings.askSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TrainColors.sheetSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: ZivoSheetHandle()),
            const SizedBox(height: 16),
            Text(l(context).askModel, style: AppText.rowTitle),
            const SizedBox(height: 4),
            Text(
              l(context).askModelSheetSubtitle,
              style: AppText.meta.copyWith(color: TrainColors.ink2),
            ),
            const SizedBox(height: 12),
            if (_active == null)
              const SizedBox(height: 180)
            else
              for (final model in kAiModelSelections)
                _ModelRow(
                  key: Key('sheet-model-$model'),
                  model: model,
                  active: model == _active,
                  onTap: () => _pick(model),
                ),
          ],
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.active,
    required this.onTap,
    super.key,
  });

  final String model;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Center(
                child: ProviderMark(provider: aiModelSelectionProvider(model)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aiModelSelectionText(context, model),
                    style: TrainType.ui(
                      size: 15.5,
                      weight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? TrainColors.inkPlain : TrainColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    aiModelSelectionDescription(context, model),
                    style: AppText.meta.copyWith(
                      color: TrainColors.ink2,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (active) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: TrainColors.violetWash,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  l(context).askModelActive,
                  style: AppText.meta.copyWith(
                    color: TrainColors.violet,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(AppIcons.check, size: 18, color: TrainColors.violet),
            ],
          ],
        ),
      ),
    );
  }
}
