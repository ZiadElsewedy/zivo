import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../domain/ai_model_selection.dart' show kDefaultAiModelSelection;
import '../../../../l10n/l10n.dart';

/// The Ask screen's header: the screen title beside three uniform glass
/// circle actions — settings, chat history, new chat — all drawn from the
/// app's single icon vocabulary so they sit consistently with every other
/// surface. The settings circle opens the Ask settings sheet (model + reply
/// style); it used to be two separate header menus.
///
/// Built to the design handoff's Ask header: Manrope 800/27 title, three
/// 38px circles on a flat `rgba(255,255,255,.04)` fill inside a hairline.
/// Circles, not squircles, and no drop shadow — this screen's depth comes
/// from its one radial glow, not from lifting every control off it
/// (identity §5).
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.onNewChat,
    required this.onSessions,
    required this.modelSelection,
    required this.onOpenSettings,
  });

  /// Starts a new chat session. Null (disabled) while a turn is in flight.
  final VoidCallback? onNewChat;

  /// Opens the sessions bottom sheet. Null (disabled) while a turn is in
  /// flight.
  final VoidCallback? onSessions;

  /// The current model selection ('auto'|'claude'|'gemini'). Drives the small
  /// "pinned" dot on the settings button when it's anything other than Auto —
  /// a glance-able hint that a specific model is forced.
  final String modelSelection;

  /// Opens the Ask settings sheet (model + reply style). Null (disabled) while
  /// a turn is in flight.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Directional: the wide inset belongs to the TITLE's edge and the
      // narrow one to the buttons', whichever side of the screen each lands
      // on. Pinned to left/right, Arabic got them swapped — the title crowded
      // against the screen edge while the button cluster sat inset from it.
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.screen,
        AppSpacing.base,
        AppSpacing.s + 4,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l(context).askTitle,
              style: TrainType.ui(
                size: 27,
                weight: FontWeight.w800,
                tracking: -0.025,
                color: TrainColors.ink,
                height: 1,
              ),
            ),
          ),
          _HeaderAction(
            key: const Key('header-settings'),
            icon: AppIcons.replyStyle,
            tooltip: l(context).askSettings,
            onTap: onOpenSettings,
            // A non-Auto model means the user has pinned a specific one —
            // surface that with a small accent dot so it's visible without
            // opening the sheet, without a label that would crowd the row.
            showDot: modelSelection != kDefaultAiModelSelection,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            key: const Key('header-history'),
            icon: AppIcons.history,
            tooltip: l(context).askChatHistory,
            onTap: onSessions,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            key: const Key('header-new-chat'),
            icon: AppIcons.chatNew,
            tooltip: l(context).askNewChat,
            onTap: onNewChat,
          ),
        ],
      ),
    );
  }
}

/// One uniform glass circle in the header row: a flat glass fill inside a
/// hairline, an `AppIcons` glyph, instant press-down scale, and a light haptic
/// on commit. Disabled while a turn is in flight. Can carry a small accent
/// dot ([showDot]) to flag a non-default state.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Draws a small accent dot at the top-end corner — used to flag a
  /// non-default state (e.g. a pinned model) without adding a label.
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        enabled: !disabled,
        child: Opacity(
          opacity: disabled ? 0.45 : 1,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: disabled
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      onTap!();
                    },
              customBorder: const CircleBorder(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: _glassDecoration(),
                    child: Icon(
                      icon,
                      size: 16,
                      color: disabled
                          ? TrainColors.ink4
                          : TrainColors.inkAt(0.7),
                    ),
                  ),
                  if (showDot)
                    PositionedDirectional(
                      top: 1,
                      end: 1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: TrainColors.violet,
                          // A ring in the ground colour so the dot reads as a
                          // badge lifted off the glass, not a stray pixel.
                          border: Border.fromBorderSide(
                            BorderSide(color: TrainColors.base, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The shared skin for header controls: a flat glass circle inside a
/// hairline. No gradient, no shadow — the screen's single radial glow is
/// what gives this surface its depth.
BoxDecoration _glassDecoration() => BoxDecoration(
  shape: BoxShape.circle,
  color: TrainColors.glassSoft,
  border: Border.fromBorderSide(BorderSide(color: TrainColors.liftAt(0.09))),
);
