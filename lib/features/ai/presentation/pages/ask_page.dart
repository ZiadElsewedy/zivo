import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../../workout/presentation/widgets/staggered_reveal.dart';
import '../../data/audio_recorder.dart';
import '../../domain/ai_conversation.dart';
import '../../domain/ai_message.dart';
import '../../domain/ai_pending_action.dart';
import '../../domain/ai_response_style.dart';
import '../../domain/ai_role.dart';
import '../../domain/ai_turn_event.dart';
import '../../domain/stt_error.dart';
import '../../domain/stt_outcome.dart';
import '../widgets/chat_header.dart';
import '../widgets/voice_composer.dart';

/// How long a voice-note transcription may run before the UI gives up
/// waiting and offers a friendly retry — a hung request must never leave the
/// composer locked.
const _kTranscribeTimeout = Duration(seconds: 35);

/// With zero gateway events for this long mid-turn, the rail admits the wait
/// ("Still working…") instead of silently spinning.
const _kSlowTurnAfter = Duration(seconds: 18);

/// After a turn's stream ends, the optimistic bubble waits this long for the
/// durable user message to land before concluding the send failed — covering
/// silent server drops that would otherwise look like an eternal hang.
const _kLandingGrace = Duration(seconds: 12);

/// The "Ask" chat surface: an iris-themed message list over a pinned
/// composer. Talks only to `AppScope.of(context).ai` — Firebase-free.
class AskPage extends StatefulWidget {
  const AskPage({super.key, this.transcribeTimeout = _kTranscribeTimeout});

  /// Injectable for tests — how long to wait on transcription before
  /// surfacing the timeout failure.
  final Duration transcribeTimeout;

  @override
  State<AskPage> createState() => _AskPageState();
}

