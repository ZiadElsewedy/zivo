/// Live events streamed from the `aiChat` gateway during a single turn
/// (Phase 3.5 Slice C). Phases are derived server-side from the loop's real
/// state — never the model's reasoning — so the client's activity rail can be
/// authoritative rather than time-guessed.
sealed class AiTurnEvent {
  const AiTurnEvent();
}

/// A coarse, user-facing stage of the turn. The confirmation card itself
/// carries the "waiting for confirmation" state, so it is not a phase here.
///
/// [thinking] is the model call that reads tool results back between steps —
/// execution progress the loop really is in, never the model's reasoning
/// (which is not streamed at all).
enum AiPhase {
  understanding,
  working,
  thinking,
  preparingChange,
  done,
  unknown,
}

/// The turn crossed into [phase].
class AiPhaseEvent extends AiTurnEvent {
  const AiPhaseEvent(this.phase, {this.replaced = false});

  final AiPhase phase;

  /// Set on the `done` event when the gateway's advice validator rejected the
  /// model's reply and persisted deterministic text in its place.
  ///
  /// It matters because the rejected draft has already streamed to the screen:
  /// the client must drop what it is showing rather than leave the user
  /// reading figures the server has already determined were wrong. Absent on
  /// every other event, and false whenever the turn wasn't validated at all.
  final bool replaced;
}

/// A single read tool starting or finishing inside the turn's tool loop.
///
/// The gateway sends the tool's **name only** — never its input, never its
/// result — and the human label is resolved on this side ([AiStepEvent.label])
/// so the wording stays localizable and can change without a functions deploy.
/// Mutating tools produce no step: they don't execute during the turn, they
/// become a proposal, which the `preparingChange` phase and the confirmation
/// card already describe.
class AiStepEvent extends AiTurnEvent {
  const AiStepEvent(this.tool, this.status);

  /// The gateway's tool identifier, e.g. `get_diet`. Unknown names are kept
  /// rather than dropped — a tool added server-side must not make the rail go
  /// silent on an older build.
  final String tool;

  final AiStepStatus status;
}

/// Where a step is in its life. There is no "pending": a step is only
/// announced once it actually starts.
enum AiStepStatus { running, ok, error }

/// One entry of a turn's activity timeline — a read tool the agent ran and
/// how it went. Built live from [AiStepEvent]s while the turn streams, and
/// persisted on the assistant's reply (`activity`) so the timeline is still
/// there on reload. Carries the tool's NAME only; its input and result never
/// reach the client, and the words shown are the client's
/// (`aiActivityLabel`).
class AiActivityStep {
  const AiActivityStep(this.tool, this.status)
    : fallbackFrom = null,
      fallbackTo = null;

  /// The active model couldn't answer (after its retry) and the turn carried
  /// on with the other one. [from]/[to] are model-selection keys
  /// (`gemini-flash`, `claude-sonnet`), never provider error text.
  const AiActivityStep.fallback(String from, String to)
    : tool = '',
      status = AiStepStatus.ok,
      fallbackFrom = from,
      fallbackTo = to;

  final String tool;
  final AiStepStatus status;
  final String? fallbackFrom;
  final String? fallbackTo;

  bool get isFallback => fallbackTo != null;

  @override
  bool operator ==(Object other) =>
      other is AiActivityStep &&
      other.tool == tool &&
      other.status == status &&
      other.fallbackFrom == fallbackFrom &&
      other.fallbackTo == fallbackTo;

  @override
  int get hashCode => Object.hash(tool, status, fallbackFrom, fallbackTo);
}

/// The router switched models mid-turn: the active one ([from]) was
/// unavailable, so the turn continues on [to]. Anything the failed attempt
/// had streamed is superseded.
class AiFallbackEvent extends AiTurnEvent {
  const AiFallbackEvent(this.from, this.to);

  final String from;
  final String to;
}

/// A chunk of the assistant's reply text as it streams in.
class AiDeltaEvent extends AiTurnEvent {
  const AiDeltaEvent(this.text);

  final String text;
}

/// The whole live reply as it should read now — sent instead of a delta when
/// text already on screen is superseded: a provider retry after partial
/// output, or a step restating the previous one's lead-in
/// (`functions/ai/chat/live_text.js`). Applied as a REPLACE, never appended,
/// so the reply can't appear to start over.
class AiReplaceEvent extends AiTurnEvent {
  const AiReplaceEvent(this.text);

  final String text;
}

/// Maps the gateway's wire phase string to an [AiPhase]; unknown values are
/// tolerated (forward-compatible) rather than thrown.
AiPhase aiPhaseFromName(String? name) => switch (name) {
  'understanding' => AiPhase.understanding,
  'working' => AiPhase.working,
  'thinking' => AiPhase.thinking,
  'preparing_change' => AiPhase.preparingChange,
  'done' => AiPhase.done,
  _ => AiPhase.unknown,
};

/// Maps the gateway's wire status to an [AiStepStatus]. An unrecognised value
/// is treated as `running` — a step that never resolves is a worse lie than a
/// step that looks busy, because the rail only ever shows the LATEST step and
/// the turn's `done` phase tears the whole rail down regardless.
AiStepStatus aiStepStatusFromName(String? name) => switch (name) {
  'ok' => AiStepStatus.ok,
  'error' => AiStepStatus.error,
  _ => AiStepStatus.running,
};

/// Parses one streamed chunk (`{type: 'phase'|'step'|'delta'|'replace', ...}`) into an
/// [AiTurnEvent], or null if the chunk is malformed / unrecognised.
AiTurnEvent? aiTurnEventFromChunk(Object? chunk) {
  if (chunk is! Map) return null;
  switch (chunk['type']) {
    case 'phase':
      return AiPhaseEvent(
        aiPhaseFromName(chunk['phase'] as String?),
        replaced: chunk['replaced'] == true,
      );
    case 'step':
      final tool = chunk['tool'];
      if (tool is! String || tool.isEmpty) return null;
      return AiStepEvent(
        tool,
        aiStepStatusFromName(chunk['status'] as String?),
      );
    case 'delta':
      final text = chunk['text'];
      return text is String ? AiDeltaEvent(text) : null;
    case 'replace':
      final text = chunk['text'];
      return text is String ? AiReplaceEvent(text) : null;
    case 'fallback':
      final from = chunk['from'];
      final to = chunk['to'];
      return from is String && to is String ? AiFallbackEvent(from, to) : null;
    default:
      return null;
  }
}
