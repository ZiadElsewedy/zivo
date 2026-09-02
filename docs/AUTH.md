# Authentication architecture

> The reference implementation. This document explains **why** the auth module is
> shaped the way it is, so the shape survives contact with the next feature — and so
> it can be lifted into another project without re-deriving the reasoning.
>
> Code: [`lib/features/auth/`](../lib/features/auth) (portable) ·
> [`lib/features/profile/`](../lib/features/profile) (app-specific) ·
> [`functions/`](../functions) (server) · [`firestore.rules`](../firestore.rules) (authorization)

---

## 1. The central decision: identity is not the user

**Firebase Auth owns the credential. It does not own the person.**

Every field the auth provider gives you — uid, email, verified flag, providers,
`displayName`, `photoURL` — exists to serve *authentication*. The moment you store
something there because it is convenient, you have put application data in a system
that cannot do any of the things application data needs:

| You need to… | Auth record | Your own document |
|---|---|---|
| Query it ("who has a birthday today?") | ✗ no query API | ✓ indexed queries |
| Validate it | ✗ `updateProfile()` accepts anything | ✓ `hasOnly` + types + bounds in rules |
| Bound its size | ✗ | ✓ enforced per field |
| Write it atomically with other data | ✗ separate system | ✓ one batch/transaction |
| Read it from security rules | ~ only via token claims, **stale up to 1 hour** | ✓ directly |
| Extend it with a new field | ✗ fixed schema | ✓ it's your schema |
| Keep it when changing auth vendor | ✗ migrate it | ✓ never moves |

So the rule this codebase follows:

> **The auth record holds what is needed to authenticate. Everything else lives in a
> `Profile` document keyed by the auth uid.**

That is the answer to "should app data go on the backend auth user?" — no, and not
as a matter of taste. The auth record is a *credential store* that happens to have a
few string fields on it.

### The one exception, and how it is contained

`displayName` **is** written at sign-up — but only ever as a **hint**:

- Google and Apple supply it free at sign-in, and it makes a good prefill.
- Apple discloses the name **only on the first authorization**, so the single chance
  to capture it is at that moment.

It is contained by having exactly **one** consumer: `resolveSessionState` seeds
`SessionNeedsProfile.suggestedName` from it. Nothing else reads it. The app's name
for a person is `UserProfile.name`, full stop. See the field's doc comment in
[`auth_user.dart`](../lib/features/auth/domain/auth_user.dart) — it explains the
failure mode, which is that two fields called "name" drift the first time someone
edits their profile and every screen quietly picks a different one.

### What about custom claims?

Custom claims are for **authorization**, not profile: roles, tenant ids, plan tier —
things security rules must branch on. They ride in every request's ID token, so they
are capped (~1 KB), they go stale for up to an hour, and changing one needs a token
refresh. ZIVO uses none today. If a role system ever lands, it goes there — and
nothing else does.

---

## 2. The module boundary

```
lib/features/auth/          PORTABLE — zero ZIVO concepts
lib/features/profile/       APP-SPECIFIC — rewritten per project
```

The test for which side a thing belongs on: **would the next app want this
verbatim?**

| Concept | Where | Why |
|---|---|---|
| `AuthUser`, `AuthState`, `AuthResult`, `AuthFailure`, `OtpResult` | auth | Identity vocabulary; identical in every app |
| `PasswordPolicy` | auth | Credential policy |
| `AuthEvent`, `AccountAuthMetadata` | auth | "When did this account authenticate?" is universal |
| `UserProfile` (name, DOB, photo, bio) | **profile** | ZIVO's fields |
| `SessionState` | **profile** | Composes auth with *this app's* readiness rule |

### The dependency direction is one-way

`profile` → `auth`. Never the reverse. That is enforced by structure, not
convention: the auth module simply contains no import of anything under
`features/profile/`.

This is what the split actually bought. `ProfileCompletionRequired` used to be a
case on `AuthState`, which meant `auth/domain/auth_state.dart` imported
`UserProfile`. One extra enum case, and the portable module depended on ZIVO's
date-of-birth field. It could not have been copied anywhere without dragging the
product with it.

