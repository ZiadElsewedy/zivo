import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/settings_row.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../domain/ai_model_selection.dart';
import '../../domain/ai_response_style.dart';
import '../../domain/ai_usage_summary.dart';
import '../ai_labels.dart';
import '../widgets/ask/provider_mark.dart';
import '../../../../l10n/l10n.dart';

/// The Ask settings **page** (pushed, not a sheet): pick which model answers
/// (Auto / Claude / Gemini, each with its brand mark and a one-line
/// description), the reply style, and see how many tokens each model has used.
///
/// Reached from the Ask header's settings button. Selections apply in place via
/// [onSelectModel]/[onSelectStyle] — the same controller setters the header
/// used — so the choice persists (optimistically, with rollback) exactly as
/// before; the page just gives the two settings room to breathe and adds the
/// usage read. Dressed in the app's own settings chrome (`TrainScreen` +
/// `TrainPageHeader` + `SettingsSectionCard`) so it sits with Settings and its
/// sub-pages rather than inventing a look.
class AskSettingsPage extends StatefulWidget {
  const AskSettingsPage({
    required this.initialModel,
    required this.initialStyle,
    required this.onSelectModel,
    required this.onSelectStyle,
    super.key,
  });

  final String initialModel;
  final String initialStyle;
  final void Function(String) onSelectModel;
  final void Function(String) onSelectStyle;

  @override
  State<AskSettingsPage> createState() => _AskSettingsPageState();
}

