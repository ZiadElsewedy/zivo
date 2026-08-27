# auth — feature map

> Sign-in, email verification, profile, settings, privacy. Backed by Firebase Auth +
> Firestore (profiles + an append-only auth-event log). The OTP email codes and
> auth-event bookkeeping live server-side in [`functions/auth/activity.js`](../../../functions/auth/activity.js).

## Start here

- `presentation/auth_gate.dart` — **`AuthGate`**: the app's root gate (`app.dart` sets
  `home: AuthGate`). Routes splash → auth → verify → profile-completion → the shell.
- `presentation/pages/`: `splash_screen.dart`, `auth_page.dart` (sign in / up),
  `verify_email_page.dart` (OTP), `profile_completion_page.dart`, `profile_page.dart`
  (the "You" tab), `settings_page.dart`, `privacy_page.dart`.
- Widgets: `email_auth_form.dart`, `social_auth_buttons.dart` (Apple/Google),
  `otp_code_input.dart`, `dob_picker_sheet.dart` (shared DOB wheel — onboarding + edit),
  `auth_action_button.dart`, `media_backup_section.dart` (the Media & Backup settings block).

## Repositories

- **`AuthRepository`** (`AppScope.auth`) — `firebase_auth_repository.dart`; email-OTP +
  Apple/Google/password. Config in `data/auth_config.dart`, policy in
  `domain/password_policy.dart`.
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
- Email verification uses **hashed** OTP codes issued by `functions/auth/activity.js`.
