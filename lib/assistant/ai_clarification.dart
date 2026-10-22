/// Native provenance for one clarification conversation. Only user turns enter
/// the execution source; assistant prompts remain display/context data.
class AiClarification {
  AiClarification({required this.question, required List<String> userTurns})
      : userTurns = List.unmodifiable(userTurns) {
    if (userTurns.isEmpty ||
        userTurns.length > 32 ||
        userTurns.any((t) => t.trim().isEmpty || t.length > 2000) ||
        userSource.length > 16000) {
      throw const FormatException('clarification size');
    }
  }
  final String question;
  final List<String> userTurns;
  String get userSource => userTurns.join('\n');

  String? sourceWithReply(String reply) {
    if (userTurns.length >= 32 || reply.trim().isEmpty || reply.length > 2000) {
      return null;
    }
    final source = '$userSource\n$reply';
    // Never truncate intent, negation, literal data or earlier quantities.
    return source.length <= 16000 ? source : null;
  }
}
