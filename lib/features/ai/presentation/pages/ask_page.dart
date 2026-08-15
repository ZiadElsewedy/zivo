import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/ai_message.dart';
import '../../domain/ai_role.dart';

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
    await ai.send(conversationId: conversationId, text: text);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

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
                      if (messages.isEmpty) return const _EmptyAsk();
                      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                      return ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screen,
                          AppSpacing.base,
                          AppSpacing.screen,
                          AppSpacing.base,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, i) => _MessageBubble(messages[i]),
                      );
                    },
                  );
                },
              ),
            ),
            _Composer(
              controller: _input,
              enabled: _canSend,
              bottomInset: media.viewInsets.bottom,
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
  const _MessageBubble(this.message);

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiRole.user;
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
              child: Text(
                message.content,
                style: AppText.body.copyWith(color: isUser ? Colors.white : AppColors.ink),
              ),
            ),
          ),
        ],
      ),
    );
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
