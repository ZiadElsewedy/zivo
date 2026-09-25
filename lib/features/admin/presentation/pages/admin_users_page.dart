import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/zivo_field.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/admin_models.dart';
import '../../domain/admin_repository.dart';
import '../admin_labels.dart';
import '../widgets/admin_ui.dart';
import 'admin_user_detail_page.dart';

/// The users table: search, one segment, one attribute filter, and
/// cursor pagination — every page is a server-side query, so this screen
/// holds at most the rows it has shown.
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({required this.repository, super.key});

  final AdminRepository repository;

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _search = TextEditingController();
  Timer? _debounce;

  AdminSegment _segment = AdminSegment.all;
  AdminUserFilter? _filter;

  final List<AdminUserRow> _rows = [];
  String? _cursor;
  bool _loading = false;
  String? _error;

  /// Bumped per query so a slow page from an old query can't land on a new
  /// one's list.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  AdminUserQuery _query({String? cursor}) => AdminUserQuery(
    segment: _segment,
    filter: _filter,
    search: _search.text,
    cursor: cursor,
  );

  Future<void> _load({required bool reset}) async {
    final gen = reset ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _rows.clear();
        _cursor = null;
      }
    });
    try {
      final page = await widget.repository.listUsers(
        _query(cursor: reset ? null : _cursor),
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _rows.addAll(page.users);
        _cursor = page.nextCursor;
        _loading = false;
      });
    } on AdminFailure catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(reset: true),
    );
    setState(() {}); // the "search ignores filters" note
  }

  Future<void> _open(AdminUserRow row) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AdminUserDetailPage(repository: widget.repository, uid: row.uid),
      ),
    );
    if (changed == true && mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final size = adminSizeOf(context);
    final searching = _search.text.trim().isNotEmpty;
    return AdminPageFrame(
      title: s.adminUsersTitle,
      onRefresh: () => _load(reset: true),
      actions: [
        AdminButton(
          label: s.adminRefresh,
          icon: AppIcons.refresh,
          onPressed: _loading ? null : () => _load(reset: true),
        ),
      ],
      children: [
        _Toolbar(
          search: _search,
          onSearchChanged: _onSearchChanged,
          segment: _segment,
          onSegment: (v) {
            setState(() => _segment = v);
            _load(reset: true);
          },
          filter: _filter,
          onFilter: (f) {
            setState(() => _filter = f);
            _load(reset: true);
          },
        ),
        if (searching) ...[
          const SizedBox(height: 10),
          Text(
            s.adminSearchIgnoresFilters,
            style: TrainType.ui(
              size: 12,
              weight: FontWeight.w500,
              color: TrainColors.ink4,
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (_loading && _rows.isEmpty) const AdminProgress(),
        if (_error != null && _rows.isEmpty)
          AdminErrorView(message: _error!, onRetry: () => _load(reset: true))
        else if (!_loading && _rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              s.adminUsersEmpty,
              style: TrainType.ui(
                size: 14,
                weight: FontWeight.w500,
                color: TrainColors.ink3,
              ),
            ),
          )
        else if (size == AdminSize.compact)
          for (final row in _rows)
            _CompactRow(row: row, onTap: () => _open(row))
        else ...[
          _HeaderRow(expanded: size == AdminSize.expanded),
          for (final row in _rows)
            _TableRow(
              row: row,
              expanded: size == AdminSize.expanded,
              onTap: () => _open(row),
            ),
        ],
        if (_cursor != null) ...[
          const SizedBox(height: 20),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AdminButton(
              label: s.adminLoadMore,
              onPressed: _loading ? null : () => _load(reset: false),
            ),
          ),
        ],
        if (_loading && _rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          const AdminProgress(),
        ],
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.search,
    required this.onSearchChanged,
    required this.segment,
    required this.onSegment,
    required this.filter,
    required this.onFilter,
  });

  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;
  final AdminSegment segment;
  final ValueChanged<AdminSegment> onSegment;
  final AdminUserFilter? filter;
  final ValueChanged<AdminUserFilter?> onFilter;

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final field = TextField(
      controller: search,
      onChanged: onSearchChanged,
      style: TrainType.ui(
        size: 14,
        weight: FontWeight.w500,
        color: TrainColors.ink,
      ),
      decoration: zivoFieldDecoration(
        hintText: s.adminSearchHint,
        prefixIcon: Icon(AppIcons.search, size: 18, color: TrainColors.ink3),
        accent: TrainColors.violet,
        fill: TrainColors.sectionFill,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 12,
        ),
      ),
    );
    final segments = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (seg, label) in [
          (AdminSegment.all, s.adminSegmentAll),
          (AdminSegment.active, s.adminSegmentActive),
          (AdminSegment.inactive, s.adminSegmentInactive),
          (AdminSegment.newUsers, s.adminSegmentNew),
        ])
          AdminPill(
            label: label,
            selected: segment == seg,
            onTap: () => onSegment(seg),
          ),
        _FilterMenu(filter: filter, onFilter: onFilter),
      ],
    );
    if (adminSizeOf(context) == AdminSize.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [field, const SizedBox(height: 12), segments],
      );
    }
    return Row(
      children: [
        SizedBox(width: 340, child: field),
        const SizedBox(width: 20),
        Expanded(child: segments),
      ],
    );
  }
}

