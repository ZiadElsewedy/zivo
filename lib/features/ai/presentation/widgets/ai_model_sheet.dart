import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/ai_model_selection.dart';
import '../../domain/ai_repository.dart';
import '../../domain/ai_response_style.dart';
import '../ai_labels.dart';
import 'ask/provider_mark.dart';

/// Picks the **active AI model** — the one picker, opened from Settings → AI
/// → Model, from Ask's header, and from the plan import/generation error
/// screens so "Claude isn't available" can be fixed on the spot. Writes
/// `users/{uid}/settings/ai`; the plan callables read it server-side on the
/// next attempt, and the chat re-reads it before each send
/// (`AskController.runSend`), so everything agrees.
///
/// Resolves to the newly active model id, or null when the sheet was closed
/// without a change.
Future<String?> showAiModelSheet(BuildContext context) {
  // Scroll-controlled so the sheet sizes to its content — described rows
  // don't fit the half-screen cap on a short phone.
  return showZivoSheet<String>(
    context: context,
    builder: (_) => _AiChoiceSheet(
      title: (c) => l(c).askModel,
      subtitle: (c) => l(c).askModelSheetSubtitle,
      options: kAiModelSelections,
      fallback: kDefaultAiModelSelection,
      load: (ai) async => validAiModelSelection(await ai.getModelSelection()),
      save: (ai, v) => ai.setModelSelection(v),
      label: aiModelSelectionText,
      description: aiModelSelectionDescription,
      leading: (m) => ProviderMark(provider: aiModelSelectionProvider(m)),
      // Which model answers must be unmissable: a word, not just a tick.
      activeBadge: true,
      keyPrefix: 'sheet-model-',
    ),
  );
}

/// Picks Ask's reply style (concise · balanced · detailed) — Settings → AI →
/// Reply style. Resolves to the new style, or null when nothing changed.
Future<String?> showResponseStyleSheet(BuildContext context) {
  return showZivoSheet<String>(
    context: context,
    builder: (_) => _AiChoiceSheet(
      title: (c) => l(c).askReplyStyle,
      subtitle: null,
      options: kResponseStyles,
      fallback: kDefaultResponseStyle,
      load: (ai) async => validResponseStyle(await ai.getResponseStyle()),
      save: (ai, v) => ai.setResponseStyle(v),
      label: responseStyleText,
      description: responseStyleDescription,
      keyPrefix: 'sheet-style-',
    ),
  );
}

/// One persisted AI setting as a list of described options, applied on tap
/// (no separate Save) and popped with the new value.
class _AiChoiceSheet extends StatefulWidget {
  const _AiChoiceSheet({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.fallback,
    required this.load,
    required this.save,
    required this.label,
    required this.description,
    required this.keyPrefix,
    this.leading,
    this.activeBadge = false,
  });

  final String Function(BuildContext) title;
  final String Function(BuildContext)? subtitle;
  final List<String> options;
  final String fallback;
  final Future<String> Function(AiRepository) load;
  final Future<void> Function(AiRepository, String) save;
  final String Function(BuildContext, String) label;
  final String Function(BuildContext, String) description;
  final Widget Function(String)? leading;
  final bool activeBadge;
  final String keyPrefix;

  @override
  State<_AiChoiceSheet> createState() => _AiChoiceSheetState();
}

class _AiChoiceSheetState extends State<_AiChoiceSheet> {
  String? _active;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_active != null) return;
    widget.load(AppScope.of(context).ai).then(
      (v) {
        if (mounted) setState(() => _active = v);
      },
      onError: (Object _) {
        if (mounted) setState(() => _active = widget.fallback);
      },
    );
  }

  Future<void> _pick(String value) async {
    if (_saving || value == _active) {
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
      _active = value;
    });
    try {
      await widget.save(ai, value);
      navigator.pop(value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(SnackBar(content: Text(strings.askSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.subtitle;
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
            Text(widget.title(context), style: AppText.rowTitle),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle(context),
                style: AppText.meta.copyWith(color: TrainColors.ink2),
              ),
            ],
            const SizedBox(height: 12),
            if (_active == null)
              SizedBox(height: 72.0 * widget.options.length)
            else
              for (final option in widget.options)
                _ModelRow(
                  key: Key('${widget.keyPrefix}$option'),
                  leading: widget.leading?.call(option),
                  title: widget.label(context, option),
                  description: widget.description(context, option),
                  active: option == _active,
                  activeBadge: widget.activeBadge,
                  onTap: () => _pick(option),
                ),
          ],
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.title,
    required this.description,
    required this.active,
    required this.activeBadge,
    required this.onTap,
    this.leading,
    super.key,
  });

  final Widget? leading;
  final String title;
  final String description;
  final bool active;
  final bool activeBadge;
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
            if (leading != null) ...[
              SizedBox(width: 24, child: Center(child: leading)),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TrainType.ui(
                      size: 15.5,
                      weight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? TrainColors.inkPlain : TrainColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: AppText.meta.copyWith(
                      color: TrainColors.ink2,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (active && activeBadge) ...[
              const SizedBox(width: 10),
              Container(
                key: const Key('model-active-badge'),
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
            ],
            if (active) ...[
              const SizedBox(width: 6),
              Icon(AppIcons.check, size: 18, color: TrainColors.violet),
            ],
          ],
        ),
      ),
    );
  }
}
