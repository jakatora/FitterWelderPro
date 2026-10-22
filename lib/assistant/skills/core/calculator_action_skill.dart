import '../../core/command_words.dart'
    show referencesInstruction, isNegatedCommand;
import '../../core/calculator_action_tools.dart';
import '../../../i18n/app_language.dart';
import '../../core/skill.dart';
import '../../core/tool_lookup.dart' show findTools, kAssistantStopWords;

final _verb = RegExp(
    r'^(?:(?:prosze|please)\s+)*(skopiuj|kopiuj|copy|wyczysc|wyzeruj|clear|reset)(?:\s+(.*))?$');
const _copyObjects = {
  '',
  'wynik',
  'wyniki',
  'wszystkie wyniki',
  'wynik kalkulatora',
  'wyniki kalkulatora',
  'wynik biezacego kalkulatora',
  'wyniki biezacego kalkulatora',
  'result',
  'results',
  'all results',
  'calculator results',
  'current calculator results',
  'the results',
  'the current calculator results',
};
const _clearObjects = {
  '',
  'pola',
  'formularz',
  'pola kalkulatora',
  'formularz kalkulatora',
  'pola biezacego kalkulatora',
  'formularz biezacego kalkulatora',
  'inputs',
  'fields',
  'form',
  'calculator inputs',
  'current calculator inputs',
  'the form',
  'the calculator inputs',
  'the current calculator inputs',
};

const _copyVerbPattern =
    r'(?:skopiuj|kopiuj|skopiowac|kopiowac|copy|wrzuc(?:ic|aj)?|umiesc(?:ic)?|przenies(?:c)?|put)';
const _clearVerbPattern =
    r'(?:wyczysc(?:ic|my)?|wyzeruj(?:my)?|wyzerowac|clear|reset)';
final _scopeVerb = RegExp('\\b($_copyVerbPattern|$_clearVerbPattern)\\b');
final _copyVerb = RegExp('^$_copyVerbPattern\$');
final _negatedScopeVerb = RegExp(
    '\\b(?:nie|not|never|dont|don t)\\s+(?:$_copyVerbPattern|$_clearVerbPattern)\\b');
final _clauses =
    RegExp(r'\b(?:nastepnie|potem|pozniej|then|after that|oraz|i|and)\b');
const _scopeFillers = {
  'wynik',
  'wyniki',
  'wyniku',
  'wynikow',
  'wszystkie',
  'pola',
  'pol',
  'formularz',
  'formularza',
  'kalkulator',
  'kalkulatora',
  'biezacego',
  'biezacy',
  'tego',
  'ten',
  'te',
  'moj',
  'mojego',
  'mi',
  'prosze',
  'z',
  'ze',
  'do',
  'schowka',
  'schowek',
  'the',
  'a',
  'an',
  'this',
  'that',
  'current',
  'calculator',
  'form',
  'fields',
  'inputs',
  'result',
  'results',
  'all',
  'from',
  'of',
  'to',
  'clipboard',
  'please',
  'me',
  'my',
  'only',
  'tylko',
  'these',
  'those',
  'tych',
  'cale',
  'caly',
  'wszystkich',
  'into',
};

/// AI may normalize an explicit whole-form/result request, but cannot create
/// permission to clear from a question, an unrelated sentence or a copy request.
String? _sourceAction(Utterance source) {
  if (referencesInstruction(source) ||
      isNegatedCommand(source) ||
      _savedObject(source) ||
      _accountObject(source) ||
      source.hasStem(const [
        'wyjasn',
        'wytlumacz',
        'explain',
        'przetlumacz',
        'translate',
        'interpret'
      ]) ||
      _negatedScopeVerb.hasMatch(source.folded) ||
      RegExp(r'\b(?:nie (?:chce|chcialbym|chcialabym|nalezy|trzeba)|(?:do not|dont|don t|never) (?:want|need)|bez (?:kopiowania|czyszczenia)|without (?:copying|clearing))\b')
          .hasMatch(source.folded) ||
      RegExp(r'^(?:(?:prosze|please|hej|hey|asystencie)\s+)*(?:jak|how|should i|can i|could i|may i|czy (?:powinienem|powinnam|moge|mozna)|what (?:does|happens))\b')
          .hasMatch(source.folded)) {
    return null;
  }
  final verbs = _scopeVerb.allMatches(source.folded).toList();
  if (verbs.isEmpty) return null;
  final actions = {
    for (final verb in verbs) _copyVerb.hasMatch(verb[1]!) ? 'copy' : 'clear'
  };
  if (actions.length != 1) return null;
  final action = actions.single;
  if (_action(source) == action) return action;
  if (action == 'copy' && !source.hasStem(const ['wynik', 'result']) ||
      action == 'clear' && !_formObject(source)) {
    return null;
  }
  if (verbs.any((v) =>
          !const {'skopiuj', 'kopiuj', 'skopiowac', 'kopiowac', 'copy'}
              .contains(v[1]) &&
          _copyVerb.hasMatch(v[1]!)) &&
      !source.hasStem(const ['schow', 'clipboard'])) {
    return null;
  }
  return action;
}

