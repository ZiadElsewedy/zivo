import 'dart:ui';

import 'package:flutter/material.dart';

import '../../scope/app_scope.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/google_drive_mark.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/rise_in.dart';
import '../../widgets/settings_row.dart';
import '../../widgets/zivo_toast.dart';
import '../domain/media_object.dart';
import '../domain/media_storage_preferences.dart';
import '../media_service.dart';

/// "Storage & Sync" — the one screen that answers *where your photos are*:
/// always on this device, and optionally backed up to a Google Drive account
/// you connect **on this device**. Connecting is explicit here and nowhere
/// else, so opening Moments or taking a photo never triggers a sign-in.
///
/// Presented in the house dashboard language — atmospheric backdrop, editorial
/// title, staggered entrance — so a pushed detail page still feels native to
/// the app rather than a settings afterthought.
class StorageSyncPage extends StatefulWidget {
  const StorageSyncPage({super.key});

  @override
  State<StorageSyncPage> createState() => _StorageSyncPageState();
}

/// Which long-running operation, if any, is in flight — drives the live
/// progress banner and which button shows a spinner.
enum _Op { none, connect, disconnect, backup, sync }

class _StorageSyncPageState extends State<StorageSyncPage> {
  _Op _op = _Op.none;
  int _opDone = 0;
  int _opTotal = 0;

  bool _connected = false;
  String? _email;
  int _total = 0;
  int _backedUp = 0;

  bool get _busy => _op != _Op.none;

