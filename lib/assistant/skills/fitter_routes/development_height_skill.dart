import '../../../domain/fitter/cone_assistant_input.dart';
import '../../../domain/fitter/eccentric_cone_assistant_input.dart';
import '../../../domain/fitter/transition_assistant_input.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';
import 'quantities.dart';

final _direct = RegExp(r'^(?:(?:prosze|please) )?(?:zmien|ustaw|change|set) ');
final _natural = RegExp(r'^(?:niech|chce zeby|potrzebuje zeby|i want|i need) ');

double? _height(Utterance source, {bool natural = false}) {
  if (referencesInstruction(source) || isNegatedCommand(source)) return null;
  final u = source
      .withRaw(source.raw.replaceAll(RegExp(r'[-−]\s*(?=\d)'), ' minus '));
  if (!_direct.hasMatch(u.folded) &&
      !(natural && _natural.hasMatch(u.folded))) {
    return null;
  }
  final n = lengthNear(u, const ['wysokosc', 'height']);
  if (n == null ||
      !n.isFinite ||
      n <= 0 ||
      u.items.where((i) => i.isNumber).length != 1 ||
      u.items
              .where((i) => !i.isNumber && lengthUnitScale(i.word) != null)
              .length !=
          1) {
    return null;
  }
  const allowed = {
    'prosze',
    'please',
    'zmien',
    'ustaw',
    'change',
    'set',
    'tylko',
    'only',
    'wysokosc',
    'height',
    'na',
    'to',
    'niech',
    'chce',
    'zeby',
    'potrzebuje',
    'i',
    'want',
    'need',
    'the',
    'be',
    'wynosi',
    'reszte',
    'zostaw',
    'bez',
    'zmian',
    'keep',
    'rest',
    'unchanged'
  };
  for (final item in u.items) {
    if (!item.isNumber &&
        !allowed.contains(item.word) &&
        lengthUnitScale(item.word) == null) {
      return null;
    }
  }
  return n;
}

Map<String, Object?>? _relative(Utterance source, {bool natural = false}) {
  if (referencesInstruction(source) || isNegatedCommand(source)) return null;
  var text = source.folded.replaceFirst(RegExp(r'^(?:prosze|please) '), '');
  if (natural) {
    text = text.replaceFirst(
        RegExp(r'^(?:chce zeby|potrzebuje zeby|i want you to|i need you to) '),
        '');
  }
  if (const ['podwoj wysokosc', 'double height', 'double the height']
      .contains(text)) {
    return {'height_operation': 'scale', 'amount': 2.0};
  }
  if (const ['zmniejsz wysokosc o polowe', 'halve height', 'halve the height']
      .contains(text)) {
    return {'height_operation': 'scale', 'amount': .5};
  }
  final direction = RegExp(
          r'^(zwieksz(?:yc)?|zmniejsz(?:yc)?|increase|decrease) (?:tylko |only |the )?(?:wysokosc|height) (?:o|by) ')
      .firstMatch(text);
  if (direction == null) return null;
  final u = source
      .withRaw(source.raw.replaceAll(RegExp(r'[-−]\s*(?=\d)'), ' minus '));
  final tail = source.withRaw(text.substring(direction.end));
  final nums = <double>[];
  for (var i = 0; i < tail.items.length; i++) {
    final item = tail.items[i];
    if (item.isNumber) {
      if (i + 1 >= tail.items.length) return null;
      final scale = lengthUnitScale(tail.items[i + 1].word);
      if (scale == null) return null;
      nums.add(signedQuantity(tail, i) * scale);
    } else if (lengthUnitScale(item.word) == null ||
        i == 0 ||
        !tail.items[i - 1].isNumber) {
      return null;
    }
  }
  // Check the original sign as folding of punctuation deliberately drops it.
  if (RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(u.raw.toLowerCase()) ||
      nums.length != 1 ||
      !nums.single.isFinite ||
      nums.single <= 0) {
    return null;
  }
  final verb = direction[1]!;
  return {
    'height_operation':
        verb.startsWith('zwieksz') || verb == 'increase' ? 'add' : 'subtract',
    'amount': nums.single
  };
}

