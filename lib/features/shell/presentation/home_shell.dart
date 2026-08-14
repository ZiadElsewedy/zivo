import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/util/money.dart';
import '../../capture/presentation/quick_capture_sheet.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/presentation/pages/expense_capture_page.dart';
import '../../home/presentation/pages/today_page.dart';
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
    ComingSoon('Hub'),
    ComingSoon('Ask'),
    ComingSoon('You'),
  ];

  Future<void> _openCapture() async {
    final choice = await showQuickCaptureSheet(context);
    if (choice == null || !mounted) return;

    if (choice == CaptureChoice.expense) {
      final saved = await Navigator.of(context).push<Expense>(
        MaterialPageRoute(
          builder: (_) => const ExpenseCapturePage(),
          fullscreenDialog: true,
        ),
      );
      if (saved != null && mounted) {
        _toast('Saved · ${formatAmount(saved.amountMinor)} ${saved.currency}');
      }
    } else {
      _toast('Coming next.');
    }
  }

  void _toast(String message) {
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
