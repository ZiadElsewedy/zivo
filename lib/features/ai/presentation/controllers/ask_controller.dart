import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/audio_recorder.dart';
import '../../domain/ai_message.dart';
import '../../domain/ai_pending_action.dart';
import '../../domain/ai_repository.dart';
import '../../domain/ai_response_style.dart';
import '../../domain/ai_role.dart';
import '../../domain/ai_turn_event.dart';
import '../../domain/stt_error.dart';
import '../../domain/stt_outcome.dart';
import '../ask_constants.dart';

/// A turn's machinery, with none of the chat's chrome.
///
/// This was the bulk of a 1,380-line `_AskPageState`, and it is the hardest
/// state in the app to reason about: an optimistic user bubble that has to
/// pair exactly with its durable Firestore copy, a live reply streamed as
/// deltas and paced out character-by-character by a ticker, a slow-turn
/// admission, a landing watchdog for silent server drops, idempotency keys
/// that survive retries, proposal cards resolved optimistically, and a voice
/// path with its own timeout and cancellation token.
///
/// All of it used to be reachable only by pumping the page. Now the page
/// renders and this decides.
///
/// **What deliberately stayed in the page:** the scroll controller and
/// auto-follow, the entrance ledger, and the reveal-active set. Those are
/// statements about a list of widgets on a screen, not about a turn — moving
/// them here would have swapped one tangle for another. The two places the
/// turn machinery genuinely needs to reach the screen are callbacks
/// ([onError], [onContentGrew]) rather than a `BuildContext`, so this class
/// never has to ask whether it is still mounted.
class AskController extends ChangeNotifier {
  AskController({
    required AiRepository ai,
    required AudioRecorderService? recorder,
    required TickerProvider vsync,
    required this.transcribeTimeout,
    this.onError,
    this.onContentGrew,
    this.onSendStarted,
  }) : // An initializing formal would have to be `this._ai`, and a named
       // parameter cannot start with an underscore — so these stay plain
       // assignments.
       // ignore: prefer_initializing_formals
       _ai = ai,
       // ignore: prefer_initializing_formals
       _recorder = recorder,
       // ignore: prefer_initializing_formals
       _vsync = vsync {
    // Bound here rather than left to the caller: `canSend` gates [send], so a
    // controller whose input wasn't wired would silently refuse to send.
    input.addListener(() {
      final next = input.text.trim().isNotEmpty;
      if (next != _canSend) {
        _canSend = next;
        _notify();
      }
    });
  }

  final AiRepository _ai;
  final AudioRecorderService? _recorder;
  final TickerProvider _vsync;

  /// How long a voice-note transcription may run before the UI gives up and
  /// offers a retry — a hung request must never leave the composer locked.
  final Duration transcribeTimeout;

  /// Surfaces a user-facing failure. The page shows a toast; this class does
  /// not know what a toast is.
  final void Function(String message)? onError;

  /// Fires whenever content grew and the list may want to follow it down.
  /// [instant] asks for a jump rather than a tween — the per-frame streaming
  /// reveal, where a restarted tween every frame would stutter.
  final void Function({required bool instant})? onContentGrew;

  /// Fires when a turn starts. The page uses it to re-arm auto-follow —
  /// scroll position is its state, not this class's.
  final VoidCallback? onSendStarted;

  bool _disposed = false;

  // ---- Conversation --------------------------------------------------------

  String? _activeConversationId;
  bool _activeResolved = false;
  bool _activeIsUntitled = false;
  String _responseStyle = kDefaultResponseStyle;
  String? _draftTitle;

  /// Null while still loading, OR while sitting in an unsaved "New chat" that
  /// hasn't sent its first message yet — see [activeResolved].
  String? get activeConversationId => _activeConversationId;

  /// True once [activeConversationId] reflects a real decision (loaded, or
  /// explicitly set by [switchTo]) — distinguishes "still loading" from
  /// "resolved to no conversation", which both read as a null id.
  bool get activeResolved => _activeResolved;