class _FilterMenu extends StatefulWidget {
  const _FilterMenu({required this.filter, required this.onFilter});

  final AdminUserFilter? filter;
  final ValueChanged<AdminUserFilter?> onFilter;

  @override
  State<_FilterMenu> createState() => _FilterMenuState();
}

class _FilterMenuState extends State<_FilterMenu> {
  final _menu = GlobalKey<PopupMenuButtonState<Object>>();

  AdminUserFilter? get filter => widget.filter;
  ValueChanged<AdminUserFilter?> get onFilter => widget.onFilter;

  String _label(BuildContext context, AdminUserFilter f) {
    final s = l(context);
    return switch (f) {
      HasPlanFilter(:final hasPlan) =>
        hasPlan ? s.adminFilterHasPlan : s.adminFilterNoPlan,
      StatusFilter(:final status) =>
        status == AdminAccountStatus.disabled
            ? s.adminFilterSuspended
            : s.adminFilterNotSuspended,
      PlatformFilter(:final platform) => s.adminFilterPlatform(
        adminPlatformLabel(platform),
      ),
      AppVersionFilter(:final version) => s.adminFilterVersionActive(
        ltrFor(context, version),
      ),
    };
  }

  Future<void> _askVersion(BuildContext context) async {
    final controller = TextEditingController();
    final version = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: TrainColors.raised,
        title: Text(
          l(context).adminFieldVersion,
          style: TrainType.ui(
            size: 18,
            weight: FontWeight.w700,
            color: TrainColors.ink,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TrainType.mono(size: 14, color: TrainColors.ink),
          decoration: zivoFieldDecoration(
            hintText: l(context).adminFilterVersionHint,
            accent: TrainColors.violet,
          ),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l(context).actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(l(context).adminApply),
          ),
        ],
      ),
    );
    controller.dispose();
    final v = version?.trim();
    if (v != null && v.isNotEmpty) onFilter(AppVersionFilter(v));
  }

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final current = filter;
    return PopupMenuButton<Object>(
      key: _menu,
      tooltip: s.adminFilter,
      color: TrainColors.raised,
      onSelected: (v) {
        if (v == #none) {
          onFilter(null);
        } else if (v == #version) {
          _askVersion(this.context);
        } else if (v is AdminUserFilter) {
          onFilter(v);
        }
      },
      itemBuilder: (context) {
        PopupMenuItem<Object> item(Object value, String label) => PopupMenuItem(
          value: value,
          child: Text(
            label,
            style: TrainType.ui(
              size: 13.5,
              weight: FontWeight.w600,
              color: TrainColors.ink,
            ),
          ),
        );
        return [
          item(#none, s.adminFilterNone),
          const PopupMenuDivider(),
          item(const HasPlanFilter(true), s.adminFilterHasPlan),
          item(const HasPlanFilter(false), s.adminFilterNoPlan),
          const PopupMenuDivider(),
          item(
            const StatusFilter(AdminAccountStatus.disabled),
            s.adminFilterSuspended,
          ),
          item(
            const StatusFilter(AdminAccountStatus.active),
            s.adminFilterNotSuspended,
          ),
          const PopupMenuDivider(),
          for (final p in adminPlatforms)
            item(
              PlatformFilter(p),
              s.adminFilterPlatform(adminPlatformLabel(p)),
            ),
          item(#version, s.adminFilterVersion),
        ];
      },
      child: AdminPill(
        label: current == null ? s.adminFilter : _label(context, current),
        selected: current != null,
        onTap: () => _menu.currentState?.showButtonMenu(),
      ),
    );
  }
}

