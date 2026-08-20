import 'package:flutter/material.dart';

import '../../scope/app_scope.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/google_drive_mark.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_row.dart';
import '../../widgets/zivo_toast.dart';
import '../domain/media_object.dart';
import '../domain/media_storage_preferences.dart';
import '../media_service.dart';

/// "Storage & Sync" — the one screen that answers *where your photos are*:
/// always on this device, and optionally backed up to a Google Drive account
/// you connect **on this device**. Connecting is explicit here and nowhere
/// else, so opening Moments or taking a photo never triggers a sign-in.
class StorageSyncPage extends StatefulWidget {
  const StorageSyncPage({super.key});

  @override
  State<StorageSyncPage> createState() => _StorageSyncPageState();
}

class _StorageSyncPageState extends State<StorageSyncPage> {
  bool _busy = false;
  bool _connected = false;
  String? _email;
  int _total = 0;
  int _backedUp = 0;

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

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  void _toast(String message, ToastKind kind) {
    if (mounted) showZivoToast(context, message, kind: kind);
  }

  Future<void> _connect() => _run(() async {
        final ok = await _media.connectBackup();
        _toast(
          ok ? 'Google Drive connected on this device.' : 'Couldn’t connect Google Drive.',
          ok ? ToastKind.success : ToastKind.error,
        );
      });

  Future<void> _disconnect() => _run(() async {
        await _media.disconnectBackup();
        _toast('Google Drive disconnected on this device.', ToastKind.info);
      });

  Future<void> _backupNow() => _run(() async {
        final n = await _media.backupNow();
        _toast(
          n == 0 ? 'Everything is already backed up.' : 'Backed up $n ${_p(n)} to Drive.',
          ToastKind.success,
        );
      });

  Future<void> _syncFromDrive() => _run(() async {
        final n = await _media.syncFromBackup();
        _toast(
          n == 0 ? 'Nothing new to download.' : 'Downloaded $n ${_p(n)} from Drive.',
          ToastKind.success,
        );
      });

  String _p(int n) => n == 1 ? 'photo' : 'photos';

  @override
  Widget build(BuildContext context) {
    final prefsRepo = _media.preferences;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Storage & Sync', style: AppText.cardTitle.copyWith(fontSize: 20)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 40),
          children: [
            _DeviceCard(total: _total),
            const SizedBox(height: 22),
            Text('BACKUP & SYNC', style: AppText.sectionLabel),
            const SizedBox(height: 8),
            _DriveCard(
              supported: _media.supportsBackup,
              connected: _connected,
              email: _email,
              total: _total,
              backedUp: _backedUp,
              busy: _busy,
              onConnect: _connect,
              onDisconnect: _disconnect,
              onBackupNow: _backupNow,
              onSync: _syncFromDrive,
            ),
            const SizedBox(height: 22),
            StreamBuilder<MediaStoragePreferences>(
              stream: prefsRepo.watch(),
              initialData: MediaStoragePreferences.defaults,
              builder: (context, snapshot) {
                final prefs = snapshot.data ?? MediaStoragePreferences.defaults;
                return SettingsSectionCard(
                  label: 'DEVICE PHOTOS',
                  children: [
                    SettingsRow(
                      icon: AppIcons.photos,
                      title: 'Save to Photos',
                      value: prefs.saveToPhotos ? 'On' : 'Off',
                      last: true,
                      trailing: Switch.adaptive(
                        value: prefs.saveToPhotos,
                        activeThumbColor: AppColors.ember,
                        onChanged: _busy
                            ? null
                            : (v) => prefsRepo.save(prefs.copyWith(saveToPhotos: v)),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Text(
              'Each ZIVO account keeps its own photos in its own Drive folder, so '
              'accounts never mix — even if they use the same Google Drive.',
              style: AppText.meta.copyWith(color: AppColors.ink3, height: 1.4),
            ),
          ],
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
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.pulseWash,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(AppIcons.check, size: 22, color: AppColors.pulse),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('On this device', style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600)),
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
    required this.busy,
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
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onBackupNow;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
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
                    Text('Google Drive', style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(_subtitle(), style: AppText.meta.copyWith(color: connected ? AppColors.pulse : AppColors.ink3)),
                  ],
                ),
              ),
              if (connected) const _ConnectedDot(),
            ],
          ),
          if (supported) ...[
            const SizedBox(height: 16),
            if (!connected)
              _PrimaryButton(label: 'Connect Google Drive', busy: busy, onTap: onConnect)
            else ...[
              if (total > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '$backedUp of $total backed up',
                    style: AppText.meta.copyWith(color: AppColors.ink2),
                  ),
                ),
              Row(
                children: [
                  Expanded(child: _MiniButton(icon: AppIcons.backupNow, label: 'Back up now', busy: busy, onTap: onBackupNow)),
                  const SizedBox(width: 10),
                  Expanded(child: _MiniButton(icon: AppIcons.retake, label: 'Sync', busy: busy, onTap: onSync)),
                ],
              ),
              const SizedBox(height: 10),
              _MiniButton(icon: AppIcons.disconnect, label: 'Disconnect', busy: busy, onTap: onDisconnect, tint: AppColors.flareText),
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

class _ConnectedDot extends StatelessWidget {
  const _ConnectedDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.pulseWash, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text('Connected', style: AppText.meta.copyWith(color: AppColors.pulse, fontSize: 11)),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.busy, required this.onTap});
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: !busy,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.ember, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(label, style: AppText.button.copyWith(color: Colors.white, fontSize: 15)),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.label, required this.busy, required this.onTap, this.tint});
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppColors.ink;
    return PressableScale(
      enabled: !busy,
      child: GestureDetector(
        onTap: busy ? null : onTap,
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
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 7),
              Text(label, style: AppText.button.copyWith(fontSize: 13, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
