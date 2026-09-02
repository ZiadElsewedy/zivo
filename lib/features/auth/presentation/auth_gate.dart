import 'package:flutter/material.dart';

import '../../../core/scope/app_scope.dart';
import '../../profile/domain/session_state.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/pages/profile_completion_page.dart';
import '../../shell/presentation/home_shell.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_state.dart';
import '../domain/auth_user.dart';
import 'pages/auth_page.dart';
import 'pages/splash_screen.dart';
import 'pages/verify_email_page.dart';

/// The app's root surface: turns the two async facts the app needs before it
/// can show anything — the auth session and the user's profile — into exactly
/// one [SessionState], and renders the screen for it.
///
/// The composition is deliberately one-way and one-shot. This widget resolves
/// nothing itself: [resolveAuthState] decides what authentication means, and
/// [resolveSessionState] decides what the app does about it. Both are pure
/// functions living beside their own domain, which is why the routing policy
/// is unit-tested without pumping a single widget.
///
/// Streams are subscribed once each and cached, so a rebuild never re-opens
/// them — a `watchX()` call inside `build` would hand [StreamBuilder] a fresh
/// stream every frame, resetting it to `waiting` forever and leaking
/// subscriptions.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthRepository? _auth;
  Stream<AuthState>? _states;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AppScope.of(context).auth;
    // Re-subscribe only if the repository itself actually changed.
    if (!identical(auth, _auth)) {
      _auth = auth;
      _states = auth.watchAuthState();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Seed from the synchronously-known user via the shared policy so an
    // already-signed-in (or pending-verification) session skips the splash
    // flash. A null user stays "unknown" until the stream resolves it —
    // "nobody is signed in" and "we haven't looked yet" are different screens.
    final seeded = _auth!.currentUser;
    return StreamBuilder<AuthState>(
      stream: _states,
      initialData: seeded == null
          ? const AuthUnknown()
          : resolveAuthState(seeded),
      builder: (context, snapshot) {
        final authState = snapshot.data;
        // Only an authenticated session has a profile worth watching, so the
        // profile subscription is opened beneath this branch rather than at
        // the root — a signed-out visitor never opens a Firestore listener.
        if (authState is Authenticated) {
          return _SessionGate(user: authState.user);
        }
        return _screenFor(
          resolveSessionState(
            authState: authState ?? const AuthUnknown(),
            profile: null,
            profileLoaded: false,
          ),
        );
      },
    );
  }
}

/// Nested beneath the auth [StreamBuilder]: adds the profile half of the
/// answer for an already-[Authenticated] [user].
///
/// Stateful so the profile stream is created exactly once per user id, and
/// re-created when the id actually changes (an account switch).
class _SessionGate extends StatefulWidget {
  const _SessionGate({required this.user});

  final AuthUser user;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  Stream<UserProfile?>? _profileStream;
  String? _uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureStream();
  }

  @override
  void didUpdateWidget(covariant _SessionGate old) {
    super.didUpdateWidget(old);
    if (old.user.uid != widget.user.uid) _ensureStream();
  }

  void _ensureStream() {
    if (_profileStream != null && _uid == widget.user.uid) return;
    _uid = widget.user.uid;
    _profileStream = AppScope.of(context).profiles.watchProfile(_uid!);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile?>(
      stream: _profileStream,
      builder: (context, snapshot) {
        return _screenFor(
          resolveSessionState(
            authState: Authenticated(widget.user),
            profile: snapshot.data,
            // `waiting` with data already in hand is a re-emission, not a
            // cold start — treating it as "not loaded" would bounce a
            // complete profile back to the splash on every update.
            profileLoaded:
                snapshot.connectionState != ConnectionState.waiting ||
                snapshot.hasData,
          ),
        );
      },
    );
  }
}

/// The one place a [SessionState] becomes a screen. Exhaustive by virtue of
/// the sealed hierarchy: a new session state is a compile error here until
/// someone decides what it looks like.
Widget _screenFor(SessionState state) => switch (state) {
  SessionActive() => const HomeShell(),
  SessionNeedsProfile(:final user, :final suggestedName) =>
    ProfileCompletionPage(user: user, suggestedName: suggestedName),
  SessionNeedsEmailVerification(:final email) => VerifyEmailPage(email: email),
  SessionSignedOut() => const AuthPage(),
  SessionResolving() => const SplashScreen(),
};
