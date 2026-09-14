import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_field.dart';
import '../../../../l10n/l10n.dart';
import '../../../ai/data/audio_recorder.dart';
import '../../../ai/domain/stt_error.dart';
import '../../../ai/domain/stt_outcome.dart';

/// A multi-line text field with a "🎙 say it instead" affordance, for the
/// places a form wants the user's own words rather than a tapped list.
///
/// It is the inline counterpart to [PlanDescribePage]: the same record →
/// transcribe → **edit before it counts** flow, but as one field inside a
/// larger form (the Diet Builder's steps) rather than a whole screen that
/// navigates onward. Speech-to-text mangles food names and amounts, so a
/// transcript always lands in the editable field, never straight into the
/// answer.
///
/// The mic hides itself on a host with no recorder (tests, or a platform
/// without one) — typing is not a fallback here, it's the same path.
class VoiceCaptureField extends StatefulWidget {
  const VoiceCaptureField({
    super.key,
    required this.controller,
    required this.hint,
    required this.keyPrefix,
    this.minLines = 4,
    Color? accent,
    // ignore: prefer_initializing_formals
  }) : _accent = accent;

  final TextEditingController controller;
  final String hint;

  /// Prefix for the widget keys tests tap (`<prefix>-text`, `-record`, …).
  final String keyPrefix;
  final int minLines;

  final Color? _accent;

  /// Defaults to the active skin's `green`, resolved on read so the const
  /// constructor holds (ADR-011).
  Color get accent => _accent ?? TrainColors.green;

  @override
  State<VoiceCaptureField> createState() => _VoiceCaptureFieldState();
}

enum _Phase { idle, recording, transcribing }

class _VoiceCaptureFieldState extends State<VoiceCaptureField> {
  final FocusNode _focus = FocusNode();
  _Phase _phase = _Phase.idle;
  String? _error;
  StreamSubscription<double>? _levelSub;
  double _level = 0;

  /// Captured while alive — the scope is unavailable during dispose.
  AudioRecorderService? _recorderOrNull;

  AudioRecorderService? get _recorder => AppScope.of(context).recorder;
  bool get _hasRecorder => AppScope.of(context).recorder != null;

  @override
  void dispose() {
    _levelSub?.cancel();
    unawaited(_recorderOrNull?.cancel() ?? Future<void>.value());
    _focus.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final recorder = _recorder;
    if (recorder == null) {
      _focus.requestFocus();
      return;
    }
    _recorderOrNull = recorder;
    setState(() => _error = null);

    final granted = await recorder.ensurePermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _error = l(context).describeMicNeeded);
      return;
    }
    try {
      await recorder.start();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l(context).describeRecordFailed);
      return;
    }
    if (!mounted) return;
    HapticFeedback.lightImpact();
    _levelSub?.cancel();
    _levelSub = recorder.inputLevels().listen((level) {
      if (mounted) setState(() => _level = level);
    }, onError: (_) {});
    setState(() => _phase = _Phase.recording);
  }

  Future<void> _stopAndTranscribe() async {
    final recorder = _recorder;
    if (recorder == null) return;
    setState(() => _phase = _Phase.transcribing);
    unawaited(_levelSub?.cancel() ?? Future<void>.value());
    _levelSub = null;

    RecordedAudio? audio;
    try {
      audio = await recorder.stop();
    } catch (_) {
      audio = null;
    }
    if (!mounted) return;
    if (audio == null) {
      setState(() {
        _phase = _Phase.idle;
        _error = l(context).describeNothingRecorded;
      });
      return;
    }

    final outcome = await AppScope.of(
      context,
    ).ai.transcribe(audioBytes: audio.bytes, mimeType: audio.mimeType);
    if (!mounted) return;
    switch (outcome) {
      case SttTranscribed(:final text):
        setState(() {
          _phase = _Phase.idle;
          // Appended, not replaced: a second pass adds to what's there.
          final existing = widget.controller.text.trim();
          widget.controller.text = existing.isEmpty ? text : '$existing\n$text';
        });
        _focus.requestFocus();
      case SttFailed(:final error, :final message):
        setState(() {
          _phase = _Phase.idle;
          _error = error == SttError.microphonePermissionDenied
              ? l(context).describeMicNeeded
              : message;
        });
    }
  }

  Future<void> _cancelRecording() async {
    unawaited(_levelSub?.cancel() ?? Future<void>.value());
    _levelSub = null;
    await _recorder?.cancel();
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  @override
  Widget build(BuildContext context) {
    if (_phase != _Phase.idle) {
      return _RecordingCard(
        level: _level,
        transcribing: _phase == _Phase.transcribing,
        accent: widget.accent,
        keyPrefix: widget.keyPrefix,
        onStop: _stopAndTranscribe,
        onCancel: _cancelRecording,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: Key('${widget.keyPrefix}-text'),
          controller: widget.controller,
          focusNode: _focus,
          maxLines: null,
          minLines: widget.minLines,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: widget.accent,
          style: AppText.body.copyWith(color: TrainColors.ink, height: 1.5),
          decoration: zivoFieldDecoration(
            hintText: widget.hint,
            hintStyle: AppText.body.copyWith(color: TrainColors.ink3),
            contentPadding: const EdgeInsets.all(14),
            radius: 14,
            focusRing: false,
          ),
        ),
        if (_hasRecorder) ...[
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: Key('${widget.keyPrefix}-record'),
              onPressed: _startRecording,
              icon: Icon(Icons.mic_none_rounded, size: 17, color: widget.accent),
              label: Text(
                widget.controller.text.trim().isEmpty
                    ? l(context).describeSayItInstead
                    : l(context).describeAddMoreByVoice,
                style: AppText.meta.copyWith(color: widget.accent),
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            key: Key('${widget.keyPrefix}-error'),
            style: AppText.meta.copyWith(color: TrainColors.ember, height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// The mic-open state: a live level bar (answering "is it hearing me?") and two
/// ways out — stop and transcribe, or discard.
class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.level,
    required this.transcribing,
    required this.accent,
    required this.keyPrefix,
    required this.onStop,
    required this.onCancel,
  });

  final double level;
  final bool transcribing;
  final Color accent;
  final String keyPrefix;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('$keyPrefix-recording'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: TrainColors.ember,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                transcribing
                    ? l(context).describeTranscribing
                    : l(context).describeListening,
                key: Key('$keyPrefix-phase'),
                style: AppText.rowTitle,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: transcribing ? null : level.clamp(0.05, 1.0),
              minHeight: 5,
              backgroundColor: TrainColors.hairlineStrong,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          if (!transcribing) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  key: Key('$keyPrefix-stop'),
                  onPressed: onStop,
                  icon: Icon(Icons.check_rounded, size: 18, color: accent),
                  label: Text(
                    l(context).dictateDoneTalking,
                    style: AppText.meta.copyWith(color: accent),
                  ),
                ),
                const Spacer(),
                TextButton(
                  key: Key('$keyPrefix-cancel'),
                  onPressed: onCancel,
                  child: Text(
                    l(context).describeDiscard,
                    style: AppText.meta.copyWith(color: TrainColors.ink3),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
