import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A finished recording's bytes and format — enough to hand straight to
/// [AiRepository.transcribe] (`ai_repository.dart`), which never needs a
/// file path, only the raw audio and its mime type.
class RecordedAudio {
  const RecordedAudio({
    required this.bytes,
    required this.mimeType,
    this.durationMs,
  });

  final Uint8List bytes;
  final String mimeType;

  /// Wall-clock duration of the recording, if known.
  final int? durationMs;
}

/// The composer's voice-note recorder seam. An interface (not a direct
/// `package:record` dependency at call sites) so widget tests can inject a
/// fake without touching the plugin, mirroring how `MediaService` sits
/// between features and the camera/gallery plugins.
abstract interface class AudioRecorderService {
  /// Requests the microphone permission if not already granted, resolving
  /// to whether recording may proceed. `record` owns the OS permission
  /// prompt itself — no separate `permission_handler` dependency.
  Future<bool> ensurePermission();

  /// Starts a new recording. Call [ensurePermission] first — this assumes
  /// permission is already granted.
  Future<void> start();

  /// Stops the in-progress recording and returns its bytes, or `null` if
  /// nothing usable was captured (e.g. an empty clip). No-op (returns
  /// `null`) if nothing is recording.
  Future<RecordedAudio?> stop();

  /// Stops and discards the in-progress recording without returning
  /// anything. No-op if nothing is recording.
  Future<void> cancel();

  /// Whether a recording is currently in progress.
  bool get isRecording;
}

/// `record`-backed [AudioRecorderService]. Records to a temporary `.m4a`
/// file (AAC-LC in an MPEG-4 container — `record`'s default encoder, and one
/// of the mime types `functions/ai/speech/gateway.js` accepts), then reads
/// the file back into memory and deletes it — [AiRepository.transcribe]
/// only ever needs bytes, never a path.
class RecordAudioRecorderService implements AudioRecorderService {
  RecordAudioRecorderService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  /// `record`'s default encoder ([AudioEncoder.aacLc]) outputs to an MPEG-4
  /// container — `audio/m4a` is the mime type `functions/ai/speech/gateway.js`
  /// maps back to that same container/codec pair.
  static const _mimeType = 'audio/m4a';

  final AudioRecorder _recorder;
  DateTime? _startedAt;
  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/zivo_voice_note_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _startedAt = DateTime.now();
    _isRecording = true;
  }

  @override
  Future<RecordedAudio?> stop() async {
    if (!_isRecording) return null;
    _isRecording = false;
    final startedAt = _startedAt;
    _startedAt = null;

    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await file.delete();
    if (bytes.isEmpty) return null;

    final durationMs = startedAt == null
        ? null
        : DateTime.now().difference(startedAt).inMilliseconds;
    return RecordedAudio(
      bytes: bytes,
      mimeType: _mimeType,
      durationMs: durationMs,
    );
  }

  @override
  Future<void> cancel() async {
    if (!_isRecording) return;
    _isRecording = false;
    _startedAt = null;
    await _recorder.cancel();
  }
}
