import 'package:flutter/widgets.dart';

import '../../../l10n/l10n.dart';
import '../domain/media_object.dart';

/// What each [CaptureSource] is called on screen.
///
/// [CaptureSource] itself is persisted by `name`, so the enum is an id and
/// must never become copy — the same split `workout_labels.dart` and
/// `password_rule_labels.dart` make. This is the presentation half.
String captureSourceText(BuildContext context, CaptureSource source) =>
    switch (source) {
      CaptureSource.camera => l(context).captureSourceCamera,
      CaptureSource.library => l(context).captureSourceLibrary,
      CaptureSource.unknown => l(context).captureSourceUnknown,
    };
