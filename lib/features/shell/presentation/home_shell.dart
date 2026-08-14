import 'package:flutter/material.dart';

import '../../home/presentation/pages/today_page.dart';
import 'widgets/capture_fab.dart';
import 'widgets/coming_soon.dart';
import 'widgets/zivo_bottom_bar.dart';

/// The root command surface: four tabs, a global Quick Capture action, and
/// a per-tab navigation stack (currently a simple IndexedStack; go_router
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _tabs),
      floatingActionButton: _index == 0
          ? CaptureFab(onPressed: () {})
          : null,
      bottomNavigationBar: ZivoBottomBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
