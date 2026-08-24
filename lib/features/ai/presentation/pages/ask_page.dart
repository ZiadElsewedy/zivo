import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
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

/// The "Ask" chat surface: an iris-themed message list over a pinned
/// composer. Talks only to `AppScope.of(context).ai` — Firebase-free.
class AskPage extends StatefulWidget {
  const AskPage({super.key});

  @override
  State<AskPage> createState() => _AskPageState();
}

class _AskPageState extends State<AskPage> {
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

  /// True while a just-stopped recording is being transcribed — disables the
  /// composer briefly so the user isn't left tapping into a stale input.
  bool _transcribing = false;

  /// The user's just-sent text while a turn is in flight or has failed —
  /// rendered as an optimistic bubble until the durable message lands.
  String? _pendingText;

  /// True when the most recent send attempt threw — shows the retry rail.
  bool _sendFailed = false;

  /// Persisted user-message count captured right before a send starts, so
  /// reconciliation can tell the optimistic message landed without
  /// comparing text.
  int _baselineUserCount = 0;

  /// The latest snapshot from `watchMessages`, kept for reconciliation.
  List<AiMessage> _lastPersisted = const [];

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

    final baselineUserCount = _lastPersisted
        .where((m) => m.role == AiRole.user)
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
    setState(() {
      _activeConversationId = conversationId;
      _activeResolved = true;
      _activeIsUntitled = isUntitled;
      _pendingText = null;
      _sendFailed = false;
      _sending = false;
      _phase = null;
      _liveText = '';
      _streamed = false;
      _expectReveal = false;
      _resolved.clear();
      _baselineUserCount = 0;
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
    setState(() {
      _sending = true;
      _expectReveal = true;
      _phase = null;
      _liveText = '';
      _streamed = false;
      _sendFailed = false;
      _autoFollow = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    try {
      await ai.send(
        conversationId: conversationId,
        text: text,
        onEvent: _onTurnEvent,
        responseStyle: _responseStyle,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendFailed = true;
          _phase = null;
          _liveText = '';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      // A streamed reply already appeared token-by-token, so don't re-type the
      // durable message; only a buffered (non-streaming) turn falls back to it.
      if (_streamed) _expectReveal = false;
      _phase = null;
      _liveText = '';
    });
    // _pendingText is intentionally left set here — the StreamBuilder
    // reconciliation below clears it once the persisted message actually
    // lands, so the optimistic bubble never gaps or duplicates the real one.
  }

  /// Applies one live turn event from the gateway: phases drive the rail,
  /// deltas accumulate the provisional reply.
  void _onTurnEvent(AiTurnEvent event) {
    if (!mounted) return;
    switch (event) {
      case AiPhaseEvent(:final phase):
        setState(() => _phase = phase);
      case AiDeltaEvent(:final text):
        setState(() {
          _streamed = true;
          _liveText += text;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoScroll());
    }
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Tap-to-toggle: not recording → request permission and start; recording
  /// → stop and transcribe. A denied permission or a recorder failure shows
  /// a toast and leaves the composer untouched — never a thrown error.
  Future<void> _toggleMic() async {
    final recorder = AppScope.of(context).requireRecorder;
    if (_recording) {
      setState(() => _recording = false);
      final audio = await recorder.stop();
      if (audio == null) {
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

  /// Sends [audio] to `ai.transcribe` and, on success, drops the transcript
  /// into the composer for the user to edit/send — never auto-sent.
  Future<void> _transcribe(RecordedAudio audio) async {
    final ai = AppScope.of(context).ai;
    setState(() => _transcribing = true);
    final outcome = await ai.transcribe(
      audioBytes: audio.bytes,
      mimeType: audio.mimeType,
    );
    if (!mounted) return;
    setState(() => _transcribing = false);
    _handleSttOutcome(outcome);
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
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              onNewChat: (!_activeResolved || _sending) ? null : _newChat,
              onSessions: (!_activeResolved || _sending)
                  ? null
                  : () => _openSessions(_activeConversationId),
              responseStyle: _responseStyle,
              onSelectStyle: _setResponseStyle,
            ),
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
                      _lastPersisted = snapshot.data ?? const <AiMessage>[];
                      final persistedUserCount = _lastPersisted
                          .where((m) => m.role == AiRole.user)
                          .length;
                      // The optimistic bubble "lands" the moment the server
                      // has persisted a new user message — state-based, not
                      // a text/id compare, so it can't mismatch or double up.
                      final landed =
                          _pendingText != null &&
                          persistedUserCount > _baselineUserCount;
                      if (landed) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted &&
                              _pendingText != null &&
                              _lastPersisted
                                      .where((m) => m.role == AiRole.user)
                                      .length >
                                  _baselineUserCount) {
                            setState(() {
                              _pendingText = null;
                              _sendFailed = false;
                            });
                          }
                        });
                      }
                      final displayed = <AiMessage>[..._lastPersisted];
                      if (_pendingText != null && !landed) {
                        displayed.add(
                          AiMessage(
                            id: '_pending',
                            role: AiRole.user,
                            content: _pendingText!,
                            createdAt: DateTime.now(),
                          ),
                        );
                      }
                      if (displayed.isEmpty && !_sending && !_sendFailed) {
                        return _EmptyAsk(onSuggestion: _sendSuggestion);
                      }
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _maybeAutoScroll(),
                      );
                      return ListView.builder(
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
                            ((_sending || _sendFailed) ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= displayed.length) {
                            // Grouped under the ZIVO label right after a user
                            // send — mirrors the runStart check below.
                            final showIdentity =
                                displayed.isEmpty ||
                                displayed.last.role != AiRole.assistant;
                            Widget trailing;
                            if (_sending && _liveText.isNotEmpty) {
                              trailing = _MessageBubble(
                                AiMessage(
                                  id: '_live',
                                  role: AiRole.assistant,
                                  content: _liveText,
                                  createdAt: DateTime.now(),
                                ),
                              );
                            } else if (_sending) {
                              trailing = _ThinkingRail(label: _railLabel());
                            } else {
                              trailing = _ErrorRetry(
                                onRetry: () => _retry(conversationId),
                              );
                            }
                            if (showIdentity) {
                              trailing = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [const _ZivoIdentity(), trailing],
                              );
                            }
                            return RiseIn(child: trailing);
                          }
                          final message = displayed[i];
                          final isLast = i == displayed.length - 1;
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
                                  displayed[i - 1].role != AiRole.assistant);
                          final action = message.pendingAction;
                          Widget content;
                          if (action == null) {
                            content = _MessageBubble(
                              message,
                              animate: animateReply,
                            );
                          } else {
                            final effective =
                                action.status != AiActionStatus.pending
                                ? action.status
                                : (_resolved[action.actionId] ??
                                      AiActionStatus.pending);
                            content = _ProposalCard(
                              action: action,
                              status: effective,
                              onConfirm: () =>
                                  _confirm(conversationId, action.actionId),
                              onCancel: () =>
                                  _cancel(conversationId, action.actionId),
                            );
                          }
                          if (runStart) {
                            content = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [const _ZivoIdentity(), content],
                            );
                          }
                          return RiseIn(
                            key: ValueKey(message.id),
                            child: content,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            _Composer(
              controller: _input,
              enabled: _canSend,
              bottomInset: math.max(
                media.viewInsets.bottom,
                media.padding.bottom,
              ),
              onSend: _send,
              isRecording: _recording,
              transcribing: _transcribing,
              sending: _sending,
              onMicTap: _toggleMic,
              onCancelRecording: _cancelRecording,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onNewChat,
    required this.onSessions,
    required this.responseStyle,
    required this.onSelectStyle,
  });

  /// Starts a new chat session. Null (disabled) while a turn is in flight.
  final VoidCallback? onNewChat;

  /// Opens the sessions bottom sheet. Null (disabled) while a turn is in
  /// flight.
  final VoidCallback? onSessions;

  /// The current reply-length preference, for the style picker's checkmark.
  final String responseStyle;

  /// Persists a newly-picked reply-length preference.
  final void Function(String style) onSelectStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.base,
        AppSpacing.s,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          Expanded(child: Text('Ask', style: AppText.cardTitle)),
          _ResponseStyleMenu(
            responseStyle: responseStyle,
            onSelect: onSelectStyle,
          ),
          IconButton(
            onPressed: onSessions,
            icon: const Icon(Icons.history_rounded),
            color: onSessions == null ? AppColors.ink3 : AppColors.ink2,
            tooltip: 'Chat history',
          ),
          IconButton(
            onPressed: onNewChat,
            icon: const Icon(Icons.add_comment_outlined),
            color: onNewChat == null ? AppColors.ink3 : AppColors.ink2,
            tooltip: 'New chat',
          ),
        ],
      ),
    );
  }
}