  MediaService get _media => AppScope.of(context).requireMedia;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final connected = await _media.isBackupConnected();
      final email = await _media.connectedBackupAccount();
      final all = await _media.registry.getAll();
      if (!mounted) return;
      setState(() {
        _connected = connected;
        _email = email;
        _total = all.length;
        _backedUp = all.where((m) => m.remoteBackup == BackupState.done).length;
      });
    } catch (_) {
      // Best-effort status.
    }
  }

  /// Runs [action] under operation [op], surfacing its progress (via the
  /// `onProgress` it's handed) in the live banner, then refreshing status.
  Future<void> _run(
    _Op op,
    Future<void> Function(void Function(int done, int total) onProgress) action,
  ) async {
    if (_busy) return;
    setState(() {
      _op = op;
      _opDone = 0;
      _opTotal = 0;
    });
    try {
      await action((done, total) {
        if (mounted) {
          setState(() {
            _opDone = done;
            _opTotal = total;
          });
        }
      });
    } finally {
      if (mounted) setState(() => _op = _Op.none);
      await _refresh();
    }
  }

  void _toast(String message, ToastKind kind) {
    if (mounted) showZivoToast(context, message, kind: kind);
  }

  Future<void> _connect() => _run(_Op.connect, (_) async {
    final ok = await _media.connectBackup();
    _toast(
      ok
          ? 'Google Drive connected on this device.'
          : 'Couldn’t connect Google Drive.',
      ok ? ToastKind.success : ToastKind.error,
    );
  });

  Future<void> _disconnect() => _run(_Op.disconnect, (_) async {
    await _media.disconnectBackup();
    _toast('Google Drive disconnected on this device.', ToastKind.info);
  });

  Future<void> _backupNow() => _run(_Op.backup, (onProgress) async {
    final n = await _media.backupNow(onProgress: onProgress);
    _toast(
      n == 0
          ? 'Everything is already backed up.'
          : 'Backed up $n ${_p(n)} to Drive.',
      ToastKind.success,
    );
  });

  Future<void> _syncFromDrive() => _run(_Op.sync, (onProgress) async {
    final n = await _media.syncFromBackup(onProgress: onProgress);
    _toast(
      n == 0
          ? 'Nothing new to download.'
          : 'Downloaded $n ${_p(n)} from Drive.',
      ToastKind.success,
    );
  });

  String _p(int n) => n == 1 ? 'photo' : 'photos';

  @override
  Widget build(BuildContext context) {
    final prefsRepo = _media.preferences;
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.15,
            colors: [Color(0xFF231B14), AppColors.ground, Color(0xFF0E0B08)],
            stops: [0.0, 0.52, 1.0],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -60,
              right: -70,
              child: _AuraBlob(color: AppColors.pulse, size: 200),
            ),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
                children: [
                  RiseIn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _BackButton(),
                        const SizedBox(height: 20),
                        Text(
                          'Storage & Sync',
                          style: AppText.greeting.copyWith(fontSize: 30),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  RiseIn(
                    delay: const Duration(milliseconds: 50),
                    child: _DeviceCard(total: _total),
                  ),
                  const SizedBox(height: 22),
                  RiseIn(
                    delay: const Duration(milliseconds: 90),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 6, bottom: 9),
                          child: Text(
                            'BACKUP & SYNC',
                            style: AppText.sectionLabel,
                          ),
                        ),

                        _DriveCard(
                          supported: _media.supportsBackup,
                          connected: _connected,
                          email: _email,
                          total: _total,
                          backedUp: _backedUp,
                          op: _op,
                          opDone: _opDone,
                          opTotal: _opTotal,
                          onConnect: _connect,
                          onDisconnect: _disconnect,
                          onBackupNow: _backupNow,
                          onSync: _syncFromDrive,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  RiseIn(
                    delay: const Duration(milliseconds: 130),
                    child: StreamBuilder<MediaStoragePreferences>(
                      stream: prefsRepo.watch(),
                      initialData: MediaStoragePreferences.defaults,
                      builder: (context, snapshot) {
                        final prefs =
                            snapshot.data ?? MediaStoragePreferences.defaults;
                        return SettingsSectionCard(
                          label: 'DEVICE PHOTOS',
                          children: [
                            SettingsRow(
                              icon: AppIcons.photos,
                              title: 'Save to Photos',
                              value: prefs.saveToPhotos ? 'On' : 'Off',
                              accent: AppColors.ember,
                              last: true,
                              trailing: Switch.adaptive(
                                value: prefs.saveToPhotos,
                                activeThumbColor: AppColors.ember,
                                onChanged: _busy
                                    ? null
                                    : (v) => prefsRepo.save(
                                        prefs.copyWith(saveToPhotos: v),
                                      ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  RiseIn(
                    delay: const Duration(milliseconds: 170),
                    child: Text(
                      'Each ZIVO account keeps its own photos in its own Drive folder, so '
                      'accounts never mix — even if they use the same Google Drive.',
                      style: AppText.meta.copyWith(
                        color: AppColors.ink3,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A soft, blurred wash of color floating behind the content — the quiet
/// "energy" glow shared across the app's surfaces. Purely decorative.
class _AuraBlob extends StatelessWidget {
  const _AuraBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.14),
          ),
        ),
      ),
    );
  }
}

/// The pushed-page back affordance — the same 38px chip language as the
/// Settings header.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Tooltip(
        message: 'Back',
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          customBorder: const CircleBorder(),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hairline2),
            ),
            child: const Icon(AppIcons.back, size: 18, color: AppColors.ink2),
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.pulse.withValues(alpha: 0.30),
                  AppColors.pulse.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.pulse.withValues(alpha: 0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.pulse.withValues(alpha: 0.30),
                  blurRadius: 22,
                  spreadRadius: -6,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(AppIcons.check, size: 22, color: AppColors.pulse),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On this device',
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  total == 0
                      ? 'Your photos are saved here first, always.'
                      : '$total ${total == 1 ? 'photo' : 'photos'} saved here.',
                  style: AppText.meta.copyWith(color: AppColors.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriveCard extends StatelessWidget {
  const _DriveCard({
    required this.supported,
    required this.connected,
    required this.email,
    required this.total,
    required this.backedUp,
    required this.op,
    required this.opDone,
    required this.opTotal,
    required this.onConnect,
    required this.onDisconnect,
    required this.onBackupNow,
    required this.onSync,
  });

  final bool supported;
  final bool connected;
  final String? email;
  final int total;
  final int backedUp;
  final _Op op;
  final int opDone;
  final int opTotal;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onBackupNow;
  final VoidCallback onSync;

  bool get _busy => op != _Op.none;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GoogleDriveMark(size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google Drive',
                      style: AppText.rowTitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(),
                      style: AppText.meta.copyWith(
                        color: connected ? AppColors.pulse : AppColors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              if (connected) const _ConnectedDot(),
            ],
          ),
          if (supported) ...[
            const SizedBox(height: 16),
            if (!connected)
              _PrimaryButton(
                label: 'Connect Google Drive',
                loading: op == _Op.connect,
                onTap: onConnect,
              )
            else ...[
              _BackupStatusBanner(
                total: total,
                backedUp: backedUp,
                op: op,
                opDone: opDone,
                opTotal: opTotal,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MiniButton(
                      icon: AppIcons.backupNow,
                      label: 'Back up now',
                      loading: op == _Op.backup,
                      enabled: !_busy,
                      onTap: onBackupNow,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniButton(
                      icon: AppIcons.retake,
                      label: 'Sync',
                      loading: op == _Op.sync,
                      enabled: !_busy,
                      onTap: onSync,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _MiniButton(
                icon: AppIcons.disconnect,
                label: 'Disconnect',
                loading: op == _Op.disconnect,
                enabled: !_busy,
                onTap: onDisconnect,
                tint: AppColors.flareText,
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _subtitle() {
    if (!supported) return 'Unavailable in this build';
    if (connected) return email ?? 'Connected on this device';
    return 'Not connected on this device';
  }
}

/// The polished status panel inside the Drive card — the app's answer to
/// "am I backed up?". It has three resting looks (all-safe, some-pending,
/// nothing-yet) and, while a backup/sync runs, becomes a live progress readout
/// with a determinate bar and a "3 of 10" counter. Replaces the old bare
/// "$backedUp of $total backed up" line with something that reads as premium.
class _BackupStatusBanner extends StatelessWidget {
  const _BackupStatusBanner({
    required this.total,
    required this.backedUp,
    required this.op,
    required this.opDone,
    required this.opTotal,
  });

  final int total;
  final int backedUp;
  final _Op op;
  final int opDone;
  final int opTotal;

  @override
  Widget build(BuildContext context) {
    final running = op == _Op.backup || op == _Op.sync;

    // Accent + copy per state.
    late final Color accent;
    late final Color wash;
    late final IconData icon;
    late final String title;
    late final String subtitle;
    double? progress; // null → no bar (or indeterminate while checking)
    bool indeterminate = false;

    if (running) {
      accent = AppColors.ember;
      wash = AppColors.emberWash;
      icon = op == _Op.backup ? AppIcons.backupNow : AppIcons.retake;
      title = op == _Op.backup ? 'Backing up…' : 'Syncing…';
      if (opTotal == 0) {
        subtitle = 'Checking your photos…';
        indeterminate = true;
      } else {
        subtitle = '$opDone of $opTotal ${opTotal == 1 ? 'photo' : 'photos'}';
        progress = opDone / opTotal;
      }
    } else if (total == 0) {
      accent = AppColors.ink3;
      wash = AppColors.surfaceRaised;
      icon = AppIcons.driveCloud;
      title = 'Nothing to back up yet';
      subtitle = 'Photos you add will back up here.';
    } else if (backedUp >= total) {
      accent = AppColors.pulse;
      wash = AppColors.pulseWash;
      icon = AppIcons.success;
      title = 'All backed up';
      subtitle =
          '$total ${total == 1 ? 'photo is' : 'photos are'} safe in Google Drive.';
    } else {
      accent = AppColors.solar;
      wash = AppColors.solarWash;
      icon = AppIcons.backupNow;
      title = '$backedUp of $total backed up';
      final pending = total - backedUp;
      subtitle =
          '$pending ${pending == 1 ? 'photo is' : 'photos are'} waiting to back up.';
      progress = total == 0 ? 0 : backedUp / total;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: running
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: accent,
                        ),
                      )
                    : Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.rowTitle.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppText.meta.copyWith(color: AppColors.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (progress != null || indeterminate) ...[
            const SizedBox(height: 12),
            _ProgressBar(value: indeterminate ? null : progress, color: accent),
          ],
        ],
      ),
    );
  }
}

/// A slim, rounded progress bar tinted to the banner's accent. A null [value]
/// renders the indeterminate sweep (used while a run is still counting work).
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});

  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: value?.clamp(0.0, 1.0),
          backgroundColor: color.withValues(alpha: 0.16),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}

class _ConnectedDot extends StatelessWidget {
  const _ConnectedDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.pulseWash,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Connected',
        style: AppText.meta.copyWith(color: AppColors.pulse, fontSize: 11),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });
  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: !loading,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF7038), AppColors.ember],
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadows.ember,
          ),
          child: InkWell(
            onTap: loading ? null : onTap,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: AppText.button.copyWith(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onTap,
    this.tint,
  });
  final IconData icon;
  final String label;

  /// This button's own action is the one in flight — show its spinner.
  final bool loading;

  /// Tappable at all — false while any operation runs (including another
  /// button's), so the row dims and disables together.
  final bool enabled;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppColors.ink;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled || loading ? 1 : 0.45,
      child: PressableScale(
        enabled: enabled,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                else
                  Icon(icon, size: 16, color: color),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: AppText.button.copyWith(fontSize: 13, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
