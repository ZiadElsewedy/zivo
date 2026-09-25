import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_loading_bar.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/admin_repository.dart';

/// The console's building blocks. The Admin Console is ZIVO's one
/// desktop-first surface, so it keeps the app's materials — the two skins,
/// Manrope for words, Azeret Mono for figures, hairlines for structure — but
/// trades the phone's stacked cards for a working layout: groups separated
/// by rules, figures set large, one accent. Violet is the accent because the
/// console is system/meta (ADR-006 hue ownership); ember appears only on the
/// one destructive action.

/// How much room the console has.
enum AdminSize { compact, medium, expanded }

AdminSize adminSizeOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 1100) return AdminSize.expanded;
  if (w >= 720) return AdminSize.medium;
  return AdminSize.compact;
}

/// The frame of one console page: a title row with optional actions, then
/// the content, left-aligned in a readable measure.
class AdminPageFrame extends StatelessWidget {
  const AdminPageFrame({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.leading,
    this.onRefresh,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final size = adminSizeOf(context);
    final gutter = switch (size) {
      AdminSize.compact => 16.0,
      AdminSize.medium => 28.0,
      AdminSize.expanded => 44.0,
    };
    final list = ListView(
      padding: EdgeInsets.fromLTRB(
        gutter,
        size == AdminSize.compact ? 12 : 36,
        gutter,
        48,
      ),
      children: [
        Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (leading != null) ...[leading!, const SizedBox(height: 14)],
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  runSpacing: 12,
                  spacing: 16,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TrainType.ui(
                            size: size == AdminSize.compact ? 26 : 32,
                            weight: FontWeight.w800,
                            tracking: -0.025,
                            color: TrainColors.ink,
                            height: 1.1,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            subtitle!,
                            style: TrainType.ui(
                              size: 13,
                              weight: FontWeight.w500,
                              color: TrainColors.ink3,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (actions.isNotEmpty)
                      Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                ),
                SizedBox(height: size == AdminSize.compact ? 20 : 32),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
    final refresh = onRefresh;
    if (refresh == null) return list;
    return RefreshIndicator(
      color: TrainColors.violet,
      onRefresh: refresh,
      child: list,
    );
  }
}

/// A titled group, opened by a hairline rule rather than boxed in a card —
/// the console's structure is the rule, not the surface.
class AdminGroup extends StatelessWidget {
  const AdminGroup({
    required this.title,
    required this.child,
    this.trailing,
    this.gap = 18,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: TrainColors.hairlineStrong)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TrainType.ui(
                    size: 14,
                    weight: FontWeight.w700,
                    color: TrainColors.ink2,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: trailing,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: gap),
          child,
        ],
      ),
    );
  }
}

/// A figure: the number set large in mono, what it counts beneath it.
class AdminFigure extends StatelessWidget {
  const AdminFigure({
    required this.value,
    required this.label,
    this.note,
    this.accent,
    this.large = false,
    super.key,
  });

  final String value;
  final String label;
  final String? note;

  /// The hue that owns what this counts (green = training, amber = money);
  /// null keeps it ink.
  final Color? accent;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TrainType.mono(
            size: large ? 34 : 26,
            weight: FontWeight.w500,
            tracking: -0.03,
            color: accent ?? TrainColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TrainType.ui(
            size: 12.5,
            weight: FontWeight.w600,
            color: TrainColors.ink3,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 3),
          Text(
            note!,
            style: TrainType.ui(
              size: 12,
              weight: FontWeight.w500,
              color: TrainColors.ink4,
            ),
          ),
        ],
      ],
    );
  }
}

