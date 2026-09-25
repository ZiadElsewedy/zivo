import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/admin_models.dart';
import '../../domain/admin_repository.dart';
import '../admin_labels.dart';
import '../widgets/admin_ui.dart';
import 'admin_user_detail_page.dart';

/// Meaningful product activity: how often each milestone happened in the
/// window, and the latest events. Tapping a count narrows the feed to it.
class AdminActivityPage extends StatefulWidget {
  const AdminActivityPage({required this.repository, super.key});

  final AdminRepository repository;

  @override
  State<AdminActivityPage> createState() => _AdminActivityPageState();
}

class _AdminActivityPageState extends State<AdminActivityPage> {
  int _days = 7;
  String? _name;

  AdminActivity? _data;
  final List<AdminActivityEvent> _events = [];
  bool _loading = false;
  String? _error;
  int _generation = 0;

  /// Events in the order the page lists them — the product's arc.
  static const _order = [
    'account_created',
    'app_opened',
    'workout_plan_created',
    'workout_started',
    'workout_completed',
    'workout_abandoned',
    'ai_request',
    'diet_imported',
    'account_deleted',
  ];

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    final gen = reset ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _events.clear();
    });
    try {
      final data = await widget.repository.activity(
        days: _days,
        eventName: _name,
        cursor: reset ? null : _data?.nextCursor,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _data = data;
        _events.addAll(data.events);
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

  void _openUser(String uid) {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) =>
            AdminUserDetailPage(repository: widget.repository, uid: uid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final data = _data;
    return AdminPageFrame(
      title: s.adminActivityTitle,
      onRefresh: () => _load(reset: true),
      actions: [
        for (final (d, label) in [
          (1, s.adminWindow1),
          (7, s.adminWindow7),
          (30, s.adminWindow30),
        ])
          AdminPill(
            label: label,
            selected: _days == d,
            onTap: () {
              setState(() => _days = d);
              _load(reset: true);
            },
          ),
      ],
      children: [
        if (data == null && _loading) const AdminProgress(),
        if (data == null && _error != null)
          AdminErrorView(message: _error!, onRetry: () => _load(reset: true)),
        if (data != null) ...[
          AdminFigureGrid(
            minWidth: 150,
            children: [
              for (final name in _order)
                _TotalTile(
                  label: adminEventLabel(context, name),
                  value: adminCount(context, data.totals[name] ?? 0),
                  selected: _name == name,
                  onTap: () {
                    setState(() => _name = _name == name ? null : name);
                    _load(reset: true);
                  },
                ),
            ],
          ),
          const SizedBox(height: 40),
          AdminGroup(
            title: _name == null
                ? s.adminFeedTitle
                : '${s.adminFeedTitle}: ${adminEventLabel(context, _name!)}',
            trailing: _name == null
                ? null
                : AdminPill(
                    label: s.adminAllEvents,
                    selected: false,
                    onTap: () {
                      setState(() => _name = null);
                      _load(reset: true);
                    },
                  ),
            gap: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_events.isEmpty && !_loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      s.adminActivityEmpty,
                      style: TrainType.ui(
                        size: 13.5,
                        weight: FontWeight.w500,
                        color: TrainColors.ink3,
                      ),
                    ),
                  ),
                for (final e in _events) _FeedRow(event: e, onUser: _openUser),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: AdminProgress(),
                  ),
                if (!_loading && data.nextCursor != null) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AdminButton(
                      label: s.adminLoadMore,
                      onPressed: () => _load(reset: false),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsetsDirectional.only(
            start: 12,
            top: 4,
            bottom: 4,
          ),
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(
                color: selected
                    ? TrainColors.violet
                    : TrainColors.hairlineStrong,
                width: 2,
              ),
            ),
          ),
          child: AdminFigure(value: value, label: label),
        ),
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.event, required this.onUser});

  final AdminActivityEvent event;
  final ValueChanged<String> onUser;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final detail = adminEventDetail(context, e);
    final who = e.displayName == null
        ? l(context).adminUnknownUser
        : isolate(e.displayName!);
    final canOpen = e.name != 'account_deleted';
    return InkWell(
      onTap: canOpen ? () => onUser(e.uid) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: TrainColors.hairline)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                adminAgo(context, e.at),
                style: TrainType.mono(size: 12, color: TrainColors.ink3),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adminEventLabel(context, e.name),
                    style: TrainType.ui(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: TrainColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      who,
                      if (detail != null && detail.isNotEmpty) detail,
                    ].join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.ui(
                      size: 12,
                      weight: FontWeight.w500,
                      color: TrainColors.ink4,
                    ),
                  ),
                ],
              ),
            ),
            if (canOpen)
              Icon(AppIcons.chevron, size: 15, color: TrainColors.ink4),
          ],
        ),
      ),
    );
  }
}
