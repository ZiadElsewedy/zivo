/// Live events streamed from the `aiChat` gateway during a single turn
/// (Phase 3.5 Slice C). Phases are derived server-side from the loop's real
/// state — never the model's reasoning — so the client's activity rail can be
/// authoritative rather than time-guessed.
sealed class AiTurnEvent {
  const AiTurnEvent();
}

/// A coarse, user-facing stage of the turn. The confirmation card itself
/// carries the "waiting for confirmation" state, so it is not a phase here.
enum AiPhase { understanding, working, preparingChange, done, unknown }

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

/// A chunk of the assistant's reply text as it streams in.
class AiDeltaEvent extends AiTurnEvent {
  const AiDeltaEvent(this.text);

  final String text;
}

/// Maps the gateway's wire phase string to an [AiPhase]; unknown values are
/// tolerated (forward-compatible) rather than thrown.
AiPhase aiPhaseFromName(String? name) => switch (name) {
  'understanding' => AiPhase.understanding,
  'working' => AiPhase.working,
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

/// Parses one streamed chunk (`{type: 'phase'|'step'|'delta', ...}`) into an
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
    default:
      return null;
  }
}
