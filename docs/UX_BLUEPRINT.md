# Personal OS — Phase -1: Product & UX Discovery Blueprint

> Codename: **zivo** · Owner: Ziad · Phase: **-1 (Product & UX Discovery)** · Status: For review
>
> This document defines **how Personal OS should feel and behave** before any technical
> architecture is derived. It intentionally precedes [PLAN.md](PLAN.md). Nothing here is code,
> Firestore, or backend. When approved, the technical plan will be **re-derived from this UX**,
> not the other way around.
>
> Reading order: §0 (philosophy) → §1 (the open-app moment) → §2 (IA, where I challenge you) →
> §4 (Today, the heart) → §5 (AI) → features → §12 (scope) → §16 (first screen).

---

## 0. Product philosophy (what "Personal OS" actually means)

An operating system does three things a folder of apps does not:

1. **It has a home surface that represents your current state** — not a launcher of icons, but a
   place that tells you what's true _right now_.
2. **It has a system-wide command layer** — you can invoke intent from anywhere (Spotlight,
   Siri) without navigating into an app first.
3. **It composes** — the apps share context; the calendar knows about reminders, the lock
   screen surfaces what matters.

So Personal OS is not "10 CRUD screens with a nice theme." It is:

- **One adaptive home surface (Today)** that reads like a sentence about your day.
- **One command layer (Capture + Ask)** reachable from anywhere in under 5 seconds.
- **Modules that feed the home surface** and that you dive into only for depth (history,
  progress, full lists).

**The test for every design decision:** does this make Personal OS feel like a _system that
knows me_, or like _another app I have to manage_? If it's the latter, cut it.

