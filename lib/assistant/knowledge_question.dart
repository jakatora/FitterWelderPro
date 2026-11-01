import 'core/utterance.dart';

String _conversationText(Utterance u) =>
    u.folded.replaceFirst(RegExp(r'^(?:(?:a|ale|and|but)\s+)+'), '');

// Conversation questions describe a problem; mentioning a tool is not a
// navigation request. Native commands and literal field replies remain owned
// by their existing workflows.
final _question = RegExp(
    r'^(?:(?:prosze|please|hej|hey|powiedz mi|tell me)\s+)*'
    r'(?:jak\w*|dlaczego|czemu|czym|czy\b|co\b|ile\b|kiedy\b|'
    r'dla\b|przy\b|jesli\b|gdy\b|for\b|if\b|'
    r'wyjasnij\w*|wytlumacz\w*|opisz\w*|explain\b|describe\b|'
    r'what\b|why\b|how\b|which\b|when\b|(?:can|could) you\b|'
    r'(?:wyszukaj|poszukaj) w (?:internecie|sieci)\b|search the web\b|look up\b)');
final _politeAction = RegExp(
    r'^(?:(?:prosze|please)\s+)*(?:czy (?:mozesz|moglbys)|can you|could you)\s+'
    r'(?:(?:mi|please)\s+)?(\w+)');
final _action = RegExp(
    r'^(?:(?:prosze|please|hej|hey)\s+)*(?:otworz\w*|pokaz\w*|uruchom\w*|'
    r'zapis\w*|dodaj\w*|ustaw\w*|zmien\w*|usun\w*|oblicz\w*|policz\w*|'
    r'narys\w*|dorys\w*|przelicz\w*|skopiuj\w*|wyczysc\w*|nazwij\w*|podsumuj\w*|'
    r'open|show|save|add|set|change|delete|calculate|compute|draw|copy|clear)\b');

// "Help me understand" asks for an explanation, while "help me open"
// still belongs to the command workflow.
final _helpUnderstand = RegExp(
    r'^(?:(?:prosze|please)\s+)*'
    r'(?:(?:czy (?:mozesz|moglbys)|can you|could you)\s+)?'
    r'(?:(?:mi|please)\s+)*(?:pomoz|pomoc|help)\s+'
    r'(?:(?:mi|me)\s+)?(?:zrozumiec|understand)\b');

bool requestsConversationAction(Utterance u) {
  final text = _conversationText(u);
  if (_helpUnderstand.hasMatch(text)) return false;
  final verb = _politeAction.firstMatch(text)?.group(1);
  final explains = verb != null &&
      RegExp(r'^(?:wyjasn|wytlumacz|opowiedz|powiedz|opis|explain|tell|describe)')
          .hasMatch(verb);
  return _action.hasMatch(text) || (verb != null && !explains);
}

bool isKnowledgeQuestion(Utterance u) =>
    !requestsConversationAction(u) &&
    !RegExp(r'co (?:potrafisz|umiesz)|w czym pomozesz|what can you do')
        .hasMatch(u.folded) &&
    (_question.hasMatch(_conversationText(u)) ||
        _helpUnderstand.hasMatch(_conversationText(u)));

bool isExplanationQuestion(Utterance u) =>
    _helpUnderstand.hasMatch(_conversationText(u)) ||
    RegExp(r'^(?:(?:prosze|please|powiedz mi|tell me)\s+)*'
            r'(?:jak\b|dlaczego\b|czemu\b|czym\b|co to\b|'
            r'wyjasnij\w*|wytlumacz\w*|opisz\w*|explain\b|describe\b|'
            r'why\b|how\b(?! (?:many|much)\b)|what is\b|what are\b)')
        .hasMatch(_conversationText(u));
