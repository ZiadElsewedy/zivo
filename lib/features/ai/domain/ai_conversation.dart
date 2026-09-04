/// The title a conversation is created with, and the marker for "this thread
/// has not earned a name yet" — the first user message renames it.
///
/// **This is a stored value, not copy.** It is written into Firestore by
/// `createConversation`, read back as the default for a doc with no title, and
/// compared against by the presentation layer to decide whether a thread is
/// still untitled. Localizing it would break every one of those comparisons
/// the moment the user switched language, and would leave older threads
/// permanently "titled" in whatever language created them — the exact trap
/// `kAmrapLabel` exists to document (see `workout/domain/progression.dart`).
///
/// Never render this directly. The UI maps it to the localized `askNewChat`
/// at the point of display — see `displayConversationTitle`.
const kUntitledConversationTitle = 'New chat';

/// A thread of [AiMessage]s. V1 keeps a single active conversation per user.
class AiConversation {
  const AiConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
}