bool _savedObject(Utterance u) => u.hasStem(const [
      'projekt',
      'histori',
      'dziennik',
      'certyfikat',
      'zapis',
      'raport',
      'project',
      'history',
      'journal',
      'certificate',
      'record',
      'report',
    ]);
bool _accountObject(Utterance u) => u.hasStem(const [
      'konto',
      'profil',
      'haslo',
      'account',
      'profile',
      'password',
    ]);
bool _formObject(Utterance u) => u.hasStem(const [
      'pola',
      'formularz',
      'field',
      'form',
      'input',
    ]);

bool _partialClear(Utterance u) {
  if (u.hasAny(const ['pole', 'field'])) return true;
  if (!u.hasAny(const ['tylko', 'only'])) return false;
  final withoutOnly =
      u.withRaw(u.folded.replaceAll(RegExp(r'\b(?:tylko|only)\b'), '').trim());
  return _action(withoutOnly) != 'clear' &&
      !u.hasStem(const ['formularz', 'form']);
}

bool _sourceTargetsCurrent(Utterance original, String action, String? active) {
  final targets = <String>{};
  var explicitAction = false;
  for (final clause in original.folded.split(_clauses)) {
    final verb = _scopeVerb.firstMatch(clause);
    if (verb == null) continue;
    final copy = _copyVerb.hasMatch(verb.group(1)!);
    if ((copy ? 'copy' : 'clear') != action) continue;
    explicitAction = true;
    final source = original.withRaw(clause);
    if (_accountObject(source) ||
        action == 'clear' &&
            (_partialClear(source) ||
                _savedObject(source) && !_formObject(source))) {
      return false;
    }
    final query = clause
        .substring(verb.end)
        .split(' ')
        .where((w) =>
            w.isNotEmpty &&
            !_scopeFillers.contains(w) &&
            !kAssistantStopWords.contains(w))
        .join(' ');
    if (query.isEmpty) continue;
    final hits = findTools(query, original.lang);
    if (hits.isEmpty) return false;
    // Incidental subtitle words are not an explicit calculator reference.
    if (hits.first.score < query.split(' ').length * 8) continue;
    final top = hits.where((h) => h.score == hits.first.score).toList();
    if (top.length != 1) return false;
    targets.add(top.single.tool.id);
  }
  if (!explicitAction &&
      (_accountObject(original) ||
          action == 'clear' &&
              (_partialClear(original) ||
                  _savedObject(original) && !_formObject(original)))) {
    return false;
  }
  return targets.isEmpty || targets.length == 1 && targets.single == active;
}

String? _action(Utterance u) {
  final match = _verb.firstMatch(u.folded);
  if (match == null) return null;
  final copy = const {'skopiuj', 'kopiuj', 'copy'}.contains(match.group(1));
  final object = match.group(2) ?? '';
  return (copy ? _copyObjects : _clearObjects).contains(object)
      ? (copy ? 'copy' : 'clear')
      : null;
}

