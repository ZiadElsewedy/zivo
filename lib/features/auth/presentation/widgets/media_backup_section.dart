import 'package:flutter/material.dart';
import '../../../../l10n/l10n.dart';

import '../../../../core/theme/train_tokens.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/media/presentation/storage_sync_page.dart';
import '../../../../core/widgets/settings_row.dart';

/// The Settings entry into media storage. The actual controls live on the
/// dedicated [StorageSyncPage] (also reachable from Moments) — this is just the
/// link, keeping Settings tidy.
class MediaBackupSection extends StatelessWidget {
  const MediaBackupSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      label: l(context).settingsSectionMedia,
      children: [
        SettingsRow(
          icon: AppIcons.backupNow,
          title: l(context).settingsStorageSync,
          value: l(context).settingsStorageSyncValue,
          accent: TrainColors.green,
          last: true,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const StorageSyncPage())),
        ),
      ],
    );
  }
}
