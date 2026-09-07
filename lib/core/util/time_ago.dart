import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';

/// A compact relative label, e.g. "now", "5m", "3h", "2d".
///
/// Takes a [BuildContext] because those four words are **copy**, not a format:
/// they were four English string literals, and an Arabic sessions sheet showed
/// a chat updated seconds ago as "now" beside an otherwise fully translated
/// row. The thresholds are the same in every language; only the words change.
String timeAgo(BuildContext context, DateTime t, DateTime now) {
  final d = now.difference(t);
  final s = l(context);
  if (d.inMinutes < 1) return s.timeAgoNow;
  if (d.inMinutes < 60) return s.timeAgoMinutes(d.inMinutes);
  if (d.inHours < 24) return s.timeAgoHours(d.inHours);
  return s.timeAgoDays(d.inDays);
}
