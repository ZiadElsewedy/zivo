/// A single password requirement: a human-readable [label] and a [test] that
/// reports whether a candidate password satisfies it.
///
/// Pure and Firebase-free so the policy is unit-testable and reusable by any
/// UI that wants to render a live requirement checklist.
class PasswordRule {
  const PasswordRule(this.label, this.test);

  final String label;
  final bool Function(String password) test;

  bool isSatisfiedBy(String password) => test(password);
}

/// The strong password policy enforced when a user creates a ZIVO account.
///
/// Sign-in intentionally does not apply this policy — existing accounts may
/// predate it, and the server remains the trust boundary for sign-in.
abstract final class PasswordPolicy {
  static final List<PasswordRule> rules = [
    PasswordRule('At least 8 characters', (p) => p.length >= 8),
    PasswordRule('One uppercase letter', (p) => p.contains(RegExp('[A-Z]'))),
    PasswordRule('One lowercase letter', (p) => p.contains(RegExp('[a-z]'))),
    PasswordRule('One number', (p) => p.contains(RegExp('[0-9]'))),
  ];

  /// The rules [password] does not yet satisfy, in declaration order — handy
  /// for rendering a live checklist.
  static List<PasswordRule> unmetRules(String password) =>
      rules.where((rule) => !rule.isSatisfiedBy(password)).toList();

  /// Whether [password] satisfies every rule in [rules].
  static bool isSatisfiedBy(String password) => unmetRules(password).isEmpty;
}
