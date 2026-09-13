/// The user's manual model/provider selection for Ask, persisted at
/// `users/{uid}/settings/ai` (field `provider`) and forwarded on every
/// [AiRepository.send] call as `provider`.
///
/// This is the client half of the routing decision the backend makes in
/// `functions/ai/routing/router.js`:
///   - `'auto'`    → Anthropic first, Gemini fallback (the default; the server
///                   treats anything unrecognized as this, so it's the safe
///                   value to send).
///   - `'claude'`  → force Anthropic, no fallback.
///   - `'gemini'`  → force Gemini, no fallback.
///
/// Like [kResponseStyles], these are persisted **ids**, not copy — their words
/// are chosen in `presentation/ai_labels.dart` where a [BuildContext] exists.
const kAiModelSelections = ['auto', 'claude', 'gemini'];

const kDefaultAiModelSelection = 'auto';

/// [selection] if it's one of [kAiModelSelections], else
/// [kDefaultAiModelSelection] — never trust a stored/round-tripped value
/// blindly (an old build, a hand-edited settings doc, a future id).
String validAiModelSelection(String? selection) =>
    kAiModelSelections.contains(selection)
        ? selection!
        : kDefaultAiModelSelection;
