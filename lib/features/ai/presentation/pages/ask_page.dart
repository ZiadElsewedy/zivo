import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../shell/presentation/widgets/bottom_chrome.dart';
import '../../domain/ai_message.dart';
import '../../domain/ai_pending_action.dart';
import '../../domain/ai_role.dart';
import '../widgets/ai_model_sheet.dart';
import '../widgets/chat_header.dart';
import '../widgets/voice_composer.dart';
import '../widgets/ask/ask_effects.dart';
import '../ask_constants.dart';
import '../controllers/ask_controller.dart';
import '../widgets/ask/ask_empty_state.dart';
import '../widgets/ask/error_retry.dart';
import '../widgets/ask/message_bubble.dart';
import '../widgets/ask/message_details_sheet.dart';
import '../../data/repository_body_data_writer.dart';
import '../widgets/ask/choice_tray.dart';
import '../widgets/ask/input_request_card.dart';
import '../widgets/ask/proposal_card.dart';
import '../widgets/ask/sessions_sheet.dart';
import '../widgets/ask/thought_trail.dart';
import '../../domain/ai_choice_request.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/ai_conversation.dart';

class AskPage extends StatefulWidget {
  const AskPage({
    super.key,
    this.transcribeTimeout = kTranscribeTimeout,
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
  /// The turn machinery — see [AskController]. What is left in this State is
  /// what a chat *list* needs and a turn does not: the scroll position, the
  /// entrance ledger, and the set of bubbles currently typing themselves in.
  AskController? _controller;
  AskController get _c => _controller!;

  late final Future<void> _initialLoad = _c.load();

  final ScrollController _scroll = ScrollController();
  bool _reposInitialized = false;

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

  /// The conversation the entrance ledger was seeded for — the first snapshot
  /// of a thread is all HISTORY (cold load), rendered settled with zero
  /// entrances; anything arriving afterwards is news and rises in once.
  String? _entranceSeededFor;

  /// The turn's last assistant message is typing itself in right now (the
  /// buffered/non-streaming fallback). Keyed by display id and REMOVED only
  /// when [TypewriterText] reports completion — so an interleaved rebuild (a
  /// snapshot emission, the send completing, a keyboard frame) can never swap
  /// the half-typed bubble for static text mid-reveal. That mid-type swap was
  /// the "reply pops in twice" glitch.
  final Set<String> _revealActive = {};

  /// Where a revealing bubble starts typing, in characters — set when a
  /// streamed reply's saved copy takes over mid-write, so it types on from
  /// what was on screen instead of snapping to its full length.
  final Map<String, int> _revealFrom = {};

  /// The live reply's words at the moment its saved copy landed, keyed by
  /// display key — consumed by the saved bubble's first build.
  final Map<String, String> _handoffText = {};

  /// ZIVO's open question, if the conversation currently ends in one — its
  /// options sit above the composer as answer chips. Mirrored out of the
  /// message stream's builder (see [_syncOpenChoice]).
  AiChoiceRequest? _openChoice;

  /// The answer chips' measured height, so the list keeps its last line
  /// clear of them as well as of the composer.
  double _trayHeight = 0;

  /// The stable identity of a message ON SCREEN. Both sides of an in-flight
  /// turn share [AiMessage.clientTurnId], so the optimistic user bubble and
  /// ZIVO's provisional live reply carry the SAME display key as their
  /// durable copies — the swap is invisible: same widget at the same slot, no
  /// second entrance. Role-scoped ('u:'/'a:') because both halves of a turn
  /// share one turn id; legacy/turnless messages fall back to their id.
  String _displayKey(AiMessage m) => switch ((m.clientTurnId, m.role)) {
    (final String t, AiRole.user) => 'u:$t',
    (final String t, AiRole.assistant) => 'a:$t',
    _ => 'm:${m.id}',
  };

  @override
  void initState() {
    super.initState();
    widget.incomingDraft?.addListener(_onIncomingDraft);
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      _autoFollow = p.pixels >= p.maxScrollExtent - 120;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Built here rather than in [initState] because it needs the AI
    // repository and recorder from [AppScope], which is an inherited widget.
    //
    // The controller has no BuildContext (ADR-008), so it is handed the
    // localized copy instead — and re-handed it on every dependency change,
    // which is what makes switching language mid-chat re-render the thinking
    // rail rather than stranding it in the old locale.
    if (_reposInitialized) {
      _controller?.updateStrings(l(context));
      return;
    }
    _reposInitialized = true;
    final scope = AppScope.of(context);
    _controller = AskController(
      ai: scope.ai,
      recorder: scope.recorder,
      vsync: this,
      transcribeTimeout: widget.transcribeTimeout,
      strings: l(context),
      // Lets the coach's input form remember height/weight straight into the
      // user's own body data (Phase 3), through the same repositories the
      // manual capture screens write to.
      bodyWriter: RepositoryBodyDataWriter(
        diet: scope.diet,
        bodyWeight: scope.bodyWeight,
      ),
      onError: _showError,
      onSendStarted: () => _autoFollow = true,
      onContentGrew: ({required bool instant}) {
        if (instant) {
          _maybeAutoScroll(instant: true);
        } else {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        }
      },
    )..addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Consumes a shell-initiated draft (voice quick-log): drops it into the
  /// composer as editable text — never auto-sent — and clears the notifier so
  /// the next log re-triggers even if identical.
  void _onIncomingDraft() {
    final text = widget.incomingDraft?.value;
    if (text == null || !mounted) return;
    widget.incomingDraft!.value = null;
    _c.fillComposer(text);
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
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- Switching conversations ---------------------------------------------

  /// Switches the active conversation. The controller drops the turn state;
  /// this drops the list state that went with it, so neither can bleed into
  /// the new thread.
  void _switchTo(String? conversationId, {required bool isUntitled}) {
    setState(() {
      _autoFollow = true;
      _userDragging = false;
      _entrancePlayed.clear();
      _entranceSeededFor = null;
      _revealActive.clear();
      _revealFrom.clear();
      _handoffText.clear();
      _openChoice = null;
    });
    _c.switchTo(conversationId, isUntitled: isUntitled);
  }

  /// Starts a new, unsaved chat — no Firestore write until the first message
  /// actually goes out. Offers an optional name first so the chat is findable
  /// in history later; a blank name keeps the auto-title behaviour.
  Future<void> _newChat() async {
    final name = await promptNewChatName(context);
    if (!mounted) return;
    final trimmed = name?.trim();
    _switchTo(null, isUntitled: true);
    if (trimmed != null && trimmed.isNotEmpty) _c.setDraftTitle(trimmed);
  }

  /// Opens the one model picker ([showAiModelSheet] — the same sheet as
  /// Settings → AI → Model). The sheet persists the pick itself; the
  /// controller just adopts it so the header and the next send agree at once.
  Future<void> _openModelPicker() async {
    final picked = await showAiModelSheet(context);
    if (picked != null && mounted) _c.adoptModelSelection(picked);
  }

  Future<void> _openSessions(String? activeConversationId) async {
    final result = await showZivoSheet<SessionsSelection>(
      context: context,
      builder: (_) => ZivoSheetSurface(
        child: SessionsSheet(
          activeConversationId: activeConversationId,
          onDeleted: _handleConversationDeleted,
        ),
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case NewChatSelected():
        _newChat();
      case ConversationSelected(:final conversation):
        if (conversation.id != activeConversationId) {
          _switchTo(
            conversation.id,
            isUntitled: conversation.title == kUntitledConversationTitle,
          );
        }
    }
  }

  /// A conversation was deleted from the sessions sheet (which stays open —
  /// this only reacts if the ACTIVE conversation was the one removed):
  /// switches to the most-recently-updated remaining one, or to the unsaved
  /// "New chat" state if none remain.
  Future<void> _handleConversationDeleted(String deletedId) async {
    if (deletedId != _c.activeConversationId) return;
    final remaining = await _c.latestConversation();
    if (!mounted) return;
    if (remaining == null) {
      _newChat();
    } else {
      _switchTo(remaining.id, isUntitled: remaining.isUntitled);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    // The app's translucent top toast — never a bottom SnackBar.
    showZivoToast(context, message, kind: ToastKind.error);
  }

  // ---- Scroll following ----------------------------------------------------

  /// Whether the list is at rest and safe to pin.
  ///
  /// A pin during a live scroll cancels the activity that owns the position,
  /// which stops the list dead under the thumb — the "stuck" scroll. A
  /// rubber-band overscroll is the case that bit hardest: it is a ballistic
  /// activity like any other, and cutting it short leaves the list parked off
  /// its own end. Let whatever is in flight land; the next metrics change
  /// re-pins.
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
    // [_userDragging] mid-stream and re-open the door to a pin fight.
    if ((target - _scroll.position.pixels).abs() < 1) return;
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Follows new content to the bottom only if the user hasn't scrolled away
  /// — never yanks them down mid-read, and resumes following once they scroll
  /// back near the bottom themselves. [instant] pins without an animation
  /// (per-frame streaming reveal, keyboard re-pin), where a restarted tween
  /// every frame would stutter and fight the list.
  void _maybeAutoScroll({bool instant = false}) {
    if (_autoFollow) _scrollToBottom(instant: instant);
  }

  /// What ZIVO is doing right now, while the turn works and isn't writing —
  /// the head of the live thought trail. Null once words are flowing (the
  /// caret is the live signal then) and once the turn is over.
  LiveThought? _liveThought() => _c.sending && !_c.writing
      ? LiveThought(
          kind: _c.railThought,
          label: _c.railLabel,
          slow: _c.turnSlow,
        )
      : null;

  /// Mirrors the conversation's open question out of the stream builder,
  /// after the frame (the builder must not set state while building).
  void _syncOpenChoice(AiChoiceRequest? open) {
    if (open?.requestId == _openChoice?.requestId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && open?.requestId != _openChoice?.requestId) {
        setState(() => _openChoice = open);
      }
    });
  }

  /// The words a message shows in its bubble: a question's lead-in and
  /// question, a card's lead-in (the card says the rest), else its text.
  static String _bubbleText(AiMessage m) {
    final choice = m.choiceRequest;
    if (choice != null) return choiceMessageText(choice, m.preface);
    if (m.pendingAction != null || m.inputRequest != null) {
      return m.preface ?? '';
    }
    return m.content;
  }

  /// How many leading characters [a] and [b] share — where a saved reply
  /// stops agreeing with what streamed, so typing resumes from there.
  static int _sharedPrefix(String a, String b) {
    final x = a.characters.toList();
    final y = b.characters.toList();
    var i = 0;
    while (i < x.length && i < y.length && x[i] == y[i]) {
      i++;
    }
    return i;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final openChoice = _openChoice;
    final trayChoice =
        openChoice != null &&
            _c.pickedValueFor(openChoice) == null &&
            !_c.sending &&
            _c.pendingText == null
        ? openChoice
        : null;
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
        decoration: BoxDecoration(gradient: TrainColors.askTint),
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  ChatHeader(
                    onNewChat: (!_c.activeResolved || _c.sending)
                        ? null
                        : _newChat,
                    onSessions: (!_c.activeResolved || _c.sending)
                        ? null
                        : () => _openSessions(_c.activeConversationId),
                    modelSelection: _c.modelSelection,
                    onOpenModel: (!_c.activeResolved || _c.sending)
                        ? null
                        : _openModelPicker,
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
                      // pads its bottom by [kComposerFloatClearance] so the newest
                      // line still rests just above the composer.
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: FutureBuilder<void>(
                              future: _initialLoad,
                              builder: (context, _) {
                                if (!_c.activeResolved) {
                                  return const SizedBox.shrink();
                                }
                                final conversationId = _c.activeConversationId;
                                if (conversationId == null) {
                                  // An unsaved "New chat" — nothing persisted yet, so
                                  // there's no message stream to watch.
                                  return EmptyAsk(
                                    onSuggestion: _c.sendSuggestion,
                                  );
                                }
                                return StreamBuilder<List<AiMessage>>(
                                  stream: _c.messagesStream(conversationId),
                                  builder: (context, snapshot) {
                                    _c.setPersisted(
                                      snapshot.data ?? const <AiMessage>[],
                                    );
                                    final displayed = <AiMessage>[
                                      ..._c.lastPersisted,
                                    ];

                                    // The durable ASSISTANT reply landing gates the
                                    // provisional live bubble — the instant it's in
                                    // the snapshot exactly one copy of the reply
                                    // renders (the persisted one). Paired by turn
                                    // id (see [_c.turnLanded]), so the window where
                                    // the server writes the reply doc slightly
                                    // before the functions stream closes can never
                                    // duplicate the response — nor can a stale or
                                    // reordered snapshot.
                                    final assistantLanded = _c.turnLanded(
                                      AiRole.assistant,
                                    );
                                    if (_c.liveText.isNotEmpty &&
                                        assistantLanded) {
                                      // The saved copy types on from the
                                      // words already on screen.
                                      final turn = _c.activeTurnId;
                                      if (turn != null) {
                                        _handoffText.putIfAbsent(
                                          'a:$turn',
                                          () => _c.liveText,
                                        );
                                      }
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => _c.retireLiveReply(),
                                          );
                                    }
                                    // The conversation's open question, if it
                                    // ends in one — answered from the chips.
                                    final last = _c.lastPersisted.isEmpty
                                        ? null
                                        : _c.lastPersisted.last;
                                    _syncOpenChoice(
                                      last?.role == AiRole.assistant
                                          ? last?.choiceRequest
                                          : null,
                                    );

                                    // The optimistic USER bubble "lands" the moment
                                    // its own turn's durable user message shows up
                                    // in the snapshot — state-based pairing, not a
                                    // text/id compare, so it can't mismatch or
                                    // double up.
                                    final pendingLanded =
                                        _c.pendingText != null &&
                                        (_c.turnLanded(AiRole.user) ||
                                            _c.lastPersisted.any(
                                              (m) =>
                                                  m.role == AiRole.user &&
                                                  m.clientTurnId == null &&
                                                  m.content.trim() ==
                                                      _c.pendingText!.trim(),
                                            ));
                                    if (pendingLanded) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (mounted &&
                                                _c.pendingText != null) {
                                              setState(_c.clearPending);
                                            }
                                          });
                                    }
                                    if (_c.pendingText != null &&
                                        !pendingLanded) {
                                      displayed.add(
                                        AiMessage(
                                          id: '_pending',
                                          role: AiRole.user,
                                          content: _c.pendingText!,
                                          createdAt: DateTime.now(),
                                          clientTurnId: _c.activeTurnId,
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
                                    // One live item carries the whole turn —
                                    // the thought trail from the first
                                    // lookup, then the words as they stream —
                                    // so nothing hands over between widgets
                                    // mid-turn and nothing jumps.
                                    final liveActive =
                                        !_c.sendFailed &&
                                        !assistantLanded &&
                                        _c.activeTurnId != null &&
                                        (_c.sending || _c.liveText.isNotEmpty);
                                    if (liveActive) {
                                      displayed.add(
                                        AiMessage(
                                          id: '_live',
                                          role: AiRole.assistant,
                                          content: _c.liveText,
                                          createdAt: DateTime.now(),
                                          clientTurnId: _c.activeTurnId,
                                          activity: _c.activity,
                                        ),
                                      );
                                    }
                                    if (displayed.isEmpty &&
                                        !_c.sending &&
                                        !_c.sendFailed) {
                                      return EmptyAsk(
                                        onSuggestion: _c.sendSuggestion,
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
                                    final liveTurn = _c.sending || liveActive;
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
                                        padding: EdgeInsets.fromLTRB(
                                          AppSpacing.screen,
                                          AppSpacing.base,
                                          AppSpacing.screen,
                                          // Clear the floating composer (and any
                                          // answer chips above it) that overlay
                                          // the bottom of the list.
                                          kComposerFloatClearance + _trayHeight,
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
                                            ((_c.sendFailed ||
                                                    (_c.sending && !liveActive))
                                                ? 1
                                                : 0),
                                        itemBuilder: (context, i) {
                                          if (i >= displayed.length) {
                                            Widget trailing;
                                            if (_c.sendFailed) {
                                              trailing = ErrorRetry(
                                                failure: _c.sendFailure,
                                                onRetry: () =>
                                                    _c.retry(conversationId),
                                                onSwitchModel: _openModelPicker,
                                              );
                                            } else {
                                              trailing = ThoughtTrail(
                                                steps: _c.activity,
                                                live: _liveThought(),
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
                                                  const ZivoIdentity(),
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
                                          // `!_c.streamed` is load-bearing: a reply
                                          // that already streamed token-by-token must
                                          // never ALSO typewriter-reveal on its
                                          // durable copy. Without it, when the
                                          // persisted assistant doc lands before
                                          // `_c.runSend`'s completion resets
                                          // `_c.expectReveal`, the same reply animates
                                          // in twice (streamed, then re-typed) — the
                                          // "response appears twice" glitch.
                                          if (isLast &&
                                              _c.expectReveal &&
                                              !_c.streamed &&
                                              message.role ==
                                                  AiRole.assistant &&
                                              message.pendingAction == null &&
                                              message.inputRequest == null) {
                                            // The decision lives in [_revealActive]
                                            // until the typewriter FINISHES — not
                                            // in this frame's flag — so later
                                            // rebuilds keep the same widget mounted
                                            // instead of cutting the animation
                                            // short mid-write.
                                            _revealActive.add(displayKey);
                                            _c.consumeExpectReveal();
                                          }
                                          final text = _bubbleText(message);
                                          final handoff = _handoffText.remove(
                                            displayKey,
                                          );
                                          if (handoff != null &&
                                              message.id != '_live') {
                                            final from = _sharedPrefix(
                                              handoff,
                                              text,
                                            );
                                            if (from < text.characters.length) {
                                              _revealActive.add(displayKey);
                                              _revealFrom[displayKey] = from;
                                            }
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
                                          final inputReq = message.inputRequest;
                                          final isLive = message.id == '_live';
                                          Widget content = MessageBubble(
                                            message,
                                            text: text,
                                            animate: revealing,
                                            revealFrom:
                                                _revealFrom[displayKey] ?? 0,
                                            onRevealDone: revealing
                                                ? () {
                                                    if (mounted) {
                                                      setState(() {
                                                        _revealActive.remove(
                                                          displayKey,
                                                        );
                                                        _revealFrom.remove(
                                                          displayKey,
                                                        );
                                                      });
                                                    }
                                                  }
                                                : null,
                                            // Only the provisional live bubble
                                            // carries the writing caret and the
                                            // live thought.
                                            streaming:
                                                isLive && _c.revealInFlight,
                                            thought: isLive
                                                ? _liveThought()
                                                : null,
                                          );
                                          // Long-press a settled assistant
                                          // reply to see that turn's model +
                                          // token/cost detail. The live bubble
                                          // has no persisted usage yet, so it
                                          // is excluded.
                                          if (message.role ==
                                                  AiRole.assistant &&
                                              !isLive &&
                                              action == null &&
                                              inputReq == null) {
                                            content = GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onLongPress: () =>
                                                  showAskTurnDetails(
                                                    context,
                                                    repo: AppScope.of(
                                                      context,
                                                    ).ai,
                                                    message: message,
                                                  ),
                                              child: content,
                                            );
                                          }
                                          if (inputReq != null) {
                                            content = Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                content,
                                                InputRequestCard(
                                                  key: ValueKey(
                                                    'input-${inputReq.requestId}',
                                                  ),
                                                  request: inputReq,
                                                  submitted: _c.submittedInputs
                                                      .containsKey(
                                                        inputReq.requestId,
                                                      ),
                                                  onSubmit: (summary, values) =>
                                                      _c.submitInput(
                                                        inputReq.requestId,
                                                        summary,
                                                        values,
                                                      ),
                                                ),
                                              ],
                                            );
                                          } else if (action != null) {
                                            final effective =
                                                action.status !=
                                                    AiActionStatus.pending
                                                ? action.status
                                                : (_c.resolved[action
                                                          .actionId] ??
                                                      AiActionStatus.pending);
                                            content = Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                content,
                                                ProposalCard(
                                                  action: action,
                                                  status: effective,
                                                  onConfirm: () => _c.confirm(
                                                    conversationId,
                                                    action.actionId,
                                                  ),
                                                  onCancel: () => _c.cancel(
                                                    conversationId,
                                                    action.actionId,
                                                  ),
                                                ),
                                              ],
                                            );
                                          }
                                          if (runStart) {
                                            content = Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const ZivoIdentity(),
                                                content,
                                              ],
                                            );
                                          }
                                          // The stable display key rides the item
                                          // itself so [findChildIndexCallback] can
                                          // relocate it after index shifts, and the
                                          // once-only entrance ledger lives INSIDE
                                          // the wrapper (see [RiseOnce]) so the
                                          // decision never flips between builds.
                                          return KeyedSubtree(
                                            key: ValueKey<String>(displayKey),
                                            child: RiseOnce(
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SizeReporter(
                                  onSize: (size) {
                                    if (size.height != _trayHeight) {
                                      setState(() => _trayHeight = size.height);
                                    }
                                  },
                                  child: AnimatedSize(
                                    // Never zero: a zero-length AnimatedSize
                                    // re-dirties itself mid-layout.
                                    duration: reducedMotion(context)
                                        ? const Duration(milliseconds: 1)
                                        : const Duration(milliseconds: 260),
                                    curve: Curves.easeOutCubic,
                                    alignment: Alignment.bottomCenter,
                                    child: trayChoice == null
                                        ? const SizedBox(width: double.infinity)
                                        : ChoiceTray(
                                            key: ValueKey(
                                              'tray-${trayChoice.requestId}',
                                            ),
                                            request: trayChoice,
                                            onSelect: (value, label) =>
                                                _c.answerChoice(
                                                  trayChoice.requestId,
                                                  value,
                                                  label,
                                                ),
                                          ),
                                  ),
                                ),
                                VoiceComposer(
                                  controller: _c.input,
                                  canSend: _c.canSend,
                                  // Bottom spacing is owned by the AnimatedPadding above —
                                  // both the safe area and the keyboard ride that one
                                  // animated value, never twice.
                                  bottomInset: 0,
                                  onSend: _c.send,
                                  isRecording: _c.recording,
                                  transcribing: _c.transcribing,
                                  sending: _c.sending,
                                  onMicToggle: _c.toggleMic,
                                  onCancelRecording: _c.cancelRecording,
                                  onCancelTranscription: _c.cancelTranscription,
                                  // Soft-resolved: hosts without a recorder simply get a
                                  // waveform-less composer; [requireRecorder]'s hard
                                  // assert belongs to the mic flow itself, not every
                                  // rebuild.
                                  recorder: AppScope.of(context).recorder,
                                ),
                              ],
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

/// Reports its child's laid-out size after each layout that changed it — how
/// the page learns the answer chips' height as they grow in and fold away.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
  }
}
