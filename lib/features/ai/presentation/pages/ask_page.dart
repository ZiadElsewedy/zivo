import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../../shell/presentation/widgets/bottom_chrome.dart';
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

/// Bottom clearance beneath the message list (and empty state) so content
/// scrolls UNDER the floating composer island instead of ending above it —
/// roughly the idle composer's rendered height (≈72) plus a small gap. The
/// composer floats over the list (see [AskPage]'s Stack), so the last line
/// still comes to rest just above it.
const _kComposerFloatClearance = 84.0;

/// The "Ask" chat surface: an iris-themed message list over a pinned
/// composer. Talks only to `AppScope.of(context).ai` — Firebase-free.
class AskPage extends StatefulWidget {
  const AskPage({
    super.key,
    this.transcribeTimeout = _kTranscribeTimeout,
    this.incomingDraft,
  });

  /// Injectable for tests — how long to wait on transcription before
  /// surfacing the timeout failure.
  final Duration transcribeTimeout;

  /// External text drops (voice quick-log): when the shell sets a non-null
  /// value, the composer takes it over as an editable draft. One-shot — the
  /// notifier resets to null after consumption so a repeated log re-triggers.
  final ValueNotifier<String?>? incomingDraft;

  @override
  State<AskPage> createState() => _AskPageState();
}

class _AskPageState extends State<AskPage> with TickerProviderStateMixin {
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
  /// rendered as an optimistic bubble until the durable message lands,
  /// paired to [_activeTurnId] (not to counts or text compares — see
  /// [_userLanded]).
  String? _pendingText;

  /// True when the most recent send attempt threw — shows the retry rail.
  bool _sendFailed = false;

  /// Persisted user-message count captured right before a send starts — the
  /// LEGACY fallback for pairing an optimistic bubble when a persisted
  /// message carries no [AiMessage.clientTurnId] (pre-dedup docs and
  /// turn-less server writes). The turn-id match always wins when present.
  int _baselineUserCount = 0;

  /// The same fallback for ASSISTANT messages — the gate that stops the
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
  /// Both durable messages of the turn carry it; the UI pairs the optimistic
  /// bubbles against it exactly.
  String? _activeTurnId;

  /// The title the user gave this new chat at creation ("Workout
  /// Changes"), used instead of auto-titling from the first message when
  /// the unsaved chat is persisted. Null for the default behavior.
  String? _draftTitle;

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

  /// True between the start and end of a USER-initiated drag (vs a
  /// programmatic scroll). Every automatic pin — auto-follow, the keyboard
  /// re-pin, the streaming reveal — stands down while this is set, so the
  /// list can always be scrolled freely: the finger owns the list.
  bool _userDragging = false;

  /// Display keys whose entrance motion has already played (or was waived as
  /// history). This is the once-only RiseIn ledger: a bubble animates in the
  /// moment it ARRIVES, and never again — not when its optimistic copy swaps
  /// to the durable doc, not when the element is disposed by scrolling out
  /// and rebuilt on the way back. This is what keeps scrolling feeling solid
  /// instead of replaying entrances forever.
  final Set<String> _entrancePlayed = {};

  /// The conversation the entrance ledger was seeded for — the first
  /// snapshot of a thread is all HISTORY (cold load), rendered settled with
  /// zero entrances; anything arriving afterwards is news and rises in once.
  String? _entranceSeededFor;

  /// The stable identity of a message ON SCREEN. Both sides of an in-flight
  /// turn share [AiMessage.clientTurnId], so the optimistic user bubble and
  /// ZIVO's provisional live reply carry the SAME display key as their
  /// durable copies — the swap is invisible: same widget at the same slot,
  /// no second entrance. Role-scoped ('u:'/'a:') because both halves of a
  /// turn share one turn id; legacy/turnless messages fall back to their id.
  String _displayKey(AiMessage m) => switch ((m.clientTurnId, m.role)) {
    (final String t, AiRole.user) => 'u:$t',
    (final String t, AiRole.assistant) => 'a:$t',
    _ => 'm:${m.id}',
  };

  /// The turn's last assistant message is typing itself in right now (the
  /// buffered/non-streaming fallback). Keyed by display id and REMOVED only
  /// when [_TypewriterText] reports completion — so an interleaved rebuild
  /// (a snapshot emission, the send completing, a keyboard frame) can never
  /// swap the half-typed bubble for static text mid-reveal. That mid-type
  /// swap was the "reply pops in twice" glitch, seen again and again.
  final Set<String> _revealActive = {};

