import 'package:flutter/material.dart';

import '../../../../core/media/domain/media_storage_preferences.dart';
import '../../../../core/media/media_service.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/google_drive_mark.dart';
import '../../../../core/widgets/zivo_toast.dart';
import 'settings_row.dart';

/// The "Media & Backup" Settings section — where each account controls what
/// happens to app-captured media beyond the always-on durable local copy:
/// optionally save to the system Photos library, and optionally back up to
/// Google Drive (connect an account, back up on demand, and a 3-day cadence).
class MediaBackupSection extends StatefulWidget {
  const MediaBackupSection({super.key});

  @override
  State<MediaBackupSection> createState() => _MediaBackupSectionState();
}

class _MediaBackupSectionState extends State<MediaBackupSection> {
  bool _busy = false;

  MediaService get _media => AppScope.of(context).requireMedia;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message, ToastKind kind) {
    if (mounted) showZivoToast(context, message, kind: kind);
  }

  Future<void> _setPrefs(MediaStoragePreferences prefs) =>
      _media.preferences.save(prefs);

  Future<void> _connectDrive() => _run(() async {
        final connected = await _media.connectDrive();
        _toast(
          connected
              ? 'Google Drive connected — backups are on.'
              : 'Couldn’t connect Google Drive.',
          connected ? ToastKind.success : ToastKind.error,
        );
      });

  Future<void> _backupNow() => _run(() async {
        final pushed = await _media.backupNow();
        _toast(
          pushed == 0
              ? 'Everything is already backed up.'
              : 'Backed up $pushed ${pushed == 1 ? 'photo' : 'photos'} to Drive.',
          ToastKind.success,
        );
      });

  Future<void> _disconnectDrive() => _run(() async {
        await _media.disconnectDrive();
        _toast('Google Drive disconnected.', ToastKind.info);
      });

  @override
  Widget build(BuildContext context) {
    final prefsRepo = _media.preferences;
    return StreamBuilder<MediaStoragePreferences>(
      stream: prefsRepo.watch(),
      initialData: MediaStoragePreferences.defaults,
      builder: (context, snapshot) {
        final prefs = snapshot.data ?? MediaStoragePreferences.defaults;
        final connected = prefs.driveConnected;
        return SettingsSectionCard(
          label: 'MEDIA & BACKUP',
          children: [
            SettingsRow(
              icon: AppIcons.photos,
              title: 'Save to Photos',
              value: prefs.saveToPhotos ? 'On' : 'Off',
              trailing: Switch.adaptive(
                value: prefs.saveToPhotos,
                activeThumbColor: AppColors.ember,
                onChanged: _busy
                    ? null
                    : (value) => _setPrefs(prefs.copyWith(saveToPhotos: value)),
              ),
            ),
            ..._driveRows(prefs, connected),
          ],
        );
      },
    );
  }

  List<Widget> _driveRows(MediaStoragePreferences prefs, bool connected) {
    // Drive backup isn't wired in offline/dev builds.
    if (!_media.supportsDrive) {
      return [
        SettingsRow(
          icon: AppIcons.driveCloud,
          title: 'Google Drive backup',
          value: 'Unavailable',
          last: true,
        ),
      ];
    }

    if (!connected) {
      return [
        SettingsRow(
          icon: Icons.cloud_outlined,
          iconWidget: const GoogleDriveMark(),
          title: 'Google Drive backup',
          value: _busy ? 'Connecting…' : 'Connect',
          last: true,
          onTap: _busy ? null : _connectDrive,
        ),
      ];
    }

    return [
      SettingsRow(
        icon: Icons.cloud_done_outlined,
        iconWidget: const GoogleDriveMark(),
        title: 'Google Drive',
        value: prefs.driveAccountEmail ?? 'Connected',
      ),
      SettingsRow(
        icon: AppIcons.backupNow,
        title: 'Back up now',
        value: _busy ? 'Working…' : '',
        onTap: _busy ? null : _backupNow,
      ),
      SettingsRow(
        icon: AppIcons.schedule3Day,
        title: 'Auto-backup every 3 days',
        value: prefs.autoBackupEveryDays != null ? 'On' : 'Off',
        trailing: Switch.adaptive(
          value: prefs.autoBackupEveryDays != null,
          activeThumbColor: AppColors.ember,
          onChanged: _busy
              ? null
              : (value) => _setPrefs(value
                  ? prefs.copyWith(autoBackupEveryDays: 3)
                  : prefs.copyWith(clearAutoBackupEveryDays: true)),
        ),
      ),
      SettingsRow(
        icon: AppIcons.wifi,
        title: 'Wi-Fi only',
        value: prefs.wifiOnly ? 'On' : 'Off',
        trailing: Switch.adaptive(
          value: prefs.wifiOnly,
          activeThumbColor: AppColors.ember,
          onChanged:
              _busy ? null : (value) => _setPrefs(prefs.copyWith(wifiOnly: value)),
        ),
      ),
      SettingsRow(
        icon: AppIcons.disconnect,
        title: 'Disconnect Drive',
        value: '',
        last: true,
        onTap: _busy ? null : _disconnectDrive,
      ),
    ];
  }
}
