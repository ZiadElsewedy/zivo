import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/auth_failure.dart';
import '../../domain/otp_result.dart';

/// Translates a Cloud Functions rejection into the domain's OTP result types.
///
/// Split out from the source that makes the calls because this is *policy*,
/// not transport: it decides what each server-side refusal means to a person
/// staring at a code field. Keeping it pure and separate means the whole
/// mapping is readable in one screen — and it is the file to read when the
/// question is "why did the user see that message?".
///
/// The server's `HttpsError` codes are the contract (see `functions/index.js`);
/// the `details` map carries the numbers the UI needs to count down with.
abstract final class OtpErrorMapper {
  /// A failed "send me a code" call.
  static OtpSendResult send(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'resource-exhausted':
        return OtpSendFailed(
          const AuthFailure(
            AuthFailureKind.tooManyRequests,
            'Too many code requests. Please try again later.',
          ),
          retryAfterSeconds: _detailInt(e.details, 'retryAfterSeconds'),
        );
      case 'unauthenticated':
        return const OtpSendFailed(
          AuthFailure(
            AuthFailureKind.providerConfig,
            'Your session expired. Please sign in again.',
          ),
        );
      // A timeout is the network, not the mail provider — don't blame the
      // wrong thing in the message.
      case 'unavailable':
      case 'deadline-exceeded':
        return const OtpSendFailed(
          AuthFailure(
            AuthFailureKind.networkError,
            "Couldn't send the code. Check your connection and try again.",
          ),
        );
      default:
        return const OtpSendFailed(
          AuthFailure(
            AuthFailureKind.emailDeliveryFailed,
            "We couldn't send your code right now. Please try again in a "
            'moment.',
          ),
        );
    }
  }

  /// A failed "here is my code" call. The variants mirror the server's exact
  /// rejections so the UI can say *which* thing went wrong — wrong, expired,
  /// and locked out are three different problems with three different fixes.
  static OtpVerifyResult verify(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'invalid-argument':
        // The reset flow tags a password rejected as too weak, so it isn't
        // mislabelled as a wrong code.
        if (_detailString(e.details, 'reason') == 'weakPassword') {
          return const OtpVerifyFailed(
            AuthFailure(
              AuthFailureKind.weakPassword,
              'Choose a stronger password (at least 8 characters, with upper- '
              'and lowercase letters and a number).',
            ),
          );
        }
        return OtpVerifyInvalid(
          attemptsRemaining: _detailInt(e.details, 'attemptsRemaining'),
        );
      case 'not-found':
      case 'failed-precondition':
        return const OtpVerifyExpired();
      case 'resource-exhausted':
        return OtpVerifyTooManyAttempts(
          retryAfterSeconds: _detailInt(e.details, 'retryAfterSeconds'),
        );
      case 'unauthenticated':
        return const OtpVerifyFailed(
          AuthFailure(
            AuthFailureKind.providerConfig,
            'Your session expired. Please sign in again.',
          ),
        );
      // A timeout is a connectivity problem, not an expired code — say so
      // rather than sending the user to request a fresh one for no reason.
      case 'deadline-exceeded':
      case 'unavailable':
        return const OtpVerifyFailed(
          AuthFailure(
            AuthFailureKind.networkError,
            "Couldn't verify the code. Check your connection and try again.",
          ),
        );
      default:
        return const OtpVerifyFailed(
          AuthFailure(
            AuthFailureKind.emailDeliveryFailed,
            "Couldn't verify your code right now. Please try again in a "
            'moment.',
          ),
        );
    }
  }

  /// Callable results are JSON-ish `Object?`; coerce a numeric field to int.
  static int? asInt(Object? v) => switch (v) {
    final int i => i,
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  static int? _detailInt(Object? details, String key) =>
      details is Map ? asInt(details[key]) : null;

  static String? _detailString(Object? details, String key) =>
      details is Map && details[key] is String ? details[key] as String : null;
}
