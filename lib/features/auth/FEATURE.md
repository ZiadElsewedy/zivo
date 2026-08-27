# auth — feature map

> Sign-in, email verification, **password reset + change**, **account deletion**, profile,
> settings, privacy. Backed by Firebase Auth + Firestore (profiles + an append-only
> auth-event log). The OTP codes are minted server-side: the shared, unit-tested OTP core is
> [`functions/auth/otp.js`](../../../functions/auth/otp.js), the callables live in
> [`functions/index.js`](../../../functions/index.js), and event/summary bookkeeping in
> [`functions/auth/activity.js`](../../../functions/auth/activity.js).

## Start here

- `presentation/auth_gate.dart` — **`AuthGate`**: the app's root gate (`app.dart` sets
  `home: AuthGate`). Routes splash → auth → verify → profile-completion → the shell.
- `presentation/pages/`: `splash_screen.dart`, `auth_page.dart` (sign in / up, with the
  **Forgot password?** link), `verify_email_page.dart` (OTP), `forgot_password_page.dart`
  (signed-out reset: email → code + new password), `change_password_page.dart` (signed-in
  reauth + new password), `profile_completion_page.dart`, `profile_page.dart` (the "You"
  tab), `settings_page.dart` (**ACCOUNT** section: change password + delete account),
  `privacy_page.dart`.
- Widgets: `email_auth_form.dart`, `social_auth_buttons.dart` (Apple/Google),
  `otp_code_input.dart`, `dob_picker_sheet.dart` (shared DOB wheel — onboarding + edit),
  `auth_action_button.dart`, `auth_text_field.dart` + `password_checklist.dart` (shared auth
  inputs, used by sign-up / reset / change), `delete_account_sheet.dart` (reauth-gated
  deletion), `media_backup_section.dart` (the Media & Backup settings block).

## Repositories

- **`AuthRepository`** (`AppScope.auth`) — `firebase_auth_repository.dart`; email-OTP +
  Apple/Google/password, plus `sendPasswordResetOtp` / `resetPasswordWithOtp` (signed-out),
  `changePassword` (reauth), and `deleteAccount` (reauth → server-side wipe). Config in
  `data/auth_config.dart`, policy in `domain/password_policy.dart`.
- **`ProfileRepository`** (`AppScope.profiles`) — `firestore_profile_repository.dart`;
  `domain/user_profile.dart`.
- **`AuthActivityRepository`** (`AppScope.activity`, nullable) — append-only event log;
  `firestore_auth_activity_repository.dart` (real) vs `noop_auth_activity_repository.dart`
  (offline). Events: `domain/auth_event.dart`, `auth_event_type.dart`.

## Domain highlights

`auth_state.dart`, `auth_user.dart`, `auth_result.dart`, `auth_failure.dart`,
`otp_result.dart`, `account_auth_metadata.dart`.

## Gotchas

- The auth-event log is **append-only** and verified by the Firestore rules suite — don't
  add mutating writes to it.
- `AuthGate`'s initial session restore is treated as *not* an account change (so a valid
  media-backup connection survives launch); the account-switch reset lives in
  [`app.dart`](../../app/app.dart)'s `_authSub`.
- Both OTP flows use **hashed** codes (HMAC + salt + `OTP_PEPPER`) from the shared
  `functions/auth/otp.js` decision core. **Throttle accounting (`windowStartAt`/`sendCount`/
  `lastSentAt`) is stored alongside the code but is NEVER cleared when the code is consumed,
  expires, or is locked out** — clearing it would let the hourly send cap be bypassed by
  exhausting attempts. If you touch `otp.js`, keep `clearCodePatch()` code-only and keep the
  regression test in `otp.test.js`.
- Two Admin-SDK-only collections are locked to clients by the rules (with rule tests):
  `emailOtps/{uid}` and `passwordResetOtps/{uid}`.
- The signed-out reset endpoints are **enumeration-safe**: they resolve the account
  server-side and return the same shape whether or not it exists (missing/social-only →
  generic "sent"; a bad reset code → the same "no active code" as an expired one). Only
  accounts with a `password` provider are eligible.
- A successful password **reset** also flips `emailVerified` (receiving the code proves
  ownership), so an unverified user isn't re-bounced through verification after resetting.
- **Account deletion** is server-side (`deleteAccount` callable: `recursiveDelete` of
  `users/{uid}` + both OTP docs + `deleteUser`), gated by a client-side **reauthentication**
  (password typed, or the provider flow re-run for Google/Apple).
- **Firebase App Check is not yet wired** (deferred by owner request) — the callables and
  Auth endpoints are otherwise reachable by anything holding the app config. See STATE.md's
  owner action items.
