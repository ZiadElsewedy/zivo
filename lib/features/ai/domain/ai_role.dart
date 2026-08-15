/// Who authored an [AiMessage]. `tool` is reserved for the server-side tool
/// transcript (Phase 9 gateway); the fake only ever emits user/assistant.
enum AiRole { user, assistant, tool }

AiRole aiRoleFromName(String? name) =>
    AiRole.values.firstWhere((r) => r.name == name, orElse: () => AiRole.assistant);