class _AskPageState extends State<AskPage>
    with TickerProviderStateMixin {
  /// Resolves the initial active conversation once at startup, from the
  /// user's most-recently-updated existing conversation — never creates one.
  /// If there are none, [_activeConversationId] stays null (an unsaved "New
  /// chat": see [_send]). Once the user starts a new chat or switches
  /// sessions, [_switchTo] takes over as the source of truth.
  late final Future<void> _initialLoad = _resolveInitialConversation();

  /// Null while still loading, OR while sitting in an unsaved "New chat"
  /// that hasn't sent its first message yet — see [_activeResolved].
  String? _activeConversationId;

  /// True once [_activeConversationId] reflects a real decision (loaded from
  /// Firestore, or explicitly set by [_switchTo]) — distinguishes "still
  /// loading" from "resolved to no conversation" (both read as a null
  /// [_activeConversationId]).
  bool _activeResolved = false;

  /// True while the active conversation is still titled 'New chat' — drives
  /// the auto-title-from-first-message behavior in [_send].
  bool _activeIsUntitled = false;

  /// The user's saved reply-length preference, forwarded on every [_send].
  /// Loaded alongside the initial conversation; changed via the header's
  /// style picker ([_setResponseStyle]).
  String _responseStyle = kDefaultResponseStyle;

  Future<void> _resolveInitialConversation() async {
    final ai = AppScope.of(context).ai;
    // A one-shot query, not `watchConversations().first` — that stream's
    // first emission can be a stale/empty local-cache snapshot that resolves
    // before Firestore's server data arrives, which would wrongly land on
    // the empty "New chat" state even when a conversation exists.
    final latestFuture = ai.latestConversation();
    final responseStyleFuture = ai.getResponseStyle();
    final latest = await latestFuture;
    final responseStyle = await responseStyleFuture;
    if (!mounted || _activeResolved) return;
    setState(() {
      _activeConversationId = latest?.id;
      _activeIsUntitled = latest?.title == 'New chat';
      _activeResolved = true;
      _responseStyle = validResponseStyle(responseStyle);
    });
  }

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _canSend = false;

  /// True while a `send` turn is in flight — drives the activity rail.
  bool _sending = false;

  /// The turn's current phase, from the gateway's authoritative stream. Null
  /// until the first phase event (or for a non-streaming turn) — the rail then
  /// reads as a calm "Thinking…".
  AiPhase? _phase;

  /// Assistant reply text accumulated from live stream deltas — shown in a
  /// provisional bubble while the turn runs, replaced by the durable message
  /// once it lands.
  String _liveText = '';

  /// True once any text delta has streamed in, so the durable reply renders
  /// statically instead of re-typing (it already streamed live).
  bool _streamed = false;

  /// Set when a `send` turn starts; consumed by the first render that shows the
  /// assistant's reply, so exactly that one reply types in when the turn did
  /// *not* stream. Cold-loaded history and confirm/cancel lines stay static.
  bool _expectReveal = false;

  /// Optimistic client-side resolution of proposal cards, keyed by actionId,
  /// so a card collapses the instant the user taps (before the stream echoes).
  final Map<String, AiActionStatus> _resolved = {};

  /// True while a voice note is being recorded (mic tapped, not yet stopped).
  bool _recording = false;

  /// True while a just-stopped recording is being transcribed — the composer
  /// shows its honest "Transcribing…" state with an escape hatch.
  bool _transcribing = false;

  /// Guards against a discarded transcription landing late: bumped on every
  /// cancel/new attempt; stale outcomes are ignored.
  int _transcribeToken = 0;

  /// True once a turn has run with no gateway event for [_kSlowTurnAfter] —
  /// lets the rail admit the wait instead of silently spinning.
  bool _turnSlow = false;
  Timer? _slowTurnTimer;

  /// Fires after a finished turn if its optimistic user message never landed
  /// in Firestore — flipping the trailing slot to the retry card instead of
  /// leaving what looks like a permanent hang.
  Timer? _landingWatchdog;

  /// The user's just-sent text while a turn is in flight or has failed —
  /// rendered as an optimistic bubble until the durable message lands.
  String? _pendingText;

  /// True when the most recent send attempt threw — shows the retry rail.
  bool _sendFailed = false;

  /// Persisted user-message count captured right before a send starts, so
  /// reconciliation can tell the optimistic message landed without
  /// comparing text.
  int _baselineUserCount = 0;

  /// The same baseline for ASSISTANT messages — the gate that stops the
  /// provisional live bubble the moment the durable reply lands in
  /// Firestore. Without it there is a window (the server writes the reply
  /// doc slightly before the functions stream closes) where the reply
  /// renders TWICE: once from the snapshot, once from the still-mounted
  /// live bubble.
  int _baselineAssistantCount = 0;

  /// Client-generated idempotency key for the in-flight turn — stable
  /// across retries of the same logical message, so a retry after a false
  /// failure (client-side throw while the server actually processed the
  /// turn) can never double-post the message or generate a second reply.
  String? _activeTurnId;

  /// The latest snapshot from `watchMessages`, kept for reconciliation.
  List<AiMessage> _lastPersisted = const [];

  // -- Live-reply pacing -----------------------------------------------------
  // Streamed deltas are NOT painted directly: they land in [_liveTargetChars]
  // and a per-frame ticker reveals characters at a fast, adaptive rate — an
  // immediate start, a smooth continuous write, and exponential catch-up so
  // the display never lags more than a few frames behind the network. The
  // result reads as ZIVO actively typing (ChatGPT-like) whether the server
  // delivers many small deltas or one big buffered blob.

  /// Characters received but not yet revealed.
  final List<String> _liveTargetChars = [];

  /// How many characters of the target are currently visible.
  int _liveShownChars = 0;

  /// Drives the reveal at frame rate while there is anything left to show.
  Ticker? _revealTicker;

  /// True while the list is pinned to the bottom; goes false the moment the
  /// user scrolls up, so incoming messages don't yank them back down.
  bool _autoFollow = true;

  Stream<List<AiMessage>>? _messagesStream;
  String? _streamConversationId;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final canSend = _input.text.trim().isNotEmpty;
      if (canSend != _canSend) setState(() => _canSend = canSend);
    });
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      _autoFollow = p.pixels >= p.maxScrollExtent - 120;
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _slowTurnTimer?.cancel();
    _landingWatchdog?.cancel();
    _revealTicker?.dispose();
    super.dispose();
  }

  /// Sends the composer's text — lazily creating the active conversation
  /// first if this is an unsaved "New chat" (ChatGPT behavior: nothing is
  /// persisted in Firestore until the first message actually goes out).
  Future<void> _send() async {
    if (!_activeResolved) return;
    if (_sending) return;
    if (!_canSend) return;
    final text = _input.text;
    _input.clear();

    var conversationId = _activeConversationId;
    if (conversationId == null) {
      final ai = AppScope.of(context).ai;
      conversationId = await ai.createConversation();
      if (!mounted) return;
      _activeIsUntitled = true;
    }

    // A fresh idempotency key per logical message; [_retry] deliberately
    // reuses it so a retry can never double-post the turn server-side.
    _activeTurnId =
        '${DateTime.now().microsecondsSinceEpoch}-${_activeConversationId.hashCode}';

    final baselineUserCount = _lastPersisted
        .where((m) => m.role == AiRole.user)
        .length;
    final baselineAssistantCount = _lastPersisted
        .where((m) => m.role == AiRole.assistant)
        .length;
    // The first user message in a still-'New chat' conversation earns an
    // auto-title — fired alongside the send, not blocking it.
    if (baselineUserCount == 0 && _activeIsUntitled) {
      _activeIsUntitled = false;
      unawaited(_autoTitle(conversationId, text));
    }
    setState(() {
      _activeConversationId = conversationId;
      _activeResolved = true;
      _pendingText = text;
      _sendFailed = false;
      _baselineUserCount = baselineUserCount;
      _baselineAssistantCount = baselineAssistantCount;
    });
    await _runSend(conversationId, text);
  }

  /// Best-effort: a failed rename just leaves the conversation titled
  /// 'New chat' in the sessions list — never surfaced as a user-facing error.
  Future<void> _autoTitle(String conversationId, String firstMessage) async {
    final ai = AppScope.of(context).ai;
    final trimmed = firstMessage.trim();
    final title = trimmed.length > 40
        ? '${trimmed.substring(0, 40).trimRight()}…'
        : trimmed;
    try {
      await ai.renameConversation(conversationId, title);
    } catch (_) {
      // Best-effort — see doc comment.
    }
  }

  /// Switches the active conversation — clears all optimistic/in-flight
  /// state from the previous one so it can't bleed into the new thread.
  /// [conversationId] is null for an unsaved "New chat" (nothing persisted
  /// yet — see [_send]).
  void _switchTo(String? conversationId, {required bool isUntitled}) {
    _slowTurnTimer?.cancel();
    _landingWatchdog?.cancel();
    _revealTicker?.dispose();
    _revealTicker = null;
    setState(() {
      _activeConversationId = conversationId;
      _activeResolved = true;
      _activeIsUntitled = isUntitled;
      _pendingText = null;
      _sendFailed = false;
      _sending = false;
      _phase = null;
      _liveText = '';
      _liveTargetChars.clear();
      _liveShownChars = 0;
      _streamed = false;
      _expectReveal = false;
      _turnSlow = false;
      _resolved.clear();
      _baselineUserCount = 0;
      _baselineAssistantCount = 0;
      _activeTurnId = null;
      _lastPersisted = const [];
      _autoFollow = true;
    });
  }

  /// Starts a new, unsaved chat — no Firestore write until [_send] actually
  /// fires the first message.
  void _newChat() => _switchTo(null, isUntitled: true);

  Future<void> _openSessions(String? activeConversationId) async {
    final result = await showModalBottomSheet<_SessionsSelection>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SessionsSheet(
        activeConversationId: activeConversationId,
        onDeleted: _handleConversationDeleted,
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case _NewChatSelected():
        _newChat();
      case _ConversationSelected(:final conversation):
        if (conversation.id != activeConversationId) {
          _switchTo(
            conversation.id,
            isUntitled: conversation.title == 'New chat',
          );
        }
    }
  }

  /// A conversation was deleted from the sessions sheet (which stays open —
  /// this only reacts if the ACTIVE conversation was the one removed):
  /// switches to the most-recently-updated remaining one, or to the unsaved
  /// "New chat" state if none remain.
  Future<void> _handleConversationDeleted(String deletedId) async {
    if (deletedId != _activeConversationId) return;
    final ai = AppScope.of(context).ai;
    // A one-shot query, not `watchConversations().first` — same staleness
    // risk as `_resolveInitialConversation` (a fresh subscription's first
    // emission can precede Firestore's post-delete server data).
    final remaining = await ai.latestConversation();
    if (!mounted) return;
    if (remaining == null) {
      _newChat();
    } else {
      _switchTo(remaining.id, isUntitled: remaining.title == 'New chat');
    }
  }

  /// Picks a new reply-length style — applied optimistically (future sends
  /// use it immediately) and persisted in the background; rolled back with a
  /// toast if the save fails.
  Future<void> _setResponseStyle(String style) async {
    final previous = _responseStyle;
    if (style == previous) return;
    setState(() => _responseStyle = style);
    try {
      await AppScope.of(context).ai.setResponseStyle(style);
    } catch (_) {
      if (!mounted) return;
      setState(() => _responseStyle = previous);
      _showError("Couldn't save that — try again.");
    }
  }

  /// Re-sends the last failed text. The server persisted nothing on a
  /// network failure, so the baseline user count from the original attempt
  /// is still correct — no duplicate optimistic bubble.
  Future<void> _retry(String conversationId) async {
    if (_pendingText == null) return;
    // Same [_activeTurnId] as the original attempt — the server treats this
    // as the same logical turn, so a retry racing a slow first attempt can
    // never append a second user message or generate a duplicate reply.
    await _runSend(conversationId, _pendingText!);
  }

  /// Fills the composer with an empty-state suggestion and sends it —
  /// setting the controller text fires the existing listener synchronously,
  /// so `_canSend` is already true by the time `_send`'s guard runs.
  void _sendSuggestion(String text) {
    _input.text = text;
    _send();
  }

  Future<void> _runSend(String conversationId, String text) async {
    final ai = AppScope.of(context).ai;
    _slowTurnTimer?.cancel();
    _landingWatchdog?.cancel();
    setState(() {
      _sending = true;
      _expectReveal = true;
      _phase = null;
      _liveText = '';
      _liveTargetChars.clear();
      _liveShownChars = 0;
      _streamed = false;
      _sendFailed = false;
      _turnSlow = false;
      _autoFollow = true;
    });
    // If the gateway goes quiet for [_kSlowTurnAfter], admit it in the rail.
    _slowTurnTimer = Timer(_kSlowTurnAfter, () {
      if (mounted && _sending) setState(() => _turnSlow = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    try {
      await ai.send(
        conversationId: conversationId,
        text: text,
        clientTurnId: _activeTurnId,
        onEvent: _onTurnEvent,
        responseStyle: _responseStyle,
      );
    } catch (_) {
      _slowTurnTimer?.cancel();
      _revealTicker?.dispose();
      _revealTicker = null;
      if (mounted) {
        setState(() {
          _sending = false;
          _sendFailed = true;
          _turnSlow = false;
          _phase = null;
          _liveText = '';
          _liveTargetChars.clear();
          _liveShownChars = 0;
        });
      }
      return;
    }
    _slowTurnTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _sending = false;
      // A streamed reply already appeared token-by-token, so don't re-type the
      // durable message; only a buffered (non-streaming) turn falls back to it.
      if (_streamed) _expectReveal = false;
      _phase = null;
      _turnSlow = false;
    });
    // _liveText is deliberately NOT cleared here: the durable reply may not
    // have landed in the watch snapshot yet, and dropping the live bubble
    // now would blank the screen for a beat. The builder clears it (and
    // stops the reveal ticker) the moment the durable assistant message
    /// lands — see the `assistantLanded` reconciliation below.
    // The stream ended cleanly, but that says nothing about persistence: if
    // the user message never lands (a silent server drop), surface the retry
    // card rather than leaving the optimistic bubble hanging forever.
    final baselineAtSend = _baselineUserCount;
    _landingWatchdog = Timer(_kLandingGrace, () {
      if (!mounted || _pendingText == null || _sending || _sendFailed) return;
      final persistedUserCount = _lastPersisted
          .where((m) => m.role == AiRole.user)
          .length;
      if (persistedUserCount > baselineAtSend) return;
      setState(() => _sendFailed = true);
    });
    // _pendingText is intentionally left set here — the StreamBuilder
    // reconciliation below clears it once the persisted message actually
    // lands, so the optimistic bubble never gaps or duplicates the real one.
  }

  /// Applies one live turn event from the gateway: phases drive the rail,
  /// deltas feed the paced revealer (never painted directly — see the
  /// pacer fields). Any event proves liveness, so the slow-turn admission
  /// resets.
  void _onTurnEvent(AiTurnEvent event) {
    if (!mounted) return;
    switch (event) {
      case AiPhaseEvent(:final phase):
        _slowTurnTimer?.cancel();
        if (_turnSlow) setState(() => _turnSlow = false);
        setState(() => _phase = phase);
      case AiDeltaEvent(:final text):
        _slowTurnTimer?.cancel();
        if (_turnSlow) setState(() => _turnSlow = false);
        _streamed = true;
        _liveTargetChars.addAll(text.characters);
        _ensureRevealTicker();
    }
  }

  /// Starts the per-frame reveal ticker if it isn't already running.
  void _ensureRevealTicker() {
    if (_revealTicker != null || !mounted) return;
    final ticker = createTicker(_onRevealTick)..start();
    _revealTicker = ticker;
  }

  /// The pacer's per-frame step: a small floor keeps the write visibly
  /// moving even between network chunks; the exponential term drains any
  /// accumulated backlog within a handful of frames, so the display tracks
  /// the server closely no matter how bursty the deltas are. At 60fps this
  /// reads as fast, fluid typing — never a crawl, never an instant dump.
  void _onRevealTick(Duration elapsed) {
    if (!mounted) return;
    final remaining = _liveTargetChars.length - _liveShownChars;
    if (remaining <= 0) return;
    final step = math.max(4, remaining >> 3);
    final next = math.min(_liveTargetChars.length, _liveShownChars + step);
    if (!mounted) return;
    setState(() {
      _liveShownChars = next;
      _liveText = _liveTargetChars.take(next).join();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoScroll());
    if (next >= _liveTargetChars.length) {
      // Fully caught up — idle the ticker until the next delta arrives.
      _revealTicker?.dispose();
      _revealTicker = null;
    }
  }

  /// Tears down the live bubble once the durable reply is on screen: stops
  /// the reveal ticker and drops the provisional text so exactly ONE copy of
  /// the reply remains. Called via post-frame from the builder.
  void _retireLiveReply() {
    _revealTicker?.dispose();
    _revealTicker = null;
    if (!mounted) return;
    setState(() {
      _liveText = '';
      _liveTargetChars.clear();
      _liveShownChars = 0;
    });
  }

  Future<void> _confirm(String conversationId, String actionId) async {
    final ai = AppScope.of(context).ai;
    setState(() => _resolved[actionId] = AiActionStatus.applied);
    try {
      await ai.confirmAction(
        conversationId: conversationId,
        actionId: actionId,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolved.remove(actionId));
      _showError("Couldn't do that just now. Try again.");
    }
  }

  Future<void> _cancel(String conversationId, String actionId) async {
    final ai = AppScope.of(context).ai;
    setState(() => _resolved[actionId] = AiActionStatus.cancelled);
    try {
      await ai.cancelAction(conversationId: conversationId, actionId: actionId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolved.remove(actionId));
      _showError("Couldn't do that just now. Try again.");
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    // The app's translucent top toast — never a bottom SnackBar.
    showZivoToast(context, message, kind: ToastKind.error);
  }

  /// Tap-to-toggle: not recording → request permission and start; recording
  /// → stop and transcribe. A denied permission or a recorder failure shows
  /// a toast and leaves the composer untouched — never a thrown error.
  Future<void> _toggleMic() async {
    final recorder = AppScope.of(context).requireRecorder;
    if (_recording) {
      // Flip straight into the transcribing state so the composer never
      // flashes back to idle between stopping and the request going out.
      setState(() {
        _recording = false;
        _transcribing = true;
      });
      final audio = await recorder.stop();
      if (audio == null) {
        if (!mounted) return;
        setState(() => _transcribing = false);
        _handleSttOutcome(
          const SttFailed(
            SttError.recordingFailed,
            "Didn't catch that — try recording again.",
          ),
        );
        return;
      }
      await _transcribe(audio);
      return;
    }

    final granted = await recorder.ensurePermission();
    if (!mounted) return;
    if (!granted) {
      _handleSttOutcome(
        const SttFailed(
          SttError.microphonePermissionDenied,
          'Turn on microphone access to use voice input.',
        ),
      );
      return;
    }
    await recorder.start();
    if (!mounted) return;
    setState(() => _recording = true);
  }

  /// Discards the in-progress recording without transcribing it.
  Future<void> _cancelRecording() async {
    final recorder = AppScope.of(context).requireRecorder;
    setState(() => _recording = false);
    await recorder.cancel();
  }

  /// Discards a clip mid-transcription: the composer unlocks immediately and
  /// any outcome from this attempt is ignored via the token.
  void _cancelTranscription() {
    setState(() {
      _transcribeToken++;
      _transcribing = false;
    });
  }

  /// Sends [audio] to `ai.transcribe` and, on success, drops the transcript
  /// into the composer for the user to edit/send — never auto-sent. A hung
  /// request times out into a friendly failure instead of locking the
  /// composer forever; a cancelled attempt is ignored by token.
  Future<void> _transcribe(RecordedAudio audio) async {
    final ai = AppScope.of(context).ai;
    final token = ++_transcribeToken;
    setState(() => _transcribing = true);
    SttOutcome outcome;
    try {
      outcome = await _withTimeout(
        ai.transcribe(audioBytes: audio.bytes, mimeType: audio.mimeType),
        widget.transcribeTimeout,
        onTimeout: () => const SttFailed(
          SttError.timeout,
          'That took too long — check your connection and try again.',
        ),
        onFailure: () => const SttFailed(
          SttError.unknown,
          "Couldn't transcribe that — check your connection and try again.",
        ),
      );
    } catch (_) {
      outcome = const SttFailed(
        SttError.unknown,
        "Couldn't transcribe that — check your connection and try again.",
      );
    }
    if (!mounted || token != _transcribeToken) return;
    setState(() => _transcribing = false);
    _handleSttOutcome(outcome);
  }

  /// Races [future] against [limit]: resolves with the future's outcome, a
  /// typed [SttFailed] from [onTimeout] if it settles too slowly, or one
  /// from [onFailure] if it throws. Hand-rolled rather than
  /// `Future.timeout` so the outcome never depends on a concrete
  /// implementation's reified generic type.
  Future<SttOutcome> _withTimeout(
    Future<SttOutcome> future,
    Duration limit, {
    required SttOutcome Function() onTimeout,
    required SttOutcome Function() onFailure,
  }) {
    final completer = Completer<SttOutcome>();
    late final Timer timer;
    timer = Timer(limit, () {
      if (!completer.isCompleted) completer.complete(onTimeout());
    });
    future
        .whenComplete(timer.cancel)
        .then(
          (outcome) {
            if (!completer.isCompleted) completer.complete(outcome);
          },
          onError: (Object _) {
            if (!completer.isCompleted) completer.complete(onFailure());
          },
        );
    return completer.future;
  }

  void _handleSttOutcome(SttOutcome outcome) {
    switch (outcome) {
      case SttTranscribed(:final text):
        _input.text = text;
        _input.selection = TextSelection.collapsed(offset: text.length);
      case SttFailed(:final message):
        if (!mounted) return;
        showZivoToast(context, message, kind: ToastKind.error);
    }
  }

  /// The rail label for the current authoritative phase; a calm "Thinking…"
  /// before any phase arrives or for a non-streaming turn.
  String _railLabel() => switch (_phase) {
    AiPhase.understanding => 'Understanding…',
    AiPhase.working => 'Working…',
    AiPhase.preparingChange => 'Preparing your change…',
    _ => 'Thinking…',
  };

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    if (reducedMotion(context)) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      return;
    }
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Follows new content to the bottom only if the user hasn't scrolled
  /// away — never yanks them down mid-read, and resumes following once
  /// they scroll back near the bottom themselves.
  void _maybeAutoScroll() {
    if (_autoFollow) _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Keyboard handling is done HERE rather than by the Scaffold: the
    // default resizeToAvoidBottomInset shrinks the body instantly (a hard,
    // jarring jump) while VoiceComposer separately padded itself by the same
    // inset — so the old layout both jumped AND double-counted the keyboard.
    // Instead the whole conversation block rides an eased AnimatedPadding
    // (matching the iOS keyboard curve), and the message list re-pins to the
    // bottom on every metrics change mid-animation, so content reads as
    // anchored under the composer while it rises — iMessage-style.
    final keyboardInset = math.max(
      media.viewInsets.bottom,
      media.padding.bottom,
    );
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatHeader(
              onNewChat: (!_activeResolved || _sending) ? null : _newChat,
              onSessions: (!_activeResolved || _sending)
                  ? null
                  : () => _openSessions(_activeConversationId),
              responseStyle: _responseStyle,
              onSelectStyle: _setResponseStyle,
            ),
            Expanded(
              child: AnimatedPadding(
                duration: reducedMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(bottom: keyboardInset),
                child: Column(
                  children: [
                    Expanded(
                      child: FutureBuilder<void>(
                        future: _initialLoad,
                        builder: (context, _) {
                          if (!_activeResolved) return const SizedBox.shrink();
                          final conversationId = _activeConversationId;
                          if (conversationId == null) {
                            // An unsaved "New chat" — nothing persisted yet, so
                            // there's no message stream to watch.
                            return _EmptyAsk(onSuggestion: _sendSuggestion);
                          }
                          final ai = AppScope.of(context).ai;
                          if (_messagesStream == null ||
                              _streamConversationId != conversationId) {
                            _streamConversationId = conversationId;
                            _messagesStream = ai.watchMessages(conversationId);
                          }
                          return StreamBuilder<List<AiMessage>>(
                            stream: _messagesStream,
                            builder: (context, snapshot) {
                              _lastPersisted =
                                  snapshot.data ?? const <AiMessage>[];
                              final persistedUserCount = _lastPersisted
                                  .where((m) => m.role == AiRole.user)
                                  .length;
                              final displayed = <AiMessage>[..._lastPersisted];

                              // The durable ASSISTANT reply landing gates the
                              // provisional live bubble — the instant it's in
                              // the snapshot exactly one copy of the reply
                              // renders (the persisted one). This closes the
                              // window where the server writes the reply doc
                              // slightly before the functions stream closes,
                              // which used to duplicate the response.
                              final assistantLanded =
                                  _lastPersisted
                                      .where(
                                        (m) => m.role == AiRole.assistant,
                                      )
                                      .length >
                                  _baselineAssistantCount;
                              if (_liveText.isNotEmpty && assistantLanded) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => _retireLiveReply(),
                                );
                              }

                              // The optimistic USER bubble "lands" the moment
                              // the server has persisted a new user message —
                              // state-based, not a text/id compare, so it can't
                              // mismatch or double up. Content equality backs
                              // the count check up against baseline desyncs.
                              final pendingLanded =
                                  _pendingText != null &&
                                  (persistedUserCount > _baselineUserCount ||
                                   _lastPersisted.any(
                                     (m) =>
                                         m.role == AiRole.user &&
                                         m.content.trim() ==
                                             _pendingText!.trim(),
                                   ));
                              if (pendingLanded) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted && _pendingText != null) {
                                    setState(() {
                                      _pendingText = null;
                                      _sendFailed = false;
                                    });
                                  }
                                });
                              }
                              if (_pendingText != null && !pendingLanded) {
                                displayed.add(
                                  AiMessage(
                                    id: '_pending',
                                    role: AiRole.user,
                                    content: _pendingText!,
                                    createdAt: DateTime.now(),
                                  ),
                                );
                              }
                              if (displayed.isEmpty &&
                                  !_sending &&
                                  !_sendFailed &&
                                  _liveText.isEmpty) {
                                return _EmptyAsk(
                                  onSuggestion: _sendSuggestion,
                                );
                              }
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => _maybeAutoScroll(),
                              );
                              return NotificationListener<
                                ScrollMetricsNotification
                              >(
                                // Fires whenever the scroll metrics change —
                                // including every frame of the keyboard's
                                // animated inset above shrinking this viewport.
                                // Re-pin instantly each frame while following,
                                // so the newest message stays glued to the
                                // composer instead of drifting out of view.
                                onNotification: (_) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                        if (!mounted || !_autoFollow) return;
                                        if (!_scroll.hasClients) return;
                                        final p = _scroll.position;
                                        if (p.maxScrollExtent > 0) {
                                          _scroll.jumpTo(p.maxScrollExtent);
                                        }
                                      });
                                  return false;
                                },
                                child: ListView.builder(
                                  controller: _scroll,
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.screen,
                                    AppSpacing.base,
                                    AppSpacing.screen,
                                    AppSpacing.base,
                                  ),
                                  // A trailing slot holds the in-flight state: the live
                                  // reply once text starts streaming, the phase rail, or
                                  // a retry prompt after a failed send.
                                  itemCount:
                                      displayed.length +
                                      ((_sending ||
                                              _sendFailed ||
                                              _liveText.isNotEmpty)
                                          ? 1
                                          : 0),
                                  itemBuilder: (context, i) {
                                    if (i >= displayed.length) {
                                      // Grouped under the ZIVO label right after a user
                                      // send — mirrors the runStart check below.
                                      final showIdentity =
                                          displayed.isEmpty ||
                                          displayed.last.role !=
                                              AiRole.assistant;
                                      // The provisional live bubble shows only while
                                      // the durable reply has NOT landed — once it
                                      // does, the persisted copy renders and this
                                      // slot retires, so the response can never
                                      /// appear twice.
                                      final liveActive =
                                          !_sendFailed &&
                                          !assistantLanded &&
                                          _liveText.isNotEmpty;
                                      final stillWriting =
                                          _liveShownChars <
                                          _liveTargetChars.length;
                                      Widget trailing;
                                      if (liveActive) {
                                        trailing = _MessageBubble(
                                          AiMessage(
                                            id: '_live',
                                            role: AiRole.assistant,
                                            content: _liveText,
                                            createdAt: DateTime.now(),
                                          ),
                                          streaming: stillWriting,
                                        );
                                      } else if (_sending && !assistantLanded) {
                                        trailing = _ThinkingRail(
                                          label: _railLabel(),
                                          slow: _turnSlow,
                                        );
                                      } else if (_sendFailed) {
                                        trailing = _ErrorRetry(
                                          onRetry: () =>
                                              _retry(conversationId),
                                        );
                                      } else {
                                        trailing = const SizedBox.shrink();
                                      }
                                      if (showIdentity &&
                                          trailing is! SizedBox) {
                                        trailing = Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const _ZivoIdentity(),
                                            trailing,
                                          ],
                                        );
                                      }
                                      return RiseIn(child: trailing);
                                    }
                                    final message = displayed[i];
                                    final isLast =
                                        i == displayed.length - 1;
                                    // Consume the reveal token on the first render of the
                                    // turn's last message; only a fresh text reply types.
                                    var animateReply = false;
                                    if (isLast && _expectReveal) {
                                      if (message.role == AiRole.assistant &&
                                          message.pendingAction == null) {
                                        animateReply = true;
                                      }
                                      _expectReveal = false;
                                    }
                                    // Groups consecutive assistant messages (a bubble
                                    // followed by its proposal card, say) under one
                                    // ZIVO label instead of repeating it per message.
                                    final runStart =
                                        message.role == AiRole.assistant &&
                                        (i == 0 ||
                                            displayed[i - 1].role !=
                                                AiRole.assistant);
                                    final action = message.pendingAction;
                                    Widget content;
                                    if (action == null) {
                                      content = _MessageBubble(
                                        message,
                                        animate: animateReply,
                                      );
                                    } else {
                                      final effective =
                                          action.status !=
                                              AiActionStatus.pending
                                          ? action.status
                                          : (_resolved[action.actionId] ??
                                                AiActionStatus.pending);
                                      content = _ProposalCard(
                                        action: action,
                                        status: effective,
                                        onConfirm: () => _confirm(
                                          conversationId,
                                          action.actionId,
                                        ),
                                        onCancel: () =>
                                            _cancel(conversationId, action.actionId),
                                      );
                                    }
                                    if (runStart) {
                                      content = Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const _ZivoIdentity(),
                                          content,
                                        ],
                                      );
                                    }
                                    return RiseIn(
                                      key: ValueKey(message.id),
                                      child: content,
                                    );
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    VoiceComposer(
                      controller: _input,
                      canSend: _canSend,
                      // Bottom spacing is owned by the AnimatedPadding above —
                      // both the safe area and the keyboard ride that one
                      // animated value, never twice.
                      bottomInset: 0,
                      onSend: _send,
                      isRecording: _recording,
                      transcribing: _transcribing,
                      sending: _sending,
                      onMicToggle: _toggleMic,
                      onCancelRecording: _cancelRecording,
                      onCancelTranscription: _cancelTranscription,
                      // Soft-resolved: hosts without a recorder simply get a
                      // waveform-less composer; [requireRecorder]'s hard assert
                      // belongs to the mic flow itself, not every rebuild.
                      recorder: AppScope.of(context).recorder,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small "✦ ZIVO" label grouping consecutive assistant content — shown
/// once above a run of assistant bubbles/proposal cards, not per-message.
class _ZivoIdentity extends StatelessWidget {
  const _ZivoIdentity();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            AppIcons.ask,
            size: 13,
            color: AppColors.iris,
          ),
          const SizedBox(width: 5),
          Text(
            'ZIVO',
            style: AppText.meta.copyWith(
              color: AppColors.irisText,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAsk extends StatelessWidget {
  const _EmptyAsk({required this.onSuggestion});

  final void Function(String prompt) onSuggestion;

  static const _suggestions = [
    'What did I spend this week?',
    'How is my training going?',
    "What's left on my diet today?",
    'Summarise my week',
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The hero: the sparkles glyph resting in its own iris glow.
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.irisWash,
                border: Border.all(color: AppColors.iris.withValues(alpha: 0.25)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.iris.withValues(alpha: 0.22),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(AppIcons.ask, size: 26, color: AppColors.irisText),
            ),
            const SizedBox(height: 18),
            // The screen's one warm aside — Fraunces italic, per brand.
            Text(
              "Hey, I'm ZIVO.",
              style: AppText.aside.copyWith(color: AppColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask about your training, diet, and spending — or I can add '
              'an expense for you.',
              style: AppText.body.copyWith(color: AppColors.ink2, height: 1.45),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final prompt in _suggestions)
                  _SuggestionChip(
                    label: prompt,
                    onTap: () => onSuggestion(prompt),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable suggestion pill in the empty state — a tap sends the prompt
/// immediately, the same as typing it and hitting send.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Text(
              label,
              style: AppText.meta.copyWith(fontSize: 12.5, color: AppColors.ink2),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(this.message, {this.animate = false, this.streaming = false});

  final AiMessage message;

  /// When true, the (assistant) text types in rather than appearing at once.
  final bool animate;

  /// When true (the provisional live bubble mid-turn), a soft iris caret
  /// rides the text so "still writing" is visible at a glance.
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiRole.user;
    final style = AppText.body.copyWith(
      color: isUser ? Colors.white : AppColors.ink,
      height: isUser ? null : 1.4,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isUser ? 16 : 2,
                vertical: isUser ? 12 : 2,
              ),
              decoration: isUser
                  ? BoxDecoration(
                      color: AppColors.iris,
                      // A softened bottom-right tail points the pill back
                      // at its author — small, but it reads as intentional.
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(6),
                      ),
                    )
                  : null,
              child: animate
                  ? _TypewriterText(message.content, style: style)
                  : streaming && !MediaQuery.of(context).disableAnimations
                  ? Text.rich(
                      TextSpan(
                        text: message.content,
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: _StreamCaret(),
                          ),
                        ],
                      ),
                      style: style,
                    )
                  : Text(message.content, style: style),
            ),
          ),
        ],
      ),
    );
  }
}

