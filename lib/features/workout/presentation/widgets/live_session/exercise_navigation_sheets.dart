import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/util/bidi.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/widgets/zivo_field.dart';
import '../../../../../core/widgets/zivo_sheet.dart';
import '../../../../../l10n/l10n.dart';
import '../../../domain/analytics/workout_analytics.dart';
import '../../../domain/identity/exercise_choice.dart';
import '../../../domain/identity/exercise_matcher.dart';
import '../../../domain/live_session.dart';
import '../../../domain/session_exercise.dart';

// The three sheets behind the live session's "something else" — the workout
// map, one exercise's options, and the exercise picker.
//
// They share one material: the raised sheet surface, a 22pt title in the
// session's text face, a quiet meta line, and rows that lead with a glyph
// in a fixed 28pt column so every sheet's text starts on the same line.
// Colour carries state only — ember for the exercise you're on, green for
// finished work — never decoration, exactly as on the session screen itself.

/// What can be done to one exercise mid-workout — the answer of
/// [showExerciseActionsSheet], carried out by the page.
enum ExerciseAction {
  doNow,
  doLater,
  swap,
  addSet,
  removeSet,
  skip,
  remove,
}

/// The actions [exercise] allows right now, in the order they're offered.
///
/// Every rule here protects the record: nothing resolved is ever deleted
/// (remove is only for an exercise nothing was logged on, and "remove set"
/// only takes a set still to do), and an exercise with nothing left to do
/// can only take another set.
List<ExerciseAction> actionsFor(LiveSession session, SessionExercise exercise) {
  final pending = exercise.sets.where((s) => s.pending).length;
  final isCurrent = session.currentExercise?.id == exercise.id;
  final owed = session.pendingExercises;
  return [
    if (pending > 0 && !isCurrent) ExerciseAction.doNow,
    if (pending > 0 && owed.length > 1 && owed.last.id != exercise.id)
      ExerciseAction.doLater,
    if (pending > 0) ExerciseAction.swap,
    ExerciseAction.addSet,
    if (pending > 0 && exercise.sets.length > 1) ExerciseAction.removeSet,
    if (pending > 0) ExerciseAction.skip,
    if (exercise.sets.every((s) => s.pending)) ExerciseAction.remove,
  ];
}

// ---- Shared sheet chrome ---------------------------------------------------

/// Handle, title and meta line — the top of every sheet here.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.meta});

  final String title;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: ZivoSheetHandle()),
          const SizedBox(height: 20),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TrainType.ui(
              size: 22,
              weight: FontWeight.w800,
              tracking: -0.02,
              height: 1.15,
              color: TrainColors.ink,
            ),
          ),
          if (meta != null) ...[
            const SizedBox(height: 5),
            Text(
              meta!,
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
          ],
        ],
      ),
    );
  }
}

/// A group of rows on one inset slab, separated by hairlines indented to the
/// text — the grouped-list shape iOS uses for a set of related choices.
class _RowGroup extends StatelessWidget {
  const _RowGroup({required this.children, this.indent = 56});

  final List<Widget> children;

  /// Where the separators start — under the text, past any glyph column.
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: TrainColors.glassSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TrainColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsetsDirectional.only(start: indent),
                child: Container(height: 1, color: TrainColors.hairline),
              ),
            child,
          ],
        ],
      ),
    );
  }
}

