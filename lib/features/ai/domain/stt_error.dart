/// The reason a speech-to-text attempt didn't produce a transcript. Covers
/// both client-side failures (permission, recording) and server-side ones
/// (`functions/ai/speech/gateway.js`'s `SpeechError` codes, surfaced via
/// `aiTranscribe`'s `HttpsError.details.sttCode`).
enum SttError {
  /// The user declined the microphone permission prompt.
  microphonePermissionDenied,

  /// The recorder itself failed to produce usable audio (e.g. `stop()`
  /// returned nothing, or the clip came back empty).
  recordingFailed,

  /// The clip was too long/large for the server to accept.
  audioTooLarge,

  /// The recorded format isn't one the server's speech gateway accepts.
  unsupportedAudioFormat,

  /// The provider ran but couldn't produce a transcript for this clip.
  transcriptionFailed,

  /// The speech-to-text provider itself is unavailable right now.
  providerUnavailable,

  /// The request took too long and was aborted.
  timeout,

  /// Anything else — network failure, an unrecognized server error, etc.
  unknown,
}
