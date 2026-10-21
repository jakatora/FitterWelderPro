import '../../../domain/grinding/grinding_check.dart';
import '../../../domain/grinding/stripe_reference.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';
import 'colour_words.dart';

Map<String, Object?> _slots(Utterance u) {
  final colours = spokenColours(u);
  final combo = colours.length == 2 &&
      colours.contains('blue') &&
      colours.contains('yellow') &&
      (u.raw.contains('+') ||
          u.hasStem(const ['niebiesko', 'dwukolor', 'combined']) ||
          u.hasAny(const ['two colour', 'two color']));
  final colourIndices = [
    for (var i = 0; i < u.tokens.length; i++)
      if (colourStems.values.any((stems) => stems.any(
          (v) => v.length <= 3 ? u.tokens[i] == v : u.tokens[i].startsWith(v))))
        i
  ];
  final stripes = [
    for (var i = 0; i < u.tokens.length; i++)
      if (u.tokens[i].startsWith('pask') ||
          u.tokens[i].startsWith('pasek') ||
          u.tokens[i].startsWith('stripe'))
        i
  ];
  final bodies = [
    for (var i = 0; i < u.tokens.length; i++)
      if (u.tokens[i].startsWith('tarc') ||
          u.tokens[i] == 'disc' ||
          u.tokens[i] == 'wheel')
        i
  ];
  final bodyOnly = colourIndices.isNotEmpty &&
      colourIndices.every((i) =>
          bodies.any((b) => (i - b).abs() == 1) &&
          !stripes.any((p) => (i - p).abs() <= 1));
  return {
    if (bodyOnly) 'body_only': true,
    if (colours.isNotEmpty)
      'stripe': bodyOnly
          ? 'ambiguous'
          : combo
              ? 'blueYellow'
              : colours.length == 1
                  ? colours.single
                  : 'ambiguous',
    if (u.hasStem(const ['listkow', 'flap', 'diament', 'diamond']))
      'outside': true,
    if (u.hasAny(const [
          'czy moge',
          'can i',
          'is it safe',
          'czy ok',
          'czy pasuje'
        ]) ||
        u.hasStem(const ['obrot', 'rpm', 'szlifierk', 'grinder']) &&
            u.hasStem(const [
              'dobierz',
              'sprawdz',
              'check',
              'uzyc',
              'uzyw',
              'use',
              'mog',
              'can',
              'obrot',
              'rpm'
            ]))
      'assessment': true,
  };
}

class GrindingStripeSkill extends AssistantSkill {
  @override
  String get id => 'grinding.stripe';
  @override
  String get toolId => 'grinding';
  @override
  bool get answersQuestionsOnly => true;
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Czerwony pasek na tarczy co oznacza',
            'Red stripe on a grinding disc meaning'),
        SkillExample('Niebieski pasek na tarczy co oznacza',
            'Blue stripe on an abrasive disc meaning'),
        SkillExample('Żółty pasek na tarczy jaka prędkość',
            'Yellow stripe on a grinding disc speed'),
        SkillExample('Zielony pasek na tarczy jaka prędkość',
            'Green stripe on a grinding disc speed'),
        SkillExample('Niebiesko-żółty pasek tarczy co oznacza',
            'Blue + yellow stripe on a grinding disc meaning'),
        SkillExample('Pokaż informację o czerwonym pasku na tarczy',
            'Show red stripe information for a grinding disc'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Zielony pas ile ton', routesTo: 'rigging.colour'),
        SkillRejection('Otwórz tarcze i szlifierki', routesTo: 'tool.open'),
        SkillRejection('zapisz TIG 2 mm 60 A'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!u.hasStem(const ['pasek', 'pask', 'stripe'])) return null;
    if (isNegatedCommand(u) ||
        kCommandVerbRe.hasMatch(u.folded) ||
        u.hasStem(const [
          'przetlum',
          'translat',
          'ustaw',
          'wybierz',
          'select',
          'zawies',
          'sling'
        ])) {
      return null;
    }
    final stripe = u.hasStem(const ['pasek', 'pask', 'stripe']);
    if (!stripe ||
        (!u.hasStem(const ['tarc', 'disc', 'wheel']) &&
            ctx.modules.activeToolId != 'grinding')) {
      return null;
    }
    return SkillMatch(this, .96, slots: _slots(u), utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) => const {};
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    return s.containsKey(slot) ? s : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    if (m.slots['outside'] == true) {
      return const FailedResult(
          AssistantText(
              'Ta tabela pasków dotyczy wyrobów ściernych spojonych EN 12413, nie tarcz listkowych ani diamentowych.',
              'This stripe table is for bonded abrasives EN 12413, not flap or diamond discs.'),
          reportMissingCapability: true);
    }
    if (m.slots['assessment'] == true) {
      return const FailedResult(
          AssistantText(
              'Nie wyznaczam dopuszczalnych obrotów ani zgodności szlifierki na podstawie samego koloru paska. Potrzebny jest nadruk i pełne dane sprzętu.',
              'Colour alone cannot determine permitted RPM or grinder compatibility. Printed ratings and complete equipment data are needed.'),
          reportMissingCapability: true);
    }
    final stripe = SpeedStripe.values
        .where((s) => s.name == m.slots['stripe'])
        .firstOrNull;
    if (m.slots['stripe'] == null || m.slots['stripe'] == 'ambiguous') {
      return AskResult(
          'stripe',
          m.slots['body_only'] == true
              ? const AssistantText(
                  'Kolor całej tarczy nie określa paska prędkości. Jaki kolor ma sam pasek?',
                  'Disc body colour does not identify its speed stripe. What colour is the stripe itself?')
              : const AssistantText(
                  'Który pasek? Wybierz jeden kolor lub wyraźnie pasek dwukolorowy.',
                  'Which stripe? Choose one colour or explicitly the combined stripe.'),
          partial: m,
          choices: [
            for (final s in SpeedStripe.values)
              FollowUp(AssistantText(s.colourPl, s.colourEn), s.colourEn)
          ]);
    }
    if (stripe == null) {
      return const FailedResult(
          AssistantText(
              'Ten kolor nie występuje w tabeli pasków aplikacji. Odczytaj nadruk producenta.',
              'This colour is absent from the app stripe table. Read the manufacturer print.'),
          reportMissingCapability: true);
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(grindingStripeReference(stripe, en: false),
                grindingStripeReference(stripe, en: true)),
            source: AssistantText.same(kSrcColour)),
        show: ShowInModule('grinding', {'reference_stripe': stripe.name}));
  }
}
