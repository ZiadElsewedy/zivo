import 'package:zivo/features/auth/data/device_session_guard.dart';
import 'package:zivo/features/auth/data/in_memory_device_session_repository.dart';

import 'fake_auth_repository.dart';

/// A [DeviceSessionGuard] for whole-app widget tests, backed entirely in memory
/// so booting `ZivoApp` never resolves `FirebaseFirestore.instance`. Inert in
/// these tests — no second device claims the account, so it never signs anyone
/// out — which is why it can own a throwaway [FakeAuthRepository].
DeviceSessionGuard fakeDeviceSessionGuard() => DeviceSessionGuard(
  authRepository: FakeAuthRepository(),
  repository: InMemoryDeviceSessionRepository(),
);
