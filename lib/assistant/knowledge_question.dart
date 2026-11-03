import 'core/utterance.dart';

final _newTopic = RegExp(
    r'^(?:(?:a|ale|and|but)\s+)*(?:mam (?:inne|nowe) pytanie|'
    r'(?:inne|nowe) pytanie|zmienmy temat|(?:new|different) question|'
    r'i have (?:another|a new|a different) question|change the subject)\b\s*');

/// Only an explicit topic change ends an unanswered knowledge question.
/// Ordinary short replies and mentions of a "new question" remain context.
bool startsNewKnowledgeTopic(Utterance u) => _newTopic.hasMatch(u.folded);

bool isBareKnowledgeTopicChange(Utterance u) =>
    startsNewKnowledgeTopic(u) && _conversationText(u).isEmpty;

// Strip discourse markers before checking action verbs as well as questions.
// For example, 'so open the calculator' must remain an explicit command.
final _continuation =
    RegExp(r'^(?:(?:a|ale|and|but|czyli|wiec|so|then|to znaczy|'
        r'in other words)\s+)+');
final _inferenceQuestion = RegExp(r'^(?:does that mean|you mean)\s+\S');

// Corrections to an answer belong to the current conversation, but a new
// explicit app command in the remainder still belongs to the action workflow.
final _answerCorrection = RegExp(
    r'^(?:(?:nie|no)\s+)?(?:nie o to mi chodz(?:i|ilo)|'
    r'nie o to (?:pytam|pytal(?:em|am))|nie pytal(?:em|am) o to|'
    r'to nie (?:jest )?to o co pytal(?:em|am)|'
    r'zle mowisz|zle mnie zrozumial(?:es|as)|nie zgadzam sie|'
    r'to (?:raczej )?tak nie (?:bedzie|jest|dziala)|'
    r'to (?:nieprawda|bledne|nieprawidlowe)|to nie to|to nie tak|wrong|that is not what i meant|'
    r'that is wrong|you are wrong|chodzilo mi o|chodzi mi o|'
    r'mial(?:em|am) na mysli|mam na mysli|i meant)\b');
final _correctionConnectors = RegExp(
    r'^(?:(?:ale|tylko|raczej|but|instead|chodzilo mi o|chodzi mi o|'
    r'mial(?:em|am) na mysli|mam na mysli|i mean)\s*)+');

String? _correctionDetail(Utterance u) {
  var remaining = u.folded;
  var matched = false;
  final discourse = RegExp(r'^(?:(?:ale|tylko|raczej|but|instead)\s+)+');
  while (true) {
    final match = _answerCorrection.firstMatch(remaining);
    if (match == null) break;
    matched = true;
    remaining = remaining.substring(match.end).trim().replaceFirst(discourse, '').trim();
  }
  if (!matched) return null;
  return remaining.replaceFirst(_correctionConnectors, '').trim();
}

bool isKnowledgeCorrection(Utterance u) {
  final detail = _correctionDetail(u);
  if (detail == null) return false;
  return detail.isEmpty ||
      (!requestsConversationAction(Utterance(detail, lang: u.lang)) &&
          !_followingAction.hasMatch(detail));
}

bool isBareKnowledgeCorrection(Utterance u) =>
    isKnowledgeCorrection(u) && _correctionDetail(u)!.isEmpty;

/// A correction that also gives a new command must not resume an older action.
bool isKnowledgeCorrectionWithAction(Utterance u) {
  final detail = _correctionDetail(u);
  return detail != null && detail.isNotEmpty &&
      (requestsConversationAction(Utterance(detail, lang: u.lang)) ||
          _followingAction.hasMatch(detail));
}

String _conversationText(Utterance u) =>
    u.folded.replaceFirst(_newTopic, '').replaceFirst(_continuation, '');

