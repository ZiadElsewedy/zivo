/// The user's **active AI model**, persisted at `users/{uid}/settings/ai`
/// (field `provider`) and used for **every** AI feature: the chat forwards it
/// on each [AiRepository.send], and the plan import/generation callables read
/// it from that settings doc server-side.
///
/// ONE model is the user's choice — the primary — and it answers every
/// request. The other provider's model is an automatic emergency fallback,
/// never a second "active" model and never shown as one (owner decision,
/// 2026-09-24): on a transient failure the primary is retried once, then the
/// request continues on the fallback and Ask's timeline says so ("Gemini Flash
/// unavailable → Switched to Claude Sonnet"); usage records the requested and
/// the actual model. Only a permanent failure, or both providers failing,
/// surfaces an [AiFailure] with Retry / Switch model. See
/// `functions/ai/routing/router.js`.
///
/// The ids are the backend model catalog's keys
/// (`functions/ai/routing/models.js`). Like [kResponseStyles], they are
/// persisted **ids**, not copy — their words are chosen in
/// `presentation/ai_labels.dart` where a [BuildContext] exists.
///
/// Exactly one model per provider, on purpose (owner decision, 2026-09-24):
/// a second Claude option next to Sonnet would ask the user to choose between
/// two flavors of the same provider on top of choosing a provider, for a
/// choice the fallback (see `functions/ai/routing/router.js`) already makes
/// moot most of the time.
const kAiModelSelections = ['claude-sonnet', 'gemini-flash'];

const kDefaultAiModelSelection = 'claude-sonnet';

/// Selections an older build may have saved, mapped onto today's ids: the
/// original provider-level picks, the retired Auto (Claude-first), Gemini
/// Pro (its alias never resolved for this project's key), and Claude Haiku
/// (removed 2026-09-24 — ZIVO offers one model per provider now).
const Map<String, String> _legacySelections = {
  'auto': 'claude-sonnet',
  'claude': 'claude-sonnet',
  'gemini': 'gemini-flash',
  'gemini-pro': 'gemini-flash',
  'claude-haiku': 'claude-sonnet',
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
