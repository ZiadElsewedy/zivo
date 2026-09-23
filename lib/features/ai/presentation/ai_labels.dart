import 'package:flutter/widgets.dart';

import '../../../l10n/l10n.dart';
import '../domain/ai_failure.dart';
import '../domain/ai_model_selection.dart';
import '../domain/ai_response_style.dart';

/// The words the AI domain's stored ids wear on screen.
///
/// `responseStyleLabel` lived in `domain/ai_response_style.dart` and could only
/// ever return English: the domain layer is Flutter-free, so there is no
/// [BuildContext] there to read a translation from. The reply-style menu on the
/// Ask header was therefore three English words — Concise / Balanced / Detailed
/// — sitting in an otherwise fully Arabic screen.
///
/// The split is the one `diet_labels.dart` and `workout_labels.dart` already
/// use: `'concise'` stays a persisted **id** (it goes to Firestore and on to
/// the gateway's `RESPONSE_STYLE_DIRECTIVES`, and must not change with the UI
/// language), and its *word* is chosen here, where a context exists.
String responseStyleText(BuildContext context, String style) =>
    switch (validResponseStyle(style)) {
      'concise' => l(context).askReplyStyleConcise,
      'detailed' => l(context).askReplyStyleDetailed,
      _ => l(context).askReplyStyleBalanced,
    };

/// The one-line description under each reply-style option in the settings
/// sheet — the parity of [aiModelSelectionDescription] for reply length.
String responseStyleDescription(BuildContext context, String style) =>
    switch (validResponseStyle(style)) {
      'concise' => l(context).askReplyStyleConciseDesc,
      'detailed' => l(context).askReplyStyleDetailedDesc,
      _ => l(context).askReplyStyleBalancedDesc,
    };

/// The name a model-selection id ([kAiModelSelections]) wears on screen.
/// `'auto'` is a translated word; the model names are product names that stay
/// as-is in every locale. Same id-vs-copy split as [responseStyleText].
String aiModelSelectionText(BuildContext context, String selection) =>
    switch (validAiModelSelection(selection)) {
      'claude-sonnet' => l(context).askModelClaudeSonnet,
      'claude-haiku' => l(context).askModelClaudeHaiku,
      'gemini-flash' => l(context).askModelGeminiFlash,
      'gemini-pro' => l(context).askModelGeminiPro,
      _ => l(context).askModelAuto,
    };

/// The display name for a routing-layer provider id ('anthropic' → "Claude",
/// 'gemini' → "Gemini") — used by the usage views, which are keyed by
/// provider rather than by the user's selection. Anthropic's product is Claude.
String aiProviderDisplayName(BuildContext context, String provider) =>
    switch (provider) {
      'gemini' => l(context).askModelGemini,
      _ => l(context).askModelClaude,
    };

/// The one-line description under each model option in the settings page —
/// context that makes the choice understandable at the point of decision.
String aiModelSelectionDescription(BuildContext context, String selection) =>
    switch (validAiModelSelection(selection)) {
      'claude-sonnet' => l(context).askModelClaudeSonnetDesc,
      'claude-haiku' => l(context).askModelClaudeHaikuDesc,
      'gemini-flash' => l(context).askModelGeminiFlashDesc,
      'gemini-pro' => l(context).askModelGeminiProDesc,
      _ => l(context).askModelAutoDesc,
    };

/// A human name for a provider-native model id as the usage log records it
/// ('claude-sonnet-5' → "Claude Sonnet"). An id this build doesn't know —
/// a model added server-side later — is shown as-is rather than mislabelled.
String aiModelIdText(BuildContext context, String modelId) {
  final id = modelId.toLowerCase();
  if (id.startsWith('claude-sonnet')) return l(context).askModelClaudeSonnet;
  if (id.startsWith('claude-haiku')) return l(context).askModelClaudeHaiku;
  if (id.startsWith('gemini') && id.contains('flash')) {
    return l(context).askModelGeminiFlash;
  }
  if (id.startsWith('gemini') && id.contains('pro')) {
    return l(context).askModelGeminiPro;
  }
  return modelId;
}

/// What a usage record's `feature` was for — the words beside each request on
/// the usage page. An unknown feature (a newer backend) reads as a generic
/// "AI request" rather than a raw id.
String aiFeatureText(BuildContext context, String feature) =>
    switch (feature) {
      'chat' => l(context).aiFeatureChat,
      'workout_import' => l(context).aiFeatureWorkoutImport,
      'diet_import' => l(context).aiFeatureDietImport,
      'diet_generate' => l(context).aiFeatureDietGenerate,
      'food_search' => l(context).aiFeatureFoodSearch,
      'transcribe' => l(context).aiFeatureTranscribe,
      _ => l(context).aiFeatureOther,
    };

/// The one line a failed AI request shows, by why it failed — never the
/// transport's or a provider's own text. [unknown] is the caller's own
/// fallback for a failure with no specific cause (an import says "couldn't
/// read that plan", generation says something else).
String aiFailureMessage(
  BuildContext context,
  AiFailureKind kind, {
  required String unknown,
}) => switch (kind) {
  AiFailureKind.unavailable => l(context).aiErrorUnavailable,
  AiFailureKind.dailyLimit => l(context).aiErrorDailyLimit,
  AiFailureKind.timeout => l(context).aiErrorTimeout,
  AiFailureKind.network => l(context).aiErrorNetwork,
  AiFailureKind.auth => l(context).importAppCheckFailed,
  AiFailureKind.notDeployed => l(context).importServiceUnavailable,
  AiFailureKind.unknown => unknown,
};
