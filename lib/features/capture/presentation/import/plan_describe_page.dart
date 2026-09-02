import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/zivo_field.dart';
import '../../../ai/data/audio_recorder.dart';
import '../../../ai/domain/stt_error.dart';
import '../../../ai/domain/stt_outcome.dart';
import '../widgets/capture_widgets.dart';

/// Describing a plan in your own words — spoken or typed — instead of having a
/// document to import. Shared by the diet and workout "type it out / say it
/// out loud" routes: the recording, transcription and edit-before-extract
/// machinery is identical, and only the copy, the tint and where the finished
/// text is sent differ (via [buildImportPage]).
///
/// **The transcript is shown and editable before anything is extracted.**
/// Speech-to-text mangles names and numbers routinely, and the cheapest place
/// to fix that is here, while the user still remembers what they said — not in
/// the review editor afterwards, where a wrong item has already become a
/// number.
///
/// The same screen serves typing: the mic is an input method, not a separate
/// feature, and a user with a noisy room or no mic permission just types into
/// the same field.
class PlanDescribePage extends StatefulWidget {
  const PlanDescribePage({
    super.key,
    required this.title,
    required this.intro,
    required this.example,
    required this.hint,
    required this.extractLabel,
    required this.doneTalkingLabel,
    required this.tint,
    required this.buildImportPage,
    this.startRecording = true,
    this.accent = TrainColors.green,
    this.minChars = _kMinDescriptionChars,
    this.keyPrefix = 'describe',
  });

  /// Prefix for the widget keys tests tap (`<prefix>-text`, `-extract`, …), so
  /// each host's tests can keep their own stable names.
  final String keyPrefix;

  /// Whether to open the mic straight away. False is the "type it out" route
  /// into the same screen.
  final bool startRecording;

  /// The screen title — the caller resolves it for the record vs type route.
  final String title;

  /// The paragraph explaining what to say/write, and a worked [example].
  final String intro;
  final String example;

  /// The empty-field hint and the commit-button label — the two lines a caller
  /// localizes.
  final String hint;
  final String extractLabel;

  /// The "stop and transcribe" button label shown while recording.
  final String doneTalkingLabel;

  /// The page ground tint (feature-owned).
  final Gradient tint;

  /// The feature's accent — the record affordance and cursor.
  final Color accent;

  /// The shortest description worth sending; below it the commit button stays
  /// disabled rather than paying for a round-trip that can only be rejected.
  final int minChars;

  /// Builds the import page the finished text is handed to — each feature
  /// wraps its own description in its own sealed input type. [dictated] is
  /// this run's [startRecording].
  final Widget Function(String text, bool dictated) buildImportPage;

  @override
  State<PlanDescribePage> createState() => _PlanDescribePageState();
}

enum _DescribePhase { idle, recording, transcribing }

