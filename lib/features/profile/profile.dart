/// The profile module's public surface.
///
/// ```dart
/// import 'package:zivo/features/profile/profile.dart';
/// ```
///
/// ## What this module is
///
/// **The application's own record of the person**, keyed by the auth uid.
/// Where `features/auth/` is portable and says nothing about ZIVO, this one is
/// the opposite: it is entirely ZIVO's, and every project that copies the auth
/// module will write its own version of this one.
///
/// The split is the point. Firebase Auth owns the credential; it does not own
/// the human. Anything you want to query, validate, bound, extend, or write
/// transactionally alongside other data belongs here — in a document you
/// control — not on the auth record. `docs/AUTH.md` sets out the reasoning.
///
/// It also owns [SessionState]: the composition of "authentication says X"
/// with "this app additionally requires Y", which is app-specific by
/// definition and therefore cannot live in the auth module.
library;

export 'data/firestore_profile_repository.dart';
export 'domain/profile_repository.dart';
export 'domain/session_state.dart';
export 'domain/user_profile.dart';
