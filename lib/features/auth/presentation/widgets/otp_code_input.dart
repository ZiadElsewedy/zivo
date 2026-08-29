import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';

/// A premium 6-digit verification-code field.
///
/// Design: a *single* hidden text field backs the whole code (so pasting or
/// platform one-time-code autofill drops all six digits in at once), while six
/// separate cells render on top. Tapping anywhere focuses the field; the caret
/// is drawn in the active cell. Fires [onCompleted] the moment the last digit
/// lands, and [onChanged] on every edit.
///
/// The field advertises [AutofillHints.oneTimeCode] and must sit inside an
/// [AutofillGroup] (the page provides one) so iOS/Android can offer the SMS/
/// email code from the keyboard — we never read the clipboard or the message
/// ourselves.
class OtpCodeInput extends StatefulWidget {
  const OtpCodeInput({
    required this.controller,
    required this.focusNode,
    required this.onCompleted,
    this.onChanged,
    this.length = 6,
    this.enabled = true,
    this.hasError = false,
    this.autofocus = true,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Called once, when the field reaches [length] digits.
  final ValueChanged<String> onCompleted;

  /// Called on every change (used to clear a stale error as the user retypes).
  final ValueChanged<String>? onChanged;

  final int length;
  final bool enabled;

  /// Paints the cells in the error tone and triggers a brief shake.
  final bool hasError;

  final bool autofocus;

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<OtpCodeInput>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(covariant OtpCodeInput old) {
    super.didUpdateWidget(old);
    // Shake when we newly enter the error state.
    if (widget.hasError && !old.hasError) {
      // Motion + haptic on the same frame — a rejected code is exactly the
      // kind of meaningful, causal moment haptics are for.
      HapticFeedback.mediumImpact();
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
    if (value.length == widget.length) {
      widget.onCompleted(value);
    }
    setState(() {}); // repaint cells + caret
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.length}-digit verification code',
      textField: true,
      value: widget.controller.text,
      child: GestureDetector(
        onTap: () {
          if (widget.enabled) widget.focusNode.requestFocus();
        },
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // The real input, kept effectively invisible but fully functional.
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  showCursor: false,
                  maxLength: widget.length,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  onChanged: _handleChanged,
                  onSubmitted: (v) {
                    if (v.length == widget.length) widget.onCompleted(v);
                  },
                ),
              ),
            ),
            // The visible cells. Ignore pointer so taps reach the field above.
            IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([widget.focusNode, _shake]),
                builder: (context, _) {
                  final dx = _shakeOffset(_shake.value);
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(widget.length, _buildCell),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Damped sine shake, ±8px, settling to zero over three oscillations.
  double _shakeOffset(double t) {
    if (t == 0) return 0;
    const amplitude = 8.0;
    return amplitude * (1 - t) * math.sin(t * 3 * 2 * math.pi);
  }

  /// One code cell.
  ///
  /// Every cell is a real filled surface rather than an outline on the ground:
  /// six hairline rectangles on a near-black screen read as an empty wireframe,
  /// where six warm tiles read as slots waiting to be filled. The active cell
  /// carries the ember border *and* the ember glow — the same light the focused
  /// field and the primary action use — so where you're typing is obvious from
  /// across the screen, and each digit springs in at the moment it lands.
  Widget _buildCell(int i) {
    final text = widget.controller.text;
    final hasFocus = widget.focusNode.hasFocus;
    final filled = i < text.length;
    // The "active" cell is where the next digit will go.
    final isActive =
        hasFocus && i == text.length && text.length < widget.length;

    final Color borderColor;
    final double borderWidth;
    final Color fill;
    if (widget.hasError) {
      borderColor = TrainColors.ember;
      borderWidth = 1.6;
      fill = TrainColors.ember.withValues(alpha: 0.08);
    } else if (isActive) {
      borderColor = TrainColors.ember;
      borderWidth = 1.8;
      fill = TrainColors.raisedStrong;
    } else if (filled) {
      borderColor = TrainColors.hairlineStrong;
      borderWidth = 1.4;
      fill = TrainColors.raisedStrong;
    } else {
      borderColor = TrainColors.hairlineStrong;
      borderWidth = 1.2;
      fill = TrainColors.raised;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: AppMotion.ease,
      width: 48,
      height: 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: isActive && !widget.hasError
            ? const [
                BoxShadow(
                  color: Color(0x33FF5A1F),
                  blurRadius: 20,
                  spreadRadius: -6,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        switchInCurve: AppMotion.ease,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.55, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: filled
            ? Text(
                text[i],
                key: ValueKey('$i:${text[i]}'),
                style: AppText.cardTitle.copyWith(
                  fontSize: 25,
                  color: widget.hasError ? TrainColors.ember : TrainColors.ink,
                ),
              )
            : (isActive
                  ? const _Caret(key: ValueKey('caret'))
                  : const SizedBox.shrink(key: ValueKey('empty'))),
      ),
    );
  }
}

/// A slim blinking caret shown in the active, empty cell.
class _Caret extends StatefulWidget {
  const _Caret({super.key});

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c.drive(Tween(begin: 1.0, end: 0.0)),
      child: Container(
        width: 2,
        height: 26,
        decoration: BoxDecoration(
          color: TrainColors.ember,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
