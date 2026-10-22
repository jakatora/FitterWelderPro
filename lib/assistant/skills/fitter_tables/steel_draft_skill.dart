import '../../../domain/steel_weight/steel_sections.dart' show standardOf;
import '../../../domain/steel_weight/steel_draft_fields.dart';
import '../../assistant_validator.dart' show assistantNumber;
import '../../core/skill.dart';
import '../../core/command_words.dart';
import '../fitter_routes/quantities.dart';

Map<String, Object?>? _edit(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) ||
      isNegatedCommand(u) ||
      RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(u.raw.toLowerCase())) {
    return null;
  }
  final text = u.folded.replaceFirst(RegExp(r'^(?:prosze|please) '), '');
  var length = RegExp(
          r'^(?:ustaw|zmien|set|change) (?:dlugosc(?: stali)?|(?:steel )?length) (?:na |to )?(.+)$')
      .firstMatch(text);
  if (natural) {
    length ??=
        RegExp(r'^(?:niech dlugosc wynosi|i need the length to be) (.+)$')
            .firstMatch(text);
    length ??=
        RegExp(r'^(?:a |and )?(?:dlugosc|length) (.+)$').firstMatch(text);
  }
  if (length != null) {
    final value = u.withRaw(length[1]!);
    if (value.items.length != 2 || !value.items.first.isNumber) {
      return null;
    }
    final scale = lengthUnitScale(value.items.last.word);
    final n = value.items.first.value! * (scale ?? 0);
    return scale != null && n.isFinite && n > 0 ? {'length_mm': n} : null;
  }
  var quantity = RegExp(
          r'^(?:ustaw|zmien|set|change) (?:ilosc(?: stali)?|liczbe sztuk(?: stali)?|(?:steel )?(?:quantity|count)) (?:na |to )?(.+)$')
      .firstMatch(text);
  if (natural) {
    quantity ??= RegExp(
            r'^(?:potrzebuje|i need) (.+?)(?: takich sztuk| takich| of these pieces| of these)$')
        .firstMatch(text);
    quantity ??=
        RegExp(r'^(?:a |and )?(?:ilosc|quantity|count) (.+)$').firstMatch(text);
  }
  if (quantity == null) return null;
  final value = u.withRaw(quantity[1]!);
  if (value.items.isEmpty ||
      value.items.length > 2 ||
      !value.items.first.isNumber) {
    return null;
  }
  if (value.items.length == 2 &&
      !const ['sztuk', 'sztuki', 'szt', 'pcs', 'pieces']
          .contains(value.items.last.word)) {
    return null;
  }
  final n = value.items.first.value!;
  return n.isFinite && n > 0 && n == n.roundToDouble() && n <= 2147483647
      ? {'quantity': n.toInt()}
      : null;
}

Map<String, Object?>? _visible(AssistantContext ctx) {
  final port = ctx.modules;
  return port.activeToolId == 'steel_weight' && port is FieldModuleContext
      ? (port as FieldModuleContext).inputFields('steel_weight')
      : null;
}

class SteelDraftEditSkill extends AssistantSkill {
  @override
  String get id => 'steel.draft.edit';
  @override
  String get toolId => 'steel_weight';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ustaw ilość stali na 5', 'Set steel quantity to 5'),
        SkillExample(
            'Zmień długość stali na 3 m', 'Change steel length to 3 m'),
        SkillExample(
            'Ustaw długość stali na 2500 mm', 'Set steel length to 2500 mm'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final active = ctx.modules.activeToolId;
    if (active != toolId &&
        (active != null || !u.hasAny(const ['stali', 'steel']))) {
      return null;
    }
    final fields = _edit(u);
    return fields == null
        ? null
        : SkillMatch(this, .99, slots: fields, utterance: u);
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final source = _edit(original, natural: true), target = _edit(command);
    return source != null &&
        target != null &&
        source.length == 1 &&
        source.keys.single == target.keys.single &&
        source.values.single == target.values.single;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final base = _visible(ctx);
    if (base == null) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz zakładkę Profil w Ciężarze stali, żeby zmienić bieżącą pozycję.',
                  'Open the Profile tab in Steel weight to change the current item.')),
          actionCompleted: false);
    }
    final next = {...base, ...m.slots};
    if (m.slots.length != 1 ||
        !const {'length_mm', 'quantity'}.contains(m.slots.keys.single) ||
        steelDraftFromFields(next) == null) {
      return const FailedResult(
          AssistantText('Nieprawidłowa długość lub liczba sztuk.',
              'Invalid length or quantity.'),
          reportMissingCapability: false);
    }
    return AnswerResult(
        const AssistantAnswer(
            text: AssistantText('Zmieniam bieżącą pozycję w kalkulatorze.',
                'Updating the current calculator item.')),
        show: ShowInModule(toolId, next));
  }
}

bool _summary(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) || isNegatedCommand(u)) return false;
  final text = u.folded.replaceFirst(RegExp(r'^(?:prosze|please) '), '');
  return const [
        'ile wazy biezaca pozycja',
        'ile wazy biezaca pozycja stali',
        'podsumuj biezaca pozycje stali',
        'how much does the current steel item weigh',
        'summarize current steel item'
      ].contains(text) ||
      natural &&
          const ['ile tego bedzie wazylo', 'how much will these weigh']
              .contains(text);
}

class SteelDraftSummarySkill extends AssistantSkill {
  @override
  String get id => 'steel.draft.summary';
  @override
  String get toolId => 'steel_weight';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile waży bieżąca pozycja stali',
            'How much does the current steel item weigh'),
        SkillExample(
            'Podsumuj bieżącą pozycję stali', 'Summarize current steel item'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      (ctx.modules.activeToolId == toolId ||
                  ctx.modules.activeToolId == null &&
                      u.hasAny(const ['stali', 'steel'])) &&
              _summary(u)
          ? SkillMatch(this, .99, utterance: u)
          : null;
  @override
  bool acceptsProposal(
          Utterance original, Utterance command, AssistantContext context) =>
      _summary(original, natural: true) && _summary(command);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final base = _visible(ctx);
    if (base == null) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz zakładkę Profil w Ciężarze stali, żeby odczytać bieżącą pozycję.',
                  'Open the Profile tab in Steel weight to read the current item.')),
          actionCompleted: false);
    }
    final item = steelDraftFromFields(base);
    if (item == null) {
      return const FailedResult(
          AssistantText(
              'Nie widzę poprawnej bieżącej pozycji stali. Otwórz zakładkę Profil.',
              'No valid current steel item is visible. Open the Profile tab.'),
          reportMissingCapability: false);
    }
    final mass = assistantNumber(item.totalKg, ctx.lang);
    final length = assistantNumber(item.lengthMm, ctx.lang);
    return AnswerResult(AssistantAnswer(
        text: AssistantText(
            '${item.label(english: false)}: $mass kg. ${item.count} szt., długość jednej $length mm. Materiał: ${item.material.label(false)}.',
            '${item.label(english: true)}: $mass kg. ${item.count} pieces, length each $length mm. Material: ${item.material.label(true)}.'),
        source: AssistantText.same(
            '${standardOf(item.shape)}; ρ = ${item.material.density} kg/m³')));
  }
}