  /// True while the active conversation is still titled 'New chat' — drives
  /// the auto-title-from-first-message behaviour in [send].
  bool get activeIsUntitled => _activeIsUntitled;

  /// The user's saved reply-length preference, forwarded on every [send].
  String get responseStyle => _responseStyle;

  /// Resolves the initial active conversation once at startup, from the
  /// user's most-recently-updated existing one — never creates one. If there
  /// are none, [activeConversationId] stays null (an unsaved "New chat").
  Future<void> load() async {
    // One-shot queries, not `watchConversations().first` — that stream's
    // first emission can be a stale/empty local-cache snapshot that resolves
    // before Firestore's server data arrives, which would wrongly land on the
    // empty "New chat" state even when a conversation exists.
    final latestFuture = _ai.latestConversation();
    final responseStyleFuture = _ai.getResponseStyle();
    final latest = await latestFuture;
    final style = await responseStyleFuture;
    if (_disposed || _activeResolved) return;
    _activeConversationId = latest?.id;
    _activeIsUntitled = latest?.title == 'New chat';
    _activeResolved = true;
    _responseStyle = validResponseStyle(style);
    _notify();
  }

  /// Switches the active conversation — clearing all optimistic/in-flight
  /// state from the previous one so it can't bleed into the new thread.
  /// [conversationId] is null for an unsaved "New chat".
  void switchTo(String? conversationId, {required bool isUntitled}) {
    _slowTurnTimer?.cancel();
    _landingWatchdog?.cancel();
    _revealTicker?.dispose();
    _revealTicker = null;
    _activeConversationId = conversationId;
    _activeResolved = true;
    _activeIsUntitled = isUntitled;
    _pendingText = null;
    _sendFailed = false;
    _sending = false;
    _phase = null;
    _stepTool = null;
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
    _draftTitle = null;
    _lastPersisted = const [];
    _messagesStream = null;
    _streamConversationId = null;
    _notify();
  }

  /// The title the user gave a new chat at creation, used instead of
  /// auto-titling from the first message.
  void setDraftTitle(String? title) {
    _draftTitle = title;
    _notify();
  }

  /// The most-recently-updated remaining conversation, for the sessions
  /// sheet's delete path. A one-shot query for the same staleness reason as
  /// [load].
  Future<({String id, bool isUntitled})?> latestConversation() async {
    final latest = await _ai.latestConversation();
    if (latest == null) return null;
    return (id: latest.id, isUntitled: latest.title == 'New chat');
  }

  /// Picks a new reply-length style — applied optimistically (future sends
  /// use it immediately) and persisted in the background; rolled back with an
  /// error if the save fails.
  Future<void> setResponseStyle(String style) async {
    final previous = _responseStyle;
    if (style == previous) return;
    _responseStyle = style;
    _notify();
    try {
      await _ai.setResponseStyle(style);
    } catch (_) {
      if (_disposed) return;
      _responseStyle = previous;
      _notify();
      onError?.call("Couldn't save that — try again.");
    }
  }

  // ---- The message stream --------------------------------------------------

  Stream<List<AiMessage>>? _messagesStream;
  String? _streamConversationId;

  /// The durable message stream for [conversationId], memoised so a rebuild
  /// does not resubscribe (which would replay the cold-load snapshot and
  /// re-run every entrance animation).
  Stream<List<AiMessage>> messagesStream(String conversationId) {
    if (_messagesStream == null || _streamConversationId != conversationId) {
      _streamConversationId = conversationId;
      _messagesStream = _ai.watchMessages(conversationId);
    }
    return _messagesStream!;
  }

  /// The latest snapshot from `watchMessages`, kept for reconciliation.
  List<AiMessage> _lastPersisted = const [];
  List<AiMessage> get lastPersisted => _lastPersisted;

  /// Hands the controller the newest durable snapshot. Called from the
  /// builder, so it must not notify — it is already inside a build.
  void setPersisted(List<AiMessage> messages) => _lastPersisted = messages;