/// A compact "tune" icon opening a small ZIVO-styled menu to pick how ZIVO
/// replies — Concise / Balanced / Detailed, persisted via [onSelect].
class _ResponseStyleMenu extends StatelessWidget {
  const _ResponseStyleMenu({
    required this.responseStyle,
    required this.onSelect,
  });

  final String responseStyle;
  final void Function(String style) onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune_rounded),
      color: AppColors.card,
      iconColor: AppColors.ink2,
      tooltip: 'Reply style',
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.hairline),
      ),
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final style in kResponseStyles)
          PopupMenuItem<String>(
            value: style,
            child: Row(
              children: [
                Icon(
                  style == responseStyle
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 16,
                  color: style == responseStyle
                      ? AppColors.iris
                      : AppColors.ink3,
                ),
                const SizedBox(width: 10),
                Text(
                  responseStyleLabel(style),
                  style: AppText.rowTitle.copyWith(color: AppColors.ink),
                ),
              ],
            ),
          ),
      ],
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
            Icons.auto_awesome_rounded,
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
            const Icon(
              Icons.auto_awesome_rounded,
              size: 30,
              color: AppColors.iris,
            ),
            const SizedBox(height: 14),
            Text(
              "Hey, I'm ZIVO.",
              style: AppText.cardTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask about your training, diet, and spending — or I can add '
              'an expense for you.',
              style: AppText.aside.copyWith(color: AppColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
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
    return Material(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: AppText.meta.copyWith(color: AppColors.ink2),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(this.message, {this.animate = false});

  final AiMessage message;

  /// When true, the (assistant) text types in rather than appearing at once.
  final bool animate;

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
                      borderRadius: BorderRadius.circular(18),
                    )
                  : null,
              child: animate
                  ? _TypewriterText(message.content, style: style)
                  : Text(message.content, style: style),
            ),
          ),
        ],
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
    // ~22ms/char, capped so long replies never crawl. Calm, not frantic.
    final ms = math.min(widget.text.characters.length * 22, 2000);
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

