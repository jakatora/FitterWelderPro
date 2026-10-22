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
      u.items.where((i) => i.isNumber).length != 1) {
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
        SkillExample('Ustaw wysokość na 60 cm', 'Set height to 60 cm'),
        SkillExample('Zmień wysokość na 1 m', 'Change height to 1 m'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final active = ctx.modules.activeToolId;
    if (active != null && active != toolId) return null;
    final value = _height(u);
    return value == null
        ? null
        : SkillMatch(this, .99, slots: {'height_mm': value}, utterance: u);
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final height = _height(original, natural: true);
    return height != null && height == _height(command);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final modules = ctx.modules;
    final base = modules.activeToolId == toolId && modules is FieldModuleContext
        ? (modules as FieldModuleContext).inputFields(toolId)
        : null;
    if (base == null) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz rozwinięcie stożka lub przejścia i powtórz zmianę wysokości.',
                  'Open a cone or transition development and repeat the height change.')),
          actionCompleted: false);
    }
    final next = <String, Object?>{...base, 'height_mm': m.slots['height_mm']};
    try {
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
                'Ustawiam wysokość na ${m.slots['height_mm']} mm. Pozostałe wymiary i ustawienia zachowuję. Stożek współosiowy będzie liczony z wysokości.',
                'Setting height to ${m.slots['height_mm']} mm. Other dimensions and settings are preserved. A concentric cone will use height-defined geometry.')),
        show: ShowInModule(toolId, next));
  }
}