/// Lays figures out in even columns that wrap on narrow screens.
class AdminFigureGrid extends StatelessWidget {
  const AdminFigureGrid({
    required this.children,
    this.minWidth = 170,
    super.key,
  });

  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columns = (c.maxWidth / minWidth).floor().clamp(
          1,
          children.length,
        );
        final w = (c.maxWidth - (columns - 1) * 24) / columns;
        return Wrap(
          spacing: 24,
          runSpacing: 26,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

/// Active / Suspended.
class AdminStatusBadge extends StatelessWidget {
  const AdminStatusBadge({required this.suspended, super.key});

  final bool suspended;

  @override
  Widget build(BuildContext context) {
    final color = suspended ? TrainColors.ember : TrainColors.ink3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: suspended ? TrainColors.ember : TrainColors.green,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          suspended
              ? l(context).adminStatusSuspended
              : l(context).adminStatusActive,
          style: TrainType.ui(
            size: 12.5,
            weight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// A quiet outlined button for secondary actions.
class AdminButton extends StatelessWidget {
  const AdminButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    this.filled = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? TrainColors.ember : TrainColors.ink;
    final style = TextButton.styleFrom(
      foregroundColor: filled ? TrainColors.base : color,
      backgroundColor: filled ? color : Colors.transparent,
      disabledForegroundColor: TrainColors.ink4,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      minimumSize: const Size(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: filled
            ? BorderSide.none
            : BorderSide(
                color: destructive
                    ? TrainColors.ember.withValues(alpha: 0.45)
                    : TrainColors.hairlineStrong,
              ),
      ),
      textStyle: TrainType.ui(size: 13, weight: FontWeight.w700),
    );
    return icon == null
        ? TextButton(onPressed: onPressed, style: style, child: Text(label))
        : TextButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 17),
            label: Text(label),
          );
  }
}

/// A selectable pill for segments and windows — violet when chosen.
class AdminPill extends StatelessWidget {
  const AdminPill({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? TrainColors.violetWash : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? TrainColors.violet.withValues(alpha: 0.5)
                  : TrainColors.hairlineStrong,
            ),
          ),
          child: Text(
            label,
            style: TrainType.ui(
              size: 12.5,
              weight: FontWeight.w700,
              color: selected ? TrainColors.violetGlyph : TrainColors.ink3,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs [load], shows a thin loading bar while it runs, the failure with a
/// retry when it fails, and [builder] with the result. [reload] re-runs it.
class AdminLoader<T> extends StatefulWidget {
  const AdminLoader({required this.load, required this.builder, super.key});

  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  builder;

  @override
  State<AdminLoader<T>> createState() => _AdminLoaderState<T>();
}

class _AdminLoaderState<T> extends State<AdminLoader<T>> {
  T? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on AdminFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null) {
      return Stack(
        children: [
          widget.builder(context, data, _run),
          if (_loading)
            const Positioned(top: 0, left: 0, right: 0, child: AdminProgress()),
        ],
      );
    }
    if (_loading) {
      return const Align(
        alignment: Alignment.topCenter,
        child: AdminProgress(),
      );
    }
    return AdminErrorView(message: _error ?? '', onRetry: _run);
  }
}

class AdminErrorView extends StatelessWidget {
  const AdminErrorView({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.warning, color: TrainColors.ink3, size: 28),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TrainType.ui(
                size: 14,
                weight: FontWeight.w500,
                color: TrainColors.ink2,
              ),
            ),
            const SizedBox(height: 16),
            AdminButton(label: l(context).adminRetry, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// A label/value line in a detail section.
class AdminField extends StatelessWidget {
  const AdminField({
    required this.label,
    required this.value,
    this.mono = false,
    super.key,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TrainType.ui(
                size: 13,
                weight: FontWeight.w500,
                color: TrainColors.ink3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: SelectableText(
              value,
              style: mono
                  ? TrainType.mono(
                      size: 12.5,
                      color: TrainColors.ink2,
                      height: 1.3,
                    )
                  : TrainType.ui(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: TrainColors.ink,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's loading bar, stretched to the space it is given.
class AdminProgress extends StatelessWidget {
  const AdminProgress({super.key});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, c) => ZivoLoadingBar(width: c.maxWidth));
}
