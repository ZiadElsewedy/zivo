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
  const AiPhaseEvent(this.phase);

  final AiPhase phase;
}

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

/// Parses one streamed chunk (`{type: 'phase'|'delta', ...}`) into an
/// [AiTurnEvent], or null if the chunk is malformed / unrecognised.
AiTurnEvent? aiTurnEventFromChunk(Object? chunk) {
  if (chunk is! Map) return null;
  switch (chunk['type']) {
    case 'phase':
      return AiPhaseEvent(aiPhaseFromName(chunk['phase'] as String?));
    case 'delta':
      final text = chunk['text'];
      return text is String ? AiDeltaEvent(text) : null;
    default:
      return null;
  }
}