  /// Whether the durable copy of the in-flight turn's [role] message has
  /// landed in the watch snapshot.
  ///
  /// The PRIMARY signal is exact: both sides of a turn carry the same
  /// [AiMessage.clientTurnId], so pairing by it can never desync the way
  /// counts and text compares could (stale cache snapshots, baseline drift,
  /// whitespace variants) — which is exactly what made a sent message and
  /// ZIVO's reply show up twice. The count checks remain only as a fallback
  /// for snapshots whose messages predate turn dedup and carry no turn id.
  bool turnLanded(AiRole role) {
    final turnId = _activeTurnId;
    if (turnId != null &&
        _lastPersisted.any((m) => m.role == role && m.clientTurnId == turnId)) {
      return true;
    }
    final persistedCount = _lastPersisted.where((m) => m.role == role).length;
    return role == AiRole.user
        ? persistedCount > _baselineUserCount
        : persistedCount > _baselineAssistantCount;
  }

  // ---- Sending -------------------------------------------------------------

  final TextEditingController input = TextEditingController();
  bool _canSend = false;
  bool _sending = false;
  AiPhase? _phase;
  String? _stepTool;
  bool _turnSlow = false;
  Timer? _slowTurnTimer;
  Timer? _landingWatchdog;
  String? _pendingText;
  bool _sendFailed = false;
  int _baselineUserCount = 0;
  int _baselineAssistantCount = 0;
  String? _activeTurnId;

  bool get canSend => _canSend;

  /// True while a `send` turn is in flight — drives the activity rail.
  bool get sending => _sending;

  /// The turn's current phase, from the gateway's authoritative stream. Null
  /// until the first phase event (or for a non-streaming turn).
  AiPhase? get phase => _phase;

  /// True once a turn has run with no gateway event for [kSlowTurnAfter] —
  /// lets the rail admit the wait instead of silently spinning.
  bool get turnSlow => _turnSlow;

  /// The user's just-sent text while a turn is in flight or has failed —
  /// rendered as an optimistic bubble until the durable message lands.
  String? get pendingText => _pendingText;

  /// True when the most recent send attempt threw — shows the retry rail.
  bool get sendFailed => _sendFailed;

  /// Client-generated idempotency key for the in-flight turn.
  String? get activeTurnId => _activeTurnId;

  /// The tool the gateway is running right now, or null between steps. Exposed
  /// mainly so tests can assert the rail follows the real loop.
  String? get stepTool => _stepTool;

  /// The rail label. A running step wins over the phase, because "Reading
  /// today's diet" says more than "Working…" — the phase is the fallback when
  /// no step is active (before the first tool, between tools, and for a
  /// non-streaming turn).
  ///
  /// These strings are English-only, like the phase labels they replace: the
  /// controller has no `BuildContext` by design (ADR-008), so it cannot reach
  /// `AppLocalizations`. The app ships Arabic too, so this is real l10n debt —
  /// pre-existing, and this widens it. Mapping lives here rather than on the
  /// server so the wording can change without a functions deploy, and so a
  /// future move to l10n is one file.
  String get railLabel {
    final step = _stepTool;
    if (step != null) return _stepLabel(step);
    return switch (_phase) {
      AiPhase.understanding => 'Understanding…',
      AiPhase.working => 'Working…',
      AiPhase.preparingChange => 'Preparing your change…',
      _ => 'Thinking…',
    };
  }

  /// A read tool's name → what it is actually doing, in the user's terms.
  ///
  /// An unknown name falls back to the generic line rather than showing a raw
  /// identifier: a tool added server-side must degrade to "Working…" on an
  /// older build, never leak `get_body_composition` onto the screen.
  static String _stepLabel(String tool) => switch (tool) {
    'get_today' => 'Reading your day…',
    'get_diet' => "Reading today's diet…",
    'get_workouts' => 'Reading your training…',
    'get_expenses' => 'Reading your spending…',
    'summarize_week' => 'Summarising your week…',
    'resolve_food' => 'Looking that food up…',
    'calculate_meal_nutrition' => 'Working out the numbers…',
    _ => 'Working…',
  };

