import 'auth_failure.dart';

/// The outcome of requesting a verification code be sent to the user's email.
///
/// A cooldown response is modelled distinctly from a failure: asking again
/// while a fresh code is still valid is *not* an error — the UI simply shows
/// the remaining countdown rather than a red banner.
sealed class OtpSendResult {
  const OtpSendResult();
}

/// A new code was generated and emailed. [cooldownSeconds] is how long before
/// another send is allowed; [expiresInSeconds] is the code's lifetime.
class OtpSendSuccess extends OtpSendResult {
  const OtpSendSuccess({
    required this.cooldownSeconds,
    required this.expiresInSeconds,
  });

  final int cooldownSeconds;
  final int expiresInSeconds;
}

/// A valid code was already sent recently; no new code was generated. The UI
/// keeps counting down [retryAfterSeconds] before offering resend again.
class OtpSendCooldown extends OtpSendResult {
  const OtpSendCooldown({required this.retryAfterSeconds});

  final int retryAfterSeconds;
}

/// The send failed for a presentable [failure] (rate cap hit, network, etc.).
class OtpSendFailed extends OtpSendResult {
  const OtpSendFailed(this.failure, {this.retryAfterSeconds});

  final AuthFailure failure;

  /// Set when the failure is a rate cap, so the UI can disable resend for a
  /// while rather than letting the user hammer it.
  final int? retryAfterSeconds;
}

/// The outcome of submitting a 6-digit code for verification.
///
/// The variants mirror the exact server-side rejections so the UI can show
/// precise, distinct copy for each (wrong vs. expired vs. locked out) — all
/// verification is decided server-side; the client only renders the verdict.
sealed class OtpVerifyResult {
  const OtpVerifyResult();
}

/// The code matched. The email is now verified server-side and the session has
/// been refreshed; the gate will advance to the app shell.
class OtpVerifySuccess extends OtpVerifyResult {
  const OtpVerifySuccess();
}

/// The code was wrong. [attemptsRemaining] is how many tries are left before
/// the code is locked (null if the server did not report it).
class OtpVerifyInvalid extends OtpVerifyResult {
  const OtpVerifyInvalid({this.attemptsRemaining});

  final int? attemptsRemaining;
}

/// No unexpired code exists — it timed out or was already consumed. The user
/// must request a fresh one.
class OtpVerifyExpired extends OtpVerifyResult {
  const OtpVerifyExpired();
}

/// Too many wrong attempts; the current code is now invalidated. The user must
/// request a fresh one (subject to the resend cooldown).
class OtpVerifyTooManyAttempts extends OtpVerifyResult {
  const OtpVerifyTooManyAttempts({this.retryAfterSeconds});

  final int? retryAfterSeconds;
}

/// The verification failed for another presentable [failure] (network, etc.).
class OtpVerifyFailed extends OtpVerifyResult {
  const OtpVerifyFailed(this.failure);

  final AuthFailure failure;
}
