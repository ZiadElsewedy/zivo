import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../data/audio_recorder.dart';

/// The Ask screen's pinned composer — one pill that morphs through three
/// states, each fully honest about what is happening:
///
/// - **Idle**: text field, mic, and a send button that fills in as soon as
///   there is something to send.
/// - **Recording**: a live waveform driven by real microphone levels, a
///   pulsing record dot, an elapsed timer — and a gentle "can't hear you"
///   hint if the input has stayed silent, so the user never wonders whether
///   their voice is actually being captured.
/// - **Transcribing**: an equalizer pulse plus a running seconds counter,
///   so a slow transcription feels accounted-for rather than stuck, with an
///   escape hatch to discard the clip.
class VoiceComposer extends StatelessWidget {
  const VoiceComposer({
    super.key,
    required this.controller,
    required this.canSend,
    required this.bottomInset,
    required this.onSend,
    required this.isRecording,
    required this.transcribing,
    required this.sending,
    required this.onMicToggle,
    required this.onCancelRecording,
    required this.onCancelTranscription,
    required this.recorder,
  });

  final TextEditingController controller;

  /// True when there is text worth sending — fills the send button in.
  final bool canSend;
  final double bottomInset;
  final VoidCallback onSend;

  /// True while a voice note is being recorded (mic tapped, not yet stopped).
  final bool isRecording;

  /// True while a just-stopped recording is being transcribed server-side.
  final bool transcribing;

  /// True while an AI turn is in flight — blocks the mic and dims send.
  final bool sending;
  final VoidCallback onMicToggle;
  final VoidCallback onCancelRecording;
  final VoidCallback onCancelTranscription;

  /// Resolved once by the page from [AppScope]; handed down so the waveform
  /// can subscribe to live input levels without reaching out itself.
  final AudioRecorderService? recorder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.s,
        AppSpacing.base,
        bottomInset + AppSpacing.s,
      ),
      // A floating, frosted island — the same lifted-off-the-content language
      // as the bottom bar: a warm drop-shadow for depth, a backdrop blur so
      // the chat softly diffuses as it scrolls underneath, and a translucent
      // warm-charcoal fill over it. It reads as a layer above the conversation
      // rather than a strip welded to the bottom of it.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 26,
              spreadRadius: -6,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: TrainColors.raised,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: TrainColors.hairlineStrong),
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previousChildren, ?currentChild],
                  ),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: isRecording
                      ? _RecordingBar(
                          key: const ValueKey('recording'),
                          recorder: recorder,
                          onCancel: onCancelRecording,
                          onStop: onMicToggle,
                        )
                      : transcribing
                      ? _TranscribingBar(
                          key: const ValueKey('transcribing'),
                          onCancel: onCancelTranscription,
                        )
                      : _IdleBar(
                          key: const ValueKey('idle'),
                          controller: controller,
                          canSend: canSend && !sending,
                          blocked: sending,
                          onSend: onSend,
                          onMicToggle: onMicToggle,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Idle
// ---------------------------------------------------------------------------

class _IdleBar extends StatelessWidget {
  const _IdleBar({
    super.key,
    required this.controller,
    required this.canSend,
    required this.blocked,
    required this.onSend,
    required this.onMicToggle,
  });

  final TextEditingController controller;

  /// Text present and no turn blocking — the send button is armed.
  final bool canSend;

  /// A turn is in flight: mic is blocked and send sits dimmed even with text.
  final bool blocked;
  final VoidCallback onSend;
  final VoidCallback onMicToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 18),
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (canSend) onSend();
                },
                cursorColor: TrainColors.violet,
                cursorWidth: 1.6,
                style: AppText.rowTitle,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Ask ZIVO…',
                ),
              ),
            ),
          ),
          PressableScale(
            child: IconButton(
              key: const Key('composer-mic'),
              onPressed: blocked ? null : onMicToggle,
              icon: Icon(
                AppIcons.mic,
                size: 22,
                color: blocked ? TrainColors.ink3 : TrainColors.violet,
              ),
              tooltip: 'Record a voice note',
            ),
          ),
          _SendCircle(canSend: canSend, blocked: blocked, onSend: onSend),
        ],
      ),
    );
  }
}

