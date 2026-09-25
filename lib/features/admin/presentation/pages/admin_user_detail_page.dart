import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/zivo_confirm.dart';
import '../../../../core/widgets/zivo_field.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/domain/auth_result.dart';
import '../../domain/admin_models.dart';
import '../../domain/admin_repository.dart';
import '../admin_labels.dart';
import '../widgets/admin_ui.dart';

/// One user, as an admin needs to see them: account facts, whether they
/// train, how much AI they use, what they did recently — counts and dates,
/// never content — and the account actions.
///
/// Pops `true` when the account changed, so the table reloads.
class AdminUserDetailPage extends StatefulWidget {
  const AdminUserDetailPage({
    required this.repository,
    required this.uid,
    super.key,
  });

  final AdminRepository repository;
  final String uid;

  @override
  State<AdminUserDetailPage> createState() => _AdminUserDetailPageState();
}

class _AdminUserDetailPageState extends State<AdminUserDetailPage> {
  bool _changed = false;
  bool _busy = false;
  Key _loaderKey = UniqueKey();

  void _reload() => setState(() => _loaderKey = UniqueKey());

  Future<void> _setSuspended(AdminUserDetail d, bool suspend) async {
    final s = l(context);
    final name = adminName(context, d.row);
    final ok = await confirmDestructive(
      context,
      title: suspend ? s.adminSuspendTitle : s.adminReinstateTitle,
      body: suspend ? s.adminSuspendBody(name) : s.adminReinstateBody(name),
      confirmLabel: suspend ? s.adminSuspendConfirm : s.adminReinstateConfirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.setDisabled(d.row.uid, disabled: suspend);
      if (!mounted) return;
      _changed = true;
      showZivoToast(
        context,
        suspend ? s.adminSuspended : s.adminReinstated,
        kind: ToastKind.success,
      );
      _reload();
    } on AdminFailure catch (e) {
      if (mounted) showZivoToast(context, e.message, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AdminUserDetail d) async {
    final auth = AppScope.of(context).auth;
    final needsPassword =
        auth.currentUser?.providerIds.contains('password') ?? false;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _DeleteDialog(
        name: adminName(context, d.row),
        code: _codeFor(d.row.uid),
        needsPassword: needsPassword,
      ),
    );
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // The server refuses an irreversible call without a fresh credential
      // proof, so re-prove it first — with the password, or the provider.
      final reauth = await auth.reauthenticate(
        password: needsPassword ? password : null,
      );
      if (!mounted) return;
      if (reauth is AuthFailed) {
        showZivoToast(context, reauth.failure.message, kind: ToastKind.error);
        return;
      }
      if (reauth is AuthCancelled) return;
      await widget.repository.deleteUser(d.row.uid);
      if (!mounted) return;
      showZivoToast(context, l(context).adminDeleted, kind: ToastKind.success);
      Navigator.of(context).pop(true);
    } on AdminFailure catch (e) {
      if (mounted) showZivoToast(context, e.message, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The last six characters of the uid — something to type that is
  /// specific to THIS account, so a confirmation can't be muscle memory.
  static String _codeFor(String uid) =>
      uid.length <= 6 ? uid : uid.substring(uid.length - 6);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: TrainColors.base,
        body: SafeArea(
          child: AdminLoader<AdminUserDetail>(
            key: _loaderKey,
            load: () => widget.repository.user(widget.uid),
            builder: (context, d, reload) => AdminPageFrame(
              leading: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AdminButton(
                  label: l(context).adminUsersTitle,
                  icon: AppIcons.back,
                  onPressed: () => Navigator.of(context).pop(_changed),
                ),
              ),
              title: adminName(context, d.row),
              subtitle: d.row.emailMasked == null
                  ? null
                  : ltrFor(context, d.row.emailMasked!),
              onRefresh: reload,
              children: [
                _Body(
                  detail: d,
                  busy: _busy,
                  onSuspend: _setSuspended,
                  onDelete: _delete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.detail,
    required this.busy,
    required this.onSuspend,
    required this.onDelete,
  });

  final AdminUserDetail detail;
  final bool busy;
  final void Function(AdminUserDetail, bool suspend) onSuspend;
  final void Function(AdminUserDetail) onDelete;

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final d = detail;
    final r = d.row;
    final suspended = r.status == AdminAccountStatus.disabled;

    final account = AdminGroup(
      title: s.adminSectionAccount,
      gap: 6,
      child: Column(
        children: [
          AdminField(
            label: s.adminFieldStatus,
            value: suspended ? s.adminStatusSuspended : s.adminStatusActive,
          ),
          AdminField(
            label: s.adminFieldCreated,
            value: adminDate(context, r.createdAt),
          ),
          AdminField(
            label: s.adminFieldLastActive,
            value: adminAgo(context, r.lastActiveAt),
          ),
          AdminField(
            label: s.adminFieldLastSignIn,
            value: adminDate(context, d.lastSignInAt),
          ),
          AdminField(
            label: s.adminFieldPlatform,
            value: adminPlatformLabel(r.platform),
          ),
          AdminField(
            label: s.adminFieldVersion,
            value: r.appVersion == null ? '—' : ltrFor(context, r.appVersion!),
            mono: true,
          ),
          AdminField(
            label: s.adminFieldSignInMethod,
            value: d.providers.isEmpty
                ? '—'
                : d.providers.map(adminProviderLabel).join(', '),
          ),
          AdminField(
            label: s.adminFieldAccountId,
            value: ltrFor(context, r.uid),
            mono: true,
          ),
        ],
      ),
    );

    final workout = AdminGroup(
      title: s.adminSectionWorkout,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminFigureGrid(
            minWidth: 110,
            children: [
              AdminFigure(
                value: adminCount(context, r.workoutsCompleted),
                label: s.adminFieldCompleted,
                accent: TrainColors.green,
              ),
              AdminFigure(
                value: adminCount(context, d.workoutsStarted),
                label: s.adminFieldSessions,
              ),
              AdminFigure(
                value: adminCount(context, d.workoutsAbandoned),
                label: s.adminFieldAbandoned,
              ),
            ],
          ),
          const SizedBox(height: 14),
          AdminField(
            label: s.adminFieldHasPlan,
            value: r.hasWorkoutPlan ? s.adminYes : s.adminNo,
          ),
          AdminField(
            label: s.adminFieldPlans,
            value: adminCount(context, d.workoutPlans),
          ),
          AdminField(
            label: s.adminFieldPlanCreated,
            value: adminDate(context, d.workoutPlanCreatedAt),
          ),
          AdminField(
            label: s.adminFieldLastWorkout,
            value: adminDate(context, d.lastWorkoutAt),
          ),
        ],
      ),
    );

    final usageKeys =
        d.features.keys.where((k) => (d.features[k] ?? 0) > 0).toList()..sort();
    final usage = AdminGroup(
      title: s.adminSectionUsage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminFigureGrid(
            minWidth: 110,
            children: [
              AdminFigure(
                value: adminCount(context, r.aiRequests),
                label: s.adminFieldAiRequests,
              ),
              AdminFigure(
                value: adminCompact(context, r.aiTokens),
                label: s.adminFieldTokens,
                note:
                    '${adminCompact(context, d.aiTokensIn)} / ${adminCompact(context, d.aiTokensOut)}',
              ),
              AdminFigure(
                value: adminUsd(context, d.aiCostUsd),
                label: s.adminFieldAiCost,
                accent: TrainColors.amber,
              ),
            ],
          ),
          if (usageKeys.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final k in usageKeys)
              AdminField(
                label: adminUsageLabel(context, k),
                value: adminCount(context, d.features[k]!),
              ),
          ],
        ],
      ),
    );