/// The caret riding the end of a streaming reply — a softly breathing iris
/// bar. Only mounted mid-turn, so its loop never outlives the stream.
class _StreamCaret extends StatefulWidget {
  const _StreamCaret();

  @override
  State<_StreamCaret> createState() => _StreamCaretState();
}

class _StreamCaretState extends State<_StreamCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    lowerBound: 0.25,
    upperBound: 1,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 2.5,
        height: 14,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: AppColors.iris,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Reveals [text] left-to-right on mount, like the assistant is composing it.
/// One-shot (never repeats), so `pumpAndSettle` completes it; honors the
/// platform "reduce motion" setting by showing the full text immediately.
class _TypewriterText extends StatefulWidget {
  const _TypewriterText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // ~9ms/char with a hard cap — a fast, fluid write that never crawls on
    // long replies (the streamed path paces itself per-frame; this is only
    // the fallback for turns that arrived without deltas).
    final ms = math.min(widget.text.characters.length * 9, 1400);
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: math.max(ms, 1)),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return Text(widget.text, style: widget.style);
    }
    final chars = widget.text.characters;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final shown = (chars.length * _c.value).round();
        return Text(chars.take(shown).toString(), style: widget.style);
      },
    );
  }
}

/// The calm "the assistant is working" state: a softly glowing iris orb that
/// breathes beside the authoritative phase label, which cross-fades between
/// phases. After [_kSlowTurnAfter] with no gateway activity, [slow] admits
/// the wait ("Still working on this one…") so a long turn never reads as a
/// silent hang. Shown only while a turn is in flight, so its looping pulse
/// is never left mounted (which would stall `pumpAndSettle`). No spinner.
class _ThinkingRail extends StatefulWidget {
  const _ThinkingRail({this.label = 'Thinking…', this.slow = false});