/// The composer's send button — an iris-filled disc that springs itself in
/// the moment there is something to send (opacity + scale, carried by the
/// house spring), with a faint glow while armed. Fires a light haptic on an
/// actual send.
class _SendCircle extends StatefulWidget {
  const _SendCircle({
    required this.canSend,
    required this.blocked,
    required this.onSend,
  });

  final bool canSend;
  final bool blocked;
  final VoidCallback onSend;

  @override
  State<_SendCircle> createState() => _SendCircleState();
}

class _SendCircleState extends State<_SendCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    value: widget.canSend ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _SendCircle old) {
    super.didUpdateWidget(old);
    if (widget.canSend != old.canSend) {
      if (reducedMotion(context)) {
        _reveal.value = widget.canSend ? 1 : 0;
      } else {
        _reveal.springTo(widget.canSend ? 1 : 0, spring: AppSprings.standard);
      }
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _reveal,
      builder: (context, child) {
        final t = _reveal.value.clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.all(9),
          child: Transform.scale(
            scale: 0.86 + 0.14 * t,
            child: Opacity(opacity: 0.45 + 0.55 * t, child: child),
          ),
        );
      },
      child: PressableScale(
        child: Material(
          key: const Key('composer-send'),
          color: widget.canSend && !widget.blocked
              ? TrainColors.violet
              : TrainColors.raisedStrong,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: widget.canSend
                ? () {
                    HapticFeedback.lightImpact();
                    widget.onSend();
                  }
                : null,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: widget.canSend && !widget.blocked
                    ? [
                        BoxShadow(
                          color: TrainColors.violet.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : const [],
              ),
              child: Icon(
                AppIcons.send,
                size: 19,
                color: widget.canSend && !widget.blocked
                    ? Colors.white
                    : TrainColors.ink3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recording
// ---------------------------------------------------------------------------

/// How many waveform columns share the meter history.
const _kWaveBars = 26;

/// Below this normalized level the input reads as silence.
const _kSilenceLevel = 0.055;

/// Silence must persist this long before the "can't hear you" hint shows —
/// brief pauses are normal speech, not a problem.
const _kSilenceHintAfter = Duration(milliseconds: 2800);

class _RecordingBar extends StatefulWidget {
  const _RecordingBar({
    super.key,
    required this.recorder,
    required this.onCancel,
    required this.onStop,
  });

  final AudioRecorderService? recorder;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar>
    with SingleTickerProviderStateMixin {
  /// Newest-last meter history feeding the waveform columns (growable — the
  /// oldest sample is shifted out on every new level).
  final List<double> _bars = List<double>.generate(_kWaveBars, (_) => 0);
  StreamSubscription<double>? _levelsSub;

  /// Peak level seen since the recording started — drives the silence hint.
  double _peak = 0;

  /// Elapsed recording time, accumulated per tick of the refresh timer.
  int _elapsedMs = 0;
  Timer? _tick;

  /// The record dot's breathing pulse.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
    lowerBound: 0.55,
    upperBound: 1,
  )..repeat(reverse: true);

  bool get _still => MediaQuery.of(context).disableAnimations;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _elapsedMs += 200);
    });
  }

  void _subscribe() {
    final stream = widget.recorder?.inputLevels();
    if (stream == null) return;
    // Metering glitches are cosmetic — swallowed so a stream error can
    // never bubble out of the composer and take the page down.
    _levelsSub = stream.listen(
      (level) {
        if (!mounted) return;
        setState(() {
          _peak = _peak > level ? _peak : level;
          _bars
            ..removeAt(0)
            ..add(level);
        });
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _levelsSub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  bool get _silentTooLong =>
      _elapsedMs >= _kSilenceHintAfter.inMilliseconds &&
      _bars.every((level) => level < _kSilenceLevel);

  String get _elapsedLabel {
    final s = _elapsedMs ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final still = _still;
    final silentTooLong = _silentTooLong;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 52,
          child: Row(
            children: [
              PressableScale(
                child: IconButton(
                  key: const Key('composer-cancel-recording'),
                  onPressed: widget.onCancel,
                  icon: const Icon(
                    AppIcons.close,
                    size: 20,
                    color: TrainColors.ink3,
                  ),
                  tooltip: 'Discard recording',
                ),
              ),
              // The live record dot — breathing while motion is allowed.
              still
                  ? const _RecordDot()
                  : ScaleTransition(
                      scale: _pulse,
                      child: FadeTransition(
                        opacity: _pulse,
                        child: const _RecordDot(),
                      ),
                    ),
              const SizedBox(width: 10),
              Expanded(child: _Waveform(bars: _bars)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  _elapsedLabel,
                  style: AppText.meta.copyWith(color: TrainColors.ink2),
                ),
              ),
              PressableScale(
                child: Material(
                  color: TrainColors.ember,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    key: const Key('composer-stop'),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      widget.onStop();
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        AppIcons.stopCircle,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
            ],
          ),
        ),
        // Honest silence feedback: if nothing has registered for a while,
        // say so instead of letting the user talk into a dead mic.
        AnimatedSwitcher(
          duration: still ? Duration.zero : const Duration(milliseconds: 240),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.4),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: silentTooLong
              ? Padding(
                  key: const ValueKey('silence-hint'),
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Text(
                    "Can't hear you yet — speak closer to the mic.",
                    style: AppText.meta.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: TrainColors.ember,
                    ),
                  ),
                )
              : const SizedBox(
                  key: ValueKey('no-hint'),
                  width: double.infinity,
                ),
        ),
      ],
    );
  }
}

