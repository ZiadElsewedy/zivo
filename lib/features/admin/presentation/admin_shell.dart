import 'package:flutter/material.dart';

import '../../../core/scope/app_scope.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/train_tokens.dart';
import '../../../core/util/bidi.dart';
import '../../../l10n/l10n.dart';
import '../domain/admin_repository.dart';
import 'pages/admin_activity_page.dart';
import 'pages/admin_dashboard_page.dart';
import 'pages/admin_users_page.dart';
import 'widgets/admin_ui.dart';

/// The Admin Console's own shell — what an account holding the `admin`
/// claim sees instead of [HomeShell] (routed by `AuthGate`).
///
/// Desktop-first: a fixed sidebar on wide windows, an icon rail on
/// tablets, a bottom bar on phones. Each section keeps its own [Navigator],
/// so opening a user keeps the sidebar and the section's place.
///
/// This shell holds no authority. Every number and action behind it comes
/// from an admin-only callable that re-checks the claim server-side.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, this.repository});

  /// Overridable for tests; defaults to [AppScope.admin].
  final AdminRepository? repository;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  /// Sections are built on first visit, so opening the console runs only
  /// the dashboard's query — not every page's.
  final Set<int> _visited = {0};
  final _navigators = List.generate(3, (_) => GlobalKey<NavigatorState>());

  List<({IconData icon, String label})> _destinations(BuildContext context) {
    final s = l(context);
    return [
      (icon: AppIcons.adminDashboard, label: s.adminNavDashboard),
      (icon: AppIcons.adminUsers, label: s.adminNavUsers),
      (icon: AppIcons.adminActivity, label: s.adminNavActivity),
    ];
  }

  void _select(int i) {
    if (i == _index) {
      // Tapping the current section returns it to its root.
      _navigators[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  Widget _section(int i, AdminRepository repo) {
    final Widget root = switch (i) {
      0 => AdminDashboardPage(repository: repo),
      1 => AdminUsersPage(repository: repo),
      _ => AdminActivityPage(repository: repo),
    };
    return Navigator(
      key: _navigators[i],
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => ColoredBox(color: TrainColors.base, child: root),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository ?? AppScope.of(context).requireAdmin;
    final size = adminSizeOf(context);
    final destinations = _destinations(context);
    final content = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < 3; i++)
          _visited.contains(i) ? _section(i, repo) : const SizedBox.shrink(),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigators[_index].currentState?.maybePop();
      },
      child: Scaffold(
        backgroundColor: TrainColors.base,
        appBar: size == AdminSize.compact
            ? AppBar(
                backgroundColor: TrainColors.base,
                surfaceTintColor: Colors.transparent,
                titleSpacing: 16,
                title: const _Wordmark(),
                actions: const [
                  _SignOutButton(iconOnly: true),
                  SizedBox(width: 8),
                ],
              )
            : null,
        bottomNavigationBar: size == AdminSize.compact
            ? NavigationBar(
                backgroundColor: TrainColors.sectionFill,
                indicatorColor: TrainColors.violetWash,
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  for (final d in destinations)
                    NavigationDestination(
                      icon: Icon(d.icon, color: TrainColors.ink3),
                      selectedIcon: Icon(
                        d.icon,
                        color: TrainColors.violetGlyph,
                      ),
                      label: d.label,
                    ),
                ],
              )
            : null,
        body: size == AdminSize.compact
            ? content
            : SafeArea(
                child: Row(
                  children: [
                    _Sidebar(
                      collapsed: size == AdminSize.medium,
                      destinations: destinations,
                      index: _index,
                      onSelect: _select,
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: TrainColors.hairline,
                    ),
                    Expanded(child: content),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final mark = Text(
      'ZIVO',
      style: TrainType.ui(
        size: 17,
        weight: FontWeight.w800,
        tracking: 0.12,
        color: TrainColors.ink,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark,
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: TrainColors.violetWash,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            l(context).adminConsoleTitle,
            style: TrainType.ui(
              size: 12,
              weight: FontWeight.w700,
              color: TrainColors.violetGlyph,
            ),
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.collapsed,
    required this.destinations,
    required this.index,
    required this.onSelect,
  });

  final bool collapsed;
  final List<({IconData icon, String label})> destinations;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).auth.currentUser;
    return SizedBox(
      width: collapsed ? 76 : 232,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          collapsed ? 12 : 20,
          28,
          collapsed ? 12 : 16,
          20,
        ),
        child: Column(
          crossAxisAlignment: collapsed
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.only(start: collapsed ? 0 : 10),
              child: collapsed
                  ? Icon(
                      AppIcons.adminShield,
                      color: TrainColors.violetGlyph,
                      size: 22,
                    )
                  : const _Wordmark(),
            ),
            const SizedBox(height: 36),
            for (var i = 0; i < destinations.length; i++)
              _NavItem(
                icon: destinations[i].icon,
                label: destinations[i].label,
                selected: i == index,
                collapsed: collapsed,
                onTap: () => onSelect(i),
              ),
            const Spacer(),
            if (!collapsed && user != null) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 10,
                  bottom: 10,
                ),
                child: Text(
                  ltrFor(context, user.email ?? user.uid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.ui(
                    size: 12,
                    weight: FontWeight.w500,
                    color: TrainColors.ink4,
                  ),
                ),
              ),
            ],
            _SignOutButton(iconOnly: collapsed),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? TrainColors.violetGlyph : TrainColors.ink3;
    final item = Semantics(
      selected: selected,
      button: true,
      label: collapsed ? label : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
          decoration: BoxDecoration(
            color: selected ? TrainColors.violetWash : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TrainType.ui(
                    size: 14,
                    weight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? TrainColors.ink : TrainColors.ink2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: collapsed ? Tooltip(message: label, child: item) : item,
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({this.iconOnly = false});

  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    final label = l(context).adminSignOut;
    if (iconOnly) {
      return IconButton(
        tooltip: label,
        onPressed: auth.signOut,
        icon: Icon(AppIcons.signOut, size: 20, color: TrainColors.ink3),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AdminButton(
        label: label,
        icon: AppIcons.signOut,
        onPressed: auth.signOut,
      ),
    );
  }
}
