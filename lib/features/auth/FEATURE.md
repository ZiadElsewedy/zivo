# auth — feature map

> **Identity, credentials, and session — and nothing else.** Sign-in, email
> verification, password reset + change, account deletion, plus the auth-activity
> audit trail. Backed by Firebase Auth + Cloud Functions.
>
> This module is deliberately **portable**: it contains no ZIVO concept at all. The
> app's own record of the person lives in [`../profile/`](../profile/FEATURE.md),
> keyed by `AuthUser.uid`. **Read [`docs/AUTH.md`](../../../docs/AUTH.md) before
> changing the shape of anything here** — it explains why the boundary is where it is.

## Start here

- **[`auth.dart`](auth.dart)** — the barrel. One import for the whole public surface.
- `presentation/auth_gate.dart` — **`AuthGate`**: the app's root gate (`app.dart` sets
  `home: AuthGate`). Subscribes to the auth stream and, beneath it, the profile
  stream; resolves both into one `SessionState` and renders the screen for it. It
  decides nothing itself — `resolveAuthState` and `resolveSessionState` are pure
  functions tested without widgets.
- `presentation/pages/`: `splash_screen.dart`, `auth_page.dart` (sign in / up, with
  **Forgot password?**), `verify_email_page.dart` (OTP),
  `forgot_password_page.dart` (signed-out reset: email → code + new password),
  `change_password_page.dart` (signed-in reauth + new password),
  `settings_page.dart` (**ACCOUNT**: change password + delete account),
  `privacy_page.dart`.
- Widgets: `email_auth_form.dart`, `social_auth_buttons.dart` (Apple/Google),
  `otp_code_input.dart`, `auth_action_button.dart`, `auth_text_field.dart` +
  `password_checklist.dart`, `delete_account_sheet.dart` (reauth-gated deletion),
  `media_backup_section.dart`.
- Shared auth chrome — use these on any new auth surface so the flow stays one system:
  `auth_backdrop.dart` (warm hue bloom), `auth_header.dart` (`AuthHeader` +
  `AuthSectionLabel`), `auth_footer_bar.dart` (`AuthFooterBar`). `AuthTextField` owns
  the floating label, focus glow, and password reveal — don't hand-roll an
  `InputDecoration` field alongside it.

## Domain — four responsibilities, four interfaces

`AuthRepository` (`AppScope.auth`) is the **union** of four facets, so a screen can
depend on only what it uses while DI still passes one object:

| Facet | Covers |
|---|---|
| `SessionAuthentication` | watch/current user, sign in (email · Google · Apple), sign up, sign out |
| `EmailVerification` | `sendEmailOtp` / `verifyEmailOtp` |
| `PasswordManagement` | `sendPasswordResetOtp` / `resetPasswordWithOtp` (signed out), `changePassword` (reauth) |
| `AccountLifecycle` | `deleteAccount` (reauth → server-side wipe) |

Also: `AuthUser` (identity only), `AuthState` + `resolveAuthState` (the verification
policy — **no profile knowledge**), `AuthResult`/`AuthFailure`, `OtpSendResult`/
`OtpVerifyResult`, `PasswordPolicy`, and the activity models (`AuthEvent`,
`AuthEventType`, `AccountAuthMetadata`).

**`AuthActivityRepository`** (`AppScope.activity`, nullable) is separate on purpose:
bookkeeping must never be able to fail a sign-in, which is a different contract.
`firestore_auth_activity_repository.dart` (real) vs `noop_auth_activity_repository.dart`
(offline).

## Data — a composition root and its sources

`firebase_auth_repository.dart` orchestrates; every mechanism sits beside it:

| File | Owns |
|---|---|
| `sources/email_password_source.dart` | Email+password credentials: create, present, re-present, replace |
| `sources/federated_auth_source.dart` | Google + Apple flows, the Apple nonce, and reauth credentials |
| `sources/auth_callables_source.dart` | Every backend call — both OTP flows share one send/verify path |
| `mappers/firebase_user_mapper.dart` | `fb.User` → `AuthUser` (+ `AuthProviderIds`) |
| `mappers/otp_error_mapper.dart` | Server rejection → domain result |
| `auth_activity_recorder.dart` | Fire-and-forget audit writes (void, error-swallowing by signature) |

## Gotchas

- **Client checks have server halves.** `resolveAuthState` ↔ `emailTrusted()` in
  `firestore.rules`; `PasswordPolicy` ↔ `isStrongPassword`; the reauth prompt ↔
  `requireRecentAuth`. Change one, change the other — the table is in `docs/AUTH.md` §4.
- **`verifyEmailOtp` must force a token refresh.** `getIdToken(true)` is not cosmetic:
  the `email_verified` claim in that token is what the Firestore rules gate writes on,
  so the refresh is what actually grants write access.
- The auth-event log is **append-only** and now `hasOnly`-pinned; the summary doc's
  `emailVerifiedAt`/`emailLastSentAt` are server-authored and rejected from client
  writes. Both are verified by the rules suite — don't add mutating writes.
- `AuthGate`'s initial session restore is treated as *not* an account change (so a
  valid media-backup connection survives launch); the account-switch reset lives in
  [`app.dart`](../../app/app.dart)'s `_authSub`.
- Both OTP flows use **hashed** codes (HMAC + salt + `OTP_PEPPER`) from the shared
  `functions/auth/otp.js` core. **Throttle accounting is NEVER cleared** when a code
  is consumed, expires, or locks out — clearing it would let the hourly cap be
  bypassed by exhausting attempts. Keep `clearCodePatch()` code-only and keep the
  regression test in `otp.test.js`.
- `emailOtps/{uid}` and `passwordResetOtps/{uid}` are Admin-SDK-only, locked to
  clients by the rules (with tests).
- The signed-out reset endpoints are **enumeration-safe** — same shape whether or not
  the account exists. The client must always advance to the code step; branching on
  existence would rebuild the oracle client-side.
- A successful **reset** also flips `emailVerified` (receiving the code proves
  ownership) and **revokes all refresh tokens** (a reset is what someone does when
  they think they're compromised). It does **not** sign the user in — owning the
  mailbox is a weaker claim than knowing the password.
- **Account deletion** is server-side (`recursiveDelete` of `users/{uid}` + both OTP
  docs + `deleteUser`) and gated by reauthentication on **both** sides: the client
  re-runs the credential flow, and the server checks the resulting token's
  `auth_time`.
- **Firebase App Check is not yet wired** (deferred by owner request) — see
  `docs/AUTH.md` §6 and STATE.md's owner action items.
