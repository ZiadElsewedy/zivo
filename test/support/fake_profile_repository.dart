import 'dart:async';

import 'package:zivo/features/profile/domain/profile_repository.dart';
import 'package:zivo/features/profile/domain/user_profile.dart';

/// In-memory [ProfileRepository] for widget/unit tests.
///
/// Defaults to a *complete* profile so existing gate tests — which emit
/// `Authenticated` and expect the home shell — keep passing without knowing
/// about profiles at all. Tests that want to exercise
/// `ProfileCompletionRequired` should call [setProfile] with `null` or an
/// incomplete profile before pumping.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({UserProfile? initial})
    : _current = initial ?? _defaultComplete;

  static final UserProfile _defaultComplete = UserProfile(
    uid: 'fake-uid',
    name: 'Ziad',
    dateOfBirth: DateTime(1990, 1, 1),
  );

  final StreamController<UserProfile?> _controller =
      StreamController<UserProfile?>.broadcast();
  UserProfile? _current;

  /// When set, [saveProfile] throws this instead of persisting — for
  /// exercising error handling in tests.
  Object? saveProfileError;

  /// The arguments of the most recent [saveProfile] call, or null if it was
  /// never called.
  UserProfile? lastSaved;

  /// Push a new profile (or null) to listeners.
  void setProfile(UserProfile? profile) {
    _current = profile;
    _controller.add(profile);
  }

  @override
  Stream<UserProfile?> watchProfile(String uid) async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<UserProfile?> fetchProfile(String uid) async => _current;

  @override
  Future<void> saveProfile({
    required String uid,
    required String name,
    required DateTime dateOfBirth,
    String? photoPath,
    String? bio,
  }) async {
    final saved = UserProfile(uid: uid, name: name, dateOfBirth: dateOfBirth, photoPath: photoPath, bio: bio);
    lastSaved = saved;
    if (saveProfileError != null) throw saveProfileError!;
    setProfile(saved);
  }

  Future<void> dispose() => _controller.close();
}