  /// The current phase label (authoritative when streaming; "Thinking…" until
  /// the first phase event or for a buffered turn).
  final String label;

  /// The turn has gone quiet — add the honest reassurance line.
  final bool slow;

  @override
  State<_ThinkingRail> createState() => _ThinkingRailState();
}

class _ThinkingRailState extends State<_ThinkingRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
    upperBound: 1,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The orb: an iris core inside its own glow.
              still
                  ? const _GlowOrb(opacity: 0.9)
                  : FadeTransition(
                      opacity: _c,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.85, end: 1).animate(_c),
                        child: const _GlowOrb(opacity: 1),
                      ),
                    ),
              const SizedBox(width: 9),
              AnimatedSwitcher(
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previousChildren, ?currentChild],
                ),
                child: Text(
                  widget.label,
                  key: ValueKey(widget.label),
                  style: AppText.meta.copyWith(
                    color: AppColors.irisText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          // Honest slow-turn reassurance — appears only when warranted.
          AnimatedSize(
            duration: still ? Duration.zero : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: widget.slow
                ? Padding(
                    key: const ValueKey('slow'),
                    padding: const EdgeInsets.only(left: 19, top: 4),
                    child: Text(
                      'Still working on this one…',
                      style: AppText.meta.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink3,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// A small iris dot wrapped in its own soft glow — the "alive" signal.
class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.iris.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Center(child: _IrisDot(1)),
    ),
  );
}

class _IrisDot extends StatelessWidget {
  const _IrisDot(this.opacity);

  final double opacity;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.iris.withValues(alpha: opacity),
      shape: BoxShape.circle,
    ),
  );
}

