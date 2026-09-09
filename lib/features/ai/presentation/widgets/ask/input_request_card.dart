import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/util/bidi.dart';
import '../../../../../l10n/l10n.dart';
import '../../../domain/ai_input_request.dart';

/// The Ask elicitation form (Phase 2): a small set of fields the coach asked
/// the user to fill in when it needs a specific value no tool can supply.
/// Submitting sends a readable summary of the entries back as the user's next
/// message (see `AskController.submitInput`) — there is no confirm/cancel, and
/// (Phase 2) the values are not written to the profile.
///
/// Once [submitted] the fields lock and the primary button reads "Sent" — the
/// summary is already on its way as a normal turn.
class InputRequestCard extends StatefulWidget {
  const InputRequestCard({
    required this.request,
    required this.submitted,
    required this.onSubmit,
    super.key,
  });

  final AiInputRequest request;

  /// True once the user has submitted this form this session.
  final bool submitted;

  /// Called with the serialized summary of the entries when the user submits.
  final void Function(String summary) onSubmit;

  @override
  State<InputRequestCard> createState() => _InputRequestCardState();
}

class _InputRequestCardState extends State<InputRequestCard> {
  /// Text-field controllers for number/text fields, keyed by field key.
  final Map<String, TextEditingController> _text = {};

  /// Selected option value for each choice field, keyed by field key.
  final Map<String, String> _picked = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.request.fields) {
      if (f.type != AiInputFieldType.choice) {
        _text[f.key] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The current value for [f] as trimmed text (the picked value for a choice),
  /// or an empty string when unset.
  String _valueOf(AiInputField f) {
    if (f.type == AiInputFieldType.choice) return _picked[f.key] ?? '';
    return _text[f.key]?.text.trim() ?? '';
  }

  /// The label shown for a choice field's current pick (falls back to value).
  String _labelOf(AiInputField f) {
    final v = _picked[f.key];
    if (v == null) return '';
    for (final o in f.options) {
      if (o.value == v) return o.label;
    }
    return v;
  }

  bool get _canSubmit => widget.request.fields
      .where((f) => f.required)
      .every((f) => _valueOf(f).isNotEmpty);

  void _submit() {
    if (!_canSubmit) return;
    final parts = <String>[];
    for (final f in widget.request.fields) {
      final value = f.type == AiInputFieldType.choice
          ? _labelOf(f)
          : _valueOf(f);
      if (value.isEmpty) continue; // skip untouched optional fields
      final unit = (f.unit != null && f.type == AiInputFieldType.number)
          ? ' ${f.unit}'
          : '';
      parts.add('${f.label}: $value$unit');
    }
    widget.onSubmit(parts.join(' · '));
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.submitted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AnimatedSize(
        duration: AppMotion.enter,
        curve: AppMotion.ease,
        alignment: Alignment.topCenter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          decoration: BoxDecoration(
            color: TrainColors.raised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: done
                  ? TrainColors.hairline
                  : TrainColors.ember.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: TrainColors.emberWash,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      AppIcons.ask,
                      size: 18,
                      color: TrainColors.ember,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.request.prompt,
                      textDirection: directionOfFor(
                        context,
                        widget.request.prompt,
                      ),
                      style: AppText.cardTitle.copyWith(
                        fontSize: 17,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (final f in widget.request.fields) ...[
                _FieldLabel(f.label),
                const SizedBox(height: 6),
                _field(f, done),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 2),
              _submitButton(context, done),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(AiInputField f, bool done) {
    if (f.type == AiInputFieldType.choice) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in f.options)
            _MiniChip(
              label: o.label,
              picked: _picked[f.key] == o.value,
              onTap: done
                  ? null
                  : () => setState(() => _picked[f.key] = o.value),
            ),
        ],
      );
    }
    final number = f.type == AiInputFieldType.number;
    return TextField(
      controller: _text[f.key],
      enabled: !done,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
          : null,
      onChanged: (_) => setState(() {}),
      style: AppText.body,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: TrainColors.base,
        suffixText: number ? f.unit : null,
        suffixStyle: AppText.meta.copyWith(color: TrainColors.ink3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: TrainColors.hairlineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: TrainColors.ember.withValues(alpha: 0.5),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: TrainColors.hairline),
        ),
      ),
    );
  }

  Widget _submitButton(BuildContext context, bool done) {
    final enabled = !done && _canSubmit;
    final color = done
        ? TrainColors.emberWash
        : (enabled ? TrainColors.ember : TrainColors.raisedStrong);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: const Key('input-submit'),
          onTap: enabled ? _submit : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            child: done
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppIcons.check,
                        size: 16,
                        color: TrainColors.ember,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l(context).askInputSent,
                        style: AppText.button.copyWith(
                          color: TrainColors.ember,
                        ),
                      ),
                    ],
                  )
                : Text(
                    l(context).askInputSubmit,
                    style: AppText.button.copyWith(
                      color: enabled ? Colors.white : TrainColors.ink3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textDirection: directionOfFor(context, text),
    style: AppText.meta.copyWith(
      color: TrainColors.ink2,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.picked,
    required this.onTap,
  });

  final String label;
  final bool picked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: picked ? TrainColors.emberWash : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: picked
                  ? TrainColors.ember.withValues(alpha: 0.4)
                  : TrainColors.hairlineStrong,
            ),
          ),
          child: Text(
            label,
            style: AppText.button.copyWith(
              color: picked ? TrainColors.ember : TrainColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
