import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/util/money.dart';
import '../../auth/presentation/pages/profile_page.dart';
import '../../capture/presentation/quick_capture_sheet.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/presentation/pages/expense_capture_page.dart';
import '../../home/presentation/pages/today_page.dart';
import '../../hub/presentation/hub_page.dart';
import '../../moments/presentation/pages/moment_capture_page.dart';
import '../../notes/presentation/pages/note_capture_page.dart';
import '../../schedule/presentation/pages/event_capture_page.dart';
import '../../tasks/presentation/pages/task_capture_page.dart';
import '../../workout/presentation/pages/workout_capture_page.dart';
import 'widgets/capture_fab.dart';
import 'widgets/coming_soon.dart';
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
    ComingSoon('Ask'),
    ProfilePage(),
  ];

  Future<void> _openCapture() async {
    final choice = await showQuickCaptureSheet(context);
    if (choice == null || !mounted) return;

    switch (choice) {
      case CaptureChoice.expense:
        final saved = await _push<Expense>(const ExpenseCapturePage());
        if (saved != null) {
          _toast('Saved · ${formatAmount(saved.amountMinor)} ${saved.currency}');
        }
      case CaptureChoice.task:
        final saved = await _push<Object>(const TaskCapturePage());
        if (saved != null) _toast('Task added');
      case CaptureChoice.event:
        final saved = await _push<Object>(const EventCapturePage());
        if (saved != null) _toast('Event added');
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
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (_) => page, fullscreenDialog: true),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.ink,
          content: Text(
            message,
            style: AppText.button.copyWith(color: Colors.white, fontSize: 14),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _tabs),
      floatingActionButton:
          _index == 0 ? CaptureFab(onPressed: _openCapture) : null,
      bottomNavigationBar: ZivoBottomBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
