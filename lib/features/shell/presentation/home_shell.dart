import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/springs.dart';
import '../../../core/scope/app_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/util/money.dart';
import '../../ai/presentation/pages/ask_page.dart';
import '../../auth/presentation/pages/profile_page.dart';
import '../../capture/presentation/quick_capture_sheet.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/presentation/pages/expense_capture_page.dart';
import '../../home/presentation/pages/today_page.dart';
import '../../hub/presentation/hub_page.dart';
import '../../moments/presentation/pages/moment_capture_page.dart';
import '../../music/music_config.dart';
import '../../music/presentation/now_playing_bar.dart';
import '../../notes/presentation/pages/note_capture_page.dart';
import '../../schedule/presentation/pages/event_capture_page.dart';
import '../../tasks/presentation/pages/task_capture_page.dart';
import '../../university/presentation/pages/university_capture_page.dart';
import '../../workout/presentation/pages/workout_capture_page.dart';
import 'widgets/capture_fab.dart';
import 'widgets/zivo_bottom_bar.dart';

/// The root command surface: four tabs, a global Quick Capture action, and
/// a per-tab navigation stack (a simple IndexedStack for now; go_router
/// StatefulShell arrives with the foundation phase).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    TodayPage(),
    HubPage(),
    AskPage(),
    ProfilePage(),
  ];

  Future<void> _openCapture() async {
    final choice = await showQuickCaptureSheet(context);
    if (choice == null || !mounted) return;

    switch (choice) {
      case CaptureChoice.expense:
        final saved = await _push<Expense>(const ExpenseCapturePage());
        if (saved != null) {
          _toast(
            'Saved · ${formatAmount(saved.amountMinor)} ${saved.currency}',
          );
        }
      case CaptureChoice.task:
        final saved = await _push<Object>(const TaskCapturePage());
        if (saved != null) _toast('Task added');
      case CaptureChoice.event:
        final saved = await _push<Object>(const EventCapturePage());
        if (saved != null) _toast('Event added');
      case CaptureChoice.university:
        final saved = await _push<Object>(const UniversityCapturePage());
        if (saved != null) _toast('Added to University');
      case CaptureChoice.note:
        final saved = await _push<Object>(const NoteCapturePage());
        if (saved != null) _toast('Note saved');
      case CaptureChoice.moment:
        final saved = await _push<Object>(const MomentCapturePage());
        if (saved != null) _toast('Moment saved');
      case CaptureChoice.workout:
        final saved = await _push<Object>(const WorkoutCapturePage());
        if (saved != null) _toast('Workout logged');
    }
  }

  Future<T?> _push<T>(Widget page) {
    return Navigator.of(
      context,
    ).push<T>(MaterialPageRoute(builder: (_) => page, fullscreenDialog: true));
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceRaised,
          content: Text(
            message,
            style: AppText.button.copyWith(color: AppColors.ink, fontSize: 14),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: _TabSwitcher(index: _index, children: _tabs),
      floatingActionButton: _index == 0
          ? CaptureFab(onPressed: _openCapture)
          : null,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gated on the compile-time flag, not just the controller's own
          // state — with it false this whole branch is dead code, so the
          // shell is byte-for-byte its pre-music behavior (see
          // `music_config.dart`'s doc comment). `NowPlayingBar` itself
          // still separately renders nothing until there's actually
          // something playing.
          if (kMusicEnabled) NowPlayingBar(controller: AppScope.of(context).requireMusic),
          ZivoBottomBar(
            currentIndex: _index,
            onTap: (i) {
              if (i == _index) return;
              HapticFeedback.selectionClick();
              setState(() => _index = i);
            },
          ),
        ],
      ),
    );
  }
}

/// Wraps the tab body so switching reads as a fast, premium cross-fade
/// (~180ms) with a subtle scale-in on the incoming tab, rather than
/// [IndexedStack]'s instant hard cut — while still using [IndexedStack]
/// underneath so every tab's scroll position/state survives the switch.
class _TabSwitcher extends StatefulWidget {
  const _TabSwitcher({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<_TabSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, value: 1);

  @override
  void didUpdateWidget(covariant _TabSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      if (reducedMotion(context)) {
        _c.value = 1;
      } else {
        // Restart from 0 on every switch — an interrupted mid-flight switch
        // (rapid tab taps) just retargets rather than jumping.
        _c.value = 0;
        _c.springTo(1, spring: AppSprings.standard);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.985 + 0.015 * t, child: child),
        );
      },
      child: IndexedStack(index: widget.index, children: widget.children),
    );
  }
}
