import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../ai/data/audio_recorder.dart';
import '../../../ai/domain/stt_error.dart';
import '../../../ai/domain/stt_outcome.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/diet_import_input.dart';
import 'diet_import_page.dart';
import '../../../../l10n/l10n.dart';

/// Describing your diet in your own words — spoken or typed — instead of
/// having a document to import.
///
/// **The transcript is shown and editable before anything is extracted.**
/// Speech-to-text mangles food names and numbers routinely ("baladi" →
/// "bloody", "150" → "115"), and the cheapest place to fix that is here,
/// while the user still remembers what they said — not in the plan editor
/// afterwards, where a wrong food has already become a calorie figure.
///
/// The same screen serves typing: the mic is an input method, not a separate
/// feature, and a user with a noisy room or no mic permission just types into
/// the same field.
class DietDictatePage extends StatefulWidget {
  const DietDictatePage({super.key, this.startRecording = true});

  /// Whether to open the mic straight away. False is the "type it out" route
  /// into the same screen.
  final bool startRecording;

  @override
  State<DietDictatePage> createState() => _DietDictatePageState();
}

enum _DictatePhase { idle, recording, transcribing }

class _DietDictatePageState extends State<DietDictatePage> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  _DictatePhase _phase = _DictatePhase.idle;
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
    // Fire-and-forget: a page being torn down mid-recording must not leave
    // the microphone open, and there is nobody left to await the result.
    unawaited(_recorderOrNull?.cancel() ?? Future<void>.value());
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// [_recorder] reads the scope, which is unavailable during dispose; this
  /// is the copy captured while the widget was alive.
  AudioRecorderService? _recorderOrNull;

  Future<void> _startRecording() async {
    final recorder = _recorder;
    if (recorder == null) {
      // A host with no recorder wired (tests, or a platform without one) is
      // not an error — it's the typing route.
      setState(() => _phase = _DictatePhase.idle);
      _focus.requestFocus();
      return;
    }
    _recorderOrNull = recorder;
    setState(() => _error = null);

    final granted = await recorder.ensurePermission();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _phase = _DictatePhase.idle;
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
        _phase = _DictatePhase.idle;
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
    setState(() => _phase = _DictatePhase.recording);
  }

  Future<void> _stopAndTranscribe() async {
    final recorder = _recorder;
    if (recorder == null) return;
    setState(() => _phase = _DictatePhase.transcribing);
    // Not awaited: nothing downstream depends on the level stream being
    // torn down, and waiting on it would put a stream-cancellation hop
    // between the user's tap and the recorder actually stopping.
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
        _phase = _DictatePhase.idle;
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
          _phase = _DictatePhase.idle;
          // Appended, not replaced: a second pass at the mic adds to what is
          // already there rather than throwing away the first take.
          _text.text = _text.text.trim().isEmpty
              ? text
              : '${_text.text.trim()}\n$text';
        });
        _focus.requestFocus();
      case SttFailed(:final error, :final message):
        setState(() {
          _phase = _DictatePhase.idle;
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
    if (mounted) setState(() => _phase = _DictatePhase.idle);
  }

  bool get _canExtract =>
      _text.text.trim().length >= _kMinDescriptionChars &&
      _phase == _DictatePhase.idle;

  Future<void> _extract() async {
    if (!_canExtract) return;
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DietImportPage(
          input: DietImportDescription(
            text: _text.text.trim(),
            dictated: widget.startRecording,
          ),
        ),
      ),
    );
    // The import flow pops itself once the review editor closes, so landing
    // back here means it's done either way — leave with it.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final recording = _phase == _DictatePhase.recording;
    final transcribing = _phase == _DictatePhase.transcribing;

    return TrainScreen(
      tint: TrainColors.dietTint,
      child: Column(
        children: [
          CaptureTopBar(
            title: widget.startRecording ? 'Describe your diet' : 'Type it out',
            onClose: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              key: const Key('dictate-list'),
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
              children: [
                Text(
                  'Say or write what you eat in a day — meals, foods and '
                  'rough amounts. ZIVO turns it into a plan you review before '
                  'anything is saved.',
                  style: AppText.body.copyWith(
                    color: TrainColors.ink2,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Example: "Breakfast is three eggs and 60 grams of oats. '
                  'Lunch is 200 grams of chicken with rice and salad."',
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                ),
                const SizedBox(height: 20),
                if (recording || transcribing)
                  _RecordingCard(
                    level: _level,
                    transcribing: transcribing,
                    onStop: _stopAndTranscribe,
                    onCancel: _cancelRecording,
                  )
                else ...[
                  const TrainSectionLabel('Your description'),
                  const SizedBox(height: 11),
                  TextField(
                    key: const Key('dictate-text'),
                    controller: _text,
                    focusNode: _focus,
                    maxLines: null,
                    minLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: TrainColors.green,
                    onChanged: (_) => setState(() {}),
                    style: AppText.body.copyWith(
                      color: TrainColors.ink,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: l(context).dictateHint,
                      hintStyle: AppText.body.copyWith(color: TrainColors.ink3),
                      filled: true,
                      fillColor: TrainColors.base,
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    // Said plainly, because transcription mistakes on food
                    // names and amounts are the norm, not the exception.
                    'Check the words before you continue — a mis-heard food '
                    'or amount becomes a calorie figure downstream.',
                    style: AppText.meta.copyWith(color: TrainColors.ink3),
                  ),
                  if (_recorderAvailable) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('dictate-record-again'),
                        onPressed: _startRecording,
                        icon: const Icon(
                          Icons.mic_none_rounded,
                          size: 17,
                          color: TrainColors.green,
                        ),
                        label: Text(
                          _text.text.trim().isEmpty
                              ? 'Say it instead'
                              : 'Add more by voice',
                          style: AppText.meta.copyWith(
                            color: TrainColors.green,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    key: const Key('dictate-error'),
                    style: AppText.meta.copyWith(
                      color: TrainColors.ember,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                PillButton(
                  key: const Key('dictate-extract'),
                  label: l(context).dictateTurnIntoPlan,
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

/// The shortest description worth sending. Below this there is nothing for
/// the extractor to work with, and a rejection round-trip is a worse answer
/// than a disabled button.
const int _kMinDescriptionChars = 12;

/// While the mic is open: a live level bar so the user can see they're being
/// heard, and two ways out — stop (transcribe it) or discard.
class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.level,
    required this.transcribing,
    required this.onStop,
    required this.onCancel,
  });

  final double level;
  final bool transcribing;
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
              key: const Key('dictate-phase'),
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
            valueColor: const AlwaysStoppedAnimation(TrainColors.green),
          ),
        ),
        const SizedBox(height: 20),
        if (!transcribing) ...[
          PillButton(
            key: const Key('dictate-stop'),
            label: l(context).dictateDoneTalking,
            icon: Icons.check_rounded,
            enabled: true,
            onTap: onStop,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              key: const Key('dictate-cancel'),
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
