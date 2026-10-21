import '../../../i18n/app_language.dart';
import '../../core/command_words.dart';
import '../../../database/weld_param_dao.dart';
import '../../../models/weld_param.dart';
import '../../assistant_intents.dart';
import '../../assistant_parser.dart';
import '../../assistant_validator.dart';
import '../../assistant_local_ops.dart';
import '../../core/skill.dart';

typedef SavedParamsReader = Future<List<WeldParam>> Function();

class MyParamsSkill extends AssistantSkill {
  MyParamsSkill({Future<List<WeldParam>> Function()? load})
      : _load = load ?? WeldParamDao().listAll;
  final Future<List<WeldParam>> Function() _load;
  @override
  String get id => 'params.saved';
  @override
  String get toolId => 'welder_pipes';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Jaki prąd mam zapisany na nierdzewkę 2 mm',
            'What current have I saved for stainless 2 mm'),
        SkillExample(
            'Pokaż moje parametry TIG', 'Show my saved TIG parameters'),
        SkillExample('Jakie parametry mam zapisane na duplex',
            'What have I saved for duplex'),
        SkillExample(
            'Pokaż moje parametry MMA', 'Show my saved MMA parameters'),
        SkillExample(
            'Co zapisałem na aluminium', 'What did I save for aluminium'),
        SkillExample('Pokaż moje zapisy na stal czarną',
            'Show my saved parameters for carbon steel'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Jaki prąd na TIG nierdzewka 2 mm?'),
        SkillRejection('Zapisz TIG nierdzewka 2 mm 60 A bez drutu'),
        SkillRejection('What current for TIG stainless 2 mm?',
            lang: AppLanguage.en),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext c) {
    if (referencesInstruction(u)) return null;
    if (!u.hasStem(['zapis', 'zapamiet', 'moj', 'moich', 'parametr', 'sav']) &&
        !u.hasAny(['my', 'have i', 'did i'])) {
      return null;
    }
    final parsed = parseAssistantCommand(u.raw);
    return parsed.intent == kIntentQueryMyParams
        ? SkillMatch(this, .94, slots: parsed.fields, utterance: u)
        : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext c) async {
    final check = validateAssistantProposal(kIntentQueryMyParams, m.slots);
    if (check is! AssistantReadyToQuery) {
      return const FailedResult(AssistantText(
          'Niepoprawne kryteria odczytu.', 'Invalid search criteria.'));
    }
    final hits = findMyWeldParams(await _load(), check.criteria);
    final description = describeMyParamsQuery(check.criteria, c.lang);
    return AnswerResult(AssistantAnswer(
        text: hits.isEmpty
            ? AssistantText('Nie masz zapisanych parametrów dla: $description.',
                'No saved parameters for: $description.')
            : AssistantText(
                'Zapisane parametry ($description): ${hits.length}.',
                'Saved parameters ($description): ${hits.length}.'),
        lines: [
          for (var i = 0; i < hits.length; i++)
            AnswerLine(AssistantText('Zapis ${i + 1}', 'Entry ${i + 1}'),
                myWeldParamLine(hits[i], c.lang))
        ]));
  }
}
