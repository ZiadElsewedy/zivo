import 'package:flutter/widgets.dart';

import '../../../l10n/l10n.dart';
import '../domain/password_policy.dart';

/// What each [PasswordRuleId] says to a reader.
///
/// The policy itself is a set of ids and predicates in `domain/` — it has to
/// be, because a `RegExp` that decides whether a password is acceptable must
/// not depend on the language the app happens to be in. The sentences live
/// here, which is also the only layer that has a `BuildContext` to read them
/// with. Same split as `workout_labels.dart` and `diet_labels.dart`.
///
/// [passwordRuleText] is the full sentence, for a screen reader or a line with
/// room; [passwordRuleShortText] is the chip-sized form the inline checklist
/// lays out in a pill.
String passwordRuleText(BuildContext context, PasswordRuleId id) =>
    switch (id) {
      PasswordRuleId.minLength => l(context).authRuleMinLength,
      PasswordRuleId.uppercase => l(context).authRuleUppercase,
      PasswordRuleId.lowercase => l(context).authRuleLowercase,
      PasswordRuleId.number => l(context).authRuleNumber,
    };

String passwordRuleShortText(BuildContext context, PasswordRuleId id) =>
    switch (id) {
      PasswordRuleId.minLength => l(context).authRuleMinLengthShort,
      PasswordRuleId.uppercase => l(context).authRuleUppercaseShort,
      PasswordRuleId.lowercase => l(context).authRuleLowercaseShort,
      PasswordRuleId.number => l(context).authRuleNumberShort,
    };
