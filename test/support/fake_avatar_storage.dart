import 'dart:io';

import 'package:zivo/features/profile/domain/avatar_storage.dart';

/// In-memory [AvatarStorage] for widget/unit tests. Records what was uploaded
/// or removed and hands back a deterministic fake URL, so a test can drive the
/// profile photo flow without Firebase Storage.
class FakeAvatarStorage implements AvatarStorage {
  /// uid → the URL the most recent upload returned.
  final Map<String, String> uploaded = {};

  /// uids passed to [remove].
  final List<String> removed = [];

  /// When set, [upload] throws this instead of succeeding — for exercising
  /// error handling.
  Object? uploadError;

  @override
  Future<String> upload({
    required String uid,
    required File file,
    String mimeType = 'image/jpeg',
  }) async {
    if (uploadError != null) throw uploadError!;
    final url = 'https://fake.storage/avatars/$uid?token=${uploaded.length + 1}';
    uploaded[uid] = url;
    return url;
  }

  @override
  Future<void> remove(String uid) async {
    removed.add(uid);
    uploaded.remove(uid);
  }
}
