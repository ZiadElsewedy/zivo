import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

/// The one ZIVO auth input — used by sign-in, sign-up, password reset, change
/// password, and the deletion sheet, so every field in the product's most
/// trust-sensitive flow reads identically.
///
/// Three pieces of craft carry it:
///
/// - **The label floats, it doesn't vanish.** A placeholder-only field throws
///   away its own label the moment you type — on a screen of three identical
///   lock rows that's the difference between a form and a guess. Here the
///   label rises into a tracked caption above the value on focus/fill, so the
///   field always says what it holds.
/// - **Focus is lit, not outlined.** The fill lifts a surface step, the icon
///   and label take the ember tint, and the pill sits in a soft ember glow —
///   the same light the primary action casts. A 1px stroke alone reads as a
///   wireframe; light reads as a material.
/// - **Passwords can be revealed.** Obscured fields carry a reveal toggle with
///   its own 44pt target and a selection tick, because typing a password you
///   can't check is the single most common source of a failed submit.
///
/// Exactly one [TextField] lives inside, and it owns the text — the chrome is
/// painted around it rather than through `InputDecoration`, which is what
/// makes the floating label and the glow possible.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.enabled,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
    this.focusNode,
    this.hasError = false,
    super.key,
  });

  final TextEditingController controller;

  /// Doubles as the placeholder (empty + unfocused) and the floating label.
  final String hint;
  final IconData icon;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Paints the field in the error tone (border + label), for a field the
  /// caller knows is the cause of a visible failure.
  final bool hasError;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  static const double _height = 64;

  /// The label/value column's own box, comfortably inside [_height] less its
  /// border so the border width animating (1.4 → 1.6) can't resize the text.
  static const double _innerHeight = 60;
  static const Duration _shift = Duration(milliseconds: 200);

  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  bool _ownsFocusNode = false;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focus.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    if (_ownsFocusNode) _focus.dispose();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  /// Focus and emptiness are the only two things the chrome reads, so a
  /// repaint on either is all this needs — the [TextField] owns the text.
  void _onFocusChanged() => setState(() {});
  void _onTextChanged() => setState(() {});

  void _toggleReveal() {
    HapticFeedback.selectionClick();
    setState(() => _revealed = !_revealed);
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final float = focused || widget.controller.text.isNotEmpty;

    final Color edge;
    final double edgeWidth;
    if (widget.hasError) {
      edge = AppColors.flare;
      edgeWidth = 1.6;
    } else if (focused) {
      edge = AppColors.ember;
      edgeWidth = 1.6;
    } else {
      edge = AppColors.hairline2;
      edgeWidth = 1.4;
    }

    final accent = widget.hasError
        ? AppColors.flareText
        : focused
            ? AppColors.emberText
            : AppColors.ink3;

    return Opacity(
      opacity: widget.enabled ? 1 : 0.55,
      child: AnimatedContainer(
        duration: _shift,
        curve: AppMotion.ease,
        height: _height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: focused ? AppColors.surfaceRaised : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: edge, width: edgeWidth),
          // The focus glow — the field catching the same light as the CTA.
          boxShadow: focused && !widget.hasError
              ? const [
                  BoxShadow(
                    color: Color(0x2EFF5A1F),
                    blurRadius: 22,
                    spreadRadius: -6,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: accent),
              duration: _shift,
              curve: AppMotion.ease,
              builder: (context, color, _) =>
                  Icon(widget.icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            // A fixed inner height, not a stretched one: the icon and the
            // reveal target keep their own sizes while the label/value stack
            // gets the definite box its positioning needs.
            Expanded(
              child: SizedBox(
                height: _innerHeight,
                child: _labelledField(float: float, accent: accent),
              ),
            ),
            if (widget.obscureText)
              _RevealToggle(
                revealed: _revealed,
                enabled: widget.enabled,
                onTap: _toggleReveal,
                label: widget.hint,
              ),
          ],
        ),
      ),
    );
  }

  /// The label and the value share one box: the label sits centred as a
  /// placeholder while the field is empty and idle, and rises to a tracked
  /// caption the moment either changes. Both transitions are the same curve,
  /// so the label reads as one object moving rather than two swapping.
  Widget _labelledField({required bool float, required Color accent}) {
    return Stack(
      children: [
        // [AnimatedPositioned] has to be the Stack's direct child, so the
        // pointer-transparency wraps its contents rather than the widget.
        AnimatedPositioned(
          duration: _shift,
          curve: AppMotion.ease,
          left: 0,
          right: 0,
          top: float ? 10 : 19,
          child: IgnorePointer(
            child: AnimatedDefaultTextStyle(
              duration: _shift,
              curve: AppMotion.ease,
              style: float
                  ? AppText.sectionLabel.copyWith(
                      fontSize: 10.5,
                      letterSpacing: 0.9,
                      color: accent,
                    )
                  : AppText.rowTitle.copyWith(color: AppColors.ink3),
              child: Text(
                widget.hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 26,
          bottom: 6,
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            enabled: widget.enabled,
            obscureText: widget.obscureText && !_revealed,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            autofocus: widget.autofocus,
            autocorrect: false,
            // Keyed off the declared kind, not the reveal state — revealing a
            // password must never start offering it to the suggestion strip.
            enableSuggestions: !widget.obscureText,
            style: AppText.rowTitle,
            cursorColor: AppColors.ember,
            cursorWidth: 2,
            cursorRadius: const Radius.circular(1),
            textAlignVertical: TextAlignVertical.center,
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }
}

/// The show/hide control for an obscured field. A plain [InkWell] rather than
/// an [IconButton] so it keeps the field's own rhythm, padded out to a 44pt
/// target and given the field's name so it doesn't announce as a bare "show".
class _RevealToggle extends StatelessWidget {
  const _RevealToggle({
    required this.revealed,
    required this.enabled,
    required this.onTap,
    required this.label,
  });

  final bool revealed;
  final bool enabled;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: revealed ? 'Hide $label' : 'Show $label',
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: AppMotion.ease,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.7, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: Icon(
              revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              key: ValueKey(revealed),
              size: 19,
              color: AppColors.ink3,
            ),
          ),
        ),
      ),
    );
  }
}
