import 'stt_error.dart';

/// The result of a speech-to-text attempt (input only — see
/// `functions/ai/speech/gateway.js`): either a genuine transcript, or an
/// honest, typed failure. A failure is never thrown past [AiRepository]'s
/// implementations — see `ai_repository.dart`'s `transcribe` — the caller
/// (the composer's mic button) always gets an [SttOutcome] to switch on,
/// mirroring [WorkoutImportOutcome]'s accepted/rejected split.
sealed class SttOutcome {
  const SttOutcome();
}

/// Audio was transcribed into text. The caller places [text] in the chat
/// composer for the user to edit/send — this never auto-sends.
class SttTranscribed extends SttOutcome {
  const SttTranscribed({
    required this.text,
    this.detectedLanguage,
    this.durationMs,
  });

  final String text;

  /// The provider's own guess at the spoken language, if it reported one.
  final String? detectedLanguage;

  /// The audio clip's duration, if the provider reported one.
  final int? durationMs;
}

/// The attempt failed — [error] is the typed reason, [message] a
/// user-presentable explanation (already friendly; safe to show verbatim).
class SttFailed extends SttOutcome {
  const SttFailed(this.error, this.message);

  final SttError error;
  final String message;
}