/// Shown in the trailing slot after a failed send — a quiet, modern inline
/// card (not a 2010 banner): the user's text stays in its optimistic bubble
/// above, this explains what happened and offers a one-tap retry.
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Container(
        key: const Key('error-retry'),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: AppColors.flare.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.flare.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            const Icon(AppIcons.warning, size: 17, color: AppColors.flareText),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Couldn't reach ZIVO",
                    style: AppText.rowTitle.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your message wasn\u2019t sent.',
                    style: AppText.body.copyWith(
                      fontSize: 13,
                      height: 1.3,
                      color: AppColors.ink2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            PressableScale(
              child: Material(
                color: AppColors.irisWash,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: onRetry,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    child: Text(
                      'Retry',
                      style: AppText.button.copyWith(
                        color: AppColors.irisText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ADR-003 confirmation card: an assistant proposal the user confirms or
/// cancels. Nothing has been written while it shows Confirm/Cancel.
class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.action,
    required this.status,
    required this.onConfirm,
    required this.onCancel,
  });

  final AiPendingAction action;
  final AiActionStatus status;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline2),
        ),
        // The card collapses smoothly from the full proposal down to the
        // one-line result when the user confirms or cancels.
        child: AnimatedSize(
          duration: AppMotion.enter,
          curve: AppMotion.ease,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(status == AiActionStatus.pending),
              child: status == AiActionStatus.pending
                  ? _pending()
                  : _resolved(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pending() {
    final meta = _kindMeta(action.kind);
    final chips = _chips();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 29,
              height: 29,
              decoration: BoxDecoration(
                color: meta.tintBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(meta.icon, size: 18, color: meta.tintFg),
            ),
            const SizedBox(width: 9),
            Text(
              meta.label,
              style: AppText.meta.copyWith(
                color: meta.tintFg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Text(
          _primaryLine(),
          style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Material(
                color: AppColors.iris,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  key: const Key('proposal-confirm'),
                  onTap: onConfirm,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    child: Text(
                      'Confirm',
                      style: AppText.button.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              key: const Key('proposal-cancel'),
              onTap: onCancel,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Text(
                  'Cancel',
                  style: AppText.button.copyWith(color: AppColors.ink2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _resolved() {
    final IconData icon;
    final Color color;
    final String text;
    switch (status) {
      case AiActionStatus.applied:
        icon = AppIcons.success;
        color = AppColors.pulseText;
        text = 'Confirmed';
      case AiActionStatus.cancelled:
        icon = AppIcons.close;
        color = AppColors.ink3;
        text = 'Cancelled';
      default:
        icon = AppIcons.clock;
        color = AppColors.ink3;
        text = 'Suggestion expired — ask again';
    }
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: AppText.body.copyWith(
              fontSize: 14,
              color: status == AiActionStatus.applied
                  ? AppColors.ink
                  : AppColors.ink3,
            ),
          ),
        ),
      ],
    );
  }

  String _primaryLine() {
    final f = action.fields;
    switch (action.kind) {
      case 'create_expense':
        return '${f['amount'] ?? ''} ${f['currency'] ?? ''}'.trim();
      case 'mark_meal_eaten':
        return '${f['meal'] ?? ''}'.trim();
      default:
        return action.summary;
    }
  }

  List<Widget> _chips() {
    final f = action.fields;
    final chips = <Widget>[];
    switch (action.kind) {
      case 'create_expense':
        if (f['category'] != null) {
          chips.add(_chip(AppIcons.tag, f['category'].toString()));
        }
        if (f['note'] != null) {
          chips.add(_chip(AppIcons.caption, f['note'].toString()));
        }
      case 'mark_meal_eaten':
        chips.add(
          _chip(
            f['state'] == 'eaten' ? AppIcons.success : AppIcons.close,
            f['state']?.toString() ?? 'eaten',
          ),
        );
    }
    return chips;
  }

  Widget _chip(IconData icon, String label, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg ?? AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg ?? AppColors.ink2),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.meta.copyWith(color: fg ?? AppColors.ink2),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String label, Color tintBg, Color tintFg}) _kindMeta(
    String kind,
  ) {
    switch (kind) {
      case 'create_expense':
        return (
          icon: AppIcons.expenses,
          label: 'New expense',
          tintBg: AppColors.solarWash,
          tintFg: AppColors.solarText,
        );
      case 'mark_meal_eaten':
        return (
          icon: AppIcons.diet,
          label: 'Diet plan',
          tintBg: AppColors.pulseWash,
          tintFg: AppColors.pulseText,
        );
      default:
        return (
          icon: AppIcons.ask,
          label: 'Suggestion',
          tintBg: AppColors.hairline,
          tintFg: AppColors.ink2,
        );
    }
  }
}

/// What the sessions sheet was dismissed with — a "New chat" tap, or a tap on
/// an existing conversation row.
sealed class _SessionsSelection {}

final class _NewChatSelected extends _SessionsSelection {}

final class _ConversationSelected extends _SessionsSelection {
  _ConversationSelected(this.conversation);

  final AiConversation conversation;
}

/// The ChatGPT-style history sheet: a "New chat" row pinned above a live list
/// of the user's conversations, newest first, with the active one
/// highlighted. Tapping either pops the sheet with the corresponding
/// [_SessionsSelection] for [_AskPageState._openSessions] to act on.
class _SessionsSheet extends StatefulWidget {
  const _SessionsSheet({
    required this.activeConversationId,
    required this.onDeleted,
  });

  final String? activeConversationId;

  /// Called with a conversation's id right after it's actually deleted —
  /// the sheet stays open; the caller reacts if it was the active one.
  final void Function(String conversationId) onDeleted;

  @override
  State<_SessionsSheet> createState() => _SessionsSheetState();
}

class _SessionsSheetState extends State<_SessionsSheet> {
  late final Stream<List<AiConversation>> _conversations = AppScope.of(
    context,
  ).ai.watchConversations();

  Future<void> _performDelete(AiConversation conversation) async {
    await AppScope.of(context).ai.deleteConversation(conversation.id);
    widget.onDeleted(conversation.id);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screen,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chats',
                      style: AppText.cardTitle.copyWith(fontSize: 19),
                    ),
                  ),
                  _NewChatPill(
                    onTap: () => Navigator.of(context).pop(_NewChatSelected()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: StreamBuilder<List<AiConversation>>(
                stream: _conversations,
                builder: (context, snapshot) {
                  final conversations =
                      snapshot.data ?? const <AiConversation>[];
                  if (conversations.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screen,
                        8,
                        AppSpacing.screen,
                        28,
                      ),
                      child: Text(
                        'No chats yet.',
                        style: AppText.aside.copyWith(color: AppColors.ink2),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                      vertical: 4,
                    ),
                    itemCount: conversations.length,
                    itemBuilder: (context, i) {
                      final conversation = conversations[i];
                      return StaggeredReveal(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Dismissible(
                            key: ValueKey(conversation.id),
                            direction: DismissDirection.endToStart,
                            background: const _DeleteChatSwipeBackground(),
                            onUpdate: (details) {
                              // Fires once, right as the swipe crosses the
                              // dismiss threshold — a felt "point of no
                              // return" before the confirm sheet even opens.
                              if (details.reached && !details.previousReached) {
                                HapticFeedback.mediumImpact();
                              }
                            },
                            confirmDismiss: (_) =>
                                _confirmDeleteChat(context, conversation.title),
                            onDismissed: (_) => _performDelete(conversation),
                            child: _SessionRow(
                              conversation: conversation,
                              isActive:
                                  conversation.id ==
                                  widget.activeConversationId,
                              onTap: () => Navigator.of(
                                context,
                              ).pop(_ConversationSelected(conversation)),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Confirms deleting a chat — destructive and irreversible (it cascades to
/// every message in it), so it always asks first. Returns true only on an
/// explicit Delete tap. A bottom sheet (not a centered dialog) so the
/// destructive action sits right under the thumb that just swiped it.
Future<bool> _confirmDeleteChat(BuildContext context, String title) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          14,
          AppSpacing.screen,
          8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Delete this chat?',
              style: AppText.cardTitle.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'This permanently removes "$title" and everything in it. '
              "This can't be undone.",
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: AppColors.ink2),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: _SheetAction(
                label: 'Delete chat',
                color: AppColors.flare,
                background: AppColors.flareWash,
                onTap: () => Navigator.pop(context, true),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _SheetAction(
                label: 'Cancel',
                color: AppColors.ink2,
                background: Colors.transparent,
                onTap: () => Navigator.pop(context, false),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return confirmed ?? false;
}

/// One full-width row in [_confirmDeleteChat]'s action sheet.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text(
              label,
              style: AppText.button.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The red trailing reveal shown as a chat row is swiped left to delete —
/// the confirm dialog ([_confirmDeleteChat]) still gates the actual delete.
class _DeleteChatSwipeBackground extends StatelessWidget {
  const _DeleteChatSwipeBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.flare.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(AppIcons.trash, color: AppColors.flare),
    );
  }
}

class _NewChatPill extends StatelessWidget {
  const _NewChatPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: AppColors.irisWash,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  AppIcons.chatNew,
                  size: 15,
                  color: AppColors.iris,
                ),
                const SizedBox(width: 6),
                Text(
                  'New chat',
                  style: AppText.meta.copyWith(
                    color: AppColors.irisText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.conversation,
    required this.isActive,
    required this.onTap,
  });

  final AiConversation conversation;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? AppColors.surfaceRaised : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  conversation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowTitle.copyWith(
                    color: isActive ? AppColors.ink : AppColors.ink2,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                timeAgo(conversation.updatedAt, DateTime.now()),
                style: AppText.meta.copyWith(color: AppColors.ink3),
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                const Icon(
                  AppIcons.success,
                  size: 16,
                  color: AppColors.iris,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
