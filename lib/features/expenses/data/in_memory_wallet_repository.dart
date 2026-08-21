import 'dart:async';

import '../domain/wallet.dart';
import '../domain/wallet_repository.dart';

/// Demo store: keeps the wallet balance in memory. Unset until the user
/// chooses a starting amount, matching production's first-run state.
class InMemoryWalletRepository implements WalletRepository {
  Wallet? _current;
  final StreamController<Wallet?> _controller =
      StreamController<Wallet?>.broadcast();

  @override
  Wallet? get current => _current;

  @override
  Stream<Wallet?> watch() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> setBalance(int minor, {String currency = 'EGP'}) async {
    _current = Wallet(
      balanceMinor: minor,
      currency: currency,
      updatedAt: DateTime.now(),
    );
    _controller.add(_current);
  }

  @override
  Future<void> adjustBy(int deltaMinor) async {
    final wallet = _current;
    if (wallet == null) return;
    _current = wallet.copyWith(
      balanceMinor: wallet.balanceMinor + deltaMinor,
      updatedAt: DateTime.now(),
    );
    _controller.add(_current);
  }

  void dispose() => _controller.close();
}
