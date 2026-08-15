# Firestore security-rules tests

Emulator-based tests for [`../firestore.rules`](../firestore.rules). They are the
"privacy guarantee" the plan calls for (PLAN §10/§20/§28): rules are code, and code
gets tests. This suite is intentionally separate from the Flutter test suite — it is a
small Node project run against the **Firestore emulator**, not Dart.

## What it covers

- **Deny-by-default** — unauthenticated access is refused; unknown top-level collections
  and unknown subcollections under `users/{uid}` are refused by the catch-all.
- **Ownership isolation** — a signed-in user can read/write only their own
  `users/{uid}` profile and their own docs in each feature subcollection; a different
  signed-in user is denied.
- **Field validation** — each feature collection rejects a malformed write (wrong type,
  missing `schemaVersion`, negative `amountMinor`, non-list `exercises`, …).
- **`emailOtps` lockout** — denied to every client, even the owner (Functions-only).

All seven persisted collections are covered: `tasks`, `expenses`, `schedule`, `notes`,
`workouts`, `moments`, `universityItems` — plus the `users/{uid}` profile doc.

## Prerequisites

- The Firebase CLI (`firebase --version`) and a JDK (the Firestore emulator needs Java).
- Dependencies installed here: `npm install` (in this directory).

## Run

From the **repo root** (so the emulator picks up `firebase.json`):

```bash
firebase emulators:exec --only firestore --project demo-zivo "npm --prefix firestore-tests test"
```

`emulators:exec` boots the Firestore emulator, sets `FIRESTORE_EMULATOR_HOST`, runs the
tests (`node --test`), then shuts the emulator down. The `demo-` project prefix keeps the
run fully offline — it never touches the real `zivo-63f15` project.

The tests load `../firestore.rules` directly, so they always exercise the real repo rules.
`node --test` alone (without the emulator wrapper) will fail to connect — always run it via
`emulators:exec`.
