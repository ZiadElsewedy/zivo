# ADR-014 — The profile avatar lives in Firebase Storage, not the Drive media pipeline

**Status:** accepted · **Date:** 2026-09-11

## Context

ZIVO's photo pipeline (`core/media`) is **local-first with optional Google
Drive backup**: captured bytes are copied into the app's documents directory,
metadata goes to Firestore (`users/{uid}/media`), and the bytes are pushed to
**the user's own Google Drive** only when they've connected it. This is the
right model for **moments** — bulk, personal photos that would otherwise sit on
ZIVO's Firebase Storage bill and in ZIVO's custody. They stay in the user's
Drive; ZIVO holds only metadata.

The **profile avatar** was routed through this same pipeline (`media.capture`
with `MediaKind.avatar`, the store ref persisted as `UserProfile.photoPath`).
That produced a reported bug: **an avatar set on one device did not appear on a
second device.** The cause is structural, not incidental — only the store
*reference* syncs (via Firestore); the bytes reach device 2 only if the user
has connected the *same* Google Drive account there and the media layer
re-fetches them. If Drive was never connected, or a different account is
connected, the avatar renders as "lives elsewhere".

That behaviour is correct for a moment. It is wrong for an avatar: the avatar is
**identity**, a single tiny image the app should show everywhere the moment the
profile document syncs, with no extra setup.

## Decision

**The avatar's bytes go to Firebase Storage; moments stay on Google Drive.**

- Avatar bytes are uploaded to Firebase Storage at `avatars/{uid}` (one object
  per user, overwritten in place). The resulting HTTPS download URL is stored on
  the user document as `users/{uid}.photoUrl`.
- The seam is `AvatarStorage` (`features/profile/domain/`), with
  `FirebaseAvatarStorage` (`data/`) as the only place `firebase_storage` types
  appear, and a fake for tests — the same repository-seam discipline every other
  feature follows, so tests still run without Firebase.
- Display prefers `photoUrl` (`Image.network`, monogram fallback). The **legacy**
  `photoPath` (Drive/local media ref) is still rendered on a device that holds
  it, so existing users don't lose their photo; setting a new avatar writes
  `photoUrl`, clears `photoPath`, and deletes the old local/Drive copy.
- `firestore.rules` pins `photoUrl` (bounded string) on the user doc; a new
  `storage.rules` scopes `avatars/{uid}` to owner-write (image, size-capped),
  authenticated-read.

Moments are explicitly **not** moved. The Drive pipeline, `MediaService`,
`MediaKind`, and the whole account-aware backup machinery are unchanged.

## Why not the alternatives

- **Keep the avatar on the Drive pipeline, just fetch it.** Rejected: it only
  works once the user connects the same Drive on each device, so the avatar
  still fails to "just appear" on a fresh device — exactly the reported bug.
- **Embed the avatar as base64 in the Firestore user doc.** Viable (no extra
  service, syncs everywhere) but bloats the hot `users/{uid}` document read on
  every profile/gate stream with ~tens-of-KB of image data, and needs a
  resize/encode step. A single Storage object with a URL keeps the doc small.

## Consequences

- Firebase Storage is now used (previously the bucket sat unused in
  `firebase_options.dart`). One small object per user — negligible cost, and
  bounded by the storage rule. Moments deliberately remain **off** this bill.
- **Owner actions:** `flutter pub get`; iOS `pod install` for `firebase_storage`;
  deploy the rules (`firebase deploy --only firestore:rules,storage`) — until
  the storage rules are deployed, avatar upload is denied by the default
  rules and the reported bug persists.
- If avatars ever need to be visible to other users (coach/teammate views), the
  Storage read rule already allows any authenticated user; the Firestore side
  would be the gate to revisit.
