import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../moments/presentation/pages/storage_sync_page.dart';
import 'settings_row.dart';

/// The Settings entry into media storage. The actual controls live on the
/// dedicated [StorageSyncPage] (also reachable from Moments) — this is just the
/// link, keeping Settings tidy.
class MediaBackupSection extends StatelessWidget {
  const MediaBackupSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      label: 'MEDIA',
      children: [
        SettingsRow(
          icon: AppIcons.backupNow,
          title: 'Storage & Sync',
          value: 'Photos, backup, Drive',
          last: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StorageSyncPage()),
          ),
        ),
      ],
    );
  }
}
