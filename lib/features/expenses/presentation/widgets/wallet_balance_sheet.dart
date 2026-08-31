import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/money.dart';
import 'amount_keypad.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';

enum WalletSheetMode { setBalance, topUp }

/// Bottom sheet for entering a wallet amount — either recalibrating the exact
/// balance ("I currently have X") or adding funds ("top up"). Reuses the same
/// [AmountKeypad] as expense capture.
class WalletBalanceSheet extends StatefulWidget {
  const WalletBalanceSheet({
    required this.mode,
    this.prefillMinor,
    this.currency = 'EGP',
    super.key,
  });

  final WalletSheetMode mode;
  final int? prefillMinor;
  final String currency;

  static Future<void> show(
    BuildContext context, {
    required WalletSheetMode mode,
    int? prefillMinor,
    String currency = 'EGP',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: TrainColors.raised,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => WalletBalanceSheet(
        mode: mode,
        prefillMinor: prefillMinor,
        currency: currency,
      ),
    );
  }

  @override
  State<WalletBalanceSheet> createState() => _WalletBalanceSheetState();
}

class _WalletBalanceSheetState extends State<WalletBalanceSheet> {
  late String _digits = widget.prefillMinor != null && widget.prefillMinor! > 0
      ? formatAmount(widget.prefillMinor!)
      : '';

  int get _amountMinor => parseMinor(_digits);
  bool get _canSave =>
      _amountMinor > 0 || widget.mode == WalletSheetMode.setBalance;

  void _onKey(KeypadKey key) {
    setState(() {
      switch (key) {
        case KeypadKey.backspace:
          if (_digits.isNotEmpty) {
            _digits = _digits.substring(0, _digits.length - 1);
          }
        case KeypadKey.dot:
          if (!_digits.contains('.') && _digits.isNotEmpty) _digits += '.';
        case KeypadKey.digit:
          break;
      }
    });
  }

  void _onDigit(String d) {
    setState(() {
      if (_digits.contains('.')) {
        final decimals = _digits.split('.')[1];
        if (decimals.length >= 2) return;
      }
      _digits = _digits == '0' ? d : _digits + d;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final service = AppScope.of(context).expensesService;
    if (widget.mode == WalletSheetMode.setBalance) {
      await service.setWalletBalance(_amountMinor, currency: widget.currency);
    } else {
      await service.topUpWallet(_amountMinor);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isSet = widget.mode == WalletSheetMode.setBalance;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: TrainColors.hairlineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            isSet ? l(context).walletSetBalanceTitle : l(context).walletTopUpTitle,
            style: AppText.cardTitle.copyWith(fontSize: 19),
          ),
          const SizedBox(height: 4),
          Text(
            isSet
                ? l(context).walletHowMuchNow
                : l(context).walletHowMuchAdding,
            style: AppText.body.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _digits.isEmpty ? '0' : _digits,
                style: AppText.heroNumber.copyWith(
                  fontSize: 52,
                  color: _digits.isEmpty ? TrainColors.ink3 : TrainColors.ink,
                ),
              ),
              Container(
                width: 3,
                height: 42,
                margin: const EdgeInsets.only(left: 5),
                decoration: BoxDecoration(
                  color: TrainColors.amber,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(widget.currency, style: AppText.sectionLabel),
          const SizedBox(height: 14),
          AmountKeypad(onDigit: _onDigit, onKey: _onKey),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _SaveButton(
              enabled: _canSave,
              label: isSet ? l(context).walletSaveBalance : l(context).walletAddFunds,
              onTap: _save,
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: TrainColors.amber,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppText.button.copyWith(
                fontSize: 16,
                color: const Color(0xFF2A2205),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
