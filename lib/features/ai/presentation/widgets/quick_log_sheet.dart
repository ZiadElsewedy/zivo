import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../data/audio_recorder.dart';
import '../../domain/stt_error.dart';
import '../../domain/stt_outcome.dart';

/// The Home-screen voice quick log: one sheet that records a short note,
/// transcribes it, and hands the text back to the shell — which drops it
/// into Ask's composer as an editable draft ("add 40 EGP parking"). Never
/// auto-sent: the user reviews and sends there, where the proposal flow
/// takes over.
///
/// Mirrors VoiceComposer's state honesty: recording shows live levels and an
/// elapsed timer, transcription shows progress with a discard hatch, and a
/// failure lands back on a retryable error line inside the sheet.
Future<String?> showQuickLogSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const QuickLogSheet(),
  );
}

class QuickLogSheet extends StatefulWidget {
  const QuickLogSheet({super.key});

  @override
  State<QuickLogSheet> createState() => _QuickLogSheetState();
}

enum _Phase { idle, recording, transcribing, failed }

class _QuickLogSheetState extends State<QuickLogSheet>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.idle;
  String? _failureMessage;

  /// The recorder this session used — kept so dispose can silence the mic
  /// without touching [AppScope] after unmount.
  AudioRecorderService? _recorder;

  int _elapsedMs = 0;
  Timer? _tick;
  double _level = 0;
  StreamSubscription<double>? _levelsSub;

  /// Guards late outcomes after cancel/dispose, mirroring AskPage's token.
  int _token = 0;

  /// The mic dot's breathing pulse while recording. Started/stopped per
  /// phase rather than looping forever — an always-on repeat would also
  /// starve tests' pumpAndSettle.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
    lowerBound: 0.55,
    upperBound: 1,
  );

  bool get _still => MediaQuery.of(context).disableAnimations;

  void _setPhase(_Phase phase) {
    setState(() => _phase = phase);
    if (_phase == _Phase.recording && !_still) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _token++;
    _tick?.cancel();
    _levelsSub?.cancel();
    _pulse.dispose();
    // If the sheet closes mid-recording, don't leave the mic hot.
    if (_recorder?.isRecording ?? false) _recorder!.cancel();
    super.dispose();
  }

  void _subscribeLevels(AudioRecorderService recorder) {
    _levelsSub?.cancel();
    _level = 0;
    // Errors on the level stream are cosmetic (metering glitches, backend
    // quirks) — swallowed here so they can never take the sheet down.
    _levelsSub = recorder.inputLevels().listen(
      (level) {
        if (!mounted || _phase != _Phase.recording) return;
        setState(() => _level = level);
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> _startRecording() async {
    if (_phase == _Phase.recording || _phase == _Phase.transcribing) return;
    // Soft-resolved: a scope without a recorder (or one whose plugin side
    // fails — a PlatformException from a denied/stale permission or an OS
    // audio-session conflict) degrades to the sheet's retryable failure
    // line. It must never throw out of this handler and take the app down.
    final recorder = AppScope.of(context).recorder;
    if (recorder == null) {
      _fail("Voice input isn't available right now.");
      return;
    }
    _recorder = recorder;

    bool granted;
    try {
      granted = await recorder.ensurePermission();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    if (!granted) {
      _fail('Turn on microphone access to use voice input.');
      return;
    }
    try {
      await recorder.start();
    } catch (_) {
      _fail("Couldn't start the microphone — try again.");
      return;
    }
    if (!mounted) return;
    _setPhase(_Phase.recording);
    setState(() => _failureMessage = null);
    _subscribeLevels(recorder);
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _phase != _Phase.recording) return;
      setState(() => _elapsedMs += 200);
    });
  }

  /// Stop-and-transcribe — the recording bar's stop button. Every plugin
  /// call is guarded: a platform failure here (audio-session conflict, a
  /// stale recorder, sandbox/TCC quirks) lands on the sheet's retryable
  /// failure line — it can never escape as an unhandled async error.
  Future<void> _stopRecording() async {
    final recorder = _recorder;
    if (_phase != _Phase.recording || recorder == null) return;
    _setPhase(_Phase.transcribing);
    _tick?.cancel();
    RecordedAudio? audio;
    try {
      audio = await recorder.stop();
    } catch (_) {
      audio = null;
    }
    await _levelsSub?.cancel();
    _levelsSub = null;
    if (!mounted) return;
    if (audio == null) {
      _fail("Didn't catch that — try recording again.");
      return;
    }
    await _transcribe(audio);
  }

  Future<void> _transcribe(RecordedAudio audio) async {
    final ai = AppScope.of(context).ai;
    final token = ++_token;
    SttOutcome outcome;
    try {
      outcome = await ai.transcribe(
        audioBytes: audio.bytes,
        mimeType: audio.mimeType,
      );
    } catch (_) {
      outcome = const SttFailed(
        SttError.unknown,
        "Couldn't transcribe that — check your connection and try again.",
      );
    }
    if (!mounted || token != _token) return;

    final resolved = outcome;
    if (resolved is SttTranscribed && resolved.text.trim().isNotEmpty) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(resolved.text.trim());
      return;
    }
    _fail(
      resolved is SttFailed
          ? resolved.message
          : "Nothing came through — try again.",
    );
  }

  /// Discard/cancel paths are best-effort too — a plugin failure while
  /// discarding must never throw out of the sheet.
  Future<void> _cancelRecording() async {
    _token++;
    _tick?.cancel();
    await _levelsSub?.cancel();
    try {
      await _recorder?.cancel();
    } catch (_) {
      // Discarding is cosmetic — nothing to surface.
    }
    if (!mounted) return;
    _setPhase(_Phase.idle);
  }

  void _fail(String message) {
    _setPhase(_Phase.failed);
    setState(() => _failureMessage = message);
  }

  String get _elapsedLabel {
    final s = _elapsedMs ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Voice log', style: AppText.rowTitle),
            const SizedBox(height: 4),
            Text(
              'Say it once — it lands in Ask ready to send.',
              style: AppText.meta.copyWith(color: AppColors.ink3),
            ),
            const SizedBox(height: 18),
            ...switch (_phase) {
              _Phase.idle => [_idleBody()],
              _Phase.recording => [_recordingBody()],
              _Phase.transcribing => [_transcribingBody()],
              _Phase.failed => [_failedBody()],
            },
          ],
        ),
      ),
    );
  }

  Widget _idleBody() {
    return Column(
      children: [
        PressableScale(
          child: Material(
            key: const Key('quicklog-mic'),
            color: AppColors.iris,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              key: const Key('quicklog-mic-tap'),
              onTap: _startRecording,
              borderRadius: BorderRadius.circular(999),
              child: const SizedBox(
                width: 64,
                height: 64,
                child: Icon(AppIcons.mic, size: 26, color: Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Tap and speak',
          style: AppText.body.copyWith(color: AppColors.ink2),
        ),
        Text(
          '"add 40 EGP parking" · "finished chest day"',
          style: AppText.meta.copyWith(color: AppColors.ink3),
        ),
      ],
    );
  }

  Widget _recordingBody() {
    final still = _still;
    final dot = Container(
      width: 11,
      height: 11,
      decoration: const BoxDecoration(
        color: AppColors.flare,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x55FF3D6E), blurRadius: 8, spreadRadius: 1),
        ],
      ),
    );
    return Row(
      children: [
        still
            ? dot
            : ScaleTransition(
                scale: _pulse,
                child: FadeTransition(opacity: _pulse, child: dot),
              ),
        const SizedBox(width: 12),
        Expanded(child: _LevelBar(level: _level)),
        Text(
          _elapsedLabel,
          style: AppText.meta.copyWith(color: AppColors.ink2),
        ),
        PressableScale(
          child: IconButton(
            key: const Key('quicklog-cancel'),
            onPressed: _cancelRecording,
            icon: const Icon(AppIcons.close, size: 20, color: AppColors.ink3),
            tooltip: 'Discard recording',
          ),
        ),
        PressableScale(
          child: Material(
            key: const Key('quicklog-stop'),
            color: AppColors.flare,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                _stopRecording();
              },
              borderRadius: BorderRadius.circular(999),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(AppIcons.stopCircle, size: 20, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _transcribingBody() {
    return Row(
      children: [
        const SizedBox(width: 4),
        Icon(AppIcons.waveform, size: 18, color: AppColors.iris),
        const SizedBox(width: 10),
        Text('Transcribing…', style: AppText.rowTitle),
        const Spacer(),
        PressableScale(
          child: IconButton(
            key: const Key('quicklog-cancel-transcribing'),
            onPressed: () {
              _token++;
              _setPhase(_Phase.idle);
            },
            icon: const Icon(AppIcons.close, size: 20, color: AppColors.ink3),
            tooltip: 'Discard voice note',
          ),
        ),
      ],
    );
  }

  Widget _failedBody() {
    return Column(
      children: [
        Text(
          _failureMessage ?? '',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: AppColors.flareText),
        ),
        const SizedBox(height: 12),
        PressableScale(
          child: Material(
            key: const Key('quicklog-retry'),
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: () => _setPhase(_Phase.idle),
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 10,
                ),
                child: Text('Try again', style: AppText.button),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A slim single-bar level meter — the sheet's compact stand-in for the
/// composer's full waveform: height tracks the live input level so the user
/// can see their voice being captured.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: 30,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: still ? Duration.zero : const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          width: 120,
          height: 5 + 24 * level.clamp(0.0, 1.0),
          decoration: BoxDecoration(
            color: AppColors.flare.withValues(alpha: 0.35 + 0.65 * level),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
