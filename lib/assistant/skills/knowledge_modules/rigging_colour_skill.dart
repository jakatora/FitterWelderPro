import '../../../domain/rigging/rigging_colors.dart';
import '../../../domain/rigging/colour_reference.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';
import 'colour_words.dart';

Map<String, Object?> _slots(Utterance u) {
  final colours = spokenColours(u);
  return {
    if (u.hasStem(const ['material', 'tworzyw', 'fabric', 'fibre', 'fiber']))
      'material_question': true,
    if (colours.isNotEmpty)
      'colour': colours.length == 1 ? colours.single : 'ambiguous',
    if (u.hasStem(const ['etykiet', 'label', 'tag']) ||
        u.hasAny(const [
          'kolor pasa',
          'kolor zawiesia',
          'sling colour',
          'sling color',
          'kolor tkaniny',
          'body colour',
          'body color'
        ]))
      'part': u.hasStem(const ['etykiet', 'label', 'tag'])
          ? (colours.length > 1 ||
                  u.hasAny(const [
                    'kolor pasa',
                    'kolor zawiesia',
                    'sling colour',
                    'sling color',
                    'body colour',
                    'body color'
                  ])
              ? 'ambiguous'
              : 'tag')
          : 'body',
    if (u.hasAny(const [
      'bez etykiety',
      'brak etykiety',
      'nieczytelna etykieta',
      'no label',
      'no tag',
      'unreadable label'
    ]))
      'missing_label': true,
    if (u.hasStem(const [
          'podnies',
          'unies',
          'wytrzym',
          'wystarcz',
          'utrzym',
          'koszow',
          'zaduszn',
          'dzwig'
        ]) ||
        u.hasAny(const [
          'can i lift',
          'can lift',
          'czy moge',
          'czy ok',
          'safe to lift'
        ]))
      'assessment': true,
  };
}

class RiggingColourSkill extends AssistantSkill {
  @override
  String get id => 'rigging.colour';
  @override
  String get toolId => 'rigging';
  @override
  bool get answersQuestionsOnly => true;
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Zielony pas ile ton', 'Green sling colour capacity'),
        SkillExample(
            'Fioletowy pas jaki kod nośności', 'Violet sling colour capacity'),
        SkillExample('Żółte zawiesie jaki kolor nośność',
            'Yellow sling colour capacity'),
        SkillExample(
            'Pomarańczowy pas ile ton', 'Orange sling colour capacity'),
        SkillExample('Niebieska etykieta zawiesia jaki materiał',
            'Blue sling label material'),
        SkillExample('Brązowa etykieta zawiesia jaki materiał',
            'Brown sling label material'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Czerwony pasek na tarczy', routesTo: 'grinding.stripe'),
        SkillRejection('Otwórz zawiesia i podwieszanie', routesTo: 'tool.open'),
        SkillRejection('zapisz MMA 2 mm 80 A'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final topic = u.hasStem(const ['zawies', 'sling', 'webbing', 'rigging']) ||
        u.hasAny(const [
          'pas',
          'pasa',
          'pasy',
          'pasie',
          'pasem',
          'pasow',
          'pasami',
          'pasach',
          'strap',
          'straps'
        ]);
    if (!topic &&
        !(ctx.modules.activeToolId == 'rigging' &&
            u.hasStem(const [
              'kolor',
              'colour',
              'color',
              'etykiet',
              'label',
              'tag'
            ]))) {
      return null;
    }
    if (isNegatedCommand(u) ||
        kCommandVerbRe.hasMatch(u.folded) ||
        u.hasStem(const [
          'przetlum',
          'translat',
          'ustaw',
          'wybierz',
          'select',
          'tarc',
          'disc',
          'szlifier'
        ])) {
      return null;
    }
    final s = _slots(u);
    if (kOpenVerbAtStartRe.hasMatch(u.folded) && !s.containsKey('colour')) {
      return null;
    }
    if (!s.containsKey('colour') &&
        !u.hasStem(const ['kolor', 'colour', 'color']) &&
        s['missing_label'] != true &&
        s['assessment'] != true) {
      return null;
    }
    return SkillMatch(this, .96, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) => const {};
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (slot == 'part' && u.hasAny(const ['pas', 'sling', 'tkanina', 'body'])) {
      return {'part': 'body'};
    }
    return s.containsKey(slot) ? s : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final s = m.slots;
    if (s['missing_label'] == true) {
      return const FailedResult(AssistantText(
          'Brak lub nieczytelna etykieta zawiesia oznacza STOP. Sam kolor nie zastępuje danych etykiety.',
          'A missing or unreadable sling label means STOP. Colour cannot replace label data.'));
    }
    if (s['assessment'] == true) {
      return const FailedResult(
          AssistantText(
              'Sam kod koloru nie ocenia konkretnego podnoszenia. Potrzebne są dane etykiety, układ, kąty, obciążenie i kontrola; sterowanie tą oceną wymaga osobnego polecenia kalkulatora.',
              'A colour code cannot assess a lift. Label data, hitch, angles, load and inspection are needed; assistant control of that assessment needs a separate calculator capability.'),
          reportMissingCapability: true);
    }
    if (s['material_question'] == true && s['part'] != 'tag') {
      return AskResult(
          'colour',
          const AssistantText(
              'Kolor tkaniny nie określa materiału. Jaki kolor ma etykieta zawiesia?',
              'Body colour does not identify the material. What colour is the sling label?'),
          partial: m.copyWith(slots: {
            ...s,
            'colour': null,
            'part': 'tag',
            'material_question': false
          }),
          choices: [
            for (final c in slingTagMaterials.keys)
              FollowUp(AssistantText(c.labelPl, c.labelEn), c.labelEn)
          ]);
    }
    if (s['part'] == 'ambiguous') {
      return AskResult(
          'part',
          const AssistantText(
              'Pytasz o kolor samego pasa czy o kolor etykiety?',
              'Do you mean the sling body colour or the label colour?'),
          partial: m,
          choices: const [
            FollowUp(AssistantText('Pas', 'Body'), 'body'),
            FollowUp(AssistantText('Etykieta', 'Label'), 'label')
          ]);
    }
    final c =
        SlingColour.values.where((c) => c.name == s['colour']).firstOrNull;
    if (s['colour'] == null || s['colour'] == 'ambiguous') {
      return AskResult(
          'colour',
          const AssistantText(
              'Jaki jeden kolor widzisz?', 'Which single colour do you see?'),
          partial: m,
          choices: [
            for (final v in SlingColour.values.where((v) => v.nominalT != null))
              FollowUp(AssistantText(v.labelPl, v.labelEn), v.labelEn)
          ]);
    }
    final tag = s['part'] == 'tag';
    if (c == null ||
        c.nominalT == null ||
        (tag && !slingTagMaterials.containsKey(c))) {
      return const FailedResult(
          AssistantText(
              'Ten kolor nie ma wpisu w odpowiednim kodzie tabeli aplikacji. Odczytaj oznakowanie producenta.',
              'This colour has no entry in the relevant app colour code. Read the manufacturer marking.'),
          reportMissingCapability: true);
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(slingColourReference(c, tag: tag, en: false),
                slingColourReference(c, tag: tag, en: true)),
            source: AssistantText.same(tag
                ? 'EN 1492-1/-2 · DGUV Information 209-013, rozdz./section 10'
                : 'EN 1492-1/-2 · DGUV Information 209-021 (08/2021)')),
        show: ShowInModule('rigging', {
          'reference_colour': c.name,
          'reference_part': tag ? 'tag' : 'body'
        }));
  }
}
