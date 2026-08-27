# ADR-005: Ask can edit and delete expenses (confirm-gated), not just create

**Status:** Accepted (2026-08-27)
**Date:** 2026-08-27
**Deciders:** Ziad (owner) · implementer
**Relates to / extends:** [`ADR-003`](ADR-003-ai-mutations-v2.md) (propose → confirm →
execute). Relaxes the "create-only" scope of the mutating-tool registry.

---

> Decision only — implementation status lives in [`../STATE.md`](../STATE.md); the tools and
> flow live in [`../../functions/ai/`](../../functions/ai) and
> [`../../lib/features/ai/FEATURE.md`](../../lib/features/ai/FEATURE.md).

## Context

Ask's mutating tools were **create-only** (`create_expense`, `mark_meal_eaten`). The system
prompt told users outright: *"you cannot edit or delete anything."* But the expenses feature
already supports editing and deleting end to end — `ExpenseRepository.update`/`remove` are
implemented, and [`firestore.rules`](../../firestore.rules) already allows owner `update` **and**
`delete` on `users/{uid}/expenses`. The only gap was that the AI backend never exposed those
capabilities, and the read tools stripped each expense's document `id`, so the model could
*describe* an expense but never *point at* one.

The owner asked for the AI to be able to edit and delete existing data — after confirmation —
using the context it already reads to identify the right record.

## Decision

1. **Add two mutating tools** — `edit_expense` and `delete_expense` — alongside the existing
   create/toggle tools. They follow ADR-003 unchanged: the model **proposes**, nothing is
   written until the user taps Confirm, and the confirm executes server-side via the Admin SDK
   (`store.updateExpense` / `store.deleteExpense`).
2. **Identify before you mutate.** `get_expenses` now returns each expense's stable `id`. The
   edit/delete tools **require** that exact id (the model must never invent one) plus a short
   human `label` for the confirmation card and history. The system prompt instructs the model to
   read the data, match the record, and **ask** when the target is ambiguous — a wrong edit/delete
   is worse than a clarifying question.
3. **Editing is a partial patch.** `edit_expense` carries only the fields being changed; unset
   fields stay as they were. Deleting is by id.
4. **The confirmation is the receipt.** The confirmation card is retained after resolution (it no
   longer collapses to a bare "Confirmed"): it keeps the verb, target, and values so a user
   returning days later can see exactly what they approved. Delete wears the alert hue and a
   "Delete" verb, because it is destructive.

## Consequences

- The expenses log is **no longer append-only in spirit** for the AI path (it never was at the
  rules layer). Corrections can now be real edits/deletes, not only compensating entries. The
  wallet balance is derived from the log, so it stays correct after an edit/delete.
- **Scope is expenses + diet-meal toggles only.** Workout/diet *plans* are still not
  restructurable from chat — extending edit/delete to other entities is future work, each needing
  its own read-tool id exposure + store methods + tests.
- Any change here needs a **`firebase deploy --only functions`** with the owner's credentials
  (ADR-003 gotcha unchanged): until deployed, the running app keeps the old create-only backend.
