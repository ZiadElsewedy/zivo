import 'package:flutter/material.dart';

import '../../../core/scope/app_scope.dart';
import '../../shell/presentation/home_shell.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_state.dart';
import '../domain/auth_user.dart';
import '../domain/user_profile.dart';
import 'pages/auth_page.dart';
import 'pages/profile_completion_page.dart';
import 'pages/splash_screen.dart';
import 'pages/verify_email_page.dart';

/// Decides the top-level surface from the auth state:
/// `AuthUnknown`/waiting → [SplashScreen], `Authenticated` (with a complete
/// profile) → [HomeShell], `Authenticated` (without one) →
/// [ProfileCompletionPage], `AwaitingEmailVerification` → [VerifyEmailPage],
/// `Unauthenticated` → [AuthPage].
///
/// The auth stream is resolved once (in [initState]) and cached, so this is the
/// single subscriber to it — one listener, no duplicate subscriptions, and no
/// re-subscription when the widget rebuilds.
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
    // Seed with a synchronously-known user so an already-signed-in session goes
    // straight to the shell without a splash flash. A null user stays "unknown"
    // (splash) until the stream resolves it to Unauthenticated.
    // Seed from the synchronously-known user via the shared policy so an
    // already-signed-in (or pending-verification) session skips the splash
    // flash. A null user stays "unknown" (splash) until the stream resolves it.
    final seeded = _auth!.currentUser;
    return StreamBuilder<AuthState>(
      stream: _states,
      initialData: seeded == null
          ? const AuthUnknown()
          : resolveAuthState(seeded),
      builder: (context, snapshot) {
        final state = snapshot.data;
        return switch (state) {
          Authenticated(:final user) => _ProfileGate(user: user),
          AwaitingEmailVerification(:final email) => VerifyEmailPage(
            email: email,
          ),
          Unauthenticated() => const AuthPage(),
          AuthUnknown() ||
          ProfileCompletionRequired() ||
          null => const SplashScreen(),
        };
      },
    );
  }
}

/// Nested beneath the outer auth [StreamBuilder]: resolves profile
/// completeness for an already-[Authenticated] [user] without coupling
/// [AuthRepository] to `ProfileRepository`.
///
/// Stateful so the profile stream is created exactly once per user id. Calling
/// `watchProfile` inside `build` would hand [StreamBuilder] a brand-new stream
/// on every rebuild, resetting it to the waiting/splash state forever and
/// leaking subscriptions — so the subscription is pinned here and only rebuilt
/// when the [user] id actually changes.
class _ProfileGate extends StatefulWidget {
  const _ProfileGate({required this.user});

  final AuthUser user;

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  Stream<UserProfile?>? _profileStream;
  String? _uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profiles = AppScope.of(context).profiles;
    if (_profileStream == null || _uid != widget.user.uid) {
      _uid = widget.user.uid;
      _profileStream = profiles.watchProfile(widget.user.uid);
    }
  }

  @override
  void didUpdateWidget(covariant _ProfileGate old) {
    super.didUpdateWidget(old);
    if (old.user.uid != widget.user.uid) {
      _uid = widget.user.uid;
      _profileStream = AppScope.of(
        context,
      ).profiles.watchProfile(widget.user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return StreamBuilder<UserProfile?>(
      stream: _profileStream,
      builder: (context, snapshot) {
        final sessionState = resolveSessionState(
          authState: Authenticated(user),
          profile: snapshot.data,
          profileLoaded:
              snapshot.connectionState != ConnectionState.waiting ||
              snapshot.hasData,
        );
        return switch (sessionState) {
          Authenticated() => const HomeShell(),
          ProfileCompletionRequired(:final user, :final suggestedName) =>
            ProfileCompletionPage(user: user, suggestedName: suggestedName),
          AuthUnknown() ||
          Unauthenticated() ||
          AwaitingEmailVerification() => const SplashScreen(),
        };
      },
    );
  }
}