### Why `SessionState` is a separate hierarchy, not a bigger `AuthState`

"Signed in" and "ready to use the product" are different questions with different
owners:

- **Auth** answers: unknown / signed out / signed in / must verify an address. Fixed
  by the provider; the same everywhere.
- **The app** answers: ...and does this person have a completed profile? Another app
  asks for a workspace, an accepted ToS, a KYC step, or nothing.

Composition, not extension:

```dart
// features/auth/domain/auth_state.dart      — portable, 4 states
AuthState resolveAuthState(AuthUser? user)

// features/profile/domain/session_state.dart — app-specific, composes the above
SessionState resolveSessionState({
  required AuthState authState,
  required UserProfile? profile,
  required bool profileLoaded,
})
```

Both are **pure functions**, which is why the app's entire routing policy is unit
tested with no widgets, no Firebase, and no async
([`session_state_test.dart`](../test/profile/session_state_test.dart)).

---

## 3. File organisation

```
lib/features/auth/
  auth.dart                          ← barrel: the whole public surface in one import
  domain/                            ← no SDK types cross this line
    auth_user.dart                     identity
    auth_state.dart                    + resolveAuthState (the verification policy)
    auth_repository.dart               4 facet interfaces + their union
    auth_activity_repository.dart      bookkeeping (separate: different failure contract)
    auth_result.dart / auth_failure.dart / otp_result.dart
    password_policy.dart
    auth_event.dart / auth_event_type.dart / account_auth_metadata.dart
  data/
    firebase_auth_repository.dart    ← composition root: orchestration only
    auth_activity_recorder.dart      ← fire-and-forget bookkeeping
    auth_config.dart
    sources/                         ← one file per mechanism
      email_password_source.dart       credentials: create, present, re-present, replace
      federated_auth_source.dart       Google + Apple, nonce, reauth credentials
      auth_callables_source.dart       every backend call (OTP ×2 flows, deletion)
    mappers/                         ← one file per translation
      firebase_user_mapper.dart        fb.User → AuthUser
      otp_error_mapper.dart            server rejection → domain result
  presentation/                      ← rewritten per project
```

### Why the repository is a composition root

It was 696 lines doing five jobs. It is now 387 lines doing **one**: deciding what
order things happen in and what the outcome means. Each source has a single reason to
change, and the split is not cosmetic — `federated_auth_source.dart` unified four
near-identical inlined provider blocks into two, and the reason that matters is that
*minting a reauthentication credential* and *signing in* must not drift, because the
former is what refreshes `auth_time` for the server's delete gate (§4).

### Why the interface is four interfaces

`SessionAuthentication` · `EmailVerification` · `PasswordManagement` ·
`AccountLifecycle`, unioned into `AuthRepository`. A screen depends on the facet it
uses; DI still passes one object. Grouping without fragmentation.

### Why bookkeeping is not on `AuthRepository`

`AuthActivityRepository` has a **different failure contract**: a lost telemetry write
must never fail a sign-in. `AuthActivityRecorder` enforces that in its signatures —
every method returns `void` and swallows its own errors — rather than relying on
someone remembering `unawaited(...)` at seven call sites.

---

## 4. Security model

Authorization is **deny-by-default and owner-scoped**. The uid *is* the ownership
key: `users/{uid}/...`. No roles, no membership lookups, no `get()` on another
document — so every rule is O(1) and hard to get subtly wrong.

### Policies stated on both sides of the wire

Neither side is redundant. The client half produces the right screen; the server
half makes it a boundary.

| Policy | Client | Server |
|---|---|---|
| Unverified email must verify | `resolveAuthState` | `emailTrusted()` in `firestore.rules` — refuses **writes** |
| Password strength | `PasswordPolicy` | `isStrongPassword` in `functions/index.js` |
| Reauth before deletion | provider/password prompt | `requireRecentAuth` reads the token's `auth_time` |
| Paid endpoints are bounded | — | `functions/shared/quota.js` |

**If you change one, change the other.** Each row is a place where a client-only
check would be decoration.

### Verification gates writes, never reads

