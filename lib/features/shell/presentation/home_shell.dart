import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/util/money.dart';
import '../../../core/scope/app_scope.dart';
import '../../ai/presentation/pages/ask_page.dart';
import '../../ai/presentation/widgets/quick_log_sheet.dart';
import '../../profile/presentation/pages/profile_page.dart';
import '../../capture/presentation/quick_capture_sheet.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/presentation/pages/expense_capture_page.dart';
import '../../home/presentation/pages/today_page.dart';
import '../../hub/presentation/hub_page.dart';
import '../../moments/presentation/pages/moment_capture_page.dart';
import '../../music/domain/music_connection.dart';
import '../../music/domain/now_playing.dart';
import '../../music/music_config.dart';
import '../../music/presentation/now_playing_lozenge.dart';
import '../../workout/presentation/pages/workout_capture_page.dart';
import 'widgets/bottom_chrome.dart';
import 'widgets/capture_fab.dart';
import 'widgets/zivo_bottom_bar.dart';
import '../../../core/theme/train_tokens.dart';

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

  /// One-way channel for shell-initiated composer text (voice quick-log):
  /// the sheet resolves with a transcript, it lands in Ask's composer, and
  /// the tab switches — one Ask instance, no duplicate route.
  final ValueNotifier<String?> _askDraft = ValueNotifier(null);

  /// Whether the now-playing strip is on screen. This is the ONE input that
  /// changes the bottom chrome's height, so it is tracked here rather than
  /// read from a `StreamBuilder` wrapped around the shell: the four tab
  /// bodies then rebuild when music appears or leaves, and not once per
  /// playback emission.
  bool _musicVisible = false;

  MusicConnection _connection = MusicConnection.disconnected;
  NowPlaying? _track;
  StreamSubscription<MusicConnection>? _connectionSub;
  StreamSubscription<NowPlaying?>? _trackSub;
  bool _musicWired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Wired here, not in initState, because the controller comes from an
    // InheritedWidget. Guarded so it happens exactly once.
    if (_musicWired || !kMusicEnabled) return;
    final music = AppScope.of(context).music;
    if (music == null) return;
    _musicWired = true;
    _connection = music.currentConnection;
    _track = music.currentNowPlaying;
    _musicVisible = _resolveVisible();
    _connectionSub = music.connection.listen((value) {
      _connection = value;
      _syncMusicVisibility();
    });
    _trackSub = music.nowPlaying.listen((value) {
      _track = value;
      _syncMusicVisibility();
    });
  }

  /// The same predicate `NowPlayingResolver` renders on — connected AND a
  /// track loaded — so the reserved height and the strip agree by definition.
  bool _resolveVisible() =>
      _connection == MusicConnection.connected && _track != null;

  /// Rebuilds only on the visibility *edge*: the strip appearing or leaving is
  /// what moves every page's bottom clearance. A track change or an advancing
  /// playhead does not, and the lozenge watches those itself.
  void _syncMusicVisibility() {
    if (!mounted) return;
    final next = _resolveVisible();
    if (next == _musicVisible) return;
    setState(() => _musicVisible = next);
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _trackSub?.cancel();
    super.dispose();
  }

  Future<void> _openQuickLog() async {
    final text = await showQuickLogSheet(context);
    if (text == null || !mounted) return;
    _askDraft.value = text;
    setState(() => _index = 2);
  }

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
          backgroundColor: TrainColors.raisedStrong,
          content: Text(
            message,
            style: AppText.button.copyWith(
              color: TrainColors.ink,
              fontSize: 14,
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Built per-frame (not a static const list) so Today can be handed a
    // live callback to switch tabs itself — needed for the pull-to-ask
    // gesture, since HomeShell is the only thing that owns `_index`.
    final tabs = [
      TodayPage(
        onOpenAsk: () => setState(() => _index = 2),
        onQuickLog: _openQuickLog,
      ),
      const HubPage(),
      AskPage(incomingDraft: _askDraft),
      const ProfilePage(),
    ];
    // The bottom is ONE object: the nav island, with the now-playing strip
    // fused to its top edge while music is on screen. Its total height is
    // published to every tab through [BottomChrome] so each page's clearance
    // is derived, never guessed — see that class for what the guessing cost.
    final chromeHeight = ZivoBottomBarMetrics.height(
      context,
      music: _musicVisible,
    );

    return Scaffold(
      extendBody: true,
      // The shell does NOT eat the keyboard inset — each tab owns it.
      // Resizing here shrank the body to the keyboard's top edge AND stripped
      // `viewInsets` out of the body's MediaQuery (Scaffold passes
      // `removeBottomInset: resizeToAvoidBottomInset`), so Ask — which lifts
      // its composer itself, on an eased curve — saw a zero inset and fell
      // back to reserving the bottom chrome, leaving the composer floating a
      // nav-island's height above the keyboard. With this false, the inset
      // reaches the tabs intact: Ask animates its own lift, and the other
      // tabs resize through their own `TrainScreen` scaffold.
      resizeToAvoidBottomInset: false,
      body: BottomChrome(
        height: chromeHeight,
        child: _TabSwitcher(index: _index, children: tabs),
      ),
      floatingActionButton: _index == 0
          ? CaptureFab(onPressed: _openCapture)
          : null,
      bottomNavigationBar: ZivoBottomBar(
        currentIndex: _index,
        onTap: (i) {
          if (i == _index) return;
          HapticFeedback.selectionClick();
          setState(() => _index = i);
        },
        // Mounted only once there is genuinely something to show, and exactly
        // as tall as [chromeHeight] just reserved for it.
        fused: _musicVisible
            ? NowPlayingLozenge(controller: AppScope.of(context).requireMusic)
            : null,
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
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: 1,
  );

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