/// Column widths shared by the header and the rows.
const _flex = (
  user: 30,
  status: 12,
  lastActive: 11,
  joined: 12,
  device: 13,
  plan: 7,
  workouts: 9,
  ai: 8,
  last: 18,
);

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    Widget cell(int flex, String label, {bool end = false}) => Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: end ? TextAlign.end : TextAlign.start,
        style: TrainType.ui(
          size: 12,
          weight: FontWeight.w700,
          color: TrainColors.ink4,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: TrainColors.hairlineStrong)),
      ),
      child: Row(
        children: [
          cell(_flex.user, s.adminColUser),
          cell(_flex.status, s.adminColStatus),
          cell(_flex.lastActive, s.adminColLastActive),
          if (expanded) cell(_flex.joined, s.adminColJoined),
          if (expanded) cell(_flex.device, s.adminColDevice),
          cell(_flex.plan, s.adminColPlan),
          cell(_flex.workouts, s.adminColWorkouts, end: true),
          cell(_flex.ai, s.adminColAi, end: true),
          if (expanded) const SizedBox(width: 20),
          if (expanded) cell(_flex.last, s.adminColLastActivity),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.row,
    required this.expanded,
    required this.onTap,
  });

  final AdminUserRow row;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final body = TrainType.ui(
      size: 13,
      weight: FontWeight.w500,
      color: TrainColors.ink2,
    );
    final num = TrainType.mono(size: 13, color: TrainColors.ink);
    Widget cell(int flex, Widget child) => Expanded(flex: flex, child: child);
    Widget text(int flex, String v, {TextStyle? style, bool end = false}) =>
        cell(
          flex,
          Text(
            v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: end ? TextAlign.end : TextAlign.start,
            style: style ?? body,
          ),
        );
    return InkWell(
      onTap: onTap,
      hoverColor: TrainColors.liftAt(0.04),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: TrainColors.hairline)),
        ),
        child: Row(
          children: [
            cell(
              _flex.user,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adminName(context, row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.ui(
                      size: 14,
                      weight: FontWeight.w700,
                      color: TrainColors.ink,
                    ),
                  ),
                  if (row.emailMasked != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      ltrFor(context, row.emailMasked!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TrainType.ui(
                        size: 12,
                        weight: FontWeight.w500,
                        color: TrainColors.ink4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            cell(
              _flex.status,
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AdminStatusBadge(
                  suspended: row.status == AdminAccountStatus.disabled,
                ),
              ),
            ),
            text(_flex.lastActive, adminAgo(context, row.lastActiveAt)),
            if (expanded) text(_flex.joined, adminDate(context, row.createdAt)),
            if (expanded)
              text(
                _flex.device,
                [
                  adminPlatformLabel(row.platform),
                  if (row.appVersion != null) ltrFor(context, row.appVersion!),
                ].join(' '),
              ),
            text(_flex.plan, row.hasWorkoutPlan ? s.adminYes : s.adminNo),
            text(
              _flex.workouts,
              adminCount(context, row.workoutsCompleted),
              style: num,
              end: true,
            ),
            text(
              _flex.ai,
              adminCount(context, row.aiRequests),
              style: num,
              end: true,
            ),
            if (expanded) const SizedBox(width: 20),
            if (expanded)
              text(
                _flex.last,
                row.lastEvent == null
                    ? '—'
                    : adminEventLabel(context, row.lastEvent!.name),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({required this.row, required this.onTap});

  final AdminUserRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final meta = TrainType.ui(
      size: 12,
      weight: FontWeight.w500,
      color: TrainColors.ink3,
    );
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: TrainColors.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adminName(context, row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.ui(
                      size: 15,
                      weight: FontWeight.w700,
                      color: TrainColors.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AdminStatusBadge(
                        suspended: row.status == AdminAccountStatus.disabled,
                      ),
                      Text(
                        '${s.adminColLastActive}: ${adminAgo(context, row.lastActiveAt)}',
                        style: meta,
                      ),
                      Text(adminPlatformLabel(row.platform), style: meta),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  adminCount(context, row.workoutsCompleted),
                  style: TrainType.mono(size: 16, color: TrainColors.green),
                ),
                const SizedBox(height: 4),
                Text(s.adminColWorkouts, style: meta),
              ],
            ),
            const SizedBox(width: 6),
            Icon(AppIcons.chevron, size: 16, color: TrainColors.ink4),
          ],
        ),
      ),
    );
  }
}