// Conversation questions describe a problem; mentioning a tool is not a
// navigation request. Native commands and literal field replies remain owned
// by their existing workflows.
final _question = RegExp(
    r'^(?:(?:prosze|please|hej|hey|powiedz mi|tell me)\s+)*'
    r'(?:jak\w*|dlaczego|czemu|czym|czy\b|co\b|ile\b|kiedy\b|'
    r'dla\b|przy\b|jesli\b|gdy\b|for\b|if\b|'
    r'wyjasnij\w*|wytlumacz\w*|opisz\w*|doradz\w*|polec\b|polecic\b|'
    r'rekomend\w*|porown\w*|explain\b|describe\b|advise\b|recommend\b|compare\b|'
    r'what\b|why\b|how\b|which\b|when\b|(?:can|could) you\b|'
    r'(?:wyszukaj|poszukaj) w (?:internecie|sieci)\b|search the web\b|look up\b)');
final _politeAction = RegExp(
    r'^(?:(?:prosze|please)\s+)*(?:czy (?:mozesz|moglbys)|can you|could you)\s+'
    r'(?:(?:mi|please)\s+)?(\w+)');
final _action = RegExp(
    r'^(?:(?:prosze|please|hej|hey)\s+)*(?:otworz\w*|pokaz\w*|uruchom\w*|'
    r'zapis\w*|dodaj\w*|ustaw\w*|zmien\w*|usun\w*|wybierz\w*|oblicz\w*|policz\w*|'
    r'narys\w*|dorys\w*|przelicz\w*|skopiuj\w*|wyczysc\w*|nazwij\w*|podsumuj\w*|'
    r'zmniejsz\w*|zwieksz\w*|wydluz\w*|skroc\w*|obroc\w*|przesun\w*|cofnij\w*|powtorz\w*|'
    r'open|show|launch|select|save|add|set|change|delete|calculate|compute|draw|copy|clear|'
    r'increase|decrease|reduce|extend|shorten|rotate|move|undo|redo|rename|reset)\b');

// "Help me understand" asks for an explanation, while "help me open"
// still belongs to the command workflow.
final _helpUnderstand = RegExp(r'^(?:(?:prosze|please)\s+)*'
    r'(?:(?:czy (?:mozesz|moglbys)|can you|could you)\s+)?'
    r'(?:(?:mi|please)\s+)*(?:pomoz|pomoc|help)\s+'
    r'(?:(?:mi|me)\s+)?(?:zrozumiec|understand)\b');

// Asking for help deciding is a request for advice, not permission to open or
// change a tool. Keep operational requests such as "help me open" as actions.
final _helpDecide = RegExp(r'^(?:(?:prosze|please)\s+)*'
    r'(?:(?:czy (?:mozesz|moglbys)|can you|could you)\s+)?'
    r'(?:(?:mi|please)\s+)*(?:pomoz|pomoc|help)\s+'
    r'(?:(?:mi|me)\s+)?(?:dobrac|wybrac|zdecydowac|porownac|'
    r'choose|decide|compare)\b');
final _needAdvice = RegExp(r'^(?:(?:prosze|please)\s+)*'
    r'(?:potrzebuje (?:porady|wskazowek)|i need (?:advice|guidance))\b');
// "Show me how" asks for instructions; "show the calculator" is a command.
final _showHow = RegExp(r'^(?:(?:prosze|please)\s+)*'
    r'(?:(?:czy (?:mozesz|moglbys)|can you|could you)\s+)?'
    r'(?:(?:mi|please)\s+)*(?:pokaz|pokazac|show)\s+'
    r'(?:(?:mi|me|please)\s+)?(?:jak|how)\b\s+\S');
final _explainTopic = RegExp(r'^(?:(?:prosze|please)\s+)*'
    r'(?:(?:opowiedz|powiedz)(?:\s+mi)?\s+(?:cos\s+)?(?:o|na temat)|'
    r'tell\s+me\s+about)\b\s+\S');
// Restrict this to information-seeking phrases; "find my project" still
// belongs to the app's own data and action workflows.
final _informationSearch = RegExp(r'^(?:(?:prosze|please)\s+)*'
    r'(?:(?:czy (?:mozesz|moglbys)|can you|could you)\s+)?'
    r'(?:(?:mi|please)\s+)*'
    r'(?:(?:wyszukaj|poszukaj|znajdz|znalezc)\s+informacj\w*\s+(?:o|na temat)|'
    r'(?:search for|find|look for)\s+information\s+(?:about|on))\b\s+\S');