    final recent = AdminGroup(
      title: s.adminSectionRecent,
      gap: 8,
      child: d.recentEvents.isEmpty
          ? Text(
              s.adminNoEvents,
              style: TrainType.ui(
                size: 13,
                weight: FontWeight.w500,
                color: TrainColors.ink3,
              ),
            )
          : Column(
              children: [
                for (final e in d.recentEvents)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                              if (adminEventDetail(context, e)
                                  case final detail?
                                  when detail.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  detail,
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
                        Text(
                          adminAgo(context, e.at),
                          style: TrainType.mono(
                            size: 12,
                            color: TrainColors.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );

    final manage = AdminGroup(
      title: s.adminSectionManage,
      child: d.isAdmin
          ? Text(
              s.adminIsAdminNote,
              style: TrainType.ui(
                size: 13,
                weight: FontWeight.w500,
                color: TrainColors.ink3,
              ),
            )
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                AdminButton(
                  label: suspended ? s.adminReinstate : s.adminSuspend,
                  icon: suspended ? AppIcons.reinstate : AppIcons.suspend,
                  onPressed: busy ? null : () => onSuspend(d, !suspended),
                ),
                AdminButton(
                  label: s.adminDelete,
                  icon: AppIcons.trash,
                  destructive: true,
                  onPressed: busy ? null : () => onDelete(d),
                ),
              ],
            ),
    );

    final privacy = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(AppIcons.privacy, size: 16, color: TrainColors.ink4),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            s.adminPrivacyNote,
            style: TrainType.ui(
              size: 12,
              weight: FontWeight.w500,
              color: TrainColors.ink4,
              height: 1.45,
            ),
          ),
        ),
      ],
    );

    const gap = SizedBox(height: 36, width: 40);
    if (adminSizeOf(context) == AdminSize.expanded) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Column(children: [account, gap, workout, gap, usage]),
          ),
          gap,
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [manage, gap, recent, gap, privacy],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        account,
        gap,
        workout,
        gap,
        usage,
        gap,
        recent,
        gap,
        manage,
        gap,
        privacy,
      ],
    );
  }
}