  Stream<List<AiMessage>>? _messagesStream;
  String? _streamConversationId;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final canSend = _input.text.trim().isNotEmpty;
      if (canSend != _canSend) setState(() => _canSend = canSend);
    });
    widget.incomingDraft?.addListener(_onIncomingDraft);
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      _autoFollow = p.pixels >= p.maxScrollExtent - 120;
    });
  }

  /// Consumes a shell-initiated draft (voice quick-log): drops it into the
  /// composer as editable text — never auto-sent — and clears the notifier
  /// so the next log re-triggers even if identical.
  void _onIncomingDraft() {
    final text = widget.incomingDraft?.value;
    if (text == null || !mounted) return;
    widget.incomingDraft!.value = null;
    setState(() {
      _input.text = text.trim();
      _canSend = _input.text.trim().isNotEmpty;
    });
  }

  @override
  void didUpdateWidget(covariant AskPage old) {
    super.didUpdateWidget(old);
    if (widget.incomingDraft != old.incomingDraft) {
      old.incomingDraft?.removeListener(_onIncomingDraft);
      widget.incomingDraft?.addListener(_onIncomingDraft);
    }
  }

  @override
  void dispose() {
    widget.incomingDraft?.removeListener(_onIncomingDraft);
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
    // One optimistic slot, one durable pairing: block a second send until
    // the previous turn's user message has actually landed (or failed).
    // In practice the server persists the user message before any reply
    // delta streams, so this never blocks a real queueing rhythm — it only
    // closes the window where a fast second send would overwrite the first
    // turn's unlanded optimistic bubble.
    if (_pendingText != null && !_sendFailed) return;
    final text = _input.text;
    _input.clear();

    var conversationId = _activeConversationId;
    var draftTitle = _draftTitle;
    if (conversationId == null) {
      final ai = AppScope.of(context).ai;
      conversationId = await ai.createConversation(title: draftTitle);
      if (!mounted) return;
      _activeIsUntitled = draftTitle == null || draftTitle.trim().isEmpty;
      draftTitle = null; // consumed — no auto-title on top of it
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
    // auto-title — fired alongside the send, not blocking it. A chat the
    // user named at creation keeps its name instead.
    if (baselineUserCount == 0 && _activeIsUntitled && draftTitle == null) {
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
      _draftTitle = null;
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

  /// Whether the durable copy of the in-flight turn's [role] message has
  /// landed in the watch snapshot. The PRIMARY signal is exact: both sides
  /// of a turn carry the same [AiMessage.clientTurnId], so pairing by it can
  /// never desync the way counts and text compares could (stale cache
  /// snapshots, baseline drift, whitespace variants) — which is exactly what
  /// made a sent message and ZIVO's reply show up twice. The count checks
  /// remain only as a fallback for snapshots whose messages predate turn
  /// dedup and carry no turn id.
  bool _turnLanded(AiRole role) {
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
      _draftTitle = null;
      _lastPersisted = const [];
      _autoFollow = true;
      _userDragging = false;
      _entrancePlayed.clear();
      _entranceSeededFor = null;
      _revealActive.clear();
    });
  }

  /// Starts a new, unsaved chat — no Firestore write until [_send] actually
  /// fires the first message. Offers an optional name first ("Workout
  /// Changes") so the chat is findable in history later; a blank name keeps
  /// today's auto-title-from-first-message behavior.
  Future<void> _newChat() async {
    final name = await _promptNewChatName(context);
    if (!mounted) return;
    final trimmed = name?.trim();
    _switchTo(null, isUntitled: true);
    if (trimmed != null && trimmed.isNotEmpty) {
      setState(() => _draftTitle = trimmed);
    }
  }

  Future<void> _openSessions(String? activeConversationId) async {
    final result = await showModalBottomSheet<_SessionsSelection>(
      context: context,
      backgroundColor: TrainColors.raised,
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
      case AiPhaseEvent(:final phase, :final replaced):
        _slowTurnTimer?.cancel();
        if (_turnSlow) setState(() => _turnSlow = false);
        setState(() => _phase = phase);
        // The server's validator threw this reply away. The draft is still on
        // screen — so drop it now rather than let the user go on reading
        // numbers the gateway has already ruled invented, and let the durable
        // (deterministic) reply type itself in as if nothing had streamed. A
        // beat of empty rail is the honest state here; the alternative is the
        // screen quoting a figure the app knows is wrong.
        if (replaced && _streamed) {
          _streamed = false;
          _retireLiveReply();
        }
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
    // A calmer, more human cadence than a fast dump: reveal ~1 char/frame
    // (~60/s) once caught up, with a gentle exponential catch-up (remaining
    // >> 4) so a big buffered delta still drains within a few frames rather
    // than lagging seconds behind. Slower than the old max(4, remaining >> 3),
    // which read as "instant" on short replies.
    final step = math.max(1, remaining >> 4);
    final next = math.min(_liveTargetChars.length, _liveShownChars + step);
    if (!mounted) return;
    setState(() {
      _liveShownChars = next;
      _liveText = _liveTargetChars.take(next).join();
    });
    // Per-frame pin while the reply writes itself — instant, so the newest
    // line stays glued to the composer without a tween restarting each frame.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeAutoScroll(instant: true),
    );
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
  /// → stop and transcribe. A denied permission, a missing recorder, or a
  /// recorder/plugin failure shows a toast and leaves the composer
  /// untouched — never a thrown error.
  Future<void> _toggleMic() async {
    final recorder = AppScope.of(context).recorder;
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
      setState(() {
        _recording = false;
        _transcribing = true;
      });
      RecordedAudio? audio;
      try {
        audio = await recorder.stop();
      } catch (_) {
        audio = null;
      }
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

    bool granted;
    try {
      granted = await recorder.ensurePermission();
    } catch (_) {
      granted = false;
    }
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
    try {
      await recorder.start();
    } catch (_) {
      if (!mounted) return;
      _handleSttOutcome(
        const SttFailed(
          SttError.recordingFailed,
          "Couldn't start the microphone — try again.",
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _recording = true);
  }

  /// Discards the in-progress recording without transcribing it.
  Future<void> _cancelRecording() async {
    final recorder = AppScope.of(context).recorder;
    setState(() => _recording = false);
    try {
      await recorder?.cancel();
    } catch (_) {
      // Discarding is best-effort — nothing to surface.
    }
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

  /// Whether the list is at rest and safe to pin.
  ///
  /// A pin during a live scroll cancels the activity that owns the position,
  /// which stops the list dead under the thumb — the "stuck" scroll. A
  /// rubber-band overscroll is the case that bit hardest: it is a ballistic
  /// activity like any other, and cutting it short leaves the list parked
  /// off its own end. Let whatever is in flight land; the next metrics
  /// change re-pins.
  bool get _restingAtPinnableOffset {
    if (!_scroll.hasClients || _userDragging) return false;
    final p = _scroll.position;
    return p.pixels <= p.maxScrollExtent && p.pixels >= p.minScrollExtent;
  }

  void _scrollToBottom({bool instant = false}) {
    if (!_restingAtPinnableOffset) return;
    final target = _scroll.position.maxScrollExtent;
    if (reducedMotion(context) || instant) {
      _scroll.jumpTo(target);
      return;
    }
    // Already there (or within a hair of it) — starting a tween would begin a
    // driven activity for nothing, and a driven scroll reports itself as a
    // non-drag scroll start, which is precisely what used to clear
    // [_userDragging] mid-stream and re-open the door to the pin fight below.
    if ((target - _scroll.position.pixels).abs() < 1) return;
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Follows new content to the bottom only if the user hasn't scrolled
  /// away — never yanks them down mid-read, and resumes following once
  /// they scroll back near the bottom themselves. [instant] pins without
  /// an animation (per-frame streaming reveal, keyboard re-pin), where a
  /// restarted tween every frame would stutter and fight the list.
  void _maybeAutoScroll({bool instant = false}) {
    if (_autoFollow) _scrollToBottom(instant: instant);
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
    // This only works because the SHELL doesn't take the inset first: a
    // resizing scaffold above this one strips `viewInsets` from the body's
    // MediaQuery, which left `keyboardInset` stuck at the chrome height and
    // the composer floating a nav-island above the keyboard. See
    // `home_shell.dart`'s `resizeToAvoidBottomInset: false`.
    // With the keyboard down the composer rests on top of the shell's bottom
    // object — nav island plus the fused now-playing strip — rather than on
    // the raw safe area, which put it *inside* the nav's band and let the
    // island paint over its lower edge. With the keyboard up it rides the
    // keyboard, which already covers the bottom bar.
    final keyboardInset = math.max(
      media.viewInsets.bottom,
      BottomChrome.of(context),
    );
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: TrainColors.base,
      body: DecoratedBox(
        // The chat's atmosphere: the ONE soft radial glow this screen gets
        // (identity §5), violet because violet is the assistant's own hue.
        // The two extra aura blobs are gone — one glow per screen.
        decoration: const BoxDecoration(gradient: TrainColors.askTint),
        child: Stack(
          children: [
            SafeArea(
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
                      // The composer floats OVER the conversation (a Stack), not
                      // docked beneath it (a Column) — so messages scroll under the
                      // frosted island, reading as a layer above the chat. The list
                      // pads its bottom by [_kComposerFloatClearance] so the newest
                      // line still rests just above the composer.
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: FutureBuilder<void>(
                              future: _initialLoad,
                              builder: (context, _) {
                                if (!_activeResolved) {
                                  return const SizedBox.shrink();
                                }
                                final conversationId = _activeConversationId;
                                if (conversationId == null) {
                                  // An unsaved "New chat" — nothing persisted yet, so
                                  // there's no message stream to watch.
                                  return _EmptyAsk(
                                    onSuggestion: _sendSuggestion,
                                  );
                                }
                                final ai = AppScope.of(context).ai;
                                if (_messagesStream == null ||
                                    _streamConversationId != conversationId) {
                                  _streamConversationId = conversationId;
                                  _messagesStream = ai.watchMessages(
                                    conversationId,
                                  );
                                }
                                return StreamBuilder<List<AiMessage>>(
                                  stream: _messagesStream,
                                  builder: (context, snapshot) {
                                    _lastPersisted =
                                        snapshot.data ?? const <AiMessage>[];
                                    final displayed = <AiMessage>[
                                      ..._lastPersisted,
                                    ];

                                    // The durable ASSISTANT reply landing gates the
                                    // provisional live bubble — the instant it's in
                                    // the snapshot exactly one copy of the reply
                                    // renders (the persisted one). Paired by turn
                                    // id (see [_turnLanded]), so the window where
                                    // the server writes the reply doc slightly
                                    // before the functions stream closes can never
                                    // duplicate the response — nor can a stale or
                                    // reordered snapshot.
                                    final assistantLanded = _turnLanded(
                                      AiRole.assistant,
                                    );
                                    if (_liveText.isNotEmpty &&
                                        assistantLanded) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => _retireLiveReply(),
                                          );
                                    }

                                    // The optimistic USER bubble "lands" the moment
                                    // its own turn's durable user message shows up
                                    // in the snapshot — state-based pairing, not a
                                    // text/id compare, so it can't mismatch or
                                    // double up.
                                    final pendingLanded =
                                        _pendingText != null &&
                                        (_turnLanded(AiRole.user) ||
                                            _lastPersisted.any(
                                              (m) =>
                                                  m.role == AiRole.user &&
                                                  m.clientTurnId == null &&
                                                  m.content.trim() ==
                                                      _pendingText!.trim(),
                                            ));
                                    if (pendingLanded) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (mounted &&
                                                _pendingText != null) {
                                              setState(() {
                                                _pendingText = null;
                                                _sendFailed = false;
                                              });
                                            }
                                          });
                                    }
                                    if (_pendingText != null &&
                                        !pendingLanded) {
                                      displayed.add(
                                        AiMessage(
                                          id: '_pending',
                                          role: AiRole.user,
                                          content: _pendingText!,
                                          createdAt: DateTime.now(),
                                          clientTurnId: _activeTurnId,
                                        ),
                                      );
                                    }

                                    // The provisional live reply rides INSIDE the
                                    // list as a provisional message carrying its
                                    // turn's clientTurnId — the exact identity its
                                    // durable copy will have. When that copy lands,
                                    // the swap is same widget, same slot, same key:
                                    // element reused, entrance NOT replayed. This is
                                    // what kills the "reply pops in twice" effect.
                                    final liveActive =
                                        !_sendFailed &&
                                        !assistantLanded &&
                                        _liveText.isNotEmpty;
                                    if (liveActive) {
                                      displayed.add(
                                        AiMessage(
                                          id: '_live',
                                          role: AiRole.assistant,
                                          content: _liveText,
                                          createdAt: DateTime.now(),
                                          clientTurnId: _activeTurnId,
                                        ),
                                      );
                                    }
                                    if (displayed.isEmpty &&
                                        !_sending &&
                                        !_sendFailed) {
                                      return _EmptyAsk(
                                        onSuggestion: _sendSuggestion,
                                      );
                                    }
                                    // First snapshot of THIS thread = cold history:
                                    // everything currently persisted is waived from
                                    // entrances so it renders settled — and keeps
                                    // rendering settled on every scroll-back remount.
                                    // Anything arriving AFTER this moment is news
                                    // and rises in exactly once (see itemBuilder).
                                    if (_entranceSeededFor != conversationId) {
                                      _entranceSeededFor = conversationId;
                                      _entrancePlayed.addAll([
                                        for (final m in displayed)
                                          _displayKey(m),
                                      ]);
                                    }
                                    // A turn in flight repaints this list on
                                    // every streamed token, so the follow has
                                    // to be an instant pin: a 220ms tween
                                    // restarted each frame never lands, and
                                    // each restart begins a DRIVEN scroll —
                                    // which announces itself as a non-drag
                                    // scroll start, clearing [_userDragging]
                                    // and letting the metrics pin below cut
                                    // the tween off mid-flight. The two then
                                    // fought for the position every frame,
                                    // which is what read as the chat stuttering
                                    // and sticking while ZIVO replied. The
                                    // eased scroll is kept for the settled
                                    // case, where there is one of them.
                                    final liveTurn = _sending || liveActive;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback(
                                          (_) => _maybeAutoScroll(
                                            instant: liveTurn,
                                          ),
                                        );
                                    final indexByKey = <String, int>{
                                      for (var j = 0; j < displayed.length; j++)
                                        _displayKey(displayed[j]): j,
                                    };
                                    return NotificationListener<Notification>(
                                      // Two jobs, one listener (ScrollMetricsNotification
                                      // is a Notification but not a ScrollNotification):
                                      //
                                      // 1. Drag bookkeeping — mark user-driven scrolls
                                      //    so NO automatic pin ever fights the thumb.
                                      // 2. Metrics changes — content growth or the
                                      //    keyboard's animated inset shrinking the
                                      //    viewport re-pins instantly while following,
                                      //    keeping the newest line glued to the
                                      //    composer without drifting.
                                      onNotification: (notification) {
                                        if (notification
                                            is ScrollStartNotification) {
                                          _userDragging =
                                              notification.dragDetails != null;
                                        } else if (notification
                                            is ScrollUpdateNotification) {
                                          if (notification.dragDetails !=
                                              null) {
                                            _userDragging = true;
                                          }
                                        } else if (notification
                                            is ScrollEndNotification) {
                                          _userDragging = false;
                                        } else if (notification
                                            is ScrollMetricsNotification) {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                if (!mounted || !_autoFollow) {
                                                  return;
                                                }
                                                // Rest check, not just a drag
                                                // check: this also declines to
                                                // pin while a rubber-band
                                                // overscroll is settling, which
                                                // a bare `jumpTo` would cancel
                                                // and leave parked off the end.
                                                if (!_restingAtPinnableOffset) {
                                                  return;
                                                }
                                                final p = _scroll.position;
                                                if (p.maxScrollExtent > 0) {
                                                  _scroll.jumpTo(
                                                    p.maxScrollExtent,
                                                  );
                                                }
                                              });
                                        }
                                        return false;
                                      },
                                      child: ListView.builder(
                                        controller: _scroll,
                                        padding: const EdgeInsets.fromLTRB(
                                          AppSpacing.screen,
                                          AppSpacing.base,
                                          AppSpacing.screen,
                                          // Clear the floating composer that overlays
                                          // the bottom of the list.
                                          _kComposerFloatClearance,
                                        ),
                                        // Lets the framework FIND an item's existing
                                        // element after index shifts (an optimistic
                                        // bubble retiring as durable docs land), so
                                        // stateful children survive instead of being
                                        // torn down and re-animated.
                                        findChildIndexCallback: (key) {
                                          if (key is ValueKey<String>) {
                                            return indexByKey[key.value];
                                          }
                                          return null;
                                        },
                                        // A trailing slot holds only the WAITING
                                        // states now — the phase rail or the retry
                                        // card. The live reply lives in [displayed]
                                        // itself (above), so it and its durable copy
                                        // can never paint as two bubbles.
                                        itemCount:
                                            displayed.length +
                                            ((_sendFailed ||
                                                    (_sending && !liveActive))
                                                ? 1
                                                : 0),
                                        itemBuilder: (context, i) {
                                          if (i >= displayed.length) {
                                            Widget trailing;
                                            if (_sendFailed) {
                                              trailing = _ErrorRetry(
                                                onRetry: () =>
                                                    _retry(conversationId),
                                              );
                                            } else {
                                              trailing = _ThinkingRail(
                                                label: _railLabel(),
                                                slow: _turnSlow,
                                              );
                                            }
                                            // Grouped under the ZIVO label right after
                                            // a user send — mirrors runStart below.
                                            final showIdentity =
                                                displayed.isEmpty ||
                                                displayed.last.role !=
                                                    AiRole.assistant;
                                            if (showIdentity) {
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
                                          final displayKey = _displayKey(
                                            message,
                                          );
                                          final isLast =
                                              i == displayed.length - 1;
                                          // Consume the reveal token ONLY when an
                                          // assistant text message actually takes
                                          // it. Earlier code cleared the flag on
                                          // ANY last-item render — so the
                                          // optimistic USER bubble (last while the
                                          // turn ran) silently burned the token,
                                          // and whether ZIVO's reply ever typed
                                          // depended on microsecond-level event
                                          // ordering.
                                          // `!_streamed` is load-bearing: a reply
                                          // that already streamed token-by-token must
                                          // never ALSO typewriter-reveal on its
                                          // durable copy. Without it, when the
                                          // persisted assistant doc lands before
                                          // `_runSend`'s completion resets
                                          // `_expectReveal`, the same reply animates
                                          // in twice (streamed, then re-typed) — the
                                          // "response appears twice" glitch.
                                          if (isLast &&
                                              _expectReveal &&
                                              !_streamed &&
                                              message.role ==
                                                  AiRole.assistant &&
                                              message.pendingAction == null) {
                                            // The decision lives in [_revealActive]
                                            // until the typewriter FINISHES — not
                                            // in this frame's flag — so later
                                            // rebuilds keep the same widget mounted
                                            // instead of cutting the animation
                                            // short mid-write.
                                            _revealActive.add(displayKey);
                                            _expectReveal = false;
                                          }
                                          final revealing = _revealActive
                                              .contains(displayKey);
                                          // Groups consecutive assistant messages (a bubble
                                          // followed by its proposal card, say) under one
                                          // ZIVO label instead of repeating it per message.
                                          final runStart =
                                              message.role ==
                                                  AiRole.assistant &&
                                              (i == 0 ||
                                                  displayed[i - 1].role !=
                                                      AiRole.assistant);
                                          final action = message.pendingAction;
                                          Widget content;
                                          if (action == null) {
                                            content = _MessageBubble(
                                              message,
                                              animate: revealing,
                                              onRevealDone: revealing
                                                  ? () {
                                                      if (mounted) {
                                                        setState(
                                                          () => _revealActive
                                                              .remove(
                                                                displayKey,
                                                              ),
                                                        );
                                                      }
                                                    }
                                                  : null,
                                              // Only the provisional live bubble
                                              // carries the writing caret.
                                              streaming:
                                                  message.id == '_live' &&
                                                  _liveShownChars <
                                                      _liveTargetChars.length,
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
                                              onCancel: () => _cancel(
                                                conversationId,
                                                action.actionId,
                                              ),
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
                                          // The stable display key rides the item
                                          // itself so [findChildIndexCallback] can
                                          // relocate it after index shifts, and the
                                          // once-only entrance ledger lives INSIDE
                                          // the wrapper (see [_RiseOnce]) so the
                                          // decision never flips between builds.
                                          return KeyedSubtree(
                                            key: ValueKey<String>(displayKey),
                                            child: _RiseOnce(
                                              ledgerKey: displayKey,
                                              played: _entrancePlayed,
                                              child: content,
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: VoiceComposer(
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
                              // waveform-less composer; [requireRecorder]'s hard
                              // assert belongs to the mic flow itself, not every
                              // rebuild.
                              recorder: AppScope.of(context).recorder,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The message list's once-only entrance: rises into place the FIRST time a
/// display key is seen, then never again. The ledger ([played]) is consulted
/// exactly once per mount — so a rebuild never re-decides and never disposes
/// a running animation — while a later REMOUNT of the same identity (scrolled
/// out and back) reads "already played" and appears settled instantly. This
/// is what keeps scrolling through history solid: no bubble ever re-entrances
/// under the thumb. Honors reduce motion.
class _RiseOnce extends StatefulWidget {
  const _RiseOnce({
    required this.ledgerKey,
    required this.played,
    required this.child,
  });

  final String ledgerKey;
  final Set<String> played;
  final Widget child;

  @override
  State<_RiseOnce> createState() => _RiseOnceState();
}

class _RiseOnceState extends State<_RiseOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.enter,
  );

  /// Whether this identity should render settled: its entrance already
  /// played, or it was waived as history, or the user reduces motion.
  bool? _settled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decided exactly once, on first dependencies — never re-decided by a
    // rebuild, so an in-flight entrance is never torn down mid-flight.
    if (_settled == null) {
      final fresh = widget.played.add(widget.ledgerKey);
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      _settled = !fresh || reduceMotion;
      if (_settled!) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_settled ?? false) {
      return widget.child;
    }
    final curved = CurvedAnimation(parent: _c, curve: AppMotion.ease);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(-9 * (1 - t), 14 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
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
          const Icon(AppIcons.ask, size: 13, color: TrainColors.violetGlyph),
          const SizedBox(width: 7),
          Text(
            'ZIVO',
            style: TrainType.caption(
              size: 9,
              tracking: 0.2,
              weight: FontWeight.w600,
              color: TrainColors.violetGlyph.withValues(alpha: 0.85),
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
    final still = MediaQuery.of(context).disableAnimations;
    // The min height is the VIEWPORT's, not a fraction of the screen's.
    // `size.height * 0.6` ignored the header above this surface, the composer
    // below it and the keyboard entirely, so the column it stretched was
    // taller than the space it had: the empty state could not centre itself,
    // and it handed the scroll view an extent with nothing in it — a
    // short screen scrolled through blank ground before reaching the pills,
    // and with the keyboard up it scrolled when it had no reason to.
    // `constraints.maxHeight` is the room actually on offer, so the content
    // centres when it fits and scrolls only when it genuinely doesn't. Same
    // shape the live session's phase scaffold already uses.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // Scrollable rather than a bare Center: with the keyboard rising, a
        // min-height column can overflow — this lets it give instead of
        // throwing yellow stripes over a premium moment.
        // Bottom padding keeps the suggestion pills clear of the floating
        // composer that overlays this surface.
        padding: const EdgeInsets.only(bottom: _kComposerFloatClearance),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(
              0,
              constraints.maxHeight - _kComposerFloatClearance,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.section,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The hero is a 54px violet glyph tile, not an
                  // illustration: identity §1.4 is "text over imagery", and the
                  // one thing this screen should lead with is ZIVO's VOICE —
                  // the Instrument Serif line below — rather than a picture of
                  // it. The tile marks the assistant; the sentence is the hero.
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: TrainColors.violetGlyph.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: TrainColors.violetGlyph.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      AppIcons.ask,
                      size: 24,
                      color: TrainColors.violetGlyph,
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Instrument Serif italic — the assistant's voice, used here
                  // and in its answers, and nowhere else in the app.
                  RiseIn(
                    delay: still
                        ? Duration.zero
                        : const Duration(milliseconds: 120),
                    child: Text(
                      "Hey, I'm ZIVO.",
                      textAlign: TextAlign.center,
                      style: TrainType.serif(size: 36, height: 1),
                    ),
                  ),
                  const SizedBox(height: 14),
                  RiseIn(
                    delay: still
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(
                        'Training, diet and spending. Ask me anything — or let '
                        'me log it for you.',
                        textAlign: TextAlign.center,
                        style: TrainType.ui(
                          size: 14,
                          weight: FontWeight.w400,
                          color: TrainColors.ink2,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, prompt) in _suggestions.indexed)
                          Padding(
                            padding: EdgeInsets.only(top: index == 0 ? 0 : 9),
                            child: RiseIn(
                              delay: still
                                  ? Duration.zero
                                  : Duration(milliseconds: 280 + index * 70),
                              child: _SuggestionChip(
                                label: prompt,
                                onTap: () => onSuggestion(prompt),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
        color: const Color(0x0BFFFFFF),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x17FFFFFF)),
            ),
            child: Text(
              label,
              style: TrainType.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color: TrainColors.inkPlain,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
    this.message, {
    this.animate = false,
    this.onRevealDone,
    this.streaming = false,
  });

  final AiMessage message;

  /// When true, the (assistant) text types in rather than appearing at once.
  final bool animate;

  /// Called once the typewriter reveal finishes — the page drops the
  /// message's reveal flag so later rebuilds render it statically.
  final VoidCallback? onRevealDone;

  /// When true (the provisional live bubble mid-turn), a soft iris caret
  /// rides the text so "still writing" is visible at a glance.
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiRole.user;
    // ZIVO's replies read a touch larger than the user's own lines — it's the
    // long-form text the user actually reads, so a bump to 16 (from body's
    // 14.5) with generous leading makes it easier on the eyes without
    // ballooning the compact user pills.
    final style = isUser
        ? TrainType.ui(
            size: 13.5,
            weight: FontWeight.w600,
            color: TrainColors.inkPlain,
            height: 1.4,
          )
        : TrainType.ui(
            size: 15,
            weight: FontWeight.w400,
            color: TrainColors.ink,
            height: 1.55,
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
              constraints: BoxConstraints(
                // The handoff caps a user bubble at 74% so a long question
                // still reads as a quoted aside, not a paragraph.
                maxWidth: isUser
                    ? MediaQuery.of(context).size.width * 0.74
                    : double.infinity,
              ),
              decoration: isUser
                  // Glass, not a saturated fill: violet is the assistant's
                  // chrome here, and painting the USER's own words in it
                  // spends the hue on the wrong speaker. The softened
                  // bottom-right tail still points the pill at its author.
                  ? const BoxDecoration(
                      color: Color(0x12FFFFFF),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(6),
                      ),
                    )
                  : null,
              child: animate
                  ? _TypewriterText(
                      message.content,
                      style: style,
                      onDone: onRevealDone,
                    )
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
          color: TrainColors.violetGlyph,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Reveals [text] left-to-right on mount, like the assistant is composing it.
/// One-shot (never repeats), so `pumpAndSettle` completes it; honors the
/// platform "reduce motion" setting by showing the full text immediately.
/// [onDone] fires when the reveal completes (including instantly under
/// reduce-motion) — the caller uses it to retire its "revealing" flag.
class _TypewriterText extends StatefulWidget {
  const _TypewriterText(this.text, {required this.style, this.onDone});

  final String text;
  final TextStyle style;
  final VoidCallback? onDone;

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // ~20ms/char with a hard cap — a calm, natural write (matching the
    // streamed path's slower cadence) that still never crawls on long replies.
    // This is only the fallback for turns that arrived without deltas.
    final ms = math.min(widget.text.characters.length * 20, 3200);
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: math.max(ms, 1)),
    )..forward().whenComplete(() => widget.onDone?.call());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      // Full text immediately; retire the caller's reveal flag post-frame
      // (a synchronous callback here would setState during build).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone?.call();
      });
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
                    color: TrainColors.violet,
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
                        color: TrainColors.ink3,
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
            color: TrainColors.violet.withValues(alpha: 0.45),
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
      color: TrainColors.violet.withValues(alpha: opacity),
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
          color: TrainColors.ember.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TrainColors.ember.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            const Icon(AppIcons.warning, size: 17, color: TrainColors.ember),
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
                      color: TrainColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your message wasn\u2019t sent.',
                    style: AppText.body.copyWith(
                      fontSize: 13,
                      height: 1.3,
                      color: TrainColors.ink2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            PressableScale(
              child: Material(
                color: TrainColors.violetWash,
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
                      style: AppText.button.copyWith(color: TrainColors.violet),
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
    final resolved = status != AiActionStatus.pending;
    final meta = _kindMeta(action.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      // The card grows/settles smoothly as it swaps between the proposal and
      // the confirmed/declined receipt.
      child: AnimatedSize(
        duration: AppMotion.enter,
        curve: AppMotion.ease,
        alignment: Alignment.topCenter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          decoration: BoxDecoration(
            color: TrainColors.raised,
            borderRadius: BorderRadius.circular(20),
            // While it's awaiting a decision the card wears a faint wash of its
            // own hue and a soft lift, so it reads as a live, tappable object;
            // once resolved it settles back to a quiet history receipt.
            border: Border.all(
              color: resolved
                  ? TrainColors.hairline
                  : meta.tintFg.withValues(alpha: 0.22),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(resolved),
              child: resolved ? _resolved(meta) : _pending(meta),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pending(
    ({IconData icon, String label, Color tintBg, Color tintFg}) meta,
  ) {
    final chips = _chips();
    final confirm = _confirmSpec();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerRow(meta),
        const SizedBox(height: 13),
        Text(
          _primaryLine(),
          style: AppText.cardTitle.copyWith(fontSize: 20, letterSpacing: -0.3),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 7, runSpacing: 7, children: chips),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Material(
                color: confirm.color,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  key: const Key('proposal-confirm'),
                  onTap: onConfirm,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    child: Text(
                      confirm.label,
                      style: AppText.button.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              key: const Key('proposal-cancel'),
              onTap: onCancel,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                child: Text(
                  'Cancel',
                  style: AppText.button.copyWith(color: TrainColors.ink2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The resolved receipt: keeps the WHAT (kind, headline, detail chips) so a
  /// confirmation read days later still says exactly what was added, changed,
  /// or removed — with a small status pill instead of the action buttons.
  Widget _resolved(
    ({IconData icon, String label, Color tintBg, Color tintFg}) meta,
  ) {
    final s = _statusSpec();
    final chips = _chips();
    final applied = status == AiActionStatus.applied;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerRow(meta, trailing: _statusPill(s)),
        const SizedBox(height: 12),
        Text(
          _primaryLine(),
          style: AppText.cardTitle.copyWith(
            fontSize: 19,
            letterSpacing: -0.3,
            color: applied ? TrainColors.ink : TrainColors.ink3,
            // A struck-through headline reads instantly as "this did not
            // happen" for a cancelled or expired proposal.
            decoration: applied ? null : TextDecoration.lineThrough,
            decorationColor: TrainColors.ink3,
          ),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 11),
          Opacity(
            opacity: applied ? 1 : 0.6,
            child: Wrap(spacing: 7, runSpacing: 7, children: chips),
          ),
        ],
      ],
    );
  }

  Widget _headerRow(
    ({IconData icon, String label, Color tintBg, Color tintFg}) meta, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: meta.tintBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(meta.icon, size: 18, color: meta.tintFg),
        ),
        const SizedBox(width: 10),
        Text(
          meta.label,
          style: AppText.meta.copyWith(
            color: meta.tintFg,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );
  }

  Widget _statusPill(({IconData icon, String label, Color fg, Color bg}) s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 13, color: s.fg),
          const SizedBox(width: 5),
          Text(
            s.label,
            style: AppText.meta.copyWith(
              fontSize: 12,
              color: s.fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String label, Color fg, Color bg}) _statusSpec() {
    switch (status) {
      case AiActionStatus.applied:
        return (
          icon: AppIcons.check,
          label: 'Confirmed',
          fg: TrainColors.green,
          bg: TrainColors.greenWash,
        );
      case AiActionStatus.cancelled:
        return (
          icon: AppIcons.close,
          label: 'Cancelled',
          fg: TrainColors.ink3,
          bg: TrainColors.hairline,
        );
      default:
        return (
          icon: AppIcons.clock,
          label: 'Expired',
          fg: TrainColors.ink3,
          bg: TrainColors.hairline,
        );
    }
  }

  /// The confirm button's verb + colour. A delete is destructive, so it wears
  /// the alert hue and says "Delete" rather than a neutral "Confirm".
  ({String label, Color color}) _confirmSpec() {
    if (action.kind == 'delete_expense') {
      return (label: 'Delete', color: TrainColors.ember);
    }
    return (label: 'Confirm', color: TrainColors.violet);
  }

  String _primaryLine() {
    final f = action.fields;
    switch (action.kind) {
      case 'create_expense':
        return '${f['amount'] ?? ''} ${f['currency'] ?? ''}'.trim();
      case 'edit_expense':
      case 'delete_expense':
        final target = f['target'];
        return (target is String && target.trim().isNotEmpty)
            ? target
            : action.summary;
      case 'mark_meal_eaten':
        return '${f['meal'] ?? ''}'.trim();
      case 'log_food':
        final items = f['items'];
        if (items is List && items.length == 1 && items.first is Map) {
          final name = (items.first as Map)['name'];
          if (name is String && name.trim().isNotEmpty) return name.trim();
        }
        final count = f['count'];
        if (count is int && count > 0) return '$count foods';
        return action.summary;
      default:
        return action.summary;
    }
  }

  /// A quantity like 2.0 → "2", 1.5 → "1.5" — plan/log amounts arrive as JSON
  /// numbers and read badly with a trailing ".0".
  String _qty(Object? value) {
    if (value is! num) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
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
      case 'edit_expense':
        // Each field being changed, shown as its NEW value ("→ 60.00 EGP").
        final amount = f['amount'];
        if (amount != null) {
          chips.add(
            _chip(AppIcons.expenses, '→ $amount ${f['currency'] ?? ''}'.trim()),
          );
        }
        if (f['category'] != null) {
          chips.add(_chip(AppIcons.tag, '→ ${f['category']}'));
        }
        if (f['note'] != null) {
          chips.add(_chip(AppIcons.caption, '→ ${f['note']}'));
        }
      case 'delete_expense':
        final amount = f['amount'];
        if (amount != null) {
          chips.add(
            _chip(AppIcons.expenses, '$amount ${f['currency'] ?? ''}'.trim()),
          );
        }
        if (f['category'] != null) {
          chips.add(_chip(AppIcons.tag, f['category'].toString()));
        }
      case 'mark_meal_eaten':
        chips.add(
          _chip(
            f['state'] == 'eaten' ? AppIcons.success : AppIcons.close,
            f['state']?.toString() ?? 'eaten',
          ),
        );
      case 'log_food':
        final items = f['items'];
        if (items is List) {
          for (final raw in items) {
            if (raw is! Map) continue;
            final name = raw['name']?.toString() ?? '';
            final amount = '${_qty(raw['quantity'])} ${raw['unit'] ?? ''}'
                .trim();
            final label = amount.isEmpty ? name : '$name · $amount';
            if (label.isNotEmpty) chips.add(_chip(AppIcons.diet, label));
          }
        }
        // A total, only when it adds something over a single item's own chip.
        final total = f['totalKcal'];
        if (total != null && items is List && items.length > 1) {
          chips.add(_chip(AppIcons.diet, '$total kcal'));
        }
    }
    return chips;
  }

  Widget _chip(IconData icon, String label, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg ?? TrainColors.raisedStrong,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg ?? TrainColors.ink2),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.meta.copyWith(color: fg ?? TrainColors.ink2),
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
          tintBg: TrainColors.amberWash,
          tintFg: TrainColors.amber,
        );
      case 'edit_expense':
        return (
          icon: AppIcons.edit,
          label: 'Edit expense',
          tintBg: TrainColors.amberWash,
          tintFg: TrainColors.amber,
        );
      case 'delete_expense':
        return (
          icon: AppIcons.trash,
          label: 'Delete expense',
          tintBg: TrainColors.emberWash,
          tintFg: TrainColors.ember,
        );
      case 'mark_meal_eaten':
        return (
          icon: AppIcons.diet,
          label: 'Diet plan',
          tintBg: TrainColors.greenWash,
          tintFg: TrainColors.green,
        );
      case 'log_food':
        return (
          icon: AppIcons.diet,
          label: 'Log food',
          tintBg: TrainColors.greenWash,
          tintFg: TrainColors.green,
        );
      default:
        return (
          icon: AppIcons.ask,
          label: 'Suggestion',
          tintBg: TrainColors.hairline,
          tintFg: TrainColors.ink2,
        );
    }
  }
}

/// What the sessions sheet was dismissed with — a "New chat" tap, or a tap on
/// an existing conversation row.
sealed class _SessionsSelection {}

final class _NewChatSelected extends _SessionsSelection {}

/// Asks for an optional chat name ("Workout Changes") when starting a new
/// chat — naming is what makes history findable later. Returns the trimmed
/// name, an empty string for "no name" (explicit skip), or null on cancel.
Future<String?> _promptNewChatName(BuildContext context) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: TrainColors.raised,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screen,
        14,
        AppSpacing.screen,
        MediaQuery.of(sheetContext).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: TrainColors.hairlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('New chat', style: AppText.cardTitle.copyWith(fontSize: 19)),
          const SizedBox(height: 6),
          Text(
            'Name it so you can find it later — or leave it blank and the '
            'first message will title it.',
            style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.35),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('new-chat-name-field'),
            controller: controller,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            style: AppText.rowTitle.copyWith(color: TrainColors.ink),
            cursorColor: TrainColors.violet,
            decoration: InputDecoration(
              hintText: 'e.g. Workout changes',
              hintStyle: AppText.body.copyWith(color: TrainColors.ink3),
              counterStyle: AppText.meta.copyWith(
                color: TrainColors.ink3,
                fontSize: 11,
              ),
              filled: true,
              fillColor: TrainColors.raisedStrong,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (value) =>
                Navigator.of(sheetContext).pop(value.trim()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: _SheetAction(
              label: 'Start chatting',
              color: TrainColors.violet,
              background: TrainColors.violetWash,
              onTap: () =>
                  Navigator.of(sheetContext).pop(controller.text.trim()),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _SheetAction(
              label: 'Cancel',
              color: TrainColors.ink2,
              background: Colors.transparent,
              onTap: () => Navigator.of(sheetContext).pop(null),
            ),
          ),
        ],
      ),
    ),
  );
}

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
                color: TrainColors.hairlineStrong,
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
                        style: AppText.aside.copyWith(color: TrainColors.ink2),
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
    backgroundColor: TrainColors.raised,
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
                color: TrainColors.hairlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Delete this chat?',
              style: AppText.cardTitle.copyWith(color: TrainColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'This permanently removes "$title" and everything in it. '
              "This can't be undone.",
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: TrainColors.ink2),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: _SheetAction(
                label: 'Delete chat',
                color: TrainColors.ember,
                background: TrainColors.emberWash,
                onTap: () => Navigator.pop(context, true),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _SheetAction(
                label: 'Cancel',
                color: TrainColors.ink2,
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
        color: TrainColors.ember.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(AppIcons.trash, color: TrainColors.ember),
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
        color: TrainColors.violetWash,
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
                  color: TrainColors.violet,
                ),
                const SizedBox(width: 6),
                Text(
                  'New chat',
                  style: AppText.meta.copyWith(
                    color: TrainColors.violet,
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
      color: isActive ? TrainColors.raisedStrong : Colors.transparent,
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
                    color: isActive ? TrainColors.ink : TrainColors.ink2,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                timeAgo(conversation.updatedAt, DateTime.now()),
                style: AppText.meta.copyWith(color: TrainColors.ink3),
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                const Icon(
                  AppIcons.success,
                  size: 16,
                  color: TrainColors.violet,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