class _PlanDescribePageState extends State<PlanDescribePage> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  _DescribePhase _phase = _DescribePhase.idle;
  String? _error;
  StreamSubscription<double>? _levelSub;
  double _level = 0;

  AudioRecorderService? get _recorder => AppScope.of(context).recorder;

  @override
  void initState() {
    super.initState();
    if (widget.startRecording) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startRecording());
    }
  }

  @override
  void dispose() {
    _levelSub?.cancel();
    // Fire-and-forget: a page being torn down mid-recording must not leave the
    // microphone open, and there is nobody left to await the result.
    unawaited(_recorderOrNull?.cancel() ?? Future<void>.value());
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// [_recorder] reads the scope, which is unavailable during dispose; this is
  /// the copy captured while the widget was alive.
  AudioRecorderService? _recorderOrNull;

  Future<void> _startRecording() async {
    final recorder = _recorder;
    if (recorder == null) {
      // A host with no recorder wired (tests, or a platform without one) is
      // not an error — it's the typing route.
      setState(() => _phase = _DescribePhase.idle);
      _focus.requestFocus();
      return;
    }
    _recorderOrNull = recorder;
    setState(() => _error = null);

    final granted = await recorder.ensurePermission();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _phase = _DescribePhase.idle;
        _error =
            'ZIVO needs microphone access to take this down. You can type '
            'it instead.';
      });
      return;
    }

    try {
      await recorder.start();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _DescribePhase.idle;
        _error = "Couldn't start recording. You can type it instead.";
      });
      return;
    }
    if (!mounted) return;
    HapticFeedback.lightImpact();
    _levelSub?.cancel();
    _levelSub = recorder.inputLevels().listen((level) {
      if (mounted) setState(() => _level = level);
    }, onError: (_) {});
    setState(() => _phase = _DescribePhase.recording);
  }

  Future<void> _stopAndTranscribe() async {
    final recorder = _recorder;
    if (recorder == null) return;
    setState(() => _phase = _DescribePhase.transcribing);
    // Not awaited: nothing downstream depends on the level stream being torn
    // down, and waiting on it would put a stream-cancellation hop between the
    // user's tap and the recorder actually stopping.
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
        _phase = _DescribePhase.idle;
        _error = "Nothing was recorded. Try again, or type it instead.";
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
          _phase = _DescribePhase.idle;
          // Appended, not replaced: a second pass at the mic adds to what is
          // already there rather than throwing away the first take.
          _text.text = _text.text.trim().isEmpty
              ? text
              : '${_text.text.trim()}\n$text';
        });
        _focus.requestFocus();
      case SttFailed(:final error, :final message):
        setState(() {
          _phase = _DescribePhase.idle;
          _error = error == SttError.microphonePermissionDenied
              ? 'ZIVO needs microphone access to take this down. You can '
                    'type it instead.'
              : message;
        });
    }
  }

  Future<void> _cancelRecording() async {
    unawaited(_levelSub?.cancel() ?? Future<void>.value());
    _levelSub = null;
    await _recorder?.cancel();
    if (mounted) setState(() => _phase = _DescribePhase.idle);
  }

  bool get _canExtract =>
      _text.text.trim().length >= widget.minChars &&
      _phase == _DescribePhase.idle;

  Future<void> _extract() async {
    if (!_canExtract) return;
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            widget.buildImportPage(_text.text.trim(), widget.startRecording),
      ),
    );
    // The import flow pops itself once the review editor closes, so landing
    // back here means it's done either way — leave with it.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final recording = _phase == _DescribePhase.recording;
    final transcribing = _phase == _DescribePhase.transcribing;

    return TrainScreen(
      tint: widget.tint,
      child: Column(
        children: [
          CaptureTopBar(
            title: widget.title,
            onClose: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              key: Key('${widget.keyPrefix}-list'),
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
              children: [
                Text(
                  widget.intro,
                  style: AppText.body.copyWith(
                    color: TrainColors.ink2,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.example,
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                ),
                const SizedBox(height: 20),
                if (recording || transcribing)
                  _RecordingCard(
                    level: _level,
                    transcribing: transcribing,
                    accent: widget.accent,
                    keyPrefix: widget.keyPrefix,
                    doneTalkingLabel: widget.doneTalkingLabel,
                    onStop: _stopAndTranscribe,
                    onCancel: _cancelRecording,
                  )
                else ...[
                  const TrainSectionLabel('Your description'),
                  const SizedBox(height: 11),
                  TextField(
                    key: Key('${widget.keyPrefix}-text'),
                    controller: _text,
                    focusNode: _focus,
                    maxLines: null,
                    minLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: widget.accent,
                    onChanged: (_) => setState(() {}),
                    style: AppText.body.copyWith(
                      color: TrainColors.ink,
                      height: 1.5,
                    ),
                    decoration: zivoFieldDecoration(
                      hintText: widget.hint,
                      hintStyle: AppText.body.copyWith(color: TrainColors.ink3),
                      contentPadding: const EdgeInsets.all(14),
                      radius: 14,
                      focusRing: false,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    // Said plainly, because transcription mistakes on names and
                    // amounts are the norm, not the exception.
                    'Check the words before you continue — a mis-heard '
                    'detail becomes a number downstream.',
                    style: AppText.meta.copyWith(color: TrainColors.ink3),
                  ),
                  if (_recorderAvailable) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: Key('${widget.keyPrefix}-record-again'),
                        onPressed: _startRecording,
                        icon: Icon(
                          Icons.mic_none_rounded,
                          size: 17,
                          color: widget.accent,
                        ),
                        label: Text(
                          _text.text.trim().isEmpty
                              ? 'Say it instead'
                              : 'Add more by voice',
                          style: AppText.meta.copyWith(color: widget.accent),
                        ),
                      ),
                    ),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    key: Key('${widget.keyPrefix}-error'),
                    style: AppText.meta.copyWith(
                      color: TrainColors.ember,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                PillButton(
                  // Ember: kicking off the extraction is the screen's single
                  // committing action (identity §3), not a feature-hued one.
                  key: Key('${widget.keyPrefix}-extract'),
                  label: widget.extractLabel,
                  icon: Icons.auto_awesome_rounded,
                  enabled: _canExtract,
                  onTap: _extract,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _recorderAvailable => AppScope.of(context).recorder != null;
}

/// The default shortest description worth sending. Below this there is nothing
/// for the extractor to work with, and a rejection round-trip is a worse
/// answer than a disabled button.
const int _kMinDescriptionChars = 12;

/// While the mic is open: a live level bar so the user can see they're being
/// heard, and two ways out — stop (transcribe it) or discard.
class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.level,
    required this.transcribing,
    required this.accent,
    required this.keyPrefix,
    required this.doneTalkingLabel,
    required this.onStop,
    required this.onCancel,
  });

  final double level;
  final bool transcribing;
  final Color accent;
  final String keyPrefix;
  final String doneTalkingLabel;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: TrainColors.ember,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              transcribing ? 'Writing it down…' : 'Listening',
              key: Key('$keyPrefix-phase'),
              style: AppText.rowTitle,
            ),
          ],
        ),
        const SizedBox(height: 14),
        // A level bar rather than a spinner: it answers "is it hearing me?",
        // which is the only question someone has while talking to a phone.
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: transcribing ? null : level.clamp(0.05, 1.0),
            minHeight: 5,
            backgroundColor: TrainColors.hairlineStrong,
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
        const SizedBox(height: 20),
        if (!transcribing) ...[
          PillButton(
            // Ember commit action, like the extract button below the field.
            key: Key('$keyPrefix-stop'),
            label: doneTalkingLabel,
            icon: Icons.check_rounded,
            enabled: true,
            onTap: onStop,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              key: Key('$keyPrefix-cancel'),
              onPressed: onCancel,
              child: Text(
                'Discard',
                style: AppText.meta.copyWith(color: TrainColors.ink3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