/// The calm "the assistant is working" state: an iris dot that breathes beside
/// a quiet label. Shown only while a turn is in flight, so its looping pulse is
/// never left mounted (which would stall `pumpAndSettle`). No spinner.
class _ThinkingRail extends StatefulWidget {
  const _ThinkingRail({this.label = 'Thinking…'});

  /// The current phase label (authoritative when streaming; "Thinking…" until
  /// the first phase event or for a buffered turn).
  final String label;

  @override
  State<_ThinkingRail> createState() => _ThinkingRailState();
}

class _ThinkingRailState extends State<_ThinkingRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
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
      child: Row(
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: still
                ? const _IrisDot(0.9)
                : FadeTransition(
                    opacity: Tween<double>(begin: 0.35, end: 1).animate(
                      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
                    ),
                    child: const _IrisDot(1),
                  ),
          ),
          const SizedBox(width: 9),
          Text(
            widget.label,
            style: AppText.meta.copyWith(
              color: AppColors.irisText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
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

/// Shown in the trailing slot after a failed send: the user's text stays in
/// its optimistic bubble (never lost) and this offers a one-tap retry
/// instead of a SnackBar that vanishes.
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Row(
        children: [
          Text(
            'Something went wrong.',
            style: AppText.meta.copyWith(color: AppColors.ink3),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Retry',
              style: AppText.meta.copyWith(
                color: AppColors.ink2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
        icon = Icons.check_circle_rounded;
        color = AppColors.pulseText;
        text = 'Confirmed';
      case AiActionStatus.cancelled:
        icon = Icons.cancel_outlined;
        color = AppColors.ink3;
        text = 'Cancelled';
      default:
        icon = Icons.schedule_rounded;
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
          chips.add(_chip(Icons.sell_outlined, f['category'].toString()));
        }
        if (f['note'] != null) {
          chips.add(_chip(Icons.notes_rounded, f['note'].toString()));
        }
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
          icon: Icons.savings_outlined,
          label: 'New expense',
          tintBg: AppColors.solarWash,
          tintFg: AppColors.solarText,
        );
      default:
        return (
          icon: Icons.auto_awesome_rounded,
          label: 'Suggestion',
          tintBg: AppColors.hairline,
          tintFg: AppColors.ink2,
        );
    }
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.bottomInset,
    required this.onSend,
    required this.isRecording,
    required this.transcribing,
    required this.sending,
    required this.onMicTap,
    required this.onCancelRecording,
  });

  final TextEditingController controller;
  final bool enabled;
  final double bottomInset;
  final VoidCallback onSend;

  /// True while a voice note is being recorded — the mic button becomes a
  /// stop button, a cancel button appears, and the text field is replaced by
  /// a "Recording…" indicator.
  final bool isRecording;

  /// True while a just-stopped recording is being transcribed — disables the
  /// mic/send buttons briefly.
  final bool transcribing;

  /// True while a turn is in flight — dims the send button and blocks the
  /// mic so the user can't start a conflicting action mid-turn.
  final bool sending;
  final VoidCallback onMicTap;
  final VoidCallback onCancelRecording;

  @override
  Widget build(BuildContext context) {
    final canSend = enabled && !isRecording && !transcribing && !sending;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.s,
        AppSpacing.base,
        bottomInset + AppSpacing.s,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            if (isRecording)
              IconButton(
                onPressed: onCancelRecording,
                icon: const Icon(Icons.close_rounded, color: AppColors.ink3),
                tooltip: 'Cancel recording',
              ),
            Expanded(
              child: isRecording
                  ? Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.fiber_manual_record_rounded,
                            size: 12,
                            color: AppColors.flare,
                          ),
                          const SizedBox(width: 8),
                          Text('Recording…', style: AppText.rowTitle),
                        ],
                      ),
                    )
                  : transcribing
                  ? const Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: _TranscribingRow(),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: TextField(
                        controller: controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) {
                          if (canSend) onSend();
                        },
                        enabled: !transcribing,
                        cursorColor: AppColors.iris,
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
                onPressed: (transcribing || sending) ? null : onMicTap,
                icon: Icon(
                  isRecording ? Icons.stop_rounded : Icons.mic_none_rounded,
                  color: (transcribing || sending)
                      ? AppColors.ink3
                      : (isRecording ? AppColors.flare : AppColors.iris),
                ),
                tooltip: isRecording ? 'Stop recording' : 'Record a voice note',
              ),
            ),
            _SendButton(canSend: canSend, onSend: onSend),
          ],
        ),
      ),
    );
  }
}

