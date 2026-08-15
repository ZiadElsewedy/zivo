# ADR-002: Document / PDF ingestion pipeline — extract once into structured data

**Status:** Proposed — awaiting owner approval; **nothing here is built yet**
**Date:** 2026-08-15
**Deciders:** Ziad (owner) · implementer
**Relates to:** `docs/PLAN.md` §3 (Workout "PDF import"), §7 (data model), §8 (Storage),
§11 (AI architecture / prompt-injection), and `docs/DECISIONS/ADR-001-ai-assistant.md`
(read-only gateway). Directly shapes the **Diet Plan** and **Workout Plan** import paths.

---

## Context

Both **Diet plans** and **Workout plans** are the kind of artefact a user is handed as a
document — a coach's PDF, a nutritionist's printout, a photographed sheet. The plan calls for
"PDF import" on Workout (PLAN §3) and the Diet feature is being built now with the same future
in mind (`DietPlan.source ∈ {manual, pdf}`).

The concern the owner raised: **sending large PDFs straight to Claude is token-expensive**, and
we don't want to blindly forward whole documents if we can preprocess them.

### What Claude actually does with a PDF (grounding the decision)

Claude's Messages API accepts a PDF via a `document` content block (base64, a URL, or the Files
API). Crucially, for each page Claude ingests **both**:

1. the **extracted text** of the page, **and**
2. a **rendered image** of the page (so it can read tables, figures, and scanned/handwritten
   content visually).

That dual ingestion is what makes native PDF input powerful for *visual* documents — but it also
means **every page costs text tokens *plus* image tokens** (a page image is on the order of
~1.5k–3k+ tokens depending on size), and PDF requests are bounded (~100 pages / ~32 MB). So:

- For a **clean, digital, text-based** plan (a nutrition table: *Meal · Food · Qty · Calories ·
  Macros*), native PDF input pays the per-page **image tax for information that is entirely
  textual** — wasteful.
- For a **scanned or photographed** plan (no real text layer, or a phone photo), the **visual**
  path is exactly what's needed — the text isn't otherwise recoverable.

So "convert everything to Markdown" and "always send the native PDF" are *both* wrong as blanket
rules. The right answer is to **route on the document**, and — more importantly — to change *when*
and *how often* the document is looked at at all.

---

## Decision

**Extract the document exactly once, at import time, into the structured domain model — never
re-send the document for day-to-day questions.** A hybrid, routed, server-side pipeline (lives in
the document/AI Cloud Function, Phase 9+; see ADR-001's gateway), producing validated
`DietPlan` / `WorkoutPlan` JSON:

1. **Classify the source.** Does the PDF have a usable text layer (digital) or not
   (scanned/image/photo)?
2. **Digital text PDF → text path (cheap, default).** Extract the text server-side and normalize
   it to **clean Markdown** — preserve headings and **tables** (which carry the meal/quantity/macro
   structure), strip page furniture (repeated headers/footers, page numbers, watermarks). Send the
   **normalized text** to Claude and ask it to emit the structured plan JSON. No page images, so no
   image tax; the useful information (the table) is fully preserved.
3. **Scanned / image / photo → multimodal path (reserved).** When there's no meaningful text
   layer (or the text path returns empty/low-confidence output), fall back to native multimodal
   input — the PDF `document` block or the page image(s) — and let Claude's vision/OCR read it,
   still emitting the **same** structured JSON. The expensive path is used **only when it earns
   its cost.**
4. **The extraction target is always the structured domain schema**, not free text — the same
   `DietPlan { days[] → meals[] → items[] {name, qty, unit, calories, macros} }` the manual editor
   produces. That is what makes the AI reliable downstream and what collapses token cost:

> **The biggest saving is architectural, not format-level.** Import is a **one-time** structured
> extraction. Every later question — *"alternatives to rice with the same calories"*, *"what am I
> supposed to eat today?"*, *"I ate breakfast, what's left?"* — runs over the **compact structured
> Firestore data** via ADR-001's read-only tools (`get_diet_today`, `get_diet_plan`), and **never
> touches the PDF again.** A 20-page PDF is paid for once; the daily queries are a few hundred
> tokens of structured JSON.

### Guardrails (fold in when built)

- **Caps & validation:** enforce page-count and size caps, and `contentType == application/pdf`,
  in the client *and* Storage rules (PLAN §8). Reject oversized uploads before they reach the model.
- **Untrusted content (PLAN §11):** extracted text/OCR is **data, not instructions** — fenced as
  such in the system prompt (prompt-injection defense). A diet PDF that says "ignore your rules"
  is just text in a table.
- **Human confirm before it becomes real:** an imported plan lands as `status: draft`; the user
  reviews the parsed days/meals/items and confirms before it is promoted to `active`. A bad
  extraction never silently becomes your diet. This reuses the `draft → active` status the Diet
  data model already carries.

---

## Consequences

**Now (this milestone):** *nothing in this ADR is implemented.* Its only claim on today's work is
that the **Diet data model is shaped so an extractor can populate it** — `DietPlan.source ∈
{manual, pdf}`, `status ∈ {draft, active, …}`, and a fully structured `days → meals → items` tree.
The Diet feature ships **manual-entry only**; the import path is deferred to the document/AI phase.

**Later:** implement the router + normalizer + a structured-extraction call inside the
document/AI Function (ADR-001), plus the draft-review confirm UI and Storage rules/caps.

**To revisit:** the digital-vs-scanned confidence threshold (when to escalate to the visual path),
and whether a lightweight on-device text pre-extract is worth it before upload.
