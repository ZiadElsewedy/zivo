import 'dart:async';

import 'package:zivo/features/auth/domain/auth_repository.dart';
import 'package:zivo/features/auth/domain/auth_result.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';

/// In-memory [AuthRepository] for widget/unit tests. Keeps Firebase out of the
/// test process entirely: it drives [AuthState] through a controller and
/// returns scripted [AuthResult]s.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthState initial = const AuthUnknown()}) : _state = initial;

  final StreamController<AuthState> _controller =
      StreamController<AuthState>.broadcast();
  AuthState _state;

  /// User handed back by a successful sign-in when no explicit result is scripted.
  AuthUser successUser = const AuthUser(
    uid: 'fake-uid',
    email: 'you@zivo.app',
    displayName: 'Ziad',
  );

  // Per-method overrides. When null, the call succeeds with [successUser].
  AuthResult? emailSignInResult;
  AuthResult? emailSignUpResult;
  AuthResult? googleResult;
  AuthResult? appleResult;

  int signOutCount = 0;

  /// Push a new auth state to listeners (used by gate tests).
  void emit(AuthState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Stream<AuthState> watchAuthState() async* {
    yield _state;
    yield* _controller.stream;
  }

  @override
  AuthUser? get currentUser =>
      _state is Authenticated ? (_state as Authenticated).user : null;

  Future<AuthResult> _resolve(AuthResult? scripted) async {
    final result = scripted ?? AuthSuccess(successUser);
    if (result is AuthSuccess) emit(Authenticated(result.user));
    return result;
  }

  @override
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) => _resolve(emailSignInResult);

  @override
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) => _resolve(emailSignUpResult);

  @override
  Future<AuthResult> signInWithGoogle() => _resolve(googleResult);

  @override
  Future<AuthResult> signInWithApple() => _resolve(appleResult);

  @override
  Future<void> signOut() async {
    signOutCount++;
    emit(const Unauthenticated());
  }

  Future<void> dispose() => _controller.close();
}