/// The composer's send button — springs itself in (opacity + scale) the
/// moment [canSend] flips false→true (the user typed something) rather than
/// just going from a dim, unpressable icon to an enabled one with no visual
/// event; also carries its own [PressableScale] and fires a light haptic on
/// an actual send.
class _SendButton extends StatefulWidget {
  const _SendButton({required this.canSend, required this.onSend});

  final bool canSend;
  final VoidCallback onSend;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    value: widget.canSend ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _SendButton old) {
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

  void _handleSend() {
    HapticFeedback.lightImpact();
    widget.onSend();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _reveal,
      builder: (context, child) {
        final t = _reveal.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: 0.55 + 0.45 * t,
          child: Transform.scale(scale: 0.88 + 0.12 * t, child: child),
        );
      },
      child: PressableScale(
        child: IconButton(
          onPressed: widget.canSend ? _handleSend : null,
          icon: Icon(
            Icons.arrow_upward_rounded,
            color: widget.canSend ? AppColors.iris : AppColors.ink3,
          ),
          tooltip: 'Send',
        ),
      ),
    );
  }
}

/// The "Transcribing…" row shown while a just-stopped recording is being
/// converted to text — an animated pulse on the icon reads as active
/// processing rather than a static, possibly-stuck state.
class _TranscribingRow extends StatefulWidget {
  const _TranscribingRow();

  @override
  State<_TranscribingRow> createState() => _TranscribingRowState();
}

class _TranscribingRowState extends State<_TranscribingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return Row(
      children: [
        still
            ? const Icon(
                Icons.graphic_eq_rounded,
                size: 14,
                color: AppColors.iris,
              )
            : FadeTransition(
                opacity: Tween<double>(
                  begin: 0.35,
                  end: 1,
                ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  size: 14,
                  color: AppColors.iris,
                ),
              ),
        const SizedBox(width: 8),
        Text('Transcribing…', style: AppText.rowTitle),
      ],
    );
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
      child: const Icon(Icons.delete_outline_rounded, color: AppColors.flare),
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
                  Icons.add_comment_outlined,
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
                  Icons.check_circle_rounded,
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
