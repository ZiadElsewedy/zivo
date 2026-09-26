import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/audio_recorder.dart';
import '../../../../core/util/parse.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/body_data_writer.dart';
import '../../domain/ai_choice_request.dart';
import '../../domain/ai_conversation.dart';
import '../../domain/ai_failure.dart';
import '../../domain/ai_message.dart';
import '../../domain/ai_pending_action.dart';
import '../../domain/ai_repository.dart';
import '../../domain/ai_model_selection.dart';
import '../../domain/ai_response_style.dart';
import '../../domain/ai_role.dart';
import '../../domain/ai_turn_event.dart';
import '../../domain/stt_error.dart';
import '../../domain/stt_outcome.dart';
import '../ai_thought.dart';
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
    required AppLocalizations strings,
    BodyDataWriter? bodyWriter,
    this.onError,
    this.onContentGrew,
    this.onSendStarted,
  }) : // An initializing formal would have to be `this._ai`, and a named
       // parameter cannot start with an underscore — so these stay plain
       // assignments.
       // ignore: prefer_initializing_formals
       _bodyWriter = bodyWriter,
       // ignore: prefer_initializing_formals
       _strings = strings,
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

  /// Persists whitelisted `request_input` values (height, weight) to the user's
  /// own body data so the coach asks once (Phase 3). Null in scopes/tests that
  /// don't wire it — persistence is then simply skipped and the value still
  /// reaches the coach as the submitted summary turn.
  final BodyDataWriter? _bodyWriter;

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
  String _modelSelection = kDefaultAiModelSelection;
  String? _draftTitle;

  /// The localized copy this controller hands to [onError] and renders on the
  /// thinking rail.
  ///
  /// ADR-008's rule is that a controller never holds a `BuildContext` — it says
  /// nothing about a value object. [AppLocalizations] is one: no element, no
  /// lifecycle, and nothing to go stale except the locale, which is what
  /// [updateStrings] is for. The page refreshes it from
  /// `didChangeDependencies`, so switching language mid-chat re-renders the
  /// rail in the new one.
  AppLocalizations _strings;

  /// Re-points this controller at the current locale's copy. Cheap and
  /// idempotent; call it whenever `Localizations` may have changed.
  void updateStrings(AppLocalizations strings) => _strings = strings;

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

  /// The user's saved model selection ('auto'|'claude'|'gemini'), forwarded on
  /// every [send] so the gateway routes the turn to the chosen provider.
  String get modelSelection => _modelSelection;

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
    final modelSelectionFuture = _ai.getModelSelection();
    final latest = await latestFuture;
    final style = await responseStyleFuture;
    final model = await modelSelectionFuture;
    if (_disposed || _activeResolved) return;
    _activeConversationId = latest?.id;
    _activeIsUntitled = latest?.title == kUntitledConversationTitle;
    _activeResolved = true;
    _responseStyle = validResponseStyle(style);
    _modelSelection = validAiModelSelection(model);
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
    _activity.clear();
    _resetLive();
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
    return (
      id: latest.id,
      isUntitled: latest.title == kUntitledConversationTitle,
    );
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
      onError?.call(_strings.askSaveFailed);
    }
  }

  /// Adopts a model the user already saved elsewhere (the shared model
  /// sheet persists its own pick) — updates what this controller sends and
  /// shows, without writing it a second time.
  void adoptModelSelection(String selection) {
    final valid = validAiModelSelection(selection);
    if (valid == _modelSelection) return;
    _modelSelection = valid;
    _notify();
  }

  /// Picks the model/provider for future turns — applied optimistically (the
  /// next send uses it immediately) and persisted in the background; rolled
  /// back with an error if the save fails. Mirrors [setResponseStyle].
  Future<void> setModelSelection(String selection) async {
    final previous = _modelSelection;
    if (selection == previous) return;
    _modelSelection = selection;
    _notify();
    try {
      await _ai.setModelSelection(selection);
    } catch (_) {
      if (_disposed) return;
      _modelSelection = previous;
      _notify();
      onError?.call(_strings.askSaveFailed);
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
  final List<AiActivityStep> _activity = [];
  bool _turnSlow = false;
  Timer? _slowTurnTimer;
  Timer? _landingWatchdog;
  String? _pendingText;
  bool _sendFailed = false;
  AiFailure _sendFailure = const AiFailure(AiFailureKind.network);
  // The text of the turn in flight / last failed — kept apart from
  // [_pendingText] because the optimistic bubble is cleared as soon as the
  // server persists the user message, which it does BEFORE calling the model.
  // A turn that then fails on the model left Retry with nothing to send (it
  // read [_pendingText], already null) — the "Retry does nothing" bug.
  String? _turnText;

  /// The tapped answer the current turn carries, if it answers a question
  /// card — kept with [_turnText] so [retry] re-sends the same structured
  /// pick, not just its label.
  AiChoiceSelection? _turnChoice;

  /// The screen Ask was just opened from ([openedFrom]), not yet sent.
  String? _entryPoint;

  /// The entry point the current turn carries — kept with [_turnText] so
  /// [retry] routes the same way.
  String? _turnEntryPoint;
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

  /// Why the most recent send failed — picks the retry card's words ("Claude
  /// isn't available: usage limit reached" reads differently from "couldn't
  /// reach ZIVO"). Only meaningful while [sendFailed].
  AiFailure get sendFailure => _sendFailure;

  /// Client-generated idempotency key for the in-flight turn.
  String? get activeTurnId => _activeTurnId;

  /// The tool the gateway is running right now, or null between steps. Exposed
  /// mainly so tests can assert the rail follows the real loop.
  String? get stepTool => _stepTool;

  /// The in-flight turn's activity timeline: every read tool the gateway has
  /// started, in order, each with its latest status. Kept after the turn
  /// ends (until the next send) so the live reply keeps its timeline until
  /// the durable message — which carries the same list — replaces it.
  List<AiActivityStep> get activity => List.unmodifiable(_activity);

  /// The live thought line — what ZIVO is doing right now, in the user's
  /// terms. A running step wins over the phase, because "Reading your meal
  /// plan…" says more than "Thinking…"; the phase is the fallback before the
  /// first lookup, between lookups ("Analyzing what I found…"), and while a
  /// change is drafted.
  ///
  /// Localized through the [AppLocalizations] the page hands in
  /// (`updateStrings`) — the controller has no `BuildContext` by design
  /// (ADR-008). The words live on the client (`ai_thought.dart`) so they stay
  /// localizable and can change without a functions deploy; the gateway only
  /// ever names the tool, and an unknown one reads as "Thinking…" — never as
  /// its identifier.
  String get railLabel {
    final step = _stepTool;
    if (step != null) return aiThoughtLiveLabel(_strings, step);
    return switch (_phase) {
      AiPhase.thinking => _strings.askThoughtAnalyzingResults,
      AiPhase.preparingChange => _strings.askPreparingChange,
      _ => _strings.askThinking,
    };
  }

  /// The kind of work behind [railLabel] — what tints the live line.
  AiThoughtKind get railThought {
    final step = _stepTool;
    if (step != null) return aiThoughtKindForTool(step);
    return switch (_phase) {
      AiPhase.thinking => AiThoughtKind.analyzing,
      AiPhase.preparingChange => AiThoughtKind.preparing,
      _ => AiThoughtKind.thinking,
    };
  }

  /// True while reply text is actively arriving — the caret is then the live
  /// signal and the thought line steps aside. Goes false the moment a lookup
  /// starts, a new step begins, or text has been quiet for [kWritingIdle]
  /// (the model is composing a tool call after a lead-in sentence), so the
  /// screen is never a still paragraph with nothing saying ZIVO is working.
  bool get writing => _writing;
  bool _writing = false;
  Timer? _writingIdle;

  void _setWriting(bool value) {
    _writingIdle?.cancel();
    if (value) {
      _writingIdle = Timer(kWritingIdle, () {
        if (_disposed || !_writing) return;
        _writing = false;
        _notify();
      });
    }
    _writing = value;
  }

  /// Ask was opened from [entryPoint] (e.g. 'readiness'). The NEXT turn tells
  /// the server, so a bare "why?" is read as a question about that screen;
  /// one turn only — after it, the conversation carries its own context.
  void openedFrom(String entryPoint) => _entryPoint = entryPoint;

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
  Future<void> send({AiChoiceSelection? choice}) async {
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
    final entryPoint = _entryPoint;
    _entryPoint = null;
    _notify();
    await runSend(conversationId, text, choice: choice, entryPoint: entryPoint);
  }

  /// Fills the composer with an empty-state suggestion and sends it —
  /// setting the controller text fires the listener synchronously, so
  /// [canSend] is already true by the time [send]'s guard runs.
  void sendSuggestion(String text) {
    input.text = text;
    send();
  }

  /// Re-sends the last failed turn's text, with the model that is active
  /// NOW — so "Claude isn't available → switch to Gemini → Retry" works.
  ///
  /// It reuses [activeTurnId], so the server treats this as the same logical
  /// turn: if the user message already landed (the model failed after the
  /// server saved it), the server skips re-appending it and just runs the
  /// model; if nothing landed (a network failure), it appends it once. Either
  /// way a retry can never double-post the message.
  Future<void> retry(String conversationId) async {
    final text = _pendingText ?? _turnText;
    if (text == null || _sending) return;
    await runSend(
      conversationId,
      text,
      choice: _turnChoice,
      entryPoint: _turnEntryPoint,
    );
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

  Future<void> runSend(
    String conversationId,
    String text, {
    AiChoiceSelection? choice,
    String? entryPoint,
  }) async {
    _turnText = text;
    _turnChoice = choice;
    _turnEntryPoint = entryPoint;
    _slowTurnTimer?.cancel();
    _landingWatchdog?.cancel();
    _sending = true;
    _expectReveal = true;
    _phase = null;
    _stepTool = null;
    _activity.clear();
    _resetLive();
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
    // The active model is one setting shared by every AI feature, and it can
    // be switched outside this tab (the plan screens' "Switch model"). Re-read
    // it so chat never sends a stale choice. Best-effort: offline, the choice
    // this controller already holds is used.
    try {
      final saved = validAiModelSelection(await _ai.getModelSelection());
      if (!_disposed) _modelSelection = saved;
    } catch (_) {}
    // Reply style is set in Settings → AI, outside this tab — same re-read.
    try {
      final style = validResponseStyle(await _ai.getResponseStyle());
      if (!_disposed) _responseStyle = style;
    } catch (_) {}
    try {
      await _ai.send(
        conversationId: conversationId,
        text: text,
        clientTurnId: _activeTurnId,
        choice: choice,
        entryPoint: entryPoint,
        onEvent: _onTurnEvent,
        responseStyle: _responseStyle,
        modelSelection: _modelSelection,
      );
    } catch (error) {
      _slowTurnTimer?.cancel();
      _revealTicker?.dispose();
      _revealTicker = null;
      if (!_disposed) {
        _sending = false;
        _sendFailed = true;
        // The repository hands back an [AiFailure]; anything else (a stream
        // torn down mid-turn) is treated as the connection it most likely was.
        _sendFailure = error is AiFailure
            ? error
            : const AiFailure(AiFailureKind.network);
        _turnSlow = false;
        _phase = null;
        _stepTool = null;
        _activity.clear();
        _resetLive();
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
    _setWriting(false);
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
      _sendFailure = const AiFailure(AiFailureKind.network);
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
  // and a ticker reveals them at a rate measured in characters per SECOND —
  // not per frame, so a 120Hz display writes at the same pace as a 60Hz one.
  // The rate rises with the backlog, so a burst that arrives after a long
  // lookup unrolls over about half a second instead of landing all at once,
  // and the text never trails the network by much more than that.

  String _liveText = '';
  bool _streamed = false;
  bool _expectReveal = false;
  final List<String> _liveTargetChars = [];
  int _liveShownChars = 0;
  Ticker? _revealTicker;
  Duration? _lastRevealTick;
  double _revealCarry = 0;

  /// Where the current agent step's text begins in [_liveTargetChars]. A
  /// model fallback supersedes only what the failed attempt wrote in THIS
  /// step — the lead-in an earlier step already wrote stays on screen.
  int _stepStartChars = 0;

  void _resetLive() {
    _liveText = '';
    _liveTargetChars.clear();
    _liveShownChars = 0;
    _stepStartChars = 0;
    _revealCarry = 0;
    _setWriting(false);
  }

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

  /// Everything streamed for the live reply so far, revealed or not — the
  /// live bubble takes its paragraph direction from this, not from the
  /// half-written [liveText], so it doesn't flip mid-reveal.
  String get liveTargetText => _liveTargetChars.join();

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
        // A new agent step starts here: its text (if any) begins a new
        // paragraph, and a fallback inside it truncates back to this point.
        if (phase == AiPhase.thinking) {
          _stepStartChars = _liveTargetChars.length;
          _setWriting(false);
        }
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
        if (status == AiStepStatus.running) _setWriting(false);
        _recordStep(tool, status);
        _notify();
      case AiFallbackEvent(:final from, :final to):
        _slowTurnTimer?.cancel();
        if (_turnSlow) _turnSlow = false;
        if (!_activity.any(
          (s) => s.fallbackFrom == from && s.fallbackTo == to,
        )) {
          _activity.add(AiActivityStep.fallback(from, to));
        }
        // Whatever the failed model streamed in this step is superseded by
        // the fallback's answer — drop it so the reply isn't written twice,
        // but keep what earlier steps already said.
        _truncateLiveTo(_stepStartChars);
        _setWriting(false);
        _notify();
      case AiDeltaEvent(:final text):
        _slowTurnTimer?.cancel();
        if (_turnSlow) _turnSlow = false;
        _streamed = true;
        _liveTargetChars.addAll(text.characters);
        final wasWriting = _writing;
        _setWriting(true);
        if (!wasWriting) _notify();
        _ensureRevealTicker();
      case AiReplaceEvent(:final text):
        _slowTurnTimer?.cancel();
        if (_turnSlow) _turnSlow = false;
        _replaceLive(text);
        _notify();
    }
  }

  /// The server superseded text already streamed (a retried attempt, or a
  /// restated lead-in) and sent the whole reply as it reads now. The part it
  /// shares with what's on screen stays put — a retry that reproduces the
  /// same words continues without a flicker — and only what differs is
  /// rewritten. Replaces, never appends: the reply can't restart on screen.
  void _replaceLive(String text) {
    final next = text.characters.toList();
    var shared = 0;
    final limit = math.min(next.length, _liveTargetChars.length);
    while (shared < limit && next[shared] == _liveTargetChars[shared]) {
      shared++;
    }
    _liveTargetChars
      ..removeRange(shared, _liveTargetChars.length)
      ..addAll(next.skip(shared));
    _liveShownChars = math.min(_liveShownChars, shared);
    _stepStartChars = math.min(_stepStartChars, _liveTargetChars.length);
    _liveText = _liveTargetChars.take(_liveShownChars).join();
    _streamed = _liveTargetChars.isNotEmpty;
    if (_liveShownChars < _liveTargetChars.length) {
      _setWriting(true);
      _ensureRevealTicker();
    }
  }

  /// Folds one step event into [_activity]: a start appends a running entry;
  /// a finish settles the latest still-running entry for that tool (the same
  /// tool can legitimately run twice in one turn). A finish with no matching
  /// start — its opening event was dropped — is still recorded, so the
  /// timeline never under-reports work that happened.
  void _recordStep(String tool, AiStepStatus status) {
    if (status == AiStepStatus.running) {
      _activity.add(AiActivityStep(tool, status));
      return;
    }
    final i = _activity.lastIndexWhere(
      (s) => s.tool == tool && s.status == AiStepStatus.running,
    );
    if (i == -1) {
      _activity.add(AiActivityStep(tool, status));
    } else {
      _activity[i] = AiActivityStep(tool, status);
    }
  }

  /// Drops live text back to [chars] (a superseded attempt), keeping what
  /// came before it.
  void _truncateLiveTo(int chars) {
    final keep = math.max(0, math.min(chars, _liveTargetChars.length));
    if (keep == _liveTargetChars.length) return;
    _liveTargetChars.removeRange(keep, _liveTargetChars.length);
    _liveShownChars = math.min(_liveShownChars, keep);
    _liveText = _liveTargetChars.take(_liveShownChars).join();
    if (_liveTargetChars.isEmpty) _streamed = false;
  }

  void _ensureRevealTicker() {
    if (_revealTicker != null || _disposed) return;
    _lastRevealTick = null;
    _revealTicker = _vsync.createTicker(_onRevealTick)..start();
  }

  /// The pacer's step. [kRevealFloorCps] keeps the write visibly moving
  /// between network chunks; the backlog term drains any accumulation within
  /// [kRevealCatchUp], so the display tracks the server closely however bursty
  /// the deltas are — never a crawl, never an instant dump.
  void _onRevealTick(Duration elapsed) {
    if (_disposed) return;
    final remaining = _liveTargetChars.length - _liveShownChars;
    if (remaining <= 0) return;
    final last = _lastRevealTick;
    _lastRevealTick = elapsed;
    // The first frame writes one frame's worth; a long gap (the app was
    // paused) is clamped so it can't dump the whole backlog in one frame.
    final dt = last == null
        ? 1 / 60
        : math.min((elapsed - last).inMicroseconds / 1e6, 0.05);
    final catchUpSeconds =
        kRevealCatchUp.inMicroseconds / Duration.microsecondsPerSecond;
    final cps = math.max(kRevealFloorCps, remaining / catchUpSeconds);
    _revealCarry += cps * dt;
    final step = _revealCarry.floor();
    if (step < 1) return;
    _revealCarry -= step;
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
      _revealCarry = 0;
    }
  }

  /// Tears down the live bubble once the durable reply is on screen: stops
  /// the reveal ticker and drops the provisional text so exactly ONE copy of
  /// the reply remains.
  void retireLiveReply() {
    _revealTicker?.dispose();
    _revealTicker = null;
    if (_disposed) return;
    _resetLive();
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
      onError?.call(_strings.askActionFailed);
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
      onError?.call(_strings.askActionFailed);
    }
  }

  // ---- Question cards (Ask elicitation) ------------------------------------

  /// Choice cards answered this session, keyed by requestId → the picked
  /// option's value, so the card settles into its "picked" state the instant
  /// they tap rather than staying live while the answer's turn is on its way.
  /// The durable record is the server's [AiChoiceRequest.selectedValue]; this
  /// only covers the beat before it lands.
  final Map<String, String> _answeredChoices = {};
  Map<String, String> get answeredChoices => _answeredChoices;

  /// The picked option for [request]: this session's tap, else the answer the
  /// server recorded. Null while the question is open.
  String? pickedValueFor(AiChoiceRequest request) =>
      _answeredChoices[request.requestId] ?? request.selectedValue;

  /// Answers a [choice_request] by tap. The turn carries the structured pick
  /// ([AiChoiceSelection] — the card's requestId and the option's stable
  /// [value]); the server resolves it against the stored card and continues
  /// from that exact option (proposing a bound change directly), so nothing
  /// depends on the model re-reading text. [label] is only what the user's
  /// bubble shows. Reuses the whole send path (optimistic bubble, idempotency
  /// key, retry), so a tap behaves like any send.
  ///
  /// Ignored while another turn is still in flight — marking the card picked
  /// then would leave it settled with nothing sent.
  Future<void> answerChoice(String requestId, String value, String label) {
    if (_answeredChoices.containsKey(requestId)) return Future<void>.value();
    _answeredChoices[requestId] = value;
    input.text = label;
    return send(
      choice: AiChoiceSelection(requestId: requestId, value: value),
    );
  }

  /// Input forms (`input_request`) submitted this session, keyed by requestId →
  /// the serialized summary that was sent, so the card settles into a disabled
  /// "sent" state the instant they submit. Session-only, like [answeredChoices].
  final Map<String, String> _submittedInputs = {};
  Map<String, String> get submittedInputs => _submittedInputs;

  /// Answers an [input_request]: persists any whitelisted values (height,
  /// weight) to the user's own body data so the coach asks once, then sends the
  /// [summary] of their entries (e.g. "Height: 180 cm · Weight: 74 kg") as an
  /// ordinary next message — the coach continues from it exactly as if the user
  /// had typed it. [values] maps each field key to its raw entry.
  ///
  /// Persistence is best-effort and never blocks the reply: a value that fails
  /// to save (or has no writer) still reaches the coach as the summary turn.
  Future<void> submitInput(
    String requestId,
    String summary,
    Map<String, String> values,
  ) async {
    if (_submittedInputs.containsKey(requestId)) return;
    _submittedInputs[requestId] = summary;
    _notify();
    // Fire-and-forget: a Firestore write's future resolves only on server ack,
    // so awaiting it would hang the whole reply offline (audit F1 — the app's
    // own capture writes fire-and-forget for the same reason). The value still
    // reaches the coach as the summary turn regardless of whether it persists.
    unawaited(_persistBodyData(values));
    input.text = summary;
    await send();
  }

  /// Writes the height/weight the user typed to their own body data through
  /// [_bodyWriter], keyed by the canonical field keys. Swallows failures — a
  /// remember that didn't land must never stop the coach from replying.
  Future<void> _persistBodyData(Map<String, String> values) async {
    final writer = _bodyWriter;
    if (writer == null) return;
    try {
      final rawHeight = values[kBodyInputHeightCm];
      if (rawHeight != null) {
        final cm = parsePositiveDecimal(rawHeight);
        if (cm != null) await writer.saveHeightCm(cm);
      }
      final rawWeight = values[kBodyInputWeightKg];
      if (rawWeight != null) {
        final kg = parsePositiveDecimal(rawWeight);
        if (kg != null) await writer.saveWeightKg(kg);
      }
    } catch (_) {
      // Best-effort: the value still reaches the coach as the summary turn.
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
        SttFailed(SttError.unknown, _strings.askVoiceUnavailable),
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
          SttFailed(SttError.recordingFailed, _strings.askDidntCatchThat),
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
        SttFailed(
          SttError.microphonePermissionDenied,
          _strings.askMicPermission,
        ),
      );
      return;
    }
    try {
      await recorder.start();
    } catch (_) {
      if (_disposed) return;
      _handleSttOutcome(
        SttFailed(SttError.recordingFailed, _strings.askMicStartFailed),
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
        onTimeout: () =>
            SttFailed(SttError.timeout, _strings.askTranscribeTimeout),
        onFailure: () =>
            SttFailed(SttError.unknown, _strings.askTranscribeFailed),
      );
    } catch (_) {
      outcome = SttFailed(SttError.unknown, _strings.askTranscribeFailed);
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
    _writingIdle?.cancel();
    _landingWatchdog?.cancel();
    _revealTicker?.dispose();
    input.dispose();
    super.dispose();
  }
}
