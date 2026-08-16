import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/ai_message.dart';
import '../../domain/ai_pending_action.dart';
import '../../domain/ai_role.dart';
import '../../domain/ai_turn_event.dart';

/// The "Ask" chat surface: an iris-themed message list over a pinned
/// composer. Talks only to `AppScope.of(context).ai` — Firebase-free.
class AskPage extends StatefulWidget {
  const AskPage({super.key});

  @override
  State<AskPage> createState() => _AskPageState();
}

class _AskPageState extends State<AskPage> {
  late final Future<String> _conversationId = AppScope.of(context).ai.ensureConversation();
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

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final canSend = _input.text.trim().isNotEmpty;
      if (canSend != _canSend) setState(() => _canSend = canSend);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String conversationId) async {
    if (!_canSend) return;
    final ai = AppScope.of(context).ai;
    final text = _input.text;
    _input.clear();
    setState(() {
      _sending = true;
      _expectReveal = true;
      _phase = null;
      _liveText = '';
      _streamed = false;
    });
    try {
      await ai.send(
        conversationId: conversationId,
        text: text,
        onEvent: _onTurnEvent,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _expectReveal = false;
          _phase = null;
          _liveText = '';
        });
      }
      _showError("Couldn't reach Ask. Check your connection and try again.");
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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
    }
  }

  Future<void> _confirm(String conversationId, String actionId) async {
    final ai = AppScope.of(context).ai;
    setState(() => _resolved[actionId] = AiActionStatus.applied);
    try {
      await ai.confirmAction(conversationId: conversationId, actionId: actionId);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// The rail label for the current authoritative phase; a calm "Thinking…"
  /// before any phase arrives or for a non-streaming turn.
  String _railLabel() => switch (_phase) {
    AiPhase.understanding => 'Understanding…',
    AiPhase.working => 'Working…',
    AiPhase.preparingChange => 'Preparing change…',
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

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: FutureBuilder<String>(
                future: _conversationId,
                builder: (context, idSnapshot) {
                  final conversationId = idSnapshot.data;
                  if (conversationId == null) return const SizedBox.shrink();
                  final ai = AppScope.of(context).ai;
                  return StreamBuilder<List<AiMessage>>(
                    stream: ai.watchMessages(conversationId),
                    builder: (context, snapshot) {
                      final messages = snapshot.data ?? const <AiMessage>[];
                      if (messages.isEmpty && !_sending) return const _EmptyAsk();
                      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                      return ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screen,
                          AppSpacing.base,
                          AppSpacing.screen,
                          AppSpacing.base,
                        ),
                        // A trailing slot holds the in-flight state: the live
                        // reply once text starts streaming, otherwise the phase
                        // rail.
                        itemCount: messages.length + (_sending ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= messages.length) {
                            if (_liveText.isNotEmpty) {
                              return RiseIn(
                                child: _MessageBubble(
                                  AiMessage(
                                    id: '_live',
                                    role: AiRole.assistant,
                                    content: _liveText,
                                    createdAt: DateTime.now(),
                                  ),
                                ),
                              );
                            }
                            return RiseIn(child: _ThinkingRail(label: _railLabel()));
                          }
                          final message = messages[i];
                          final isLast = i == messages.length - 1;
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
                          final action = message.pendingAction;
                          if (action == null) {
                            return RiseIn(
                              key: ValueKey(message.id),
                              child: _MessageBubble(
                                message,
                                animate: animateReply,
                              ),
                            );
                          }
                          final effective =
                              action.status != AiActionStatus.pending
                              ? action.status
                              : (_resolved[action.actionId] ??
                                    AiActionStatus.pending);
                          return RiseIn(
                            key: ValueKey(message.id),
                            child: _ProposalCard(
                              action: action,
                              status: effective,
                              onConfirm: () =>
                                  _confirm(conversationId, action.actionId),
                              onCancel: () =>
                                  _cancel(conversationId, action.actionId),
                            ),
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
              bottomInset: math.max(media.viewInsets.bottom, media.padding.bottom),
              onSend: () async {
                final conversationId = await _conversationId;
                await _send(conversationId);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.base,
        AppSpacing.screen,
        AppSpacing.s,
      ),
      child: Text('Ask', style: AppText.cardTitle),
    );
  }
}

class _EmptyAsk extends StatelessWidget {
  const _EmptyAsk();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 30, color: AppColors.iris),
            const SizedBox(height: 14),
            Text('Ask about your day.', style: AppText.aside, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Try "what\'s due this week?" or "summarise my week."',
              style: AppText.meta.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
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
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? AppColors.iris : AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: isUser ? null : Border.all(color: AppColors.hairline),
              ),
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
                    opacity: Tween<double>(begin: 0.35, end: 1)
                        .animate(CurvedAnimation(
                          parent: _c,
                          curve: Curves.easeInOut,
                        )),
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
      case 'create_task':
      case 'create_event':
        return (f['title'] ?? action.summary).toString();
      default:
        return action.summary;
    }
  }

  List<Widget> _chips() {
    final f = action.fields;
    final chips = <Widget>[];
    switch (action.kind) {
      case 'create_task':
        if (f['due'] != null) {
          chips.add(_chip(Icons.calendar_today_rounded, _date(f['due'])));
        }
        if (f['priority'] == 'High') {
          chips.add(_chip(
            Icons.flag_rounded,
            'High',
            bg: const Color(0xFFFBEAF0),
            fg: AppColors.flareText,
          ));
        }
      case 'create_expense':
        if (f['category'] != null) {
          chips.add(_chip(Icons.sell_outlined, f['category'].toString()));
        }
        if (f['note'] != null) {
          chips.add(_chip(Icons.notes_rounded, f['note'].toString()));
        }
      case 'create_event':
        if (f['start'] != null) {
          chips.add(_chip(Icons.schedule_rounded, _dateTime(f['start'])));
        }
        if (f['location'] != null) {
          chips.add(_chip(Icons.place_outlined, f['location'].toString()));
        }
    }
    return chips;
  }

  Widget _chip(IconData icon, String label, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg ?? const Color(0xFFF1EFE8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg ?? AppColors.ink2),
          const SizedBox(width: 5),
          Text(label, style: AppText.meta.copyWith(color: fg ?? AppColors.ink2)),
        ],
      ),
    );
  }

  static String _date(Object? iso) {
    final s = iso.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  static String _dateTime(Object? iso) {
    final s = iso.toString();
    return s.length >= 16 ? s.substring(0, 16).replaceFirst('T', ' ') : s;
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
      case 'create_event':
        return (
          icon: Icons.event_rounded,
          label: 'New event',
          tintBg: const Color(0xFFEEEDFE),
          tintFg: AppColors.irisText,
        );
      case 'create_task':
        return (
          icon: Icons.add_task_rounded,
          label: 'New task',
          tintBg: const Color(0xFFEEEDFE),
          tintFg: AppColors.irisText,
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
  });

  final TextEditingController controller;
  final bool enabled;
  final double bottomInset;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
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
            IconButton(
              onPressed: enabled ? onSend : null,
              icon: Icon(
                Icons.arrow_upward_rounded,
                color: enabled ? AppColors.iris : AppColors.ink3,
              ),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
