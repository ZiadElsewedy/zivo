import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/auth_failure.dart';
import '../../domain/otp_result.dart';
import '../mappers/otp_error_mapper.dart';

/// Every call the auth feature makes to the ZIVO backend (`functions/`).
///
/// Four callables, one shape each way:
///
///   sendEmailOtp()                              → email a verification code
///   verifyEmailOtp(code)                        → verify it
///   sendPasswordResetOtp(email)                 → email a code (signed out)
///   resetPasswordWithOtp(email, code, password) → verify it, set the password
///   deleteAccount()                             → erase all data + identity
///
/// The two OTP *flows* differ only in which callable they name and what they
/// send, so they share one send path and one verify path here rather than
/// duplicating the transport and its error mapping twice. That shared path is
/// the client mirror of `functions/auth/otp.js`, which does the same thing on
/// the server for the same reason.
///
/// Nothing here decides policy. Code generation, hashing, expiry, attempt
/// caps, throttling, enumeration-safety and password strength all live
/// server-side; the client only names the call and renders the verdict. That
/// is the whole point — a client that could decide any of those could bypass
/// all of them.
class AuthCallablesSource {
  AuthCallablesSource({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Requests a verification code for the signed-in user's own address.
  Future<OtpSendResult> sendEmailOtp() => _send('sendEmailOtp');

  /// Requests a password-reset code for [email], signed OUT.
  ///
  /// The backend returns the same result whether or not the address has an
  /// account, so the UI must always advance to the code step. Branching on
  /// "does this account exist?" here would rebuild, on the client, exactly the
  /// enumeration oracle the server was designed to withhold.
  Future<OtpSendResult> sendPasswordResetOtp(String email) =>
      _send('sendPasswordResetOtp', {'email': email.trim()});

  /// Submits a verification code for the signed-in user.
  Future<OtpVerifyResult> verifyEmailOtp(String code) =>
      _verify('verifyEmailOtp', {'code': code});

  /// Submits a reset code and the new password, signed OUT.
  Future<OtpVerifyResult> resetPasswordWithOtp({
    required String email,
    required String code,
    required String newPassword,
  }) => _verify('resetPasswordWithOtp', {
    'email': email.trim(),
    'code': code,
    'newPassword': newPassword,
  });

  /// Erases the account server-side: every document under `users/{uid}`, both
  /// OTP records, then the auth identity itself.
  ///
  /// The caller MUST have reauthenticated immediately before — the server
  /// checks the ID token's `auth_time` and refuses a stale one, so a client
  /// that skips the prompt gets a `failed-precondition`, not a deletion.
  Future<void> deleteAccount() =>
      _functions.httpsCallable('deleteAccount').call<Map<dynamic, dynamic>>();

  /// The shared "request a code" transport. [payload] is null for the
  /// authenticated verification send and carries the address for the
  /// signed-out reset send.
  Future<OtpSendResult> _send(
    String callable, [
    Map<String, dynamic>? payload,
  ]) async {
    try {
      final fn = _functions.httpsCallable(callable);
      final res = payload == null
          ? await fn.call<Map<dynamic, dynamic>>()
          : await fn.call<Map<dynamic, dynamic>>(payload);
      final data = res.data;
      switch (data['status'] as String?) {
        case 'already-verified':
          return const OtpSendAlreadyVerified();
        case 'cooldown':
          return OtpSendCooldown(
            retryAfterSeconds:
                OtpErrorMapper.asInt(data['retryAfterSeconds']) ?? 60,
          );
        default:
          return OtpSendSuccess(
            cooldownSeconds:
                OtpErrorMapper.asInt(data['cooldownSeconds']) ?? 60,
            expiresInSeconds:
                OtpErrorMapper.asInt(data['expiresInSeconds']) ?? 600,
          );
      }
    } on FirebaseFunctionsException catch (e) {
      return OtpErrorMapper.send(e);
    } catch (_) {
      return const OtpSendFailed(_unknownFailure);
    }
  }

  /// The shared "submit a code" transport. Success is the absence of a
  /// rejection: the server returns no payload worth reading, because every
  /// consequence of a correct code is applied server-side.
  Future<OtpVerifyResult> _verify(
    String callable,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _functions
          .httpsCallable(callable)
          .call<Map<dynamic, dynamic>>(payload);
      return const OtpVerifySuccess();
    } on FirebaseFunctionsException catch (e) {
      return OtpErrorMapper.verify(e);
    } catch (_) {
      return const OtpVerifyFailed(_unknownFailure);
    }
  }
}

const _unknownFailure = AuthFailure(
  AuthFailureKind.unknown,
  'Something went wrong. Please try again.',
);
