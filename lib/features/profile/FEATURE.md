# profile — feature map

> **The application's own record of the person**, keyed by the auth uid. Where
> [`../auth/`](../auth/FEATURE.md) is portable and says nothing about ZIVO, this
> module is the opposite: it is entirely ZIVO's, and every project that copies the
> auth module writes its own version of this one.
>
> The reasoning is in [`docs/AUTH.md`](../../../docs/AUTH.md) §1: Firebase Auth owns
> the credential, not the human. Anything you need to query, validate, bound, extend,
> or write transactionally with other data belongs in a document you control.

## Start here

- **[`profile.dart`](profile.dart)** — the barrel.
- `domain/user_profile.dart` — `UserProfile` (name · date of birth · photo · bio) and
  `isProfileComplete`. Stored at `users/{uid}` — the same document whose
  *subcollections* hold every feature's data. Fields and subcollections are
  independent in Firestore, which is why the rule can pin this shape with `hasOnly`
  without touching anything nested beneath it.
- `domain/session_state.dart` — **`SessionState` + `resolveSessionState`.** The
  composition of "what authentication says" with "what this app additionally
  requires". Lives here, not in auth, because *what a session needs before the shell
  opens* is an application decision — see `docs/AUTH.md` §2.
- `domain/profile_repository.dart` / `data/firestore_profile_repository.dart` —
  `AppScope.profiles`.
- `presentation/pages/profile_page.dart` — the **"You"** tab (not a shell page).
- `presentation/pages/profile_completion_page.dart` — first-run onboarding.
- `presentation/widgets/dob_picker_sheet.dart` — the shared DOB wheel, used by both
  onboarding and profile editing.

## The session states

| State | Screen | Meaning |
|---|---|---|
| `SessionResolving` | splash | Auth or profile not resolved yet |
| `SessionSignedOut` | `AuthPage` | Nobody signed in |
| `SessionNeedsEmailVerification` | `VerifyEmailPage` | Address not yet proven |
| `SessionNeedsProfile` | `ProfileCompletionPage` | Authenticated, but this app doesn't know them |
| `SessionActive` | `HomeShell` | Verified identity **and** complete profile |

`resolveSessionState` is a pure, total function — the whole routing policy is unit
tested with no widgets, no Firebase, no async
([`test/profile/session_state_test.dart`](../../../test/profile/session_state_test.dart)).

## Gotchas

- **`profileLoaded: false` must resolve to `SessionResolving`, not
  `SessionNeedsProfile`.** "We haven't looked yet" and "we looked and there is none"
  are different screens; confusing them flashes the onboarding form at users who
  completed it long ago.
- **`suggestedName` prefers the profile's own name over the provider's.** A
  half-saved name is a better prefill than a provider's guess, because the user typed
  it. The provider's `displayName` is only ever a hint — see `AuthUser.displayName`.
- **This module depends on `auth`; `auth` must never depend on this.** That direction
  is what keeps the auth module liftable. If you find yourself importing
  `features/profile/` from `features/auth/`, the thing you're adding belongs on this
  side of the line.
- The `users/{uid}` rule pins the field vocabulary with `hasOnly` plus type and length
  bounds, and **denies client deletes** — account deletion runs server-side via
  `recursiveDelete`, because a client delete would strand every subcollection under a
  document that no longer describes anyone.
- Writes require a verified email (`canWrite` in `firestore.rules`); reads only
  require ownership.
