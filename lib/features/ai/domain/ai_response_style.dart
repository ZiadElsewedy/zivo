/// The user's saved reply-length/style preference for Ask, persisted at
/// `users/{uid}/settings/ai` (field `responseStyle`) and forwarded on every
/// [AiRepository.send] call. 'balanced' is the default and adds no directive
/// to the system prompt — see `functions/ai/gateway.js`'s
/// `RESPONSE_STYLE_DIRECTIVES`.
const kResponseStyles = ['concise', 'balanced', 'detailed'];

const kDefaultResponseStyle = 'balanced';

/// [style] if it's one of [kResponseStyles], else [kDefaultResponseStyle] —
/// never trust a stored/round-tripped value blindly.
String validResponseStyle(String? style) =>
    kResponseStyles.contains(style) ? style! : kDefaultResponseStyle;

String responseStyleLabel(String style) => switch (style) {
  'concise' => 'Concise',
  'detailed' => 'Detailed',
  _ => 'Balanced',
};
