import 'wallet.dart';

/// The seam between the app and wallet storage. A single balance per user —
/// `null` until they set a starting amount.
abstract interface class WalletRepository {
  /// Latest snapshot (synchronous, for initial paint).
  Wallet? get current;

  /// Emits the current balance immediately, then again on every change.
  Stream<Wallet?> watch();

  /// Recalibrates to an exact amount — "I currently have X in my wallet".
  Future<void> setBalance(int minor, {String currency = 'EGP'});

  /// Applies a relative change: negative to spend, positive to refund or top
  /// up. If no balance has been set yet, this is a no-op (nothing to adjust).
  Future<void> adjustBy(int deltaMinor);
}