  /// Drops text into the composer as editable content — never auto-sent.
  /// Used by the shell's voice quick-log and by transcription.
  void fillComposer(String text, {bool collapseSelection = false}) {
    input.text = collapseSelection ? text : text.trim();
    if (collapseSelection) {
      input.selection = TextSelection.collapsed(offset: text.length);
    }
    _canSend = input.text.trim().isNotEmpty;
    _notify();
  }

  /// Sends the composer's text — lazily creating the active conversation
  /// first if this is an unsaved "New chat" (nothing is persisted until the
  /// first message actually goes out).
  Future<void> send() async {
    if (!_activeResolved) return;
    if (_sending) return;
    if (!_canSend) return;
    // One optimistic slot, one durable pairing: block a second send until the
    // previous turn's user message has actually landed (or failed). In
    // practice the server persists the user message before any reply delta
    // streams, so this never blocks a real queueing rhythm — it only closes
    // the window where a fast second send would overwrite the first turn's
    // unlanded optimistic bubble.
    if (_pendingText != null && !_sendFailed) return;
    final text = input.text;
    input.clear();

    var conversationId = _activeConversationId;
    var draftTitle = _draftTitle;
    if (conversationId == null) {
      conversationId = await _ai.createConversation(title: draftTitle);
      if (_disposed) return;
      _activeIsUntitled = draftTitle == null || draftTitle.trim().isEmpty;
      draftTitle = null; // consumed — no auto-title on top of it
    }

    // A fresh idempotency key per logical message; [retry] deliberately
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
    // auto-title — fired alongside the send, not blocking it. A chat the user
    // named at creation keeps its name instead.
    if (baselineUserCount == 0 && _activeIsUntitled && draftTitle == null) {
      _activeIsUntitled = false;
      unawaited(_autoTitle(conversationId, text));
    }
    _activeConversationId = conversationId;
    _activeResolved = true;
    _pendingText = text;
    _sendFailed = false;
    _baselineUserCount = baselineUserCount;
    _baselineAssistantCount = baselineAssistantCount;
    _draftTitle = null;
    _notify();
    await runSend(conversationId, text);
  }

  /// Fills the composer with an empty-state suggestion and sends it —
  /// setting the controller text fires the listener synchronously, so
  /// [canSend] is already true by the time [send]'s guard runs.
  void sendSuggestion(String text) {
    input.text = text;
    send();
  }

  /// Re-sends the last failed text. The server persisted nothing on a network
  /// failure, so the baseline user count from the original attempt is still
  /// correct — no duplicate optimistic bubble. It reuses [activeTurnId], so
  /// the server treats this as the same logical turn and a retry racing a
  /// slow first attempt can never append a second user message.
  Future<void> retry(String conversationId) async {
    if (_pendingText == null) return;
    await runSend(conversationId, _pendingText!);
  }

  /// Best-effort: a failed rename just leaves the conversation titled 'New
  /// chat' in the sessions list — never surfaced as a user-facing error.
  Future<void> _autoTitle(String conversationId, String firstMessage) async {
    final trimmed = firstMessage.trim();
    final title = trimmed.length > 40
        ? '${trimmed.substring(0, 40).trimRight()}…'
        : trimmed;
    try {
      await _ai.renameConversation(conversationId, title);
    } catch (_) {
      // Best-effort — see doc comment.
    }
  }