**Anti-goals (design smells we reject):**
- Dashboards of vanity statistics.
- A tab per feature (that's a launcher, not an OS).
- Forcing all intelligence through a chat box.
- Empty states that feel broken instead of intentional.
- "Configure everything" settings dumps.

---

## 1. Product experience — the open-app moment

**The scenario that governs everything:** _"I wake up, unlock my phone, open Personal OS. What
should the app tell me?"_

### The 3-second test
Within 3 seconds of opening, I should understand, without tapping:
1. **What time-shaped thing defines the next part of my day** (next event, or "morning is
   open").
2. **What needs me** (tasks/deadlines due, or "nothing urgent").
3. **The state of my key routines** (workout today? did I log spending?).
4. **That I can immediately capture or ask** — the command layer is visible.

What I should **not** see: a grid of numbers, six equal-weight cards, or a generic "Good
morning, here's your dashboard."

### Today is time-aware (the single most important product idea)
The Home surface is **not a static list of sections**. It **adapts to the time of day**, because
what I need at 7am is not what I need at 10pm. This is what makes it feel like an OS rather than
a report.

| Time context | Emphasis |
|---|---|
| **Morning** | The day ahead: next event, today's workout, what's due, a clean plan. Forward-looking. |
| **Midday** | Now/next event, remaining tasks, quick-capture spending. Operational. |
| **Evening** | What's left today, gentle nudge on unlogged things, **tomorrow preview**. |
| **End of day** | Reflective: what got done, spend summary, tomorrow's first commitment. Calm. |

The _sections_ are stable; their _ordering, prominence, and copy_ shift with context. (V1 uses
deterministic time buckets; AI-authored daily briefs come in V1.5.)

### What the app proactively surfaces (V1, deterministic — no AI required)
- The **next** schedule event (with countdown when near).
- **Today's workout** state (planned / rest / in-progress / done).
- **Tasks due today** and **university deadlines within N days**, merged and prioritized.
- **Spending glance** (today / this week) — one line, not a chart.
- **Gentle end-of-day nudges** (e.g., "no workout logged", "3 tasks still open") — quiet, never
  nagging, never red-alert.

### What must never feel like complexity
- Capturing an expense, task, or note (must be near-instant).
- Understanding "what's my day."
- Starting a workout.
- Asking a question.

Everything else (managing, editing, browsing history, configuring) can live one layer deeper.

---

## 2. Information architecture (challenging the previous navigation)

> You asked me to challenge the navigation from [PLAN.md](PLAN.md), which assumed a bottom nav
> with "Today + the primary sections." **I don't think a tab-per-feature is right.** Ten features
> cannot be ten tabs, and picking an arbitrary five (why Workout but not Schedule?) makes it feel
> like a launcher. Here's the reasoning and my recommendation.

### The core IA problem
The ten areas split into three fundamentally different interaction types:

| Type | Areas | How you use them |
|---|---|---|
| **Command surface** | Today, AI, Capture | Constantly, from anywhere, low friction |
| **Capture-first modules** | Expenses, Tasks, Notes, Moments | Add fast; browse occasionally |
| **Depth modules** | Workout, Schedule, University | Dive in for a session/agenda; summarized on Today |

Insight: **capture** is a cross-cutting _verb_, not a place. Expenses/Tasks/Notes/Moments all
share "add something in <5s." Treating each as a destination you navigate to is the wrong model —
it's why the previous nav felt off.

### Recommended IA — "Command surface + launcher + global capture/ask"

**Bottom navigation: 4 tabs (not per-feature).**

```
┌──────────┬──────────┬──────────┬──────────┐
│  Today   │   Hub    │   Ask/AI │  Profile │
│  (home)  │(modules) │(assistant)│(you)     │
└──────────┴──────────┴──────────┴──────────┘
                  ＋  (global Quick Capture — floating / long-press)
```

1. **Today** — the adaptive command center. Where life actually happens. Most days you never
   leave it.
2. **Hub** — the "OS home screen": a clean launcher into the depth of each module (Workout,
   Schedule, Tasks, Expenses, University, Notes, Moments) — history, full lists, progress. This
   is the honest, OS-native place for "the collection of modules," so Today stays curated.
3. **AI / Ask** — the assistant's home (conversation history, analytical sessions). But AI is
   **also** invoked globally and appears inline — it is not _only_ this tab (see §5).
4. **Profile** — identity, preferences, AI/data controls. Minimal.

**Global affordances (deliberately NOT tabs):**
- **Quick Capture (＋)** — one entry point that opens a capture sheet offering
  Expense / Task / Note / Event / Moment. Reachable from Today's header and a tab long-press.
  This is the command layer's "create."
- **Ask** — a persistent way to invoke AI from anywhere (a pull-down on Today, or an "Ask" pill).
  This is the command layer's "query/act."

### Why this, and the trade-offs
- **Pro:** Today stays sacred and curated; capture is uniform and instant; AI is ambient, not
  boxed; the Hub gives an honest OS-launcher metaphor without polluting Today.
- **Con / alternative A — "No Hub, everything from Today":** Today's sections each have a "see
  all" that opens the module. Fewer tabs (Today / AI / Profile). _Risk:_ deep module screens
  (workout history, expense reports) become hard to reach and discoverability drops.
- **Con / alternative B — AI as center tab with prominence:** makes AI the star. _Risk:_ pushes
  you toward "chat for everything," which you explicitly don't want.
- **Why not tab-per-feature (previous plan):** arbitrary selection, feels like a launcher,
  doesn't scale to 10 areas, buries capture.

> **Open decision (D-1):** 4-tab (Today/Hub/AI/Profile) vs. 3-tab (Today/AI/Profile with Hub
> folded into Today "see all"). I recommend **4-tab** for discoverability, but this is a
> genuine fork worth deciding together. See §15.

### AI entry points (summary — detailed in §5)
- Inline on Today (ambient brief, nudges).
- Global "Ask" (pull-down / pill) → focused answer or action, then dismiss.
- AI tab (history, longer analysis).
- In-context inside modules ("how's my progress?" in Workout; "where did it go?" in Expenses).

---

## 3. Complete screen map

```
Today (tab)
  ├─ Now/Next detail (event → Schedule detail)
  ├─ Task quick-complete (inline)
  ├─ Workout card → Workout Overview / Session
  ├─ Spending glance → Expenses summary
  └─ Ask (pull-down) → Ask surface

Hub (tab)  — launcher into module depth
  ├─ Workout
  │    ├─ Today's Workout / Overview
  │    ├─ Active Session (exercise → set → next → finish)
  │    ├─ Session Summary
  │    ├─ History
  │    ├─ Progress (per exercise)
  │    ├─ Plans (list / view / edit)
  │    └─ [V2] Import PDF → Review Extraction → Confirm
  ├─ Schedule
  │    ├─ Today / Agenda (list) · [optional] Week
  │    ├─ Event Detail
  │    └─ Create/Edit Event
  ├─ Tasks
  │    ├─ Task List (Today / Upcoming / All)
  │    ├─ Task Detail
  │    └─ Create/Edit Task (usually via Capture)
  ├─ Expenses
  │    ├─ History (grouped by day)
  │    ├─ Summaries (day/week/month)
  │    ├─ Expense Detail
  │    └─ Quick Add (via Capture)
  ├─ University
  │    ├─ Courses (list / detail)
  │    ├─ Items (assignments/exams) — Upcoming / All
  │    └─ Create/Edit Item
  ├─ Notes
  │    ├─ Notes List + Search
  │    ├─ Note Editor
  │    └─ Quick Note (via Capture)
  └─ Moments
       ├─ Timeline / Gallery
       ├─ Moment Detail
       └─ Capture Moment (via Capture)

Ask / AI (tab)
  ├─ Conversation list / current conversation
  ├─ Ask surface (focused, transient)
  └─ Action confirmation sheet (system-styled)

Profile (tab)
  ├─ Identity (name, avatar)
  ├─ Preferences (theme, units, currency, week start)
  ├─ AI settings (enable, tone, data scope)
  ├─ Data & privacy (export, what leaves device)
  └─ About

Global (modal, from anywhere)
  ├─ Quick Capture sheet → Expense / Task / Note / Event / Moment
  └─ Ask (pull-down)
```

---

## 4. Home / Today — deep specification (the heart)

Today is the product. If Today is right, the app is right.

### Composition (recommended, morning context shown)

```
┌─────────────────────────────────────────────┐
│  Friday, 15 August           ⌄ pull to Ask   │   ← header: date, subtle greeting,
│  Good morning, Ziad                          │      pull-down reveals Ask
│                                              │
│  ── NOW / NEXT ─────────────────────────────  │
│  ┌─────────────────────────────────────────┐ │
│  │ 10:00  Lecture — Algorithms             │ │   ← the single most relevant time-thing;
│  │        in 2h · Hall B                   │ │      countdown when near; tap → detail
│  └─────────────────────────────────────────┘ │
│                                              │
│  ── TODAY ──────────────────────────────────  │
│  ◦ Finish assignment 2            due today  │   ← merged focus list: tasks + uni
│  ◦ Pay tuition installment        due today  │      deadlines, prioritized; tap to
│  ◦ Call dentist                              │      complete inline (swipe / checkbox)
│                                              │
│  ── WORKOUT ────────────────────────────────  │
│  ┌─────────────────────────────────────────┐ │
│  │ Today: Chest                            │ │   ← state-driven: Planned / Rest /
│  │ 5 exercises · ~50 min      [ Start → ]  │ │      In progress / Done
│  └─────────────────────────────────────────┘ │
│                                              │
│  ── SPENDING ───────────────────────────────  │
│  Today 120 EGP · This week 940 EGP           │   ← one glance line, not a chart;
│                                       [ + ]  │      tap → summary; [+] quick add
│                                              │
└─────────────────────────────────────────────┘
                   ＋ Capture      (floating)
```

### Section behavior & priority
1. **Now/Next** (highest priority): the current or next schedule event. If none, becomes a calm
   line ("Your morning is open"). Countdown appears when the event is near.
2. **Today focus list**: tasks due today **merged with** university deadlines within the window,
   sorted by (overdue → due-today → priority). Inline complete. This is where Schedule, Tasks,
   and University _converge_ — the OS composing, not siloed lists.
3. **Workout card**: single card, state-driven (see states below). One primary action.
4. **Spending glance**: today + this-week totals on one line + quick-add. Never a chart on Today.
5. **(V1.5) Ambient AI brief**: a one-line, AI-authored summary/nudge at the top or as the
   greeting subtitle ("Busy morning — lecture at 10, then two deadlines"). Deterministic fallback
   in V1.

### Time-adaptive variants
- **Morning:** as above — forward plan; workout prominent if today.
- **Midday:** Now/Next tightens to the immediate event; remaining tasks float up; spending
  quick-add more prominent.
- **Evening:** "Today" shows what's _left_; add a **Tomorrow preview** mini-section (first event,
  anything due); workout card shows "not logged" quietly if applicable.
- **End of day:** collapses to a **reflective** state — "You closed 4 tasks, spent 260 EGP,
  finished Chest. Tomorrow starts 09:00." Calm, satisfying, not another to-do list.

### Today UI states
- **First-use:** a warm, guided empty Today — "This is your day. Add your first event or task."
  with a single obvious action. Not a blank screen, not a feature tour.
- **Empty (configured but nothing today):** intentional calm — "Nothing scheduled. A clear day."
  Capture stays available. Empty ≠ broken.
- **Loading:** skeletons that match the final layout (section-shaped shimmer), never a spinner on
  the whole screen. Cached content shows instantly, refreshes in place.
- **Populated:** as designed.
- **Partial data (some sections empty):** each section owns its own empty line; the screen never
  looks half-broken.
- **Offline:** cached Today renders fully; a subtle top inline indicator "Offline — showing last
  synced"; AI/rollup-dependent bits show a quiet "updating when back online."
- **Completed/end-of-day:** the reflective variant above.
- **Error:** never a raw error on Today; a section that fails shows a tiny inline "couldn't load ·
  retry," the rest of Today stays usable.

### Product decisions on Today
- **Why merged focus list over separate Tasks/Uni sections?** Because at 8am I don't think "tasks
  vs. university" — I think "what do I need to do today." Merging by _time relevance_ is the OS
  composing my life. _Trade-off:_ slightly less module purity; mitigated by clear source labels
  and "see all" into each module. **Challenge to you:** if you'd rather keep university visually
  distinct, that's a valid call — flagged as **D-2**.
- **Why no charts on Today?** Charts are analysis, not awareness. Today answers "what/now," not
  "how am I trending." Trends live in module summaries and AI. Keeps Today calm and fast.
- **Why one workout card, one action?** Reduces the most common daily action (start workout) to a
  single tap from home.

---

## 5. AI experience — what AI _is_ inside Personal OS

> You were explicit: **don't design "an AI chat screen."** Agreed. AI here is a **system
> capability that appears in four modes**, only one of which is a conversation.

### The four modes of AI

**1. Ambient (AI as narration, no interaction)**
AI-authored context woven into the UI: the Today daily brief line, gentle nudges, an end-of-day
summary sentence. You don't "use" it; it's just there, like a smart lock-screen. _V1.5._

**2. Ask (transient command, the star of daily AI)**
A global, low-friction invocation — pull down on Today, or an "Ask" pill — that opens a **focused,
transient surface**: you ask, it answers (or proposes an action), you're done. It **dismisses**;
you don't "visit" it. This is where most daily AI lives.

```
   ⌄ pull down / tap Ask
┌─────────────────────────────────────────────┐
│  Ask                                    ✕    │
│  ┌─────────────────────────────────────────┐ │
│  │ How much did I spend on food this week? │ │
│  └─────────────────────────────────────────┘ │
│                                              │
│  You spent 430 EGP on food this week,        │   ← concise answer, then it gets out
│  across 6 expenses.           [ Details → ]  │      of the way. Optional deep-link.
└─────────────────────────────────────────────┘
```

For an **action** ("Add gym at 6pm", "Start my workout"), Ask returns a **confirmation**, not a
chat bubble:

```
┌─────────────────────────────────────────────┐
│  Add to schedule?                            │
│  ┌─────────────────────────────────────────┐ │
│  │  Gym                                    │ │
│  │  Today · 18:00–19:00                    │ │   ← exactly what will happen,
│  └─────────────────────────────────────────┘ │      editable inline
│              [ Cancel ]      [ Add ]         │
└─────────────────────────────────────────────┘
```

**3. Conversation (the AI tab — depth, not default)**
For multi-turn, analytical work: "Summarize my week," "Analyze my workout progress," "What's been
eating my budget?" Here history persists. This is the _minority_ of AI use, not the front door.

**4. In-context (AI where the data lives)**
Inside a module, a contextual AI affordance scoped to that data: in Workout Progress, "How am I
progressing on bench?"; in Expenses, "Where did my money go this month?" The AI already knows the
context — no need to re-state it. This is the most "OS-like" AI: intelligence attached to the
thing you're looking at.

### What AI can do (capability ladder — maps to V-scopes)
| Capability | Example | Scope |
|---|---|---|
| **Ask/answer** (read) | "What's on my schedule today?" | V1 |
| **Search** | "Find my note about the visa" | V1 |
| **Understand my day** (ambient brief) | Today summary line | V1.5 |
| **Analyze** | "How's my bench progress?" "Summarize my week" | V1.5 |
| **Recommend** | "You usually work out Mondays — want to start?" | V1.5 |
| **Take actions** (write, confirmed) | "Add this to my schedule", "Start my workout" | V2 |
| **Guide activities** | AI narrates a workout set-by-set | V2 |

### AI UX principles (non-negotiable)
- **Reads are instant and ambient; writes are always confirmed.** No silent mutations, ever.
- **Confirmations are native sheets showing exact effects**, editable before commit — not chat
  text you have to trust.
- **AI answers are concise and link into the real UI** ("Details →") rather than reproducing it.
- **AI appears where context already exists** (in-context) so you never re-explain yourself.
- **The chat tab is the exception, not the interface.** If we find ourselves routing capture or
  simple reads through chat, we've failed the design.

### Product decision on AI placement
- **Why not make AI the primary tab/center?** Because centering chat trains you to _type at your
  data_ instead of _seeing and touching it_. A personal OS should make the direct UI so good that
  AI is an accelerator, not a crutch. AI earns prominence through Ask (global) and in-context,
  not through a giant chat button. _Trade-off:_ AI is slightly less "in your face"; that's
  intentional and reversible.

---

## 6. Workout UX — the full journey

The most demanding real-time screen in the app. Design for **glanceable, one-handed, sweaty-hands,
between-sets** use.

### Flow
```
Hub → Workout → Today's Workout (Overview) → [Start] → Active Session
   → Exercise → log Set → (rest) → next Set → next Exercise → [Finish] → Summary → History/Progress
```

### 6.1 Today's Workout / Overview
```
┌─────────────────────────────────────────────┐
│  Today · Chest                               │
│  5 exercises · ~50 min                       │
│                                              │
│  1  Bench Press           4 × 8              │
│  2  Incline DB Press      3 × 10             │
│  3  Cable Fly             3 × 12             │
│  4  Dips                  3 × failure        │
│  5  Push-ups (burnout)    2 × max            │
│                                              │
│              [  Start workout  → ]           │
└─────────────────────────────────────────────┘
```
Preview the whole session; one dominant Start. Edit-on-the-fly allowed but secondary.

### 6.2 Active Session (the critical screen)
```
┌─────────────────────────────────────────────┐
│  Chest · Exercise 1 of 5          ⏱ 00:42   │   ← session clock; exercise progress
│                                              │
│            Bench Press                        │   ← big, unmissable current exercise
│            Set 2 of 4                         │
│                                              │
│     ┌───────────┐        ┌───────────┐       │
│     │   REPS    │        │  WEIGHT   │       │   ← large steppers, prefilled from
│     │  −  8  +  │        │ − 60kg +  │       │      last session; tap number to type
│     └───────────┘        └───────────┘       │
│                                              │
│            [   Log set  ✓   ]                │   ← one dominant action; haptic on log
│                                              │
│  ─────────────────────────────────────────   │
│  Previous: Set 1 · 8 × 60kg          ✓       │   ← recent sets visible for reference
│                                              │
│  [ Rest 90s ▸ ]        [ Skip ]  [ Next ▸ ]  │   ← rest timer auto-starts after log
└─────────────────────────────────────────────┘
```
- **Prefill from last session** (smart defaults) — the single biggest friction-killer; usually
  you just tap "Log set."
- **Rest timer** auto-starts on log; visible, dismissible; optional gentle haptic/sound at 0.
- **Big targets, high contrast, minimal chrome** — usable at a glance mid-set.
- **Keep-awake** while session active. One-handed reachable controls.

### 6.3 Finish → Summary
```
┌─────────────────────────────────────────────┐
│  Chest · Done                    52:10       │
│  18 sets · 5 exercises · 6,240 kg volume     │
│                                              │
│  Bench Press   4×8   @60kg   ↑ +2.5kg vs last│   ← per-exercise recap with deltas
│  Incline DB    3×10  @22kg   =                │
│  ...                                         │
│           [ Done ]     [ Add note ]          │
└─────────────────────────────────────────────┘
```
Satisfying close: totals + progress deltas. Optional note. This is a reward moment — design it to
feel earned (subtle celebration, haptic), not a data dump.

### 6.4 History & Progress
- **History:** reverse-chronological sessions, each collapsible to sets.
- **Progress:** per-exercise trend (best/estimated 1RM or top set over time) — the _one_ place a
  chart is appropriate, and where **in-context AI** lives ("How's my bench progressing?").

### 6.5 Future: PDF → structured workout (design intent, not built)
```
Import PDF → [processing] → Review extracted plan (fully editable) → Confirm → becomes a Plan
```
UX rule: the extraction is a **draft you review and edit**; it never silently becomes your plan.
The review screen is a normal editable plan editor pre-filled with AI's guess, with a clear
"this was read from your PDF — check it" framing. (Deferred to V2; UX placeholder only.)

### Workout states
Planned · Rest day ("Rest day — recover well") · In-progress (resume banner on Today/Hub) ·
Completed · No plan yet (offer to create/import) · Offline (logging works, syncs later).

---

## 7. Tasks UX (lightweight — a personal OS, not Jira)

### Principles
- **Capture in <5s**, mostly from the global ＋. Title is enough; everything else optional.
- **Live on Today**, not in a heavy manager. The Tasks module is for browsing/managing, not the
  primary interaction.

### Quick create (via Capture sheet)
```
┌─────────────────────────────────────────────┐
│  New task                               ✕    │
│  ┌─────────────────────────────────────────┐ │
│  │ Call dentist                            │ │   ← title focused immediately
│  └─────────────────────────────────────────┘ │
│  [ Today ]  [ Tomorrow ]  [ Date ]   ‹due›   │   ← one-tap due chips
│  [ ! Priority ]                              │   ← optional, single toggle
│                                   [ Add ]    │
└─────────────────────────────────────────────┘
```

### Task list (module)
- Segments: **Today · Upcoming · All** (and completed accessible but out of the way).
- Row: checkbox + title + due chip + optional priority dot. Swipe to complete/delete.
- Complete = immediate, optimistic, satisfying (haptic + subtle strike/settle).
- **Detail** only when needed (notes, editing) — most tasks never open a detail screen.

### States
First-use ("Add your first task"), empty-today ("Nothing due today"), populated, completed
(celebratory-quiet), offline (fully works), overdue (surfaced, not shamed).

### Deliberately excluded (keep it light)
Subtasks, projects, tags, recurring, reminders/notifications, assignees. If any return, it's V2
and must justify itself. **Challenge:** you may want _recurring_ tasks sooner — flagged **D-3**.

---

## 8. Schedule UX

### Principles
- Schedule is the **time backbone** that powers Today's Now/Next. Its own screens are for the
  fuller agenda.
- **Agenda (list) over calendar grid** for V1 — a scrolling list of upcoming events reads faster
  on a phone and matches the "OS timeline" feel. Month-grid is heavier and lower-value for one
  person. (Optional Week view later.)

### Agenda
```
┌─────────────────────────────────────────────┐
│  Today                                       │
│  10:00  Lecture — Algorithms      Hall B     │
│  14:00  Gym                                  │
│  ───────────────────────────────────────     │
│  Tomorrow                                    │
│  09:00  Lecture — Databases                  │
│  ...                                         │
└─────────────────────────────────────────────┘
```
Grouped by day; today pinned. Tap → detail. ＋ or Capture → create.

### Create / edit event
Title (focused) · date · start/end (end optional → default duration) · optional location. Fast,
few fields. All-day toggle.

### Time conflicts & relationship to Tasks/Today
- **Conflicts:** if a new event overlaps an existing one, show a **quiet inline warning** ("Overlaps
  Gym 14:00"), never a blocking error — it's your calendar, you decide.
- **Tasks vs events:** events are **time-anchored commitments**; tasks are **things to do**. They
  converge on Today but stay distinct types (an event isn't a checkbox). A task _can_ have a due
  time and appear near the timeline, but it remains a task.

### States
Empty ("No events — your schedule is clear"), populated, offline (works), conflict (inline warn),
loading (skeleton agenda rows).

---

## 9. Expenses UX — the <5-second capture

> Governing scenario: _"I just spent 120 EGP. Record it in under 5 seconds."_ Everything about
> Expenses is optimized for this.

### Quick add (via Capture — amount-first)
```
┌─────────────────────────────────────────────┐
│  New expense                            ✕    │
│                                              │
│              120                             │   ← amount is the FIRST, focused field;
│              EGP                             │      big; numeric pad up immediately
│                                              │
│  [🍔 Food] [🚕 Transport] [☕ Coffee] [🛒 …]  │   ← category as chips: recent/frequent
│                                              │      first; one tap
│  note (optional)              today ▾        │   ← note + date optional; date defaults
│                                   [ Save ]   │      today
└─────────────────────────────────────────────┘
```
- **Type amount → tap category → Save.** ~3 interactions, well under 5 seconds.
- Category chips are **learned/frequent-first** (V1: static frequent set; smarter later).
- Note and date are optional and out of the way. Currency defaults to your setting (EGP).
- **Money is always exact minor units** (an implementation note carried from PLAN.md, surfaced
  here because it affects the input UX: no floating-point rounding surprises in what you see).

### History & summaries (module)
- **History:** grouped by day, each day showing a small day-total; rows are amount · category ·
  note. Tap → detail/edit.
- **Summaries:** day / week / month totals and by-category breakdown. This is where a modest
  visual (a simple bar/segment) is welcome — and where **in-context AI** answers "where did it
  go?"

### States
First-use ("Log your first expense"), empty-period ("Nothing spent today"), populated, offline
(capture works, totals show "syncing"), partial (rollup updating).

### Deliberately deferred
Budgets, recurring expenses, multi-currency, receipts/photos, income tracking. V1 is _capture +
see_. **Challenge:** budgets are tempting but add real complexity and a "management" feel — I'd
hold. Flagged **D-4**.

---

## 10. University UX

### Principles
- Model just enough: **Courses** and **Items** (assignments + exams) with **deadlines**. Not a
  full LMS/timetable/grade system.
- Its main job is to **feed Today's focus list** with upcoming deadlines.

### Structure
```
Courses                          Upcoming
  Algorithms   CS301               Fri  Assignment 2 — Algorithms
  Databases    CS310               Mon  Exam — Databases
  ...                              ...
```
- **Courses:** name, code, color/tag; tap → its items.
- **Items:** type (assignment/exam), title, course, due, status. Create/edit is a light form.
- **Upcoming** view = the cross-course deadline list; the same items surface on Today.

### States
First-use ("Add your courses to track deadlines"), no-upcoming ("Nothing due soon"), populated,
during-break (calm empty), offline.

### Deliberately excluded
Grades/GPA, timetable/class-schedule import, attendance, materials. If class times matter, they're
just **Schedule events**, not a separate university calendar. **Challenge:** you might want class
times auto-reflected on Today — that's Schedule's job, not University's. Flagged **D-5**.

---

## 11. Notes UX (speed-first)

### Principles
- **Capture in one tap** from ＋; body-first, title optional.
- Notes are for _fast thought capture_, not documents. Search matters more than folders.

### Quick capture & list
```
Quick note:  [ body-first textarea ]  → Save

Notes list:  [ 🔍 Search ]
  Visa appointment — bring passport…      2d
  Ideas for project…                      5d
  ...
```
- **List** sorted by recently-updated; each row = title-or-first-line + snippet + relative time.
- **Search** is prominent (text match V1; semantic search via AI is V1.5+).
- **Editor** is calm and minimal (title optional, body, optional tags). Autosave.
- **Future AI:** "summarize this note," "find the note about X," "turn this into tasks" —
  in-context, later.

### States
First-use, empty, populated, search-no-results ("No notes match"), offline (full CRUD), editing/
autosaving.

### Deliberately deferred
Rich formatting/markdown rendering polish, attachments, note linking, folders. Tags are the only
organization primitive in V1.

---

## 12b. Moments UX

### Principles
- A **lightweight personal timeline** of memories — photo + caption + time (+ optional place).
  Not a social feed, not a photo manager.

### Capture & timeline
```
Capture:  [ photo ]  caption…  · time (now) · 📍 optional

Timeline (reverse-chronological, grouped by date):
  August
   ┌────┐ ┌────┐ ┌────┐
   │img │ │img │ │img │   caption · time
   └────┘ └────┘ └────┘
```
- Capture: pick/take photo → caption → save. Location strictly optional and **off by default**
  (privacy). Client-compresses images.
- Timeline/gallery grouped by day/month; tap → moment detail.
- **Future AI:** "show me moments from last month," "what did I do in Ramadan" — later.

### States
First-use ("Capture your first moment"), empty, populated, offline (queues upload), upload-in-
progress, upload-failed (retry).

### Product decision
- **Why Moments at all in a productivity-leaning OS?** Because a _personal_ OS is about your life,
  not just your obligations. Moments is the humanizing counterweight to tasks/expenses. But it's
  **low-priority for V1** — see scope. **Challenge:** if it dilutes focus, Moments is the first
  thing to cut from V1. Flagged **D-6**.

---

## 13. Profile / Settings (only what's necessary)

Resist the settings dump. Include only:
- **Identity:** name, avatar.
- **Preferences:** theme (system/light/dark), **currency** (EGP default), **units** (kg/lb),
  **week start**, date/time format.
- **AI:** enable/disable, tone (concise default), data scope (what AI may read), clear
  conversation history.
- **Data & privacy:** export my data, "what leaves this device" transparency, sign out. (Account
  deletion later.)
- **About:** version.

Everything else is a candidate for _not existing_. No notification center, no integrations, no
themes gallery in V1.

---

## 14. Cross-feature user flows (the system composing)

These are the flows that prove Personal OS is a system, not modules.

**A. Schedule → Today → Workout**
```
Event/plan says today is "Chest"  →  Today shows a Workout card "Today: Chest [Start]"
   →  tap Start  →  Active Session  →  Finish  →  Today card flips to "Chest · done ✓"
```

**B. University assignment → Task/Focus → Today**
```
Add assignment "Algo 2, due Fri"  →  appears in University Upcoming
   →  auto-surfaces in Today's focus list as Friday nears (labeled its course)
   →  complete on Today  →  marked done in University too
```
_(Decision: a due university item appears on Today directly — we do **not** force you to also make
a task. One source of truth; Today composes it.)_

**C. Expense → Today glance → Weekly summary → AI**
```
Capture 120 EGP  →  Today spending line updates (today/this week)
   →  Expenses summary shows week/month by category
   →  Ask "how much on food this week?"  →  concise answer + Details →
```

**D. Workout history → AI (in-context)**
```
Workout Progress screen  →  in-context "How's my progress?"
   →  AI reads sessions/sets  →  "Bench up 5kg over 4 weeks; volume steady."
```

**E. Ask → Action → module (write, confirmed)** _(V2)_
```
Ask "add gym at 6pm"  →  confirmation sheet (Gym · today 18:00)  →  Add
   →  event created in Schedule  →  appears on Today Now/Next
```

**F. Morning open → whole-day comprehension** _(the meta-flow)_
```
Open app (morning)  →  Now/Next + focus list + workout + spend glance
   →  understand the day in 3s  →  optionally Ask "what's most important today?"
```

The design north star: **every capture and every completion ripples to Today, and Today ripples
to AI.** No feature is an island.

---

## 15. UI states — the premium checklist (all major screens)

For each screen we specify all of: **Loading · Empty · First-use · Populated · Partial · Completed
· Offline · Error.** Principles that apply everywhere:

- **Loading:** layout-shaped skeletons (never full-screen spinners); cached data shows instantly
  and refreshes in place.
- **Empty:** intentional and calm ("A clear day") — never looks broken; always offers the one
  relevant action.
- **First-use:** warm, single-action guidance — not a multi-step tour, not a wall of tips.
- **Partial:** each section owns its own empty/loaded state; the screen never looks half-broken.
- **Completed:** quietly rewarding (haptic + subtle motion), especially workout finish and task
  complete.
- **Offline:** capture/edit keep working (queued); a subtle, non-alarming indicator; AI/rollup
  features degrade gracefully ("updates when back online").
- **Error:** localized and recoverable ("couldn't load · retry"); never a raw exception; never
  takes down a whole screen.

| Screen | Notable state nuance |
|---|---|
| Today | time-adaptive + end-of-day reflective; per-section partial states |
| Workout session | keep-awake; resume-in-progress; offline logging |
| Expenses capture | works fully offline; totals show "syncing" |
| AI Ask | thinking state (brief, elegant); offline → "AI needs a connection" |
| Notes | autosave/editing state; search-no-results |
| Moments | upload-in-progress / upload-failed-retry |

---

## 16. Design system direction (visual language)

**Identity:** Minimal · Premium · Monochrome · Apple-like · highly intentional. Every element
justifies its ink. The feeling target: **calm, precise, fast** — like a well-made instrument.

- **Color:** true monochrome foundation — a near-black and a near-white with a **carefully graded
  neutral scale** for surfaces/text. **At most one functional accent** (used only for active/
  interactive emphasis and key CTAs), and semantic tones (success/warn) used _sparingly_ and
  desaturated. Dark and light both first-class. No gradients-as-decoration, no color-coded
  dashboards. _(Consider: monochrome + a single restrained accent, or pure grayscale with
  emphasis via weight/contrast only — decide during first-screen design.)_
- **Typography:** one strong family (system SF-like for native feel, or a premium geometric
  sans), used across a **tight, deliberate scale** (e.g., Display / Title / Body / Caption).
  Hierarchy comes from **weight, size, and spacing**, not color. Numerals matter (tabular for
  amounts/reps). Generous line-height; text is the primary UI.
- **Spacing:** strict **8pt grid**, generous whitespace, breathing room over density where it
  counts. Information-dense _where needed_ (workout session, expense history) but never cramped.
- **Surface hierarchy:** depth via **subtle elevation and hairline separation**, not heavy
  shadows or borders. Cards are quiet containers; Today's cards read as calm blocks, not
  competing tiles. Sheets are the primary modal surface.
- **Corner radius:** consistent, moderately rounded (a small set of radii — e.g., controls,
  cards, sheets), never fully pill-everything, never sharp/harsh. Cohesive across the app.
- **Icons:** a single line-icon set (SF Symbols-like), consistent weight, used sparingly and
  meaningfully — never decorative.
- **Buttons:** a clear hierarchy — one **primary** style (filled, high-contrast) used once per
  screen, **secondary** (subtle/tinted), **tertiary/text**. Big, confident primary actions
  (Start workout, Save, Log set).
- **Sheets:** the workhorse for capture, Ask, confirmations — bottom sheets with a grabber, spring
  presentation, content-height where possible. Capture and Ask both live here.
- **Cards & lists:** lists are the backbone (agenda, tasks, expenses, notes); rows are quiet,
  swipeable, tappable, with clear touch targets. Cards used only for genuine "objects" (workout,
  now/next).
- **Navigation:** minimal bottom bar (4 items), clear active state (weight/contrast, not loud
  color); large titles that collapse on scroll (native iOS feel); back is predictable.
- **Motion:** **spring-based, quick, purposeful** — sheets spring up, completes settle, Today
  sections stagger-in subtly on load. Nothing bouncy-for-fun; motion communicates state and
  hierarchy. Respect reduce-motion.
- **Haptics:** deliberate and meaningful — a crisp tick on task complete and set logged, a
  success cue on workout finish and capture saved, a subtle warning on conflicts. Haptics are
  part of the premium feel, not noise.

**Overall:** the app should feel like **iOS-native but quieter and more personal** — closer to
Apple's own first-party apps (Reminders/Fitness/Health) than to any SaaS dashboard.

---

## 17. Scope & the rest

### MVP UX scope (the daily-usable core — matches PLAN.md Phases 0–5)
- **Today** (adaptive, with Now/Next + focus list + workout card + spending glance + all states).
- **Global Quick Capture** (Task / Expense / Event; Note optional here).
- **Tasks** (capture, list, complete, Today integration).
- **Schedule** (agenda, create/edit, Now/Next, Today integration).
- **Expenses** (<5s capture, history, day/week/month summaries, Today glance).
- **Profile** (minimal preferences).
- No AI, no Workout, no University depth, no Notes/Moments yet.
> If you'd use _this_ every morning and it feels like an OS, the product is validated.

### V1 UX scope (the complete personal OS you run your life on)
- MVP **plus**: **Workout** (manual plans, full session/logging/summary/history/progress),
  **University** (courses/items/deadlines → Today), **Notes** (capture/list/search),
  **Moments** (capture/timeline), and **AI read-only** (Ask + in-context answers across all
  data; ambient brief). No AI writes, no PDF import.

### Features/UX to postpone
- **AI actions** (write, confirmed) and **guided workouts** → V2.
- **PDF → structured workout** → V2 (review-and-confirm UX only sketched now).
- **Semantic note search / AI over notes & moments** → V1.5+.
- **Budgets, recurring expenses, multi-currency, receipts** → later.
- **Recurring tasks, reminders/notifications, subtasks** → later.
- **Calendar sync, week/month grid, class-timetable import** → later.
- **Grades/GPA, attendance** → not planned.
- **Widgets, Watch app, Live Activities, lock-screen** → post-V1 (though Today is designed to feed
  them later).

### UX risks
1. **Today becoming a cluttered dashboard.** _Mitigation:_ ruthless section limit, no charts,
   time-adaptive emphasis, "see all" for depth.
2. **Module sprawl re-creating "10 CRUD apps."** _Mitigation:_ Hub is a launcher into _depth_;
   daily life stays on Today; capture is unified.
3. **AI defaulting to a chat box.** _Mitigation:_ four-mode model; Ask is transient; in-context
   AI; chat is the exception.
4. **Capture friction creeping up.** _Mitigation:_ hard <5s budget for expense/task/note; test it.
5. **Empty/first-use feeling broken.** _Mitigation:_ intentional empty states as a first-class
   design task, not an afterthought.
6. **Workout session unusable mid-set.** _Mitigation:_ big targets, prefill, one-handed, keep-
   awake — usability-test with actual sweaty hands.
7. **Over-scoping V1** (Moments/University pulling focus). _Mitigation:_ clear cut list; Moments
   first to go if needed.
8. **Premium feel underspecified → generic result.** _Mitigation:_ motion/haptics/states budgeted
   into every screen, not "polish later."

### Open product decisions (need your call before/at first-screen design)
- **D-1 — Navigation:** 4-tab (Today/Hub/AI/Profile) vs. 3-tab (Hub folded into Today). _Rec:
  4-tab._
- **D-2 — Today focus list:** merge Tasks + University deadlines into one list vs. keep visually
  separate. _Rec: merge, with source labels._
- **D-3 — Recurring tasks:** V1 or defer? _Rec: defer._
- **D-4 — Expense budgets:** V1 or defer? _Rec: defer (keeps it capture+see)._
- **D-5 — Class times:** model as Schedule events (not a University timetable)? _Rec: yes,
  Schedule owns time._
- **D-6 — Moments in V1:** keep or cut to sharpen focus? _Rec: keep but lowest priority; first to
  cut._
- **D-7 — AI prominence:** confirm AI is Ask+in-context first, chat-tab second (not centered). _Rec:
  yes._
- **D-8 — Design accent:** single restrained accent vs. pure grayscale (emphasis by weight/
  contrast only). _Decide during first-screen design._

### Recommended first UI screen to design
**Today (morning, populated state) — as a static, high-fidelity design.**

**Why Today first:**
- It's the product's thesis; if it doesn't feel like an OS, nothing else matters.
- It **forces** us to resolve the design system (type scale, spacing, cards, monochrome accent)
  on the most important surface, so every other screen inherits proven tokens.
- It exercises the hardest composition problem (multiple features on one calm surface) up front.
- It surfaces the open decisions (D-1, D-2, D-8) concretely instead of abstractly.

**Sequence after Today:** Today (morning) → Today states (empty/first-use/evening) → Quick Capture
sheet → Expense capture (proves the <5s claim) → Workout Active Session (proves the hardest real-
time screen) → Ask surface. These six establish the entire visual + interaction language; the
remaining screens are then largely composition of settled patterns.

---

## Deliverables index (mapping to your Phase -1 request)

| # | Requested deliverable | Section |
|---|---|---|
| 1 | Product experience definition | §0, §1 |
| 2 | Information architecture | §2 |
| 3 | Navigation map | §2, §3 |
| 4 | Complete screen map | §3 |
| 5 | User flows | §14 |
| 6 | Home / Today specification | §4 |
| 7 | AI experience specification | §5 |
| 8 | Feature-by-feature UX | §6–§13 |
| 9 | Cross-feature flows | §14 |
| 10 | UI state specification | §4 (Today), §15 |
| 11 | Design system direction | §16 |
| 12 | MVP UX scope | §17 |
| 13 | V1 UX scope | §17 |
| 14 | Features to postpone | §17 |
| 15 | UX risks | §17 |
| 16 | Open product decisions | §17 (D-1…D-8) |
| 17 | Recommended first UI screen | §17 |

---

_End of Phase -1 blueprint. This is the product contract. On approval, we re-derive the technical
plan (domain → use cases → data → Firebase → AI) to **serve** this experience — never the reverse.
Do not proceed to technical architecture until this is reviewed and the open decisions (D-1…D-8)
are settled._
