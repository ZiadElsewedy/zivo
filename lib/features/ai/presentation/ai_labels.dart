import 'package:flutter/widgets.dart';

import '../../../l10n/l10n.dart';
import '../domain/ai_response_style.dart';

/// The words the AI domain's stored ids wear on screen.
///
/// `responseStyleLabel` lived in `domain/ai_response_style.dart` and could only
/// ever return English: the domain layer is Flutter-free, so there is no
/// [BuildContext] there to read a translation from. The reply-style menu on the
/// Ask header was therefore three English words — Concise / Balanced / Detailed
/// — sitting in an otherwise fully Arabic screen.
///
/// The split is the one `diet_labels.dart` and `workout_labels.dart` already
/// use: `'concise'` stays a persisted **id** (it goes to Firestore and on to
/// the gateway's `RESPONSE_STYLE_DIRECTIVES`, and must not change with the UI
/// language), and its *word* is chosen here, where a context exists.
String responseStyleText(BuildContext context, String style) =>
    switch (validResponseStyle(style)) {
      'concise' => l(context).askReplyStyleConcise,
      'detailed' => l(context).askReplyStyleDetailed,
      _ => l(context).askReplyStyleBalanced,
    };
