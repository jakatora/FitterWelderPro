import 'core/utterance.dart';

// Conversation questions describe a problem; mentioning a tool is not a
// navigation request. Native commands and literal field replies remain owned
// by their existing workflows.
final _question =
    RegExp(r'^(?:(?:prosze|please|hej|hey|powiedz mi|tell me)\s+)*'
        r'(?:jak\w*|dlaczego|czemu|czym|czy\b|co\b|ile\b|kiedy\b|'
        r'wyjasnij\w*|wytlumacz\w*|opisz\w*|explain\b|describe\b|'
        r'what\b|why\b|how\b|which\b|when\b|can you explain\b)');
final _politeAction = RegExp(
    r'^(?:(?:prosze|please)\s+)*(?:czy (?:mozesz|moglbys)|can you|could you)\s+'
    r'(?:(?:mi|please)\s+)?(?:otworz\w*|pokaz\w*|uruchom\w*|zapis\w*|dodaj\w*|'
    r'ustaw\w*|zmien\w*|zmniejsz\w*|zwieksz\w*|usun\w*|oblicz\w*|policz\w*|narys\w*|'
    r'open|show|save|add|set|change|delete|calculate|draw)\b');
final _action = RegExp(
    r'^(?:(?:prosze|please|hej|hey)\s+)*(?:otworz\w*|pokaz\w*|uruchom\w*|'
    r'zapis\w*|dodaj\w*|ustaw\w*|zmien\w*|usun\w*|oblicz\w*|policz\w*|'
    r'narys\w*|dorys\w*|przelicz\w*|skopiuj\w*|wyczysc\w*|'
    r'open|show|save|add|set|change|delete|calculate|compute|draw|copy|clear)\b');

bool requestsConversationAction(Utterance u) =>
    _action.hasMatch(u.folded) || _politeAction.hasMatch(u.folded);

bool isKnowledgeQuestion(Utterance u) =>
    !requestsConversationAction(u) &&
    !RegExp(r'co (?:potrafisz|umiesz)|w czym pomozesz|what can you do')
        .hasMatch(u.folded) &&
    _question.hasMatch(u.folded);

bool isExplanationQuestion(Utterance u) =>
    RegExp(r'^(?:(?:prosze|please|powiedz mi|tell me)\s+)*'
            r'(?:jak\b|dlaczego\b|czemu\b|czym\b|co to\b|'
            r'wyjasnij\w*|wytlumacz\w*|opisz\w*|explain\b|describe\b|'
            r'why\b|how\b|what is\b|what are\b)')
        .hasMatch(u.folded);
