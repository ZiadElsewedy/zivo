import 'package:flutter/material.dart';

import '../../../../core/media/domain/media_storage_preferences.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import 'settings_row.dart';

/// The "Media & Backup" Settings section — where each account controls what
/// happens to app-captured media beyond the always-on durable local copy.
///
/// Phase 1 surfaces the fully-working "Save to Photos" toggle and a Google
/// Drive status row that is intentionally a placeholder until the Drive backup
/// target (and its Google Cloud OAuth setup) lands in Phase 2. The remaining
/// controls (auto-backup cadence, wifi-only, "Back up now") appear once a Drive
/// account can be connected, keeping Settings honest — no dead toggles.
class MediaBackupSection extends StatelessWidget {
  const MediaBackupSection({super.key});

  @override
  Widget build(BuildContext context) {
    final prefsRepo = AppScope.of(context).requireMedia.preferences;
    return StreamBuilder<MediaStoragePreferences>(
      stream: prefsRepo.watch(),
      initialData: MediaStoragePreferences.defaults,
      builder: (context, snapshot) {
        final prefs = snapshot.data ?? MediaStoragePreferences.defaults;
        return SettingsSectionCard(
          label: 'MEDIA & BACKUP',
          children: [
            SettingsRow(
              icon: Icons.photo_library_outlined,
              title: 'Save to Photos',
              value: prefs.saveToPhotos ? 'On' : 'Off',
              trailing: Switch.adaptive(
                value: prefs.saveToPhotos,
                activeThumbColor: AppColors.ember,
                onChanged: (value) =>
                    prefsRepo.save(prefs.copyWith(saveToPhotos: value)),
              ),
            ),
            SettingsRow(
              icon: Icons.cloud_outlined,
              title: 'Google Drive backup',
              value: prefs.driveConnected
                  ? (prefs.driveAccountEmail ?? 'Connected')
                  : 'Set up soon',
              last: true,
              onTap: () => _showDrivePending(context),
            ),
          ],
        );
      },
    );
  }

  void _showDrivePending(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceRaised,
          content: Text(
            'Google Drive backup arrives next — it unlocks once the Google '
            'Cloud setup is finished.',
          ),
        ),
      );
  }
}
