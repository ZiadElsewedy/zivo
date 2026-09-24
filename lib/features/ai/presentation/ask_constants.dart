/// The Ask screen's shared constants — the timings its turn machinery runs
/// on, and the one layout value the composer and the scroll view must agree
/// about.
///
/// They live beside `pages/` and `widgets/` rather than inside either,
/// because both need them: `_kComposerFloatClearance` was a file-private
/// constant in a 3,000-line page, which is exactly why the empty state could
/// read it. Once the empty state became its own widget, "how much room the
/// floating composer needs" had to become something with an address.
library;

import 'package:flutter/foundation.dart';

/// How long a voice-note transcription may run before the UI gives up
/// waiting and offers a friendly retry — a hung request must never leave the
/// composer locked.
const kTranscribeTimeout = Duration(seconds: 35);

/// With zero gateway events for this long mid-turn, the rail admits the wait
/// ("Still working…") instead of silently spinning.
const kSlowTurnAfter = Duration(seconds: 18);

/// After a turn's stream ends, the optimistic bubble waits this long for the
/// durable user message to land before concluding the send failed — covering
/// silent server drops that would otherwise look like an eternal hang.
const kLandingGrace = Duration(seconds: 12);

/// The streamed reply's writing pace, in characters per second, once it has
/// caught up with the network — a calm, legible write rather than a dump.
const kRevealFloorCps = 55.0;

/// How long a backlog of streamed text takes to unroll: the pace rises with
/// what's waiting so a burst lands over this long, and the display never
/// trails the network by much more.
const kRevealCatchUp = Duration(milliseconds: 450);

/// With no new reply text for this long mid-turn, ZIVO isn't writing any more
/// (it's composing a lookup after a lead-in) — the thought line comes back.
const kWritingIdle = Duration(milliseconds: 700);

/// Whether the thought trail also shows each step's raw tool id. On in debug
/// builds only, so the team can see exactly what ran while the chat is being
/// tuned; a release build never shows an identifier.
const kShowAiToolIds = kDebugMode;

/// Bottom clearance beneath the message list (and empty state) so content
/// scrolls UNDER the floating composer island instead of ending above it —
/// roughly the idle composer's rendered height (≈72) plus a small gap. The
/// composer floats over the list (see [AskPage]'s Stack), so the last line
/// still comes to rest just above it.
const kComposerFloatClearance = 84.0;

/// The "Ask" chat surface: an iris-themed message list over a pinned
/// composer. Talks only to `AppScope.of(context).ai` — Firebase-free.