`emailTrusted()` guards mutations only. An account that somehow ends up stranded must
still be able to see and export what it already has: losing write access is a gate,
losing read access is data loss. The audit collections (`authEvents`, `auth/account`)
are the deliberate exception — they use plain ownership, because an unverified
account still signs in and those sign-ins are exactly the ones worth recording.

### Things worth knowing before editing rules

- **`request.resource.data` is the resulting document, not the delta.** On a merge
  write it includes untouched fields, so `hasOnly` must list every field that can
  exist — including server-authored ones. Which means `hasOnly` alone cannot make a
  field server-only; immutability has to be stated separately (absent on create,
  unchanged on update). See `users/{uid}/auth/{docId}`.
- **`allow delete` must be split from `create, update`.** On a delete
  `request.resource.data` is null, so any field check in a combined `allow write`
  evaluates false and silently denies every delete.
- **Rules do not cascade.** A rule on `users/{uid}` says nothing about
  `users/{uid}/expenses`. Every collection needs its own block.
- **A document's fields and its subcollections are independent.** Pinning the
  profile's shape at `users/{uid}` does not constrain anything nested beneath it.
- **Client-supplied ids must be validated before reaching `.doc()`.** Firestore reads
  a slash-bearing string as a *path*, so on the Admin SDK — which bypasses rules — an
  unvalidated id lets the client choose where a rule-exempt write lands. See
  `functions/shared/ids.js`.

Every rule has a test: [`firestore-tests/`](../firestore-tests) (129 cases). A new
collection needs a rule **and** a rule test.

### Server-side OTP

Both flows share one unit-tested decision core,
[`functions/auth/otp.js`](../functions/auth/otp.js): CSPRNG codes, HMAC-SHA256 keyed
by a server pepper plus per-code salt, constant-time compare, single-use, TTL,
attempt cap, resend cooldown, hourly send cap. The code is never stored or logged in
plaintext.

Two properties that are easy to lose in a refactor:

1. **Throttle accounting survives a code being cleared.** Wiping the whole record on
   consume/expiry/lockout would let a caller reset the hourly cap by exhausting
   attempts.
2. **The signed-out reset endpoints are enumeration-safe.** Missing account,
   social-only account, and bad code all return the shape a real one does. The client
   must therefore always advance to the code step — branching on existence would
   rebuild the oracle on the client.

---

## 5. Porting this to another project

1. Copy `lib/features/auth/` **except** `presentation/` (rewrite the screens).
2. Copy `functions/auth/`, `functions/shared/`, and the auth callables from
   `functions/index.js`.
3. Copy the OTP/quota rules blocks and the ownership helpers from `firestore.rules`,
   plus `firestore-tests/`.
4. Write your own `features/profile/`: your `UserProfile`, its repository, its
   Firestore rule with `hasOnly` + bounds, and your own `SessionState` encoding
   whatever *your* app requires before its shell opens.
5. Set the secrets: `RESEND_API_KEY`, `OTP_PEPPER`.
6. Wire `AuthRepository` + `ProfileRepository` into your DI and point your root gate
   at the `SessionState` switch.

Step 4 is the one that is genuinely yours. Steps 1–3 should need no edits, and if
they do, that is a bug in the boundary worth fixing here.

---

## 6. Known gaps

- **Firebase App Check is not wired** (deferred by owner). Until it is, the callables
  and the Auth endpoints are reachable by anything holding the app config. It is the
  ceiling on scripted abuse of account creation and the unauthenticated reset
  endpoint. It needs a real release keystore first — Android release currently signs
  with the debug key.
- **The in-app password change does not explicitly revoke other sessions.** The
  client SDK's `updatePassword` does this itself; the Admin SDK path (the signed-out
  reset) does not, which is why `resetPasswordWithOtp` calls `revokeRefreshTokens`
  explicitly. There is no "sign out all devices" affordance yet — `revokeRefreshTokens`
  is the one call it would need.
- **Sign-up password strength is client-side only.** Reset is validated server-side,
  but `signUpWithEmail` goes straight to Firebase, which enforces its own 6-character
  floor. Fix in the console: Firebase Auth has a server-enforced password policy.