/// The deletion confirmation: what will happen, a code to type that belongs
/// to this account, and — for a password admin — the password the server's
/// freshness gate needs. Pops the password ('' for provider accounts), or
/// null on cancel.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({
    required this.name,
    required this.code,
    required this.needsPassword,
  });

  final String name;
  final String code;
  final bool needsPassword;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _code = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready =>
      _code.text.trim() == widget.code &&
      (!widget.needsPassword || _password.text.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    return AlertDialog(
      backgroundColor: TrainColors.raised,
      title: Text(
        s.adminDeleteTitle,
        style: TrainType.ui(
          size: 18,
          weight: FontWeight.w700,
          color: TrainColors.ink,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.adminDeleteBody(widget.name),
              style: TrainType.ui(
                size: 14,
                weight: FontWeight.w500,
                color: TrainColors.ink2,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.adminDeleteTypeCode(ltrFor(context, widget.code)),
              style: TrainType.ui(
                size: 13,
                weight: FontWeight.w600,
                color: TrainColors.ink2,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('admin-delete-code'),
              controller: _code,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: TrainType.mono(size: 15, color: TrainColors.ink),
              decoration: zivoFieldDecoration(
                hintText: widget.code,
                accent: TrainColors.ember,
              ),
            ),
            const SizedBox(height: 14),
            if (widget.needsPassword)
              TextField(
                key: const Key('admin-delete-password'),
                controller: _password,
                obscureText: true,
                onChanged: (_) => setState(() {}),
                style: TrainType.ui(
                  size: 14,
                  weight: FontWeight.w500,
                  color: TrainColors.ink,
                ),
                decoration: zivoFieldDecoration(
                  hintText: s.adminDeletePassword,
                  accent: TrainColors.ember,
                ),
              )
            else
              Text(
                s.adminDeleteReauthNote,
                style: TrainType.ui(
                  size: 12.5,
                  weight: FontWeight.w500,
                  color: TrainColors.ink3,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            s.actionCancel,
            style: TrainType.ui(
              size: 14,
              weight: FontWeight.w700,
              color: TrainColors.ink3,
            ),
          ),
        ),
        TextButton(
          key: const Key('admin-delete-confirm'),
          onPressed: _ready
              ? () => Navigator.pop(context, _password.text)
              : null,
          child: Text(
            s.adminDeleteConfirm,
            style: TrainType.ui(
              size: 14,
              weight: FontWeight.w700,
              color: _ready ? TrainColors.ember : TrainColors.ink4,
            ),
          ),
        ),
      ],
    );
  }
}