class _AskSettingsPageState extends State<AskSettingsPage> {
  late String _model = widget.initialModel;
  late String _style = widget.initialStyle;
  Future<List<AiProviderUsage>>? _usage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load once — AppScope isn't safe to read in initState.
    _usage ??= AppScope.of(context).ai.usageByProvider();
  }

  /// The brand whose mark represents a model selection: Claude → anthropic,
  /// Gemini → gemini, Auto → the neutral ZIVO spark.
  String _markFor(String selection) => switch (selection) {
    'claude' => 'anthropic',
    'gemini' => 'gemini',
    _ => 'auto',
  };

  void _pickModel(String selection) {
    if (selection == _model) return;
    HapticFeedback.selectionClick();
    setState(() => _model = selection);
    widget.onSelectModel(selection);
  }

  void _pickStyle(String selection) {
    if (selection == _style) return;
    HapticFeedback.selectionClick();
    setState(() => _style = selection);
    widget.onSelectStyle(selection);
  }

  @override
  Widget build(BuildContext context) {
    return TrainScreen(
      tint: TrainColors.settingsTint,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, 12, 22, TrainBottomInset.of(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RiseIn(child: TrainPageHeader(title: l(context).askSettings)),
            const SizedBox(height: 26),
            // --- Model ---------------------------------------------------
            RiseIn(
              delay: const Duration(milliseconds: 50),
              child: SettingsSectionCard(
                label: l(context).askModel,
                children: [
                  for (var i = 0; i < kAiModelSelections.length; i++)
                    _SelectRow(
                      key: Key('model-${kAiModelSelections[i]}'),
                      leading: ProviderMark(
                        provider: _markFor(kAiModelSelections[i]),
                      ),
                      title: aiModelSelectionText(context, kAiModelSelections[i]),
                      subtitle: aiModelSelectionDescription(
                        context,
                        kAiModelSelections[i],
                      ),
                      selected: kAiModelSelections[i] == _model,
                      last: i == kAiModelSelections.length - 1,
                      onTap: () => _pickModel(kAiModelSelections[i]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // --- Reply style ---------------------------------------------
            RiseIn(
              delay: const Duration(milliseconds: 90),
              child: SettingsSectionCard(
                label: l(context).askReplyStyle,
                children: [
                  for (var i = 0; i < kResponseStyles.length; i++)
                    _SelectRow(
                      key: Key('style-${kResponseStyles[i]}'),
                      title: responseStyleText(context, kResponseStyles[i]),
                      subtitle: responseStyleDescription(
                        context,
                        kResponseStyles[i],
                      ),
                      selected: kResponseStyles[i] == _style,
                      last: i == kResponseStyles.length - 1,
                      onTap: () => _pickStyle(kResponseStyles[i]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // --- Usage ---------------------------------------------------
            RiseIn(
              delay: const Duration(milliseconds: 130),
              child: SettingsSectionCard(
                label: l(context).askUsage,
                children: [_UsageList(future: _usage)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The usage section's body: a per-provider list once the read resolves, an
/// empty line when there's none, and a quiet placeholder while loading (never
/// a spinner that would make a settings page feel busy).
class _UsageList extends StatelessWidget {
  const _UsageList({required this.future});

  final Future<List<AiProviderUsage>>? future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AiProviderUsage>>(
      future: future,
      builder: (context, snapshot) {
        final usage = snapshot.data;
        if (usage == null) {
          // Loading — reserve a little height, no spinner.
          return const SizedBox(height: 64);
        }
        if (usage.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 17),
            child: Text(
              l(context).askUsageEmpty,
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < usage.length; i++)
              _UsageRow(usage: usage[i], last: i == usage.length - 1),
          ],
        );
      },
    );
  }
}

/// One provider's usage row: brand mark, name, "N turns · ~$cost est.", and the
/// total token count as the headline instrument on the right.
class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.usage, required this.last});

  final AiProviderUsage usage;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        '${l(context).askUsageTurns(usage.turns)} · '
        '${l(context).askUsageEstCost(_formatCost(usage.costUsd))}';
    return _DetailRow(
      leading: ProviderMark(provider: usage.provider),
      title: aiProviderDisplayName(context, usage.provider),
      subtitle: subtitle,
      last: last,
      trailing: Text(
        ltrFor(context, _compact(usage.tokensTotal)),
        style: TrainType.mono(
          size: 15,
          color: TrainColors.inkPlain,
          height: 1.1,
        ),
      ),
    );
  }
}

/// A selectable settings row: an optional leading [leading] mark, a bold
/// [title] over a [subtitle] description, and an iris check when [selected].
class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.last,
    this.leading,
    super.key,
  });

  final Widget? leading;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: _DetailRow(
            leading: leading,
            title: title,
            subtitle: subtitle,
            selectedTitle: selected,
            last: last,
            trailing: selected
                ? Icon(AppIcons.check, size: 18, color: TrainColors.violet)
                : null,
          ),
        ),
      ),
    );
  }
}

/// The shared two-line row body used by both the selectable rows and the usage
/// rows — leading mark column, title over subtitle, a trailing widget, and the
/// title-inset hairline unless it's [last]. Metrics match [SettingsRow] so this
/// page's rows line up with the rest of the app's settings.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.title,
    required this.subtitle,
    required this.last,
    this.leading,
    this.trailing,
    this.selectedTitle = false,
  });

  final Widget? leading;
  final String title;
  final String subtitle;
  final bool last;
  final Widget? trailing;
  final bool selectedTitle;

  static const _markWidth = 24.0;
  static const _iconColumn = 17.0 + _markWidth + 14.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 17),
          child: Row(
            children: [
              if (leading != null) ...[
                SizedBox(width: _markWidth, child: Center(child: leading)),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TrainType.ui(
                        size: 15,
                        weight: selectedTitle
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selectedTitle
                            ? TrainColors.inkPlain
                            : TrainColors.ink2,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.meta.copyWith(
                        color: TrainColors.ink3,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
        if (!last)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: leading != null ? _iconColumn : 17,
            ),
            child: Divider(height: 1, thickness: 1, color: TrainColors.hairline),
          ),
      ],
    );
  }
}

/// Compact token count: 1_850_000 → "1.9M", 50_600 → "50.6K", 812 → "812".
String _compact(int n) {
  if (n >= 1000000) return '${_trim(n / 1000000)}M';
  if (n >= 1000) return '${_trim(n / 1000)}K';
  return n.toString();
}

String _trim(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// A small USD figure: 0 → "\$0", under a cent → "<\$0.01", else two decimals.
String _formatCost(double c) {
  if (c <= 0) return '\$0';
  if (c < 0.01) return '<\$0.01';
  return '\$${c.toStringAsFixed(2)}';
}