/// One tappable row: a glyph in the fixed leading column, a label, and an
/// optional second line.
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.iconColor,
    super.key,
  });

  /// Null for a row that is just a name (the picker's exercises).
  final IconData? icon;
  final String label;
  final String? detail;
  final Color? iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          child: Row(
            children: [
              if (icon != null) ...[
                SizedBox(
                  width: 28,
                  child: Icon(icon, size: 18, color: iconColor ?? TrainColors.ink2),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TrainType.ui(
                        size: 15,
                        weight: FontWeight.w600,
                        color: TrainColors.ink,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail!,
                        style: AppText.meta.copyWith(color: TrainColors.ink3),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "2/4 sets · Chest" — how far along an exercise is and what it trains.
String _exerciseMeta(BuildContext context, SessionExercise e) {
  final resolved = e.sets.where((s) => !s.pending).length;
  final sets = ltrFor(
    context,
    l(context).liveExerciseSetsProgress(resolved, e.sets.length),
  );
  final muscle = e.muscleGroup;
  return muscle == null ? sets : '$sets · ${isolate(muscle)}';
}

// ---- Workout map -----------------------------------------------------------

/// What the workout map was closed with.
sealed class SessionMapResult {
  const SessionMapResult();
}

/// A row was tapped: make that exercise the current one.
class SessionMapJump extends SessionMapResult {
  const SessionMapJump(this.exerciseId);
  final String exerciseId;
}

/// A row's options were opened.
class SessionMapOptions extends SessionMapResult {
  const SessionMapOptions(this.exerciseId);
  final String exerciseId;
}

/// "Add exercise" at the foot of the map.
class SessionMapAdd extends SessionMapResult {
  const SessionMapAdd();
}

/// The whole workout on one sheet — a timeline of every exercise, each with
/// a ring that fills as its sets are done, so where you are and what's left
/// read at a glance, and jumping anywhere is one tap.
Future<SessionMapResult?> showSessionMapSheet(
  BuildContext context, {
  required LiveSession session,
}) => showZivoSheet<SessionMapResult>(
  context: context,
  builder: (_) => ZivoSheetSurface(child: _SessionMapSheet(session: session)),
);

class _SessionMapSheet extends StatelessWidget {
  const _SessionMapSheet({required this.session});

  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final exercises = session.exercises;
    final done = exercises.where((e) => e.sets.every((s) => !s.pending)).length;
    final currentId = session.currentExercise?.id;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(
              title: strings.liveSessionMap,
              meta: strings.liveSessionMapProgress(done, exercises.length),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                // The add row is the timeline's last stop.
                itemCount: exercises.length + 1,
                itemBuilder: (context, i) {
                  if (i == exercises.length) {
                    return _MapAddRow(
                      key: const Key('map-add-exercise'),
                      connectAbove: exercises.isNotEmpty,
                      onTap: () =>
                          Navigator.of(context).pop(const SessionMapAdd()),
                    );
                  }
                  final e = exercises[i];
                  return _MapRow(
                    key: Key('map-row-${e.id}'),
                    index: i,
                    exercise: e,
                    isCurrent: e.id == currentId,
                    connectAbove: i > 0,
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Where an exercise stands, for the map's ring.
enum _MapState { upcoming, current, done, skipped }

class _MapRow extends StatelessWidget {
  const _MapRow({
    required this.index,
    required this.exercise,
    required this.isCurrent,
    required this.connectAbove,
    super.key,
  });

  final int index;
  final SessionExercise exercise;
  final bool isCurrent;
  final bool connectAbove;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final sets = exercise.sets;
    final resolved = sets.where((s) => !s.pending).length;
    final finished = resolved == sets.length;
    final state = isCurrent
        ? _MapState.current
        : finished && sets.isNotEmpty && sets.every((s) => s.skipped)
        ? _MapState.skipped
        : finished
        ? _MapState.done
        : _MapState.upcoming;
    final fraction = sets.isEmpty ? 0.0 : resolved / sets.length;
    return PressableScale(
      scale: 0.99,
      child: Material(
        color: isCurrent ? TrainColors.emberWash : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            // A finished exercise has nothing to jump to — its row opens
            // what it CAN still take (another set).
            Navigator.of(context).pop(
              finished ? SessionMapOptions(exercise.id) : SessionMapJump(exercise.id),
            );
          },
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: _TimelineNode(
                    connectAbove: connectAbove,
                    connectBelow: true,
                    child: _ProgressRing(
                      state: state,
                      fraction: fraction,
                      label: '${index + 1}',
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isolate(exercise.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TrainType.ui(
                          size: 15.5,
                          weight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                          tracking: -0.01,
                          color: state == _MapState.done || state == _MapState.skipped
                              ? TrainColors.ink2
                              : TrainColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        state == _MapState.skipped
                            ? strings.liveSkipped
                            : _exerciseMeta(context, exercise),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.meta.copyWith(
                          color: isCurrent
                              ? TrainColors.ember.withValues(alpha: 0.85)
                              : TrainColors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('map-options-${exercise.id}'),
                  tooltip: strings.liveExerciseOptions,
                  onPressed: () =>
                      Navigator.of(context).pop(SessionMapOptions(exercise.id)),
                  icon: Icon(AppIcons.more, size: 18, color: TrainColors.ink3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The map's last stop: a dashed ring with a plus, on the same line as
/// every ring above it — adding an exercise extends the timeline.
class _MapAddRow extends StatelessWidget {
  const _MapAddRow({
    required this.connectAbove,
    required this.onTap,
    super.key,
  });

  final bool connectAbove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.99,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: _TimelineNode(
                    connectAbove: connectAbove,
                    dashedAbove: true,
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CustomPaint(
                        painter: _DashedCirclePainter(TrainColors.ink4),
                        child: Icon(AppIcons.add, size: 14, color: TrainColors.ink2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  l(context).liveAddExercise,
                  style: TrainType.ui(
                    size: 15,
                    weight: FontWeight.w600,
                    color: TrainColors.ink2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The ring on the timeline's spine: a hairline runs into it from the row
/// above and on to the row below, so the rows read as one sequence.
class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.child,
    required this.connectAbove,
    this.connectBelow = false,
    this.dashedAbove = false,
  });

  final Widget child;
  final bool connectAbove;
  final bool connectBelow;
  final bool dashedAbove;

  @override
  Widget build(BuildContext context) {
    Widget line(bool on, {bool dashed = false}) => Expanded(
      child: on
          ? SizedBox(
              width: 1.5,
              child: dashed
                  ? CustomPaint(
                      painter: _DashedLinePainter(TrainColors.hairlineStrong),
                    )
                  : ColoredBox(color: TrainColors.hairlineStrong),
            )
          : const SizedBox.shrink(),
    );
    return Column(
      children: [
        line(connectAbove, dashed: dashedAbove),
        const SizedBox(height: 4),
        child,
        const SizedBox(height: 4),
        line(connectBelow),
      ],
    );
  }
}

/// Where one exercise stands, drawn: an arc that fills with its resolved
/// sets. Upcoming is a hairline ring with its position; current is ember;
/// done fills solid green with a check; skipped is a muted ring with the
/// skip mark.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.state,
    required this.fraction,
    required this.label,
  });

  final _MapState state;
  final double fraction;
  final String label;

  @override
  Widget build(BuildContext context) {
    const size = 30.0;
    if (state == _MapState.done) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: TrainColors.green, shape: BoxShape.circle),
        child: Icon(AppIcons.check, size: 15, color: TrainColors.onGreen),
      );
    }
    final hue = state == _MapState.current ? TrainColors.ember : TrainColors.green;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          track: state == _MapState.current
              ? TrainColors.ember.withValues(alpha: 0.28)
              : TrainColors.hairlineStrong,
          arc: hue,
          fraction: state == _MapState.skipped ? 0 : fraction,
        ),
        child: Center(
          child: state == _MapState.skipped
              ? Icon(AppIcons.skipExercise, size: 12, color: TrainColors.ink3)
              : Text(
                  label,
                  style: TrainType.mono(
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: state == _MapState.current
                        ? TrainColors.ember
                        : TrainColors.ink2,
                  ),
                ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.track, required this.arc, required this.fraction});

  final Color track;
  final Color arc;
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke / 2);
    canvas.drawOval(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (fraction <= 0) return;
    canvas.drawArc(
      ring,
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.track != track || old.arc != arc || old.fraction != fraction;
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    final ring = (Offset.zero & size).deflate(1);
    const dashes = 14;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(ring, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.color != color;
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width;
    for (var y = 0.0; y < size.height; y += 5) {
      canvas.drawLine(Offset(0, y), Offset(0, math.min(y + 2.5, size.height)), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

// ---- Exercise actions ------------------------------------------------------

/// The options for one exercise, grouped by what they touch: its place in
/// the workout (now · later · swap), its sets, and whether it happens at all.
/// Only what [actionsFor] allows is offered.
Future<ExerciseAction?> showExerciseActionsSheet(
  BuildContext context, {
  required LiveSession session,
  required SessionExercise exercise,
}) {
  final actions = actionsFor(session, exercise).toSet();
  return showZivoSheet<ExerciseAction>(
    context: context,
    builder: (context) {
      final strings = l(context);
      Widget row(ExerciseAction a, IconData icon, String label, {String? detail}) =>
          _SheetRow(
            key: Key('exercise-action-${a.name}'),
            icon: icon,
            label: label,
            detail: detail,
            onTap: () => Navigator.of(context).pop(a),
          );
      final groups = [
        [
          if (actions.contains(ExerciseAction.doNow))
            row(ExerciseAction.doNow, AppIcons.next, strings.liveDoNow),
          if (actions.contains(ExerciseAction.doLater))
            row(ExerciseAction.doLater, AppIcons.doLater, strings.liveDoLater),
          if (actions.contains(ExerciseAction.swap))
            row(
              ExerciseAction.swap,
              AppIcons.swapExercise,
              strings.liveSwapExercise,
            ),
        ],
        [
          if (actions.contains(ExerciseAction.addSet))
            row(ExerciseAction.addSet, AppIcons.add, strings.liveAddSet),
          if (actions.contains(ExerciseAction.removeSet))
            row(ExerciseAction.removeSet, AppIcons.minus, strings.liveRemoveSet),
        ],
        [
          if (actions.contains(ExerciseAction.skip))
            row(
              ExerciseAction.skip,
              AppIcons.skipExercise,
              strings.liveSkipExercise,
            ),
          if (actions.contains(ExerciseAction.remove))
            row(ExerciseAction.remove, AppIcons.trash, strings.liveRemoveExercise),
        ],
      ].where((g) => g.isNotEmpty).toList();
      return ZivoSheetSurface(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHeader(
                  title: isolate(exercise.name),
                  meta: _exerciseMeta(context, exercise),
                ),
                const SizedBox(height: 18),
                for (final (i, g) in groups.indexed) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _RowGroup(children: g),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ---- Exercise picker -------------------------------------------------------

/// Picks an exercise to add or swap in: the user's own exercises (library
/// and splits, one row per identity), filtered as they type, plus an "Add"
/// row for a name they don't have yet. When swapping, exercises for the
/// same muscle come first — the substitute you want is almost always one.
///
/// A typed name comes back without an id — whether it is an exercise they
/// already have is [resolveExerciseChoice]'s call, not the picker's.
Future<ExerciseChoice?> showExercisePickerSheet(
  BuildContext context, {
  required List<ExerciseChoice> candidates,
  String? swappingName,
  String? swappingMuscle,
}) => showZivoSheet<ExerciseChoice>(
  context: context,
  builder: (_) => ZivoSheetSurface(
    child: _ExercisePicker(
      candidates: candidates,
      swappingName: swappingName,
      swappingMuscle: swappingMuscle,
    ),
  ),
);

class _ExercisePicker extends StatefulWidget {
  const _ExercisePicker({
    required this.candidates,
    this.swappingName,
    this.swappingMuscle,
  });

  final List<ExerciseChoice> candidates;
  final String? swappingName;
  final String? swappingMuscle;

  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Word-prefix filtering over the same normalized tokens identity uses,
  /// so "db press" finds "Dumbbell Press" and "pulldown" finds "Lat Pull
  /// Down".
  List<ExerciseChoice> _filter(List<String> probe) => [
    for (final c in widget.candidates)
      if (_matches(normalizeExerciseTokens(c.name), probe)) c,
  ];

  static bool _matches(List<String> name, List<String> probe) =>
      probe.every((p) => name.any((w) => w.startsWith(p)));

  void _pick(ExerciseChoice c) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(c);
  }

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final typed = _query.text.trim();
    final probe = normalizeExerciseTokens(typed);
    final searching = probe.isNotEmpty;
    final filtered = searching ? _filter(probe) : widget.candidates;
    final exact = filtered.any(
      (c) => c.name.trim().toLowerCase() == typed.toLowerCase(),
    );
    final swapping = widget.swappingName;

    // Sections only while browsing; a search is one ranked list.
    final bucket = normalizeMuscleGroup(widget.swappingMuscle);
    final same = !searching && bucket != null
        ? [
            for (final c in filtered)
              if (normalizeMuscleGroup(c.muscleGroup) == bucket) c,
          ]
        : const <ExerciseChoice>[];
    final rest = same.isEmpty
        ? filtered
        : [for (final c in filtered) if (!same.contains(c)) c];

    // Existing exercises first — the one you already have is almost always
    // the one you meant — and the new-exercise row after them. With nothing
    // found it is the only row, under a line that says so.
    final addNamed = typed.isNotEmpty && !exact
        ? _RowGroup(
            children: [
              _SheetRow(
                key: const Key('exercise-picker-add-named'),
                icon: AppIcons.add,
                iconColor: TrainColors.green,
                label: strings.livePickExerciseAddNamed(isolate(typed)),
                detail: strings.livePickNewNote,
                onTap: () => _pick(ExerciseChoice(name: typed)),
              ),
            ],
          )
        : null;
    final children = <Widget>[
      if (widget.candidates.isEmpty && typed.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          child: Text(
            strings.livePickExerciseEmpty,
            style: AppText.body.copyWith(color: TrainColors.ink3),
          ),
        ),
      if (searching && filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
          child: Text(
            strings.livePickNoMatch,
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
        ),
      if (same.isNotEmpty) ...[
        _SectionLabel(strings.livePickSameMuscle),
        _RowGroup(indent: 16, children: [for (final c in same) _choiceRow(c)]),
        const SizedBox(height: 14),
      ],
      if (rest.isNotEmpty) ...[
        if (!searching) _SectionLabel(strings.livePickAllExercises),
        _RowGroup(indent: 16, children: [for (final c in rest) _choiceRow(c)]),
      ],
      if (addNamed != null) ...[
        if (filtered.isNotEmpty) const SizedBox(height: 14),
        addNamed,
      ],
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetHeader(
                title: swapping == null
                    ? strings.livePickExercise
                    : strings.liveSwapExercise,
                meta: swapping == null
                    ? null
                    : strings.livePickExerciseSwapNote(isolate(swapping)),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: const Key('exercise-picker-search'),
                  controller: _query,
                  autofocus: widget.candidates.isEmpty,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  cursorColor: TrainColors.green,
                  style: AppText.rowTitle.copyWith(color: TrainColors.ink),
                  decoration: zivoFieldDecoration(
                    hintText: strings.livePickExerciseSearch,
                    fill: TrainColors.glass,
                    prefixIcon: Icon(AppIcons.search, size: 18, color: TrainColors.ink3),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 12,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (typed.isEmpty) return;
                    _pick(
                      exact
                          ? filtered.firstWhere(
                              (c) => c.name.trim().toLowerCase() == typed.toLowerCase(),
                            )
                          : ExerciseChoice(name: typed),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 14),
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceRow(ExerciseChoice c) => _SheetRow(
    key: Key('exercise-picker-${c.canonicalId ?? c.name}'),
    label: isolate(c.name),
    detail: c.muscleGroup == null ? null : isolate(c.muscleGroup!),
    onTap: () => _pick(c),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 0, 30, 8),
      child: Text(
        text,
        style: TrainType.ui(
          size: 13,
          weight: FontWeight.w700,
          color: TrainColors.ink3,
        ),
      ),
    );
  }
}
