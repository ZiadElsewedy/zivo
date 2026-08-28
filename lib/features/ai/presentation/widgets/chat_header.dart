import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../domain/ai_response_style.dart';

/// The Ask screen's header: the screen title beside three uniform glass
/// circle actions — reply style, chat history, new chat — all drawn from the
/// app's single Lucide vocabulary so they sit consistently with every other
/// surface.
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
    required this.responseStyle,
    required this.onSelectStyle,
  });

  /// Starts a new chat session. Null (disabled) while a turn is in flight.
  final VoidCallback? onNewChat;

  /// Opens the sessions bottom sheet. Null (disabled) while a turn is in
  /// flight.
  final VoidCallback? onSessions;

  /// The current reply-length preference, for the style menu's checkmark.
  final String responseStyle;

  /// Persists a newly-picked reply-length preference.
  final void Function(String style) onSelectStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.base,
        AppSpacing.s + 4,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Ask',
              style: TrainType.ui(
                size: 27,
                weight: FontWeight.w800,
                tracking: -0.025,
                color: TrainColors.ink,
                height: 1,
              ),
            ),
          ),
          _ReplyStyleMenu(
            responseStyle: responseStyle,
            onSelect: onSelectStyle,
            enabled: onSessions != null,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            key: const Key('header-history'),
            icon: AppIcons.history,
            tooltip: 'Chat history',
            onTap: onSessions,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            key: const Key('header-new-chat'),
            icon: AppIcons.chatNew,
            tooltip: 'New chat',
            onTap: onNewChat,
          ),
        ],
      ),
    );
  }
}

/// One uniform glass squircle in the header row. The premium treatment:
/// a lit-from-above gradient fill (warm charcoal catching light at the top
/// edge), hairline outline, soft contact shadow for real lift, a Lucide
/// glyph, instant press-down scale, and a light haptic on commit. Disabled
/// while a turn is in flight.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

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
              child: Container(
                width: 38,
                height: 38,
                decoration: _glassDecoration(),
                child: Icon(
                  icon,
                  size: 16,
                  color: disabled ? TrainColors.ink4 : const Color(0xB2F4F4F0),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The shared "glass squircle" skin for header controls: a diagonal gradient
/// from a raised warm charcoal down to card, a hairline edge, a faint top
/// sheen as if lit from above, and a low soft shadow that lifts it off the
/// chat's aurora background.
/// The shared skin for header controls: a flat glass circle inside a
/// hairline. No gradient, no shadow — the screen's single radial glow is
/// what gives this surface its depth.
BoxDecoration _glassDecoration() => const BoxDecoration(
  shape: BoxShape.circle,
  color: Color(0x0AFFFFFF),
  border: Border.fromBorderSide(BorderSide(color: Color(0x17FFFFFF))),
);

/// The reply-length picker: a glass squircle opening a small ZIVO-styled
/// menu (Concise / Balanced / Detailed), persisted via [onSelect]. The
/// current choice carries an iris checkmark.
class _ReplyStyleMenu extends StatelessWidget {
  const _ReplyStyleMenu({
    required this.responseStyle,
    required this.onSelect,
    required this.enabled,
  });

  final String responseStyle;
  final void Function(String style) onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('header-style'),
      tooltip: 'Reply style',
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.hairline),
      ),
      position: PopupMenuPosition.under,
      onSelected: onSelect,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          width: 38,
          height: 38,
          decoration: _glassDecoration(),
          child: const Icon(
            AppIcons.replyStyle,
            size: 16,
            color: Color(0xB2F4F4F0),
          ),
        ),
      ),
      itemBuilder: (context) => [
        for (final style in kResponseStyles)
          PopupMenuItem<String>(
            value: style,
            height: 42,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    responseStyleLabel(style),
                    style: AppText.rowTitle.copyWith(
                      fontSize: 15,
                      fontWeight: style == responseStyle
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: style == responseStyle
                          ? AppColors.ink
                          : AppColors.ink2,
                    ),
                  ),
                ),
                if (style == responseStyle)
                  const Icon(AppIcons.check, size: 15, color: AppColors.iris),
              ],
            ),
          ),
      ],
    );
  }
}
