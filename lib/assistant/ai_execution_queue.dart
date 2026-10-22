import 'assistant_ai_client.dart';

/// A proposed plan advances once per actual result. Questions/confirmations
/// pause it; superseding commands and failure discard the remainder.
class AiExecutionQueue {
  final List<AiCommandStep> _remaining = [];
  String? original, waitingSkill;
  bool get hasNext => _remaining.isNotEmpty;
  bool get waiting => waitingSkill != null;
  bool start(String source, List<AiCommandStep> steps) {
    cancel();
    // One native operation may include editing inputs and calculating them.
    // Preserve its complete source, including those parameter relationships.
    final clauses = steps.length == 1 ? [source] : aiSourceClauses(source);
    if (clauses == null ||
        steps.isEmpty ||
        clauses.length > 1 && clauses.length != steps.length) {
      return false;
    }
    original = source;
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      _remaining.add(AiCommandStep(step.skillId, step.command,
          sourceClause: clauses.length == 1 ? source : clauses[i]));
    }
    return true;
  }

  AiCommandStep? takeNext() =>
      waiting || _remaining.isEmpty ? null : _remaining.removeAt(0);
  void pause(String id) => waitingSkill = id;
  bool resolve(String? id, {required bool completed}) {
    if (id != waitingSkill) {
      cancel();
      return false;
    }
    if (!completed) return false;
    waitingSkill = null;
    return hasNext;
  }

  void cancel() {
    _remaining.clear();
    original = null;
    waitingSkill = null;
  }
}

/// Partition only explicit action connectors. All source words remain in their
/// original clause, including signs and negation. No model-chosen spans.
List<String>? aiSourceClauses(String source) {
  final boundary = RegExp(
      r"(?:\s+(?:i|oraz|potem|nast[eę]pnie|and|then|after that)\s+|[,;]\s*)(?=(?:(?:prosz[eę]|please)\s+)?(?:(?:nie|do not|not|don['’]t)\s+)?(?:ustaw\w*|zmie[ńn]\w*|zmniejsz\w*|zwi[eę]ksz\w*|narysuj|dorysuj|nazwij|podsumuj|otw[oó]rz|dodaj|zapisz|odczytaj|oblicz|policz|set|change|reduce|decrease|increase|draw|append|name|rename|summari[sz]e|open|add|save|read|calculate|copy|clear|reset)(?=\s|$))",
      caseSensitive: false);
  final matches = boundary.allMatches(source).toList();
  if (matches.isEmpty) return [source];
  // Quoted titles may contain apparent command separators. Ask for distinct
  // requests rather than splitting inside literal data.
  if (RegExp('["„“”]').hasMatch(source)) return null;
  final clauses = <String>[];
  var start = 0;
  for (final match in matches) {
    clauses.add(source.substring(start, match.start).trim());
    start = match.end;
  }
  clauses.add(source.substring(start).trim());
  if (clauses.any((text) =>
      text.isEmpty ||
      RegExp(r"^(?:(?:prosz[eę]|please)\s+)?(?:nie|not|do not|don['’]t)\b",
              caseSensitive: false)
          .hasMatch(text))) {
    return null;
  }
  return clauses;
}
