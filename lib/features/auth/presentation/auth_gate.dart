import 'package:flutter/material.dart';

import '../../../core/scope/app_scope.dart';
import '../../shell/presentation/home_shell.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_state.dart';
import 'pages/auth_page.dart';
import 'pages/splash_screen.dart';

/// Decides the top-level surface from the auth state:
/// `AuthUnknown`/waiting → [SplashScreen], `Authenticated` → [HomeShell],
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
    final seeded = _auth!.currentUser;
    return StreamBuilder<AuthState>(
      stream: _states,
      initialData: seeded == null ? const AuthUnknown() : Authenticated(seeded),
      builder: (context, snapshot) {
        final state = snapshot.data;
        return switch (state) {
          Authenticated() => const HomeShell(),
          Unauthenticated() => const AuthPage(),
          AuthUnknown() || null => const SplashScreen(),
        };
      },
    );
  }
}