  Future<void> runSend(String conversationId, String text) async {
    _slowTurnTimer?.cancel();
    _landingWatchdog?.cancel();
    _sending = true;
    _expectReveal = true;
    _phase = null;
    _stepTool = null;
    _liveText = '';
    _liveTargetChars.clear();
    _liveShownChars = 0;
    _streamed = false;
    _sendFailed = false;
    _turnSlow = false;
    _notify();
    // A send always re-arms following: the user just spoke, so pin to the
    // bottom even if they had scrolled up to re-read something.
    onSendStarted?.call();
    // If the gateway goes quiet for [kSlowTurnAfter], admit it in the rail.
    _slowTurnTimer = Timer(kSlowTurnAfter, () {
      if (!_disposed && _sending) {
        _turnSlow = true;
        _notify();
      }
    });
    onContentGrew?.call(instant: false);
    try {
      await _ai.send(
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
      if (!_disposed) {
        _sending = false;
        _sendFailed = true;
        _turnSlow = false;
        _phase = null;
        _stepTool = null;
        _liveText = '';
        _liveTargetChars.clear();
        _liveShownChars = 0;
        _notify();
      }
      return;
    }
    _slowTurnTimer?.cancel();
    if (_disposed) return;
    _sending = false;
    // A streamed reply already appeared token-by-token, so don't re-type the
    // durable message; only a buffered (non-streaming) turn falls back to it.
    if (_streamed) _expectReveal = false;
    _phase = null;
    _stepTool = null;
    _turnSlow = false;
    _notify();
    // [liveText] is deliberately NOT cleared here: the durable reply may not
    // have landed in the watch snapshot yet, and dropping the live bubble now
    // would blank the screen for a beat. The builder clears it (via
    // [retireLiveReply]) the moment the durable assistant message lands.
    //
    // The stream ended cleanly, but that says nothing about persistence: if
    // the user message never lands (a silent server drop), surface the retry
    // card rather than leaving the optimistic bubble hanging forever.
    final baselineAtSend = _baselineUserCount;
    _landingWatchdog = Timer(kLandingGrace, () {
      if (_disposed || _pendingText == null || _sending || _sendFailed) return;
      final persistedUserCount = _lastPersisted
          .where((m) => m.role == AiRole.user)
          .length;
      if (persistedUserCount > baselineAtSend) return;
      _sendFailed = true;
      _notify();
    });
    // [pendingText] is intentionally left set — the builder's reconciliation
    // clears it once the persisted message actually lands, so the optimistic
    // bubble never gaps or duplicates the real one.
  }

  /// Clears the optimistic user bubble once its durable copy is on screen.
  void clearPending() {
    _pendingText = null;
    _sendFailed = false;
  }

  // ---- Live reply pacing ---------------------------------------------------
  // Streamed deltas are NOT painted directly: they land in [_liveTargetChars]
  // and a per-frame ticker reveals characters at a fast, adaptive rate — an
  // immediate start, a smooth continuous write, and exponential catch-up so
  // the display never lags more than a few frames behind the network.

  String _liveText = '';
  bool _streamed = false;
  bool _expectReveal = false;
  final List<String> _liveTargetChars = [];
  int _liveShownChars = 0;
  Ticker? _revealTicker;

  /// Assistant reply text accumulated from live stream deltas — shown in a
  /// provisional bubble while the turn runs, replaced by the durable message
  /// once it lands.
  String get liveText => _liveText;

  /// True once any text delta has streamed in, so the durable reply renders
  /// statically instead of re-typing.
  bool get streamed => _streamed;

  /// Set when a `send` turn starts; consumed by the first render that shows
  /// the assistant's reply, so exactly that one reply types in when the turn
  /// did *not* stream. Cold-loaded history and confirm/cancel lines stay
  /// static.
  bool get expectReveal => _expectReveal;

  /// Consumed by the builder the moment it hands a reply to the typewriter.
  void consumeExpectReveal() => _expectReveal = false;

  /// True while the paced reveal still has characters left to write.
  bool get revealInFlight => _liveShownChars < _liveTargetChars.length;

  /// Applies one live turn event from the gateway: phases drive the rail,
  /// deltas feed the paced revealer. Any event proves liveness, so the
  /// slow-turn admission resets.
  void _onTurnEvent(AiTurnEvent event) {
    if (_disposed) return;
    switch (event) {
      case AiPhaseEvent(:final phase, :final replaced):
        _slowTurnTimer?.cancel();
        if (_turnSlow) _turnSlow = false;
        _phase = phase;
        // A phase boundary outlives any step inside it — notably `done`, which
        // must not leave a step label behind if a tool's closing event was
        // dropped.
        _stepTool = null;
        _notify();
        // The server's validator threw this reply away. The draft is still on
        // screen — so drop it now rather than let the user go on reading
        // numbers the gateway has already ruled invented, and let the durable
        // (deterministic) reply type itself in as if nothing had streamed. A
        // beat of empty rail is the honest state here; the alternative is the
        // screen quoting a figure the app knows is wrong.
        if (replaced && _streamed) {
          _streamed = false;
          retireLiveReply();
        }
      case AiStepEvent(:final tool, :final status):
        _slowTurnTimer?.cancel();
        if (_turnSlow) _turnSlow = false;
        // Only a RUNNING step names the rail. On ok/error the step is cleared
        // so the label falls back to the phase, rather than leaving a finished
        // step's line on screen claiming work that has already stopped.
        _stepTool = status == AiStepStatus.running ? tool : null;
        _notify();
      case AiDeltaEvent(:final text):
        _slowTurnTimer?.cancel();
        if (_turnSlow) _turnSlow = false;
        _streamed = true;
        _liveTargetChars.addAll(text.characters);
        _ensureRevealTicker();
    }
  }

  void _ensureRevealTicker() {
    if (_revealTicker != null || _disposed) return;
    _revealTicker = _vsync.createTicker(_onRevealTick)..start();
  }

  /// The pacer's per-frame step: a small floor keeps the write visibly moving
  /// between network chunks; the exponential term drains any accumulated
  /// backlog within a handful of frames, so the display tracks the server
  /// closely no matter how bursty the deltas are. At 60fps this reads as
  /// fast, fluid typing — never a crawl, never an instant dump.
  void _onRevealTick(Duration elapsed) {
    if (_disposed) return;
    final remaining = _liveTargetChars.length - _liveShownChars;
    if (remaining <= 0) return;
    // ~1 char/frame once caught up, with a gentle exponential catch-up so a
    // big buffered delta still drains within a few frames rather than lagging
    // seconds behind.
    final step = math.max(1, remaining >> 4);
    final next = math.min(_liveTargetChars.length, _liveShownChars + step);
    _liveShownChars = next;
    _liveText = _liveTargetChars.take(next).join();
    _notify();
    // Per-frame pin while the reply writes itself — instant, so the newest
    // line stays glued to the composer without a tween restarting each frame.
    onContentGrew?.call(instant: true);
    if (next >= _liveTargetChars.length) {
      // Fully caught up — idle the ticker until the next delta arrives.
      _revealTicker?.dispose();
      _revealTicker = null;
    }
  }

  /// Tears down the live bubble once the durable reply is on screen: stops
  /// the reveal ticker and drops the provisional text so exactly ONE copy of
  /// the reply remains.
  void retireLiveReply() {
    _revealTicker?.dispose();
    _revealTicker = null;
    if (_disposed) return;
    _liveText = '';
    _liveTargetChars.clear();
    _liveShownChars = 0;
    _notify();
  }

  // ---- Proposal cards ------------------------------------------------------

  /// Optimistic client-side resolution of proposal cards, keyed by actionId,
  /// so a card collapses the instant the user taps (before the stream echoes).
  final Map<String, AiActionStatus> _resolved = {};
  Map<String, AiActionStatus> get resolved => _resolved;

  Future<void> confirm(String conversationId, String actionId) async {
    _resolved[actionId] = AiActionStatus.applied;
    _notify();
    try {
      await _ai.confirmAction(
        conversationId: conversationId,
        actionId: actionId,
      );
    } catch (_) {
      if (_disposed) return;
      _resolved.remove(actionId);
      _notify();
      onError?.call("Couldn't do that just now. Try again.");
    }
  }

  Future<void> cancel(String conversationId, String actionId) async {
    _resolved[actionId] = AiActionStatus.cancelled;
    _notify();
    try {
      await _ai.cancelAction(
        conversationId: conversationId,
        actionId: actionId,
      );
    } catch (_) {
      if (_disposed) return;
      _resolved.remove(actionId);
      _notify();
      onError?.call("Couldn't do that just now. Try again.");
    }
  }

  // ---- Voice ---------------------------------------------------------------

  bool _recording = false;
  bool _transcribing = false;
  int _transcribeToken = 0;

  /// True while a voice note is being recorded (mic tapped, not yet stopped).
  bool get recording => _recording;

  /// True while a just-stopped recording is being transcribed — the composer
  /// shows its honest "Transcribing…" state with an escape hatch.
  bool get transcribing => _transcribing;

  /// Tap-to-toggle: not recording → request permission and start; recording →
  /// stop and transcribe. A denied permission, a missing recorder, or a
  /// recorder failure surfaces through [onError] and leaves the composer
  /// untouched — never a thrown error.
  Future<void> toggleMic() async {
    final recorder = _recorder;
    if (recorder == null) {
      _handleSttOutcome(
        const SttFailed(
          SttError.unknown,
          "Voice input isn't available right now.",
        ),
      );
      return;
    }
    if (_recording) {
      // Flip straight into the transcribing state so the composer never
      // flashes back to idle between stopping and the request going out.
      _recording = false;
      _transcribing = true;
      _notify();
      RecordedAudio? audio;
      try {
        audio = await recorder.stop();
      } catch (_) {
        audio = null;
      }
      if (audio == null) {
        if (_disposed) return;
        _transcribing = false;
        _notify();
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

    bool granted;
    try {
      granted = await recorder.ensurePermission();
    } catch (_) {
      granted = false;
    }
    if (_disposed) return;
    if (!granted) {
      _handleSttOutcome(
        const SttFailed(
          SttError.microphonePermissionDenied,
          'Turn on microphone access to use voice input.',
        ),
      );
      return;
    }
    try {
      await recorder.start();
    } catch (_) {
      if (_disposed) return;
      _handleSttOutcome(
        const SttFailed(
          SttError.recordingFailed,
          "Couldn't start the microphone — try again.",
        ),
      );
      return;
    }
    if (_disposed) return;
    _recording = true;
    _notify();
  }

  /// Discards the in-progress recording without transcribing it.
  Future<void> cancelRecording() async {
    _recording = false;
    _notify();
    try {
      await _recorder?.cancel();
    } catch (_) {
      // Discarding is best-effort — nothing to surface.
    }
  }

  /// Discards a clip mid-transcription: the composer unlocks immediately and
  /// any outcome from this attempt is ignored via the token.
  void cancelTranscription() {
    _transcribeToken++;
    _transcribing = false;
    _notify();
  }

  /// Sends [audio] to `ai.transcribe` and, on success, drops the transcript
  /// into the composer for the user to edit/send — never auto-sent. A hung
  /// request times out into a friendly failure instead of locking the
  /// composer forever; a cancelled attempt is ignored by token.
  Future<void> _transcribe(RecordedAudio audio) async {
    final token = ++_transcribeToken;
    _transcribing = true;
    _notify();
    SttOutcome outcome;
    try {
      outcome = await _withTimeout(
        _ai.transcribe(audioBytes: audio.bytes, mimeType: audio.mimeType),
        transcribeTimeout,
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
    if (_disposed || token != _transcribeToken) return;
    _transcribing = false;
    _notify();
    _handleSttOutcome(outcome);
  }

  /// Races [future] against [limit]: resolves with the future's outcome, a
  /// typed [SttFailed] from [onTimeout] if it settles too slowly, or one from
  /// [onFailure] if it throws. Hand-rolled rather than `Future.timeout` so
  /// the outcome never depends on a concrete implementation's reified
  /// generic type.
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
        fillComposer(text, collapseSelection: true);
      case SttFailed(:final message):
        if (_disposed) return;
        onError?.call(message);
    }
  }

  // ---- Lifecycle -----------------------------------------------------------

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _slowTurnTimer?.cancel();
    _landingWatchdog?.cancel();
    _revealTicker?.dispose();
    input.dispose();
    super.dispose();
  }
}
