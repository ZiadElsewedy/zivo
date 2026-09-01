import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/train_tokens.dart';

/// The one way to present a ZIVO modal bottom sheet.
///
/// Before this existed, 28 call sites each spelled out their own
/// `showModalBottomSheet` configuration, and they had drifted: the top radius
/// was 24 in some, 26 in most and 28 in one, and half of them painted the
/// sheet's own background through `backgroundColor`/`shape` while the other
/// half passed `Colors.transparent` and painted a [Container] themselves.
/// The two approaches are not interchangeable — only the transparent one lets
/// a sheet round its own corners over a gradient or run content to the edge —
/// so this presents the transparent variant and lets the body paint itself —
/// with [ZivoSheetSurface] for the ones that used to pass `backgroundColor` +
/// `shape`, and [ZivoSheetHandle] for the drag affordance.
///
/// [isScrollControlled] defaults to true because a sheet that hosts a text
/// field must be able to grow past half the screen when the keyboard opens;
/// the handful of fixed-height sheets pay nothing for it.
Future<T?> showZivoSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  Color? barrierColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    barrierColor: barrierColor,
    builder: builder,
  );
}

/// Just the sheet's surface — the raised background and the rounded top —
/// for a body that already owns its own padding, safe area and keyboard
/// inset.
///
/// This exists for the seven sheets that used to pass `backgroundColor` +
/// `shape` to `showModalBottomSheet` and let the framework's own [Material]
/// paint them: routing them through [showZivoSheet] means the surface has to
/// move inside the builder, and their bodies already handle their own insets.
class ZivoSheetSurface extends StatelessWidget {
  const ZivoSheetSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
      child: ColoredBox(color: TrainColors.raised, child: child),
    );
  }
}

/// The drag affordance at the top of a sheet — the 38×4 pill that was copied
/// verbatim into fourteen files.
class ZivoSheetHandle extends StatelessWidget {
  const ZivoSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 4,
      decoration: BoxDecoration(
        color: TrainColors.hairlineStrong,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}