/// A named whole-form/result action may require opening that calculator first.
/// No saved records, partial fields, accounts or guessed targets qualify.
({String toolId, String action})? calculatorNavigationPrerequisite(
    Utterance source) {
  if (referencesInstruction(source) ||
      isNegatedCommand(source) ||
      _accountObject(source) ||
      _savedObject(source)) {
    return null;
  }
  final verb = _verb.firstMatch(source.folded);
  if (verb == null) {
    return null;
  }
  final action =
      const {'skopiuj', 'kopiuj', 'copy'}.contains(verb[1]) ? 'copy' : 'clear';
  if (action == 'clear' && _partialClear(source)) {
    return null;
  }
  final query = (verb[2] ?? '')
      .split(' ')
      .where((w) =>
          w.isNotEmpty &&
          !_scopeFillers.contains(w) &&
          !kAssistantStopWords.contains(w))
      .join(' ');
  if (query.isEmpty) {
    return null;
  }
  final hits = findTools(query, source.lang);
  if (hits.isEmpty ||
      hits.first.score < query.split(' ').length * 8 ||
      hits.length > 1 && hits[1].score == hits.first.score) {
    return null;
  }
  final target = hits.first.tool.id;
  return fitterCalculatorActionToolIds.contains(target) &&
          _sourceTargetsCurrent(source, action, target)
      ? (toolId: target, action: action)
      : null;
}

/// Acts only on the visible opt-in calculator, through its actual native port.
class CalculatorActionSkill extends AssistantSkill {
  @override
  bool get canInterruptPendingWithAi => true;
  @override
  Iterable<String> aiTaskSwitchCommands(
      Utterance source, AssistantContext ctx) {
    final active = ctx.modules.activeToolId;
    final action = _sourceAction(source);
    if (action == null ||
        !fitterCalculatorActionToolIds.contains(active) ||
        !_sourceTargetsCurrent(source, action, active)) {
      return const [];
    }
    final example = examples[action == 'copy' ? 0 : 1];
    return [ctx.lang == AppLanguage.en ? example.en : example.pl];
  }

  @override
  String get id => 'calculator.action';
  @override
  String? get toolId => null;
  @override
  SkillActionScope get actionScope => const SkillActionScope(
        toolIds: fitterCalculatorActionToolIds,
        actions: {
          'copy': NativeActionTarget.allResults,
          'clear': NativeActionTarget.allInputs,
        },
      );
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Skopiuj wyniki bieżącego kalkulatora',
            'Copy current calculator results'),
        SkillExample('Wyczyść pola bieżącego kalkulatora',
            'Clear current calculator inputs'),
        SkillExample('Skopiuj wszystkie wyniki', 'Copy all results'),
        SkillExample('Wyczyść formularz', 'Clear the form'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('wyczyść dziennik spoin'),
        SkillRejection('skopiuj hasło do konta'),
        SkillRejection('wyjaśnij polecenie wyczyść formularz'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final active = ctx.modules.activeToolId;
    if (active != null && !fitterCalculatorActionToolIds.contains(active)) {
      return null;
    }
    final action = _action(u);
    if (action != null) {
      return SkillMatch(this, .99,
          slots: {'module_action': action}, utterance: u);
    }
    // A named/natural action must not fall into a calculator's numeric parser
    // and start asking about dimensions instead of interpreting the action.
    if (_verb.hasMatch(u.folded) &&
        (active != null ||
            _formObject(u) ||
            u.hasStem(const ['wynik', 'result']))) {
      return SkillMatch(this, .99,
          utterance: u, requiresAiInterpretation: true);
    }
    return null;
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final proposed = _action(command);
    return proposed != null &&
        _sourceAction(original) == proposed &&
        _sourceTargetsCurrent(original, proposed, context.modules.activeToolId);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final modules = ctx.modules;
    final active = modules.activeToolId;
    if (!fitterCalculatorActionToolIds.contains(active) ||
        modules is! ModuleActionContext) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz kalkulator montera, którego pola lub wyniki chcesz użyć, i powtórz polecenie.',
                  'Open the fitter calculator whose inputs or results you want to use and repeat the command.')),
          actionCompleted: false);
    }
    final action = m.slots['module_action'];
    if (action != 'copy' && action != 'clear') {
      return const FailedResult(
          AssistantText(
              'Nieznana czynność kalkulatora.', 'Unknown calculator action.'),
          reportMissingCapability: false);
    }
    final result = await (modules as ModuleActionContext)
        .performModuleAction(active!, action as String);
    return AnswerResult(AssistantAnswer(text: result.message),
        actionCompleted: result.completed);
  }
}
