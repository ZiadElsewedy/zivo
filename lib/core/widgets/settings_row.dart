import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';
import '../theme/train_tokens.dart';
import 'pressable_scale.dart';
import 'train_surfaces.dart';

/// A grouped, hairline-divided list of [SettingsRow]s under a mono uppercase
/// [label] — the iOS Settings "inset grouped" pattern in the design handoff's
/// material: a 1px hairline over a barely-there fill, with each rule inset
/// past the icon column so it starts at the row's title.
///
/// Shared by You, Settings, and Settings' own sub-pages, which is why it
/// carries the handoff's list-row spec directly rather than each page
/// re-deriving it.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    required this.label,
    required this.children,
    super.key,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: TrainSectionLabel(label),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0x08FFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: TrainColors.hairline),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// One row inside a [SettingsSectionCard]: a leading 32px icon tile, a title,
/// a right-aligned mono value, and either a custom [trailing] widget or (when
/// [onTap] is set) a chevron.
///
/// **There is no icon tile.** The mark is a bare glyph in a fixed-width
/// column. This row carried a 32px tinted plate for several revisions — first
/// a saturated gradient chip, then a flat single-hue tint — and the plate was
/// always the weakest thing on the page: nine rounded rectangles down the left
/// edge that carry no information the glyph beside them doesn't already carry.
/// The identity doc rules out multi-hue saturated icon tiles outright (§8);
/// dropping the plate finishes that thought rather than softening it. It is
/// also what the restrained end of this category actually does — iOS 18
/// Settings, Linear, Things all set a bare glyph against the row.
///
/// A bare glyph needs more ink than a plated one did, because it no longer has
/// a tint behind it doing half the work of separating it from the ground —
/// hence [_markInk] at ~76% rather than the old `ink2` at 45%.
///
/// [accent] recolours the glyph, and is now reserved for the two hues that
/// mean something: **ember on a destructive row**, amber on the one sign-in
/// mark that owns a hue. The decorative violet every second row used to carry
/// is gone — a column that alternates violet and neutral with no rule behind
/// it reads arbitrary, which is the opposite of considered.
///
/// Dividers are inset past the icon column ([_iconColumn]), so each row's mark
/// reads as the start of its own line.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    this.iconWidget,
    this.trailing,
    this.onTap,
    this.accent,
    this.monospace = false,
    this.last = false,
    super.key,
  });

  final IconData icon;

  /// Optional custom mark shown inside the leading tile instead of [icon]
  /// (e.g. a brand logo like the Google or Google Drive mark).
  final Widget? iconWidget;
  final String title;

  /// The right-aligned value. Pass **`''` when [trailing] is a control that
  /// already shows the state** — a `Switch` next to the word "On" says the
  /// same thing twice, and the text competes with [title] for the width,
  /// which truncates it on a phone.
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The row's identity hue. Null keeps the neutral tile.
  final Color? accent;

  /// Retained for call sites that used it; every value is mono now — figures
  /// are instruments (identity §1.2) — so it no longer changes anything.
  final bool monospace;
  final bool last;

  /// The glyph's own ink when the row has no [accent]. Brighter than `ink2`,
  /// which was tuned for a glyph sitting on a tinted plate; with the plate
  /// gone the mark has to hold the column on its own, and at 45% it read as a
  /// smudge rather than a drawn thing.
  static const _markInk = Color(0xC2F4F4F0); // .76

  /// Width of the leading mark's column. Fixed, so glyphs of different natural
  /// widths still line the titles up with each other.
  static const _markWidth = 24.0;

  /// Where the inset hairline starts: the row's left padding plus the mark
  /// column plus the gap — i.e. exactly under the title. Local rather than
  /// `TrainListRow.dividerInset`, because that row still leads with a 32px
  /// tile and the two geometries are no longer the same.
  static const _iconColumn = 17.0 + _markWidth + 14.0;

  @override
  Widget build(BuildContext context) {
    final editable = onTap != null;

    // 20px bare, where the plated glyph was 17. Nothing is boxing it in any
    // more, and a thin Regular stroke needs the extra size to read as drawn
    // (see `AppIcons` on why the set is Regular and not Bold).
    final mark = SizedBox(
      width: _markWidth,
      child: Center(
        child:
            iconWidget ?? Icon(icon, size: 20, color: accent ?? _markInk),
      ),
    );

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 17),
          child: Row(
            children: [
              mark,
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.ui(
                    size: 15,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                    height: 1.1,
                  ),
                ),
              ),
              if (value.isNotEmpty)
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TrainType.mono(
                      size: 12.5,
                      color: TrainColors.ink4,
                      height: 1.2,
                    ),
                  ),
                ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (editable) ...[
                const SizedBox(width: 8),
                const Icon(
                  AppIcons.chevron,
                  size: 15,
                  color: Color(0x40F4F4F0),
                ),
              ],
            ],
          ),
        ),
        // Inset hairline — starts at the title, not the card edge. Directional,
        // because "the title" is on the right under RTL.
        if (!last)
          const Padding(
            padding: EdgeInsetsDirectional.only(start: _iconColumn),
            child: Divider(
              height: 1,
              thickness: 1,
              color: TrainColors.hairline,
            ),
          ),
      ],
    );

    if (!editable) return content;
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap!();
          },
          child: content,
        ),
      ),
    );
  }
}
