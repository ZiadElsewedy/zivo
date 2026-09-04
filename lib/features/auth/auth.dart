/// The authentication module's public surface.
///
/// Everything a consumer — inside this app or in the next one — needs, in one
/// import:
///
/// ```dart
/// import 'package:zivo/features/auth/auth.dart';
/// ```
///
/// ## What this module is, and is not
///
/// It is **identity, credentials, and session**. It owns who someone is to the
/// auth provider, how they prove it, and whether a session is usable right
/// now. There is deliberately nothing here about *this* application: no
/// profile, no onboarding, no roles, no product concepts. That is what makes
/// the folder liftable into another project — see `docs/AUTH.md` for the
/// architecture and the porting checklist.
///
/// The application's own record of the person lives in `features/profile/`,
/// keyed by [AuthUser.uid]. If you ever find yourself adding a product field
/// to [AuthUser], that field belongs there instead.
///
/// Presentation is exported separately (and is the part every project
/// rewrites): the screens live in `presentation/` and depend only on the
/// domain interfaces below.
library;

// --- domain: what the app talks to ------------------------------------------
export 'domain/account_auth_metadata.dart';
export 'domain/auth_activity_repository.dart';
export 'domain/auth_event.dart';
export 'domain/auth_event_type.dart';
export 'domain/auth_failure.dart';
export 'domain/auth_repository.dart';
export 'domain/auth_result.dart';
export 'domain/auth_state.dart';
export 'domain/auth_user.dart';
export 'domain/otp_result.dart';
export 'domain/password_policy.dart';

// --- data: the Firebase-backed implementation -------------------------------
// Swapping backend means replacing these and nothing above.
export 'data/auth_config.dart';
export 'data/firebase_auth_repository.dart';
export 'data/firestore_auth_activity_repository.dart';
export 'data/noop_auth_activity_repository.dart';
