/// Native provenance for one clarification conversation. Only user turns enter
/// the execution source; assistant prompts remain display/context data.
class AiClarification {
  const AiClarification({required this.question, required this.userSource});
  final String question, userSource;

  String? sourceWithReply(String reply) {
    final source = '$userSource\n$reply';
    // Never truncate intent, negation, literal data or earlier quantities.
    return source.length <= 16000 ? source : null;
  }
}
