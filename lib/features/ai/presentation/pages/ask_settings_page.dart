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
import '../widgets/ask/ai_detail_row.dart';
import '../widgets/ask/provider_mark.dart';
import 'ai_usage_page.dart';
import '../../../../l10n/l10n.dart';

/// The Ask settings **page** (pushed, not a sheet): pick the **active** AI
/// model (each with its brand mark, a one-line description, and an "Active"
/// badge on the live one — the choice applies to every AI feature, and ZIVO
/// never switches on its own), the reply style, and see tokens + cost per
/// provider; tapping a provider opens its full breakdown ([AiUsagePage]).
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
                        provider: aiModelSelectionProvider(kAiModelSelections[i]),
                      ),
                      title: aiModelSelectionText(context, kAiModelSelections[i]),
                      subtitle: aiModelSelectionDescription(
                        context,
                        kAiModelSelections[i],
                      ),
                      selected: kAiModelSelections[i] == _model,
                      // The model answering everything wears a word, not
                      // just a tick — which one is live must be unmissable.
                      activeBadge: kAiModelSelections[i] == _model,
                      last: i == kAiModelSelections.length - 1,
                      onTap: () => _pickModel(kAiModelSelections[i]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                l(context).askModelAppliesNote,
                style: AppText.meta.copyWith(
                  color: TrainColors.ink2,
                  height: 1.4,
                ),
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
        '${l(context).askUsageRequests(usage.turns)} · '
        '${l(context).askUsageEstCost(formatUsd(usage.costUsd))}';
    // Tapping a provider opens its full breakdown — requests by type,
    // tokens in/out, cost and cost per request.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('usage-row-${usage.provider}'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AiUsagePage(initialProvider: usage.provider),
          ),
        ),
        child: AiDetailRow(
          leading: ProviderMark(provider: usage.provider),
          title: aiProviderDisplayName(context, usage.provider),
          subtitle: subtitle,
          last: last,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ltrFor(context, compactTokens(usage.tokensTotal)),
                style: TrainType.mono(
                  size: 15,
                  color: TrainColors.inkPlain,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 6),
              Icon(AppIcons.chevron, size: 14, color: TrainColors.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// A selectable settings row: an optional leading [leading] mark, a bold
/// [title] over a [subtitle] description, and an iris check when [selected]
/// — plus an "Active" badge when [activeBadge] (the model picker).
class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.last,
    this.leading,
    this.activeBadge = false,
    super.key,
  });

  final bool activeBadge;
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
          child: AiDetailRow(
            leading: leading,
            title: title,
            subtitle: subtitle,
            selectedTitle: selected,
            last: last,
            trailing: !selected
                ? null
                : activeBadge
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        key: const Key('model-active-badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
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
                      const SizedBox(width: 8),
                      Icon(AppIcons.check, size: 18, color: TrainColors.violet),
                    ],
                  )
                : Icon(AppIcons.check, size: 18, color: TrainColors.violet),
          ),
        ),
      ),
    );
  }
}
