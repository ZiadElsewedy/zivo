/// A single password requirement: a human-readable [label] and a [test] that
/// reports whether a candidate password satisfies it.
///
/// Pure and Firebase-free so the policy is unit-testable and reusable by any
/// UI that wants to render a live requirement checklist.
class PasswordRule {
  const PasswordRule(this.label, this.test, {String? shortLabel})
    : shortLabel = shortLabel ?? label;

  /// The full requirement, as a sentence — for screen readers and any UI with
  /// a line to spare.
  final String label;

  /// A chip-sized form of [label] ("Uppercase" for "One uppercase letter").
  /// Requirement UI that lays the rules out inline needs a form that fits a
  /// pill; defaults to [label] for a rule that doesn't declare one.
  final String shortLabel;

  final bool Function(String password) test;

  bool isSatisfiedBy(String password) => test(password);
}

/// The strong password policy enforced when a user creates a ZIVO account.
///
/// Sign-in intentionally does not apply this policy — existing accounts may
/// predate it, and the server remains the trust boundary for sign-in.
abstract final class PasswordPolicy {
  static final List<PasswordRule> rules = [
    PasswordRule(
      'At least 8 characters',
      (p) => p.length >= 8,
      shortLabel: '8+ characters',
    ),
    PasswordRule(
      'One uppercase letter',
      (p) => p.contains(RegExp('[A-Z]')),
      shortLabel: 'Uppercase',
    ),
    PasswordRule(
      'One lowercase letter',
      (p) => p.contains(RegExp('[a-z]')),
      shortLabel: 'Lowercase',
    ),
    PasswordRule(
      'One number',
      (p) => p.contains(RegExp('[0-9]')),
      shortLabel: 'Number',
    ),
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
