/// Which requirement a [PasswordRule] states.
///
/// An **id**, not a label. The rule used to carry its own English sentence,
/// which made the checklist untranslatable without moving the policy into the
/// widget layer — and would have put a screen-reader string in `domain/`. Ids
/// travel, labels translate: `presentation/password_rule_labels.dart` turns
/// each of these into the sentence and the chip-sized form a reader sees.
enum PasswordRuleId { minLength, uppercase, lowercase, number }

/// A single password requirement: which rule it is ([id]) and a [test] that
/// reports whether a candidate password satisfies it.
///
/// Pure and Firebase-free so the policy is unit-testable and reusable by any
/// UI that wants to render a live requirement checklist.
class PasswordRule {
  const PasswordRule(this.id, this.test);

  final PasswordRuleId id;

  final bool Function(String password) test;

  bool isSatisfiedBy(String password) => test(password);
}

/// The strong password policy enforced when a user creates a ZIVO account.
///
/// Sign-in intentionally does not apply this policy — existing accounts may
/// predate it, and the server remains the trust boundary for sign-in.
abstract final class PasswordPolicy {
  static final List<PasswordRule> rules = [
    PasswordRule(PasswordRuleId.minLength, (p) => p.length >= 8),
    PasswordRule(PasswordRuleId.uppercase, (p) => p.contains(RegExp('[A-Z]'))),
    PasswordRule(PasswordRuleId.lowercase, (p) => p.contains(RegExp('[a-z]'))),
    PasswordRule(PasswordRuleId.number, (p) => p.contains(RegExp('[0-9]'))),
  ];

  /// The rules [password] does not yet satisfy, in declaration order — handy
  /// for rendering a live requirement list.
  static List<PasswordRule> unmetRules(String password) =>
      rules.where((rule) => !rule.isSatisfiedBy(password)).toList();

  /// How many of [rules] [password] currently satisfies — the strength meter's
  /// only input, so "strength" here means exactly "policy progress" and never
  /// drifts from what [isSatisfiedBy] will accept.
  static int metCount(String password) =>
      rules.where((rule) => rule.isSatisfiedBy(password)).length;

  /// Whether [password] satisfies every rule in [rules].
  static bool isSatisfiedBy(String password) => unmetRules(password).isEmpty;
}