final _followingAction =
    RegExp(r'\b(?:i|oraz|potem|nastepnie|and|then)\s+(?:(?:prosze|please)\s+)?'
    r'(?:otworz|pokaz|uruchom|zapisz|dodaj|ustaw|zmien|usun|wybierz|'
    r'oblicz|policz|przelicz|narysuj|dorysuj|skopiuj|wyczysc|nazwij|'
    r'podsumuj|zmniejsz|zwieksz|wydluz|skroc|obroc|przesun|cofnij|powtorz|'
    r'open|show|launch|save|add|set|change|delete|select|calculate|compute|'
    r'draw|copy|clear|increase|decrease|reduce|extend|shorten|rotate|move|'
    r'undo|redo|rename|reset)\b');

bool _isAdviceRequest(String text) =>
    _helpUnderstand.hasMatch(text) ||
    _helpDecide.hasMatch(text) ||
    _needAdvice.hasMatch(text) ||
    _showHow.hasMatch(text) ||
    _explainTopic.hasMatch(text);

bool requestsConversationAction(Utterance u) {
  final text = _conversationText(u);
  if (_isAdviceRequest(text) || _informationSearch.hasMatch(text)) {
    return _followingAction.hasMatch(text);
  }
  final verb = _politeAction.firstMatch(text)?.group(1);
  final explains = verb != null &&
      RegExp(r'^(?:wyjasn|wytlumacz|opowiedz|powiedz|opis|doradz|'
              r'polec(?:ic|$)|rekomend|porown|explain|tell|describe|advise|recommend|compare)')
          .hasMatch(verb);
  return _action.hasMatch(text) || (verb != null && !explains);
}

/// Requires a current knowledge conversation when punctuation is absent.
bool isEllipticalKnowledgeFollowUp(Utterance u) =>
    !requestsConversationAction(u) &&
    (_continuation.hasMatch(u.folded) ||
        _inferenceQuestion.hasMatch(u.folded)) &&
    _conversationText(u).isNotEmpty;

bool isKnowledgeQuestion(Utterance u) =>
    !requestsConversationAction(u) &&
    !RegExp(r'co (?:potrafisz|umiesz)|w czym pomozesz|what can you do')
        .hasMatch(u.folded) &&
    (_question.hasMatch(_conversationText(u)) ||
        _isAdviceRequest(_conversationText(u)) ||
        _informationSearch.hasMatch(_conversationText(u)) ||
        // Written elliptical questions still belong to the conversation;
        // explicit action verbs above retain their native workflow.
        (u.raw.trimRight().endsWith('?') && isEllipticalKnowledgeFollowUp(u)));

/// A question followed by a separate explicit action needs both parts to be
/// handled. The action-only planner cannot represent an answer and an action
/// in the same plan, so do not allow it to silently drop either part.
bool hasMixedKnowledgeAndAction(Utterance u) {
  final text = _conversationText(u);
  final action = _followingAction.firstMatch(text);
  if (action == null || action.start == 0) return false;
  final question = text.substring(0, action.start).trim();
  return question.isNotEmpty &&
      isKnowledgeQuestion(Utterance(question, lang: u.lang));
}

bool isExplanationQuestion(Utterance u) =>
    _isAdviceRequest(_conversationText(u)) ||
    RegExp(r'^(?:(?:prosze|please|powiedz mi|tell me)\s+)*'
            r'(?:(?:czy (?:mozesz|moglbys)|can you|could you)\s+(?:(?:mi|please)\s+)?)?'
            r'(?:jak\b|dlaczego\b|czemu\b|czym\b|co to\b|'
            r'wyjasn\w*|wytlumacz\w*|opis\w*|doradz\w*|polec\b|polecic\b|'
            r'rekomend\w*|porown\w*|explain\b|describe\b|advise\b|recommend\b|compare\b|'
            r'why\b|how\b(?! (?:many|much)\b)|what is\b|what are\b)')
        .hasMatch(_conversationText(u));
