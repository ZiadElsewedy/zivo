/// The user's AI model selection, persisted at `users/{uid}/settings/ai`
/// (field `provider`) and applied to **every** AI feature: the chat forwards it
/// on each [AiRepository.send], and the plan import/generation callables read
/// it from that settings doc server-side.
///
/// This is the client half of the routing decision the backend makes in
/// `functions/ai/routing/router.js`. The ids are the backend model catalog's
/// keys (`functions/ai/routing/models.js`):
///   - `'auto'`          → Claude Sonnet first, Gemini Flash if Claude can't
///                         answer (the default; the server treats anything
///                         unrecognized as this, so it's the safe value).
///   - any model id      → that model first, the Auto order behind it. A
///                         chosen model is a **preference, not a pin**: if its
///                         provider is down or out of credit, the request still
///                         lands on the next model instead of failing.
///
/// Like [kResponseStyles], these are persisted **ids**, not copy — their words
/// are chosen in `presentation/ai_labels.dart` where a [BuildContext] exists.
const kAiModelSelections = [
  'auto',
  'claude-sonnet',
  'claude-haiku',
  'gemini-flash',
  'gemini-pro',
];

const kDefaultAiModelSelection = 'auto';

/// Selections saved before per-model choice existed, mapped onto today's ids —
/// someone who picked "Claude" keeps Claude.
const Map<String, String> _legacySelections = {
  'claude': 'claude-sonnet',
  'gemini': 'gemini-flash',
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

/// The routing-layer provider behind a selection ('anthropic' | 'gemini'), or
/// 'auto' — what the brand mark beside it shows.
String aiModelSelectionProvider(String selection) =>
    switch (validAiModelSelection(selection)) {
      'claude-sonnet' || 'claude-haiku' => 'anthropic',
      'gemini-flash' || 'gemini-pro' => 'gemini',
      _ => 'auto',
    };
