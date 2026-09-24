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

/// The name a model-selection id ([kAiModelSelections]) wears on screen —
/// product names, the same in every locale, but still routed through l10n.
/// Same id-vs-copy split as [responseStyleText].
String aiModelSelectionText(BuildContext context, String selection) =>
    switch (validAiModelSelection(selection)) {
      'gemini-flash' => l(context).askModelGeminiFlash,
      _ => l(context).askModelClaudeSonnet,
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
      'gemini-flash' => l(context).askModelGeminiFlashDesc,
      _ => l(context).askModelClaudeSonnetDesc,
    };

/// A human name for a provider-native model id as the usage log records it
/// ('claude-sonnet-5' → "Claude Sonnet"). An id this build doesn't know —
/// a model added server-side later — is shown as-is rather than mislabelled.
String aiModelIdText(BuildContext context, String modelId) {
  final id = modelId.toLowerCase();
  if (id.startsWith('claude-sonnet')) return l(context).askModelClaudeSonnet;
  if (id.startsWith('gemini') && id.contains('flash')) {
    return l(context).askModelGeminiFlash;
  }
  // Covers a retired id too (Claude Haiku, removed 2026-09-24) — an old usage
  // record naming it shows the raw id rather than mislabelling it as Sonnet.
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

/// The provider's display name in a failure, or "The AI model" when the
/// server didn't say which.
String _failedProviderName(BuildContext context, AiFailure f) =>
    switch (f.provider) {
      'anthropic' || 'gemini' => aiProviderDisplayName(context, f.provider!),
      _ => l(context).aiModelGeneric,
    };

/// The headline for a failed AI request — for a provider failure, the
/// provider by name ("Claude isn't available", "Gemini didn't respond"), so
/// it's obvious the AI model is what failed, not the phone or the message.
String aiFailureTitle(BuildContext context, AiFailure f) {
  final name = _failedProviderName(context, f);
  return switch (f.kind) {
    AiFailureKind.unavailable => switch (f.issue) {
      AiProviderIssue.noResponse => l(context).aiProviderNoResponseTitle(name),
      AiProviderIssue.busy ||
      AiProviderIssue.overloaded => l(context).aiProviderBusyTitle(name),
      _ => l(context).aiProviderUnavailableTitle(name),
    },
    AiFailureKind.dailyLimit => l(context).aiErrorDailyLimitTitle,
    AiFailureKind.timeout => l(context).aiErrorTimeoutTitle,
    AiFailureKind.network ||
    AiFailureKind.auth ||
    AiFailureKind.notDeployed => l(context).askUnreachableTitle,
    AiFailureKind.unknown => l(context).aiErrorUnknownTitle,
  };
}

/// The explanation under [aiFailureTitle]: what happened and what to do.
/// Never the transport's or a provider's own text.
String aiFailureBody(BuildContext context, AiFailure f) => switch (f.kind) {
  AiFailureKind.unavailable => switch (f.issue ?? AiProviderIssue.down) {
    AiProviderIssue.outOfCredit => l(context).aiIssueOutOfCredit,
    AiProviderIssue.quotaExceeded => l(context).aiIssueQuota,
    AiProviderIssue.notConfigured => l(context).aiIssueNotConfigured,
    AiProviderIssue.busy => l(context).aiIssueBusy,
    AiProviderIssue.overloaded => l(context).aiIssueOverloaded,
    AiProviderIssue.noResponse => l(context).aiIssueNoResponse,
    AiProviderIssue.modelRetired => l(context).aiIssueModelRetired,
    AiProviderIssue.down => l(context).aiIssueDown,
  },
  AiFailureKind.dailyLimit => l(context).aiErrorDailyLimitBody,
  AiFailureKind.timeout => l(context).aiErrorTimeout,
  AiFailureKind.network => l(context).aiErrorNetworkBody,
  AiFailureKind.auth => l(context).importAppCheckFailed,
  AiFailureKind.notDeployed => l(context).importServiceUnavailable,
  AiFailureKind.unknown => l(context).aiErrorUnknownBody,
};

/// Whether switching the active model could fix [f] — the error surfaces
/// then offer a "Switch model" action.
bool aiFailureSuggestsSwitch(AiFailure f) =>
    f.kind == AiFailureKind.unavailable &&
    f.issue != AiProviderIssue.busy &&
    f.issue != AiProviderIssue.noResponse;

/// The single line a failed AI request shows on the full-screen import/
/// generation error — title and explanation joined. [unknown] is the caller's
/// own line for a failure with no specific cause (an import says "couldn't
/// read that plan", generation says something else).
String aiFailureMessage(
  BuildContext context,
  AiFailure f, {
  required String unknown,
}) => switch (f.kind) {
  AiFailureKind.unknown => unknown,
  AiFailureKind.dailyLimit => l(context).aiErrorDailyLimit,
  AiFailureKind.network => l(context).aiErrorNetwork,
  AiFailureKind.auth => l(context).importAppCheckFailed,
  AiFailureKind.notDeployed => l(context).importServiceUnavailable,
  AiFailureKind.timeout => l(context).aiErrorTimeout,
  AiFailureKind.unavailable =>
    '${aiFailureTitle(context, f)}. ${aiFailureBody(context, f)}',
};

/// A tool name → the chip on Ask's activity timeline ("Grab · Diet details").
///
/// The gateway sends only the tool's identifier; the words are chosen here so
/// they stay localizable and never leak `get_diet` onto the screen. An
/// unknown tool (one added server-side after this build) returns null and the
/// timeline simply leaves it out — the rail below still says "Working…".
String? aiActivityLabel(BuildContext context, String tool) {
  final s = l(context);
  final (String, String)? parts = switch (tool) {
    'get_today' => (s.askActivityGrab, s.askActivityToday),
    'get_diet' => (s.askActivityGrab, s.askActivityDiet),
    'get_workouts' => (s.askActivityGrab, s.askActivityWorkouts),
    'get_last_workout' => (s.askActivityGrab, s.askActivityLastWorkout),
    'get_training_analysis' => (
      s.askActivityGrab,
      s.askActivityTrainingAnalysis,
    ),
    'get_exercise_analysis' => (
      s.askActivityGrab,
      s.askActivityExerciseHistory,
    ),
    'get_expenses' => (s.askActivityGrab, s.askActivitySpending),
    'summarize_week' => (s.askActivityGrab, s.askActivityWeek),
    'get_readiness' => (s.askActivityGrab, s.askActivityReadiness),
    'get_sleep_summary' => (s.askActivityGrab, s.askActivitySleep),
    'resolve_food' => (s.askActivitySearch, s.askActivityFoodDetails),
    'calculate_meal_nutrition' => (
      s.askActivityCalculate,
      s.askActivityMealNutrition,
    ),
    'search_food_product' => (s.askActivitySearch, s.askActivityFoodProduct),
    'search_food_alternatives' || 'suggest_meal_replacement' => (
      s.askActivitySearch,
      s.askActivityFoodAlternatives,
    ),
    _ => null,
  };
  if (parts == null) return null;
  return '${parts.$1} · ${parts.$2}';
}
