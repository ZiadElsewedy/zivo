import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../core/util/bidi.dart';
import '../../../core/util/date_format.dart';
import '../../../core/util/time_ago.dart';
import '../../../l10n/l10n.dart';
import '../../ai/presentation/ai_labels.dart';
import '../domain/admin_models.dart';

/// The words and number formats of the Admin Console. Event names and usage
/// keys are ids from the server (`functions/admin/events.js`) — never shown
/// raw; an unknown one reads as a generic label so a newer backend is safe.
String adminEventLabel(BuildContext context, String name) {
  final s = l(context);
  return switch (name) {
    'account_created' => s.adminEventAccountCreated,
    'app_opened' => s.adminEventAppOpened,
    'workout_plan_created' => s.adminEventPlanCreated,
    'workout_started' => s.adminEventWorkoutStarted,
    'workout_completed' => s.adminEventWorkoutCompleted,
    'workout_abandoned' => s.adminEventWorkoutAbandoned,
    'workout_voided' => s.adminEventWorkoutVoided,
    'ai_request' => s.adminEventAiRequest,
    'diet_imported' => s.adminEventDietImported,
    'diet_plan_created' => s.adminEventDietCreated,
    'account_disabled' => s.adminEventDisabled,
    'account_enabled' => s.adminEventEnabled,
    'account_deleted' => s.adminEventDeleted,
    _ => s.adminEventOther,
  };
}

/// A usage counter's label: `ai_<feature>` reuses the AI usage page's
/// feature words; the rest map to their event.
String adminUsageLabel(BuildContext context, String key) {
  if (key.startsWith('ai_')) return aiFeatureText(context, key.substring(3));
  return switch (key) {
    'app_opened' => l(context).adminFieldAppOpens,
    'diet_imported' => l(context).adminFieldDietImports,
    _ => adminEventLabel(context, key),
  };
}

/// Platform ids as people say them. Brand names — not translated.
String adminPlatformLabel(String? platform) => switch (platform) {
  'ios' => 'iOS',
  'android' => 'Android',
  'macos' => 'macOS',
  'web' => 'Web',
  'windows' => 'Windows',
  'linux' => 'Linux',
  null || '' => '—',
  _ => platform,
};

/// The platforms offered as filters.
const adminPlatforms = ['ios', 'android', 'macos', 'web'];

/// Sign-in provider ids → names. Brand names — not translated.
String adminProviderLabel(String id) => switch (id) {
  'password' => 'Email',
  'google.com' => 'Google',
  'apple.com' => 'Apple',
  _ => id,
};

/// `12,480`, pinned left-to-right.
String adminCount(BuildContext context, num n) =>
    ltrFor(context, NumberFormat.decimalPattern('en').format(n));

/// `1.2M` for token counts.
String adminCompact(BuildContext context, num n) =>
    ltrFor(context, NumberFormat.compact(locale: 'en').format(n));

/// `$4.21` — an estimate, so two decimals at most.
String adminUsd(BuildContext context, double usd) => ltrFor(
  context,
  NumberFormat.currency(
    locale: 'en',
    symbol: r'$',
    decimalDigits: usd >= 100 ? 0 : 2,
  ).format(usd),
);

/// A date, or "Never".
String adminDate(BuildContext context, DateTime? d) =>
    d == null ? l(context).adminNever : formatDayMonthYear(context, d);

/// "3h" style relative time, or "Never".
String adminAgo(BuildContext context, DateTime? d) =>
    d == null ? l(context).adminNever : timeAgo(context, d, DateTime.now());

/// A display name that is never blank.
String adminName(BuildContext context, AdminUserRow u) {
  final name = u.displayName?.trim();
  return name == null || name.isEmpty ? l(context).adminUnnamed : isolate(name);
}

/// The one-line detail an event carries (duration, platform, AI feature).
String? adminEventDetail(BuildContext context, AdminActivityEvent e) {
  final p = e.props;
  switch (e.name) {
    case 'workout_completed':
      final m = p['durationMinutes'];
      return m is num ? l(context).adminEventMinutes(m.round()) : null;
    case 'app_opened':
      final parts = [
        if (p['platform'] is String)
          adminPlatformLabel(p['platform'] as String),
        if (p['appVersion'] is String)
          ltrFor(context, p['appVersion'] as String),
      ];
      return parts.isEmpty ? null : parts.join(' ');
    case 'ai_request':
      final feature = p['feature'] is String
          ? aiFeatureText(context, p['feature'] as String)
          : null;
      final tokens =
          (p['tokensIn'] is num ? p['tokensIn'] as num : 0) +
          (p['tokensOut'] is num ? p['tokensOut'] as num : 0);
      return [
        ?feature,
        if (tokens > 0)
          l(context).adminEventTokens(adminCompact(context, tokens)),
      ].join(', ');
    default:
      return null;
  }
}
