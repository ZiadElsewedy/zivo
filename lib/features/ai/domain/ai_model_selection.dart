/// The user's **active AI model**, persisted at `users/{uid}/settings/ai`
/// (field `provider`) and used for **every** AI feature: the chat forwards it
/// on each [AiRepository.send], and the plan import/generation callables read
/// it from that settings doc server-side.
///
/// Exactly one model answers every request — there is no automatic switching
/// to another provider (owner decision, 2026-09-23: one active model keeps
/// cost and usage attributable). If the active model's provider can't answer,
/// the request fails with an [AiFailure] naming the provider, and the user
/// switches model here. See `functions/ai/routing/router.js`.
///
/// The ids are the backend model catalog's keys
/// (`functions/ai/routing/models.js`). Like [kResponseStyles], they are
/// persisted **ids**, not copy — their words are chosen in
/// `presentation/ai_labels.dart` where a [BuildContext] exists.
const kAiModelSelections = ['claude-sonnet', 'claude-haiku', 'gemini-flash'];

const kDefaultAiModelSelection = 'claude-sonnet';

/// Selections an older build may have saved, mapped onto today's ids: the
/// original provider-level picks, the retired Auto (Claude-first), and Gemini
/// Pro, removed because its alias never resolved for this project's key.
const Map<String, String> _legacySelections = {
  'auto': 'claude-sonnet',
  'claude': 'claude-sonnet',
  'gemini': 'gemini-flash',
  'gemini-pro': 'gemini-flash',
};

/// [selection] if it's one of [kAiModelSelections] (or a legacy id, upgraded),
/// else [kDefaultAiModelSelection] — never trust a stored/round-tripped value
/// blindly (an old build, a hand-edited settings doc, a future id).
String validAiModelSelection(String? selection) {
  final upgraded = _legacySelections[selection] ?? selection;
  return kAiModelSelections.contains(upgraded)
      ? upgraded!
      : kDefaultAiModelSelection;
}

/// The routing-layer provider behind a selection: 'anthropic' | 'gemini'.
String aiModelSelectionProvider(String selection) =>
    validAiModelSelection(selection).startsWith('gemini')
    ? 'gemini'
    : 'anthropic';
