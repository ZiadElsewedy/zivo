import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/scope/app_scope.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/util/time_ago.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/widgets/zivo_sheet.dart';
import '../../../../../core/widgets/zivo_field.dart';
import '../../../../workout/presentation/widgets/staggered_reveal.dart';
import '../../../domain/ai_conversation.dart';

/// What the sessions sheet was dismissed with — a "New chat" tap, or a tap on
/// an existing conversation row.
sealed class SessionsSelection {}

final class NewChatSelected extends SessionsSelection {}

/// Asks for an optional chat name ("Workout Changes") when starting a new
/// chat — naming is what makes history findable later. Returns the trimmed
/// name, an empty string for "no name" (explicit skip), or null on cancel.
Future<String?> promptNewChatName(BuildContext context) {
  final controller = TextEditingController();
  return showZivoSheet<String>(
    context: context,
    builder: (sheetContext) => ZivoSheetSurface(
      child: Padding(
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
              style: AppText.meta.copyWith(
                color: TrainColors.ink3,
                height: 1.35,
              ),
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
              decoration: zivoFieldDecoration(
                hintText: 'e.g. Workout changes',
                hintStyle: AppText.body.copyWith(color: TrainColors.ink3),
                counterStyle: AppText.meta.copyWith(
                  color: TrainColors.ink3,
                  fontSize: 11,
                ),
                fill: TrainColors.raisedStrong,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                radius: 14,
                focusRing: false,
              ),
              onSubmitted: (value) =>
                  Navigator.of(sheetContext).pop(value.trim()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SheetAction(
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
              child: SheetAction(
                label: 'Cancel',
                color: TrainColors.ink2,
                background: Colors.transparent,
                onTap: () => Navigator.of(sheetContext).pop(null),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class ConversationSelected extends SessionsSelection {
  ConversationSelected(this.conversation);

  final AiConversation conversation;
}

/// The ChatGPT-style history sheet: a "New chat" row pinned above a live list
/// of the user's conversations, newest first, with the active one
/// highlighted. Tapping either pops the sheet with the corresponding
/// [SessionsSelection] for [_AskPageState._openSessions] to act on.
class SessionsSheet extends StatefulWidget {
  const SessionsSheet({
    required this.activeConversationId,
    required this.onDeleted,
    super.key,
  });

  final String? activeConversationId;

  /// Called with a conversation's id right after it's actually deleted —
  /// the sheet stays open; the caller reacts if it was the active one.
  final void Function(String conversationId) onDeleted;

  @override
  State<SessionsSheet> createState() => _SessionsSheetState();
}

class _SessionsSheetState extends State<SessionsSheet> {
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
                  NewChatPill(
                    onTap: () => Navigator.of(context).pop(NewChatSelected()),
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
                            background: const DeleteChatSwipeBackground(),
                            onUpdate: (details) {
                              // Fires once, right as the swipe crosses the
                              // dismiss threshold — a felt "point of no
                              // return" before the confirm sheet even opens.
                              if (details.reached && !details.previousReached) {
                                HapticFeedback.mediumImpact();
                              }
                            },
                            confirmDismiss: (_) =>
                                confirmDeleteChat(context, conversation.title),
                            onDismissed: (_) => _performDelete(conversation),
                            child: SessionRow(
                              conversation: conversation,
                              isActive:
                                  conversation.id ==
                                  widget.activeConversationId,
                              onTap: () => Navigator.of(
                                context,
                              ).pop(ConversationSelected(conversation)),
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
Future<bool> confirmDeleteChat(BuildContext context, String title) async {
  final confirmed = await showZivoSheet<bool>(
    context: context,
    // A short, fixed-height confirmation — it never needs to grow past half
    // the screen, and letting it would change how far it rises.
    isScrollControlled: false,
    builder: (context) => ZivoSheetSurface(
      child: SafeArea(
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
                child: SheetAction(
                  label: 'Delete chat',
                  color: TrainColors.ember,
                  background: TrainColors.emberWash,
                  onTap: () => Navigator.pop(context, true),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SheetAction(
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
    ),
  );
  return confirmed ?? false;
}

/// One full-width row in [confirmDeleteChat]'s action sheet.
class SheetAction extends StatelessWidget {
  const SheetAction({
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
    super.key,
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
/// the confirm dialog ([confirmDeleteChat]) still gates the actual delete.
class DeleteChatSwipeBackground extends StatelessWidget {
  const DeleteChatSwipeBackground({super.key});

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

class NewChatPill extends StatelessWidget {
  const NewChatPill({required this.onTap, super.key});

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

class SessionRow extends StatelessWidget {
  const SessionRow({
    required this.conversation,
    required this.isActive,
    required this.onTap,
    super.key,
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
