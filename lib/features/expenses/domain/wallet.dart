/// The user's running cash balance — set once, then adjusted automatically as
/// expenses are added, edited, or removed (see `ExpensesService`).
class Wallet {
  const Wallet({
    required this.balanceMinor,
    required this.currency,
    required this.updatedAt,
  });

  final int balanceMinor; // may go negative — overspending is shown, not blocked
  final String currency;
  final DateTime updatedAt;

  Wallet copyWith({int? balanceMinor, String? currency, DateTime? updatedAt}) {
    return Wallet(
      balanceMinor: balanceMinor ?? this.balanceMinor,
      currency: currency ?? this.currency,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