Map<String, Object?>? _visible(AssistantContext ctx) {
  final modules = ctx.modules;
  return modules.activeToolId == 'cone_layout' && modules is FieldModuleContext
      ? (modules as FieldModuleContext).inputFields('cone_layout')
      : null;
}

double _currentHeight(Map<String, Object?> base) => switch (base['shape']) {
      'concentric' => ConeAssistantInput.fromFields(base).result.heightMm,
      'eccentric' =>
        EccentricConeAssistantInput.fromFields(base).input.heightMm,
      'transition' => TransitionAssistantInput.fromFields(base).input.heightMm,
      _ => throw const FormatException('unknown shape'),
    };

double _resolve(Map<String, Object?> operation, Map<String, Object?>? base) {
  if (operation['height_mm'] case final num value) return value.toDouble();
  if (base == null || operation['amount'] is! num) {
    throw const FormatException('missing visible height');
  }
  final current = _currentHeight(base),
      amount = (operation['amount'] as num).toDouble();
  return switch (operation['height_operation']) {
    'add' => current + amount,
    'subtract' => current - amount,
    'scale' => current * amount,
    _ => throw const FormatException('unknown height operation'),
  };
}

class DevelopmentHeightSkill extends AssistantSkill {
  @override
  String get id => 'development.height';
  @override
  String get toolId => 'cone_layout';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Zmień tylko wysokość na 500 mm', 'Change only height to 500 mm'),
        SkillExample('Zwiększ wysokość o 100 mm', 'Increase height by 100 mm'),
        SkillExample('Zmniejsz wysokość o połowę', 'Halve height'),
        SkillExample('Podwój wysokość', 'Double height'),
        SkillExample('Ustaw wysokość na 60 cm', 'Set height to 60 cm'),
        SkillExample('Zmniejsz wysokość o 10 cm', 'Decrease height by 10 cm'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final active = ctx.modules.activeToolId;
    if (active != null && active != toolId) return null;
    final value = _height(u);
    final operation =
        value != null ? <String, Object?>{'height_mm': value} : _relative(u);
    return operation == null
        ? null
        : SkillMatch(this, .99, slots: operation, utterance: u);
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final height = _height(original, natural: true),
        proposed = _height(command);
    final source = height != null
        ? <String, Object?>{'height_mm': height}
        : _relative(original, natural: true);
    final target = proposed != null
        ? <String, Object?>{'height_mm': proposed}
        : _relative(command);
    if (source == null || target == null) return false;
    try {
      final base = _visible(context);
      final expected = _resolve(source, base), actual = _resolve(target, base);
      return expected.isFinite && expected > 0 && expected == actual;
    } on FormatException {
      return false;
    }
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final base = _visible(ctx);
    if (base == null) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz rozwinięcie stożka lub przejścia i powtórz zmianę wysokości.',
                  'Open a cone or transition development and repeat the height change.')),
          actionCompleted: false);
    }
    final next = <String, Object?>{...base};
    try {
      next['height_mm'] = _resolve(m.slots, base);
      switch (base['shape']) {
        case 'concentric':
          ConeAssistantInput.fromFields(base);
          next.remove('half_angle_deg');
          next.remove('slant_mm');
          next['mode'] = 'height';
          ConeAssistantInput.fromFields(next);
        case 'eccentric':
          EccentricConeAssistantInput.fromFields(base);
          EccentricConeAssistantInput.fromFields(next);
        case 'transition':
          TransitionAssistantInput.fromFields(base);
          TransitionAssistantInput.fromFields(next);
        default:
          throw const FormatException('unknown shape');
      }
    } on FormatException {
      return const FailedResult(
          AssistantText(
              'Formularz ma niepełne lub nieprawidłowe dane. Popraw je przed zmianą wysokości.',
              'The form has incomplete or invalid inputs. Correct them before changing height.'),
          reportMissingCapability: false);
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Ustawiam wysokość na ${next['height_mm']} mm. Pozostałe wymiary i ustawienia zachowuję. Stożek współosiowy będzie liczony z wysokości.',
                'Setting height to ${next['height_mm']} mm. Other dimensions and settings are preserved. A concentric cone will use height-defined geometry.')),
        show: ShowInModule(toolId, next));
  }
}