class _RecordDot extends StatelessWidget {
  const _RecordDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: const BoxDecoration(
        color: TrainColors.ember,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x55FF5C1A), blurRadius: 8, spreadRadius: 1),
        ],
      ),
    );
  }
}

/// A row of slim columns mirroring recent microphone levels — height tracks
/// the sample, colour intensity tracks it too, so loud speech visibly lifts
/// the whole wave and silence sinks it to a calm baseline.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.bars});

  final List<double> bars;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      key: const Key('composer-waveform'),
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final level in bars)
            AnimatedContainer(
              duration: still
                  ? Duration.zero
                  : const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              width: 3,
              height: 5 + 24 * level.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                color: TrainColors.ember.withValues(alpha: 0.35 + 0.65 * level),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transcribing
// ---------------------------------------------------------------------------

/// Shown while a just-stopped recording is converted to text: an animated
/// equalizer reads as active processing, and a running seconds counter makes
/// a slow request feel tracked rather than frozen. The X discards the clip.
class _TranscribingBar extends StatefulWidget {
  const _TranscribingBar({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  State<_TranscribingBar> createState() => _TranscribingBarState();
}

class _TranscribingBarState extends State<_TranscribingBar>
    with SingleTickerProviderStateMixin {
  /// Elapsed seconds, accumulated per tick so it tracks the frame clock.
  int _seconds = 0;
  Timer? _tick;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
    upperBound: 1,
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final glyph = Icon(AppIcons.waveform, size: 18, color: TrainColors.violet);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 16),
          still ? glyph : FadeTransition(opacity: _c, child: glyph),
          const SizedBox(width: 10),
          Text('Transcribing…', style: AppText.rowTitle),
          // A visible counter: long waits read as progress, not a hang.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              ' · ${_seconds}s',
              key: ValueKey(_seconds),
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
          ),
          const Spacer(),
          PressableScale(
            child: IconButton(
              key: const Key('composer-cancel-transcribing'),
              onPressed: widget.onCancel,
              icon: const Icon(
                AppIcons.close,
                size: 20,
                color: TrainColors.ink3,
              ),
              tooltip: 'Discard voice note',
            ),
          ),
        ],
      ),
    );
  }
}
