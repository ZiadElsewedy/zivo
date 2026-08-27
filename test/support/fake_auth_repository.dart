import 'dart:async';

import 'package:zivo/features/auth/domain/auth_repository.dart';
import 'package:zivo/features/auth/domain/auth_result.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/domain/otp_result.dart';

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

  /// Scripted OTP outcomes for verify-screen tests. Default to a happy path.
  OtpSendResult sendOtpResult =
      const OtpSendSuccess(cooldownSeconds: 60, expiresInSeconds: 600);
  OtpVerifyResult verifyOtpResult = const OtpVerifySuccess();

  int sendOtpCount = 0;
  final List<String> verifiedCodes = <String>[];

  @override
  Future<OtpSendResult> sendEmailOtp() async {
    sendOtpCount++;
    return sendOtpResult;
  }

  @override
  Future<OtpVerifyResult> verifyEmailOtp(String code) async {
    verifiedCodes.add(code);
    // On success, mimic the real repo: the email becomes verified and the gate
    // advances to the signed-in user.
    if (verifyOtpResult is OtpVerifySuccess) emit(Authenticated(successUser));
    return verifyOtpResult;
  }

  /// Scripted outcomes for the password-reset + account-management flows.
  OtpSendResult sendResetOtpResult =
      const OtpSendSuccess(cooldownSeconds: 60, expiresInSeconds: 600);
  OtpVerifyResult resetPasswordResult = const OtpVerifySuccess();
  AuthResult? changePasswordResult;
  AuthResult? deleteAccountResult;

  int sendResetOtpCount = 0;
  int changePasswordCount = 0;
  int deleteAccountCount = 0;
  final List<String> resetEmails = <String>[];

  @override
  Future<OtpSendResult> sendPasswordResetOtp({required String email}) async {
    sendResetOtpCount++;
    resetEmails.add(email);
    return sendResetOtpResult;
  }

  @override
  Future<OtpVerifyResult> resetPasswordWithOtp({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    verifiedCodes.add(code);
    // Mimic the real repo: a successful reset signs the user in.
    if (resetPasswordResult is OtpVerifySuccess) {
      emit(Authenticated(successUser));
    }
    return resetPasswordResult;
  }

  @override
  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCount++;
    return changePasswordResult ?? AuthSuccess(successUser);
  }

  @override
  Future<AuthResult> deleteAccount({String? password}) async {
    deleteAccountCount++;
    final result = deleteAccountResult ?? AuthSuccess(successUser);
    // Mimic the real repo: a successful delete signs out.
    if (result is AuthSuccess) emit(const Unauthenticated());
    return result;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    emit(const Unauthenticated());
  }

  Future<void> dispose() => _controller.close();
}
