import 'package:flutter/foundation.dart' show mapEquals;
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

// Conversational wording is normalized by AI, then independently checked here.
// An unspecified amount stays unspecified and becomes a native follow-up.
Map<String, Object?>? _conversationalHeight(Utterance source) {
  if (referencesInstruction(source) || isNegatedCommand(source)) return null;
  final text = source.folded.replaceFirst(RegExp(r'^(?:prosze|please) '), '');
  final pl = RegExp(
          r'^zrob (?:go|to|ten stozek|to przejscie) (?:troche )?(wyzsz(?:y|ego)|nizsz(?:y|ego))(?: o (.+))?$')
      .firstMatch(text);
  final en = RegExp(
          r'^make (?:it|this cone|this transition) (?:a little )?(taller|shorter)(?: by (.+))?$')
      .firstMatch(text);
  final m = pl ?? en;
  if (m == null) return null;
  final add = m[1]!.startsWith('wyzsz') || m[1] == 'taller';
  final amountText = m[2];
  if (amountText == null) return {'height_operation': add ? 'add' : 'subtract'};
  final amount = _heightDelta(source.withRaw(amountText));
  if (amount == null) return null;
  // Folding removes minus punctuation; reject the original negative sign too.
  if (RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(source.raw.toLowerCase())) {
    return null;
  }
  return {'height_operation': add ? 'add' : 'subtract', 'amount': amount};
}

double? _heightDelta(Utterance source) {
  if (referencesInstruction(source) ||
      isNegatedCommand(source) ||
      RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(source.raw.toLowerCase())) {
    return null;
  }
  final u =
      source.withRaw(source.folded.replaceFirst(RegExp(r'^(?:o|by) '), ''));
  if (u.items.length != 2 || !u.items.first.isNumber) return null;
  final scale = lengthUnitScale(u.items.last.word);
  final n = u.items.first.value! * (scale ?? 0);
  return scale != null && n.isFinite && n > 0 ? n : null;
}

// AI may resolve an explicit correction or half of an explicit length in the
// still-owned amount question. Check the user's operands independently; never
// accept the first number found in arbitrary prose or evaluate arbitrary math.
double? _interpretedHeightDelta(Utterance source) {
  if (referencesInstruction(source) ||
      isNegatedCommand(source) ||
      RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(source.raw.toLowerCase())) {
    return null;
  }
  final literal = _heightDelta(source);
  if (literal != null) return literal;
  final text = source.folded;
  final prefix =
      RegExp(r'^(?:jednak|wlasciwie|mam na mysli|actually|i mean) (.+)$')
          .firstMatch(text);
  if (prefix != null) return _heightDelta(source.withRaw(prefix[1]!));
  for (final pattern in [
    (RegExp(r'^(.+) (?:zamiast|instead of) (.+)$'), 1),
    (RegExp(r'^(?:nie|not) (.+) (?:tylko|but) (.+)$'), 2),
  ]) {
    final m = pattern.$1.firstMatch(text);
    if (m == null) continue;
    final first = _heightDelta(source.withRaw(m[1]!));
    final second = _heightDelta(source.withRaw(m[2]!));
    if (first == null || second == null) return null;
    return pattern.$2 == 1 ? first : second;
  }
  final half = RegExp(r'^(?:polowa|half(?: of)?) (.+)$').firstMatch(text);
  if (half != null) {
    final full = _heightDelta(source.withRaw(half[1]!));
    final value = full == null ? null : full / 2;
    return value != null && value.isFinite && value > 0 ? value : null;
  }
  return null;
}

Map<String, Object?>? _relative(Utterance source, {bool natural = false}) {
  if (referencesInstruction(source) || isNegatedCommand(source)) return null;
  var text = source.folded.replaceFirst(RegExp(r'^(?:prosze|please) '), '');
  if (natural) {
    text = text.replaceFirst(
        RegExp(r'^(?:chce zeby|potrzebuje zeby|i want you to|i need you to) '),
        '');
  }
  if (const ['zwieksz wysokosc', 'increase height', 'increase the height']
      .contains(text)) {
    return {'height_operation': 'add'};
  }
  if (const ['zmniejsz wysokosc', 'decrease height', 'decrease the height']
      .contains(text)) {
    return {'height_operation': 'subtract'};
  }
  if (natural) {
    final conversational = _conversationalHeight(source);
    if (conversational != null) return conversational;
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
        SkillExample('Zwiększ wysokość', 'Increase height'),
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
    if (!source.containsKey('amount') && !source.containsKey('height_mm')) {
      return !target.containsKey('amount') &&
          !target.containsKey('height_mm') &&
          source['height_operation'] == target['height_operation'];
    }
    try {
      final base = _visible(context);
      final expected = _resolve(source, base), actual = _resolve(target, base);
      return expected.isFinite && expected > 0 && expected == actual;
    } on FormatException {
      return false;
    }
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    if (slot != 'amount') return null;
    final amount = _heightDelta(u);
    return amount == null ? null : {'amount': amount};
  }

  @override
  Map<String, Object?>? fillProposalSlot(String slot, Utterance command,
      Utterance original, AssistantContext ctx) {
    if (slot != 'amount') return null;
    final expected = _interpretedHeightDelta(original);
    final target = fillSlot(slot, command, ctx);
    return expected != null && target?['amount'] == expected ? target : null;
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
    final savedBase = m.slots['expected_inputs'];
    if (savedBase is Map && !mapEquals(savedBase, base)) {
      return const FailedResult(
          AssistantText(
              'Dane rozwinięcia zmieniły się od pytania. Powtórz zmianę dla aktualnych danych.',
              'Development inputs changed since the question. Repeat the change for the current inputs.'),
          reportMissingCapability: false);
    }
    if (m.slots['height_operation'] != null && m.slots['amount'] == null) {
      try {
        _currentHeight(base);
      } on FormatException {
        return const FailedResult(
            AssistantText('Najpierw popraw dane rozwinięcia.',
                'Correct the development inputs first.'),
            reportMissingCapability: false);
      }
      final add = m.slots['height_operation'] == 'add';
      return AskResult(
          'amount',
          AssistantText(
              add
                  ? 'O ile zwiększyć wysokość? Podaj wymiar, np. 10 cm.'
                  : 'O ile zmniejszyć wysokość? Podaj wymiar, np. 10 cm.',
              add
                  ? 'How much taller? Give a length, for example 10 cm.'
                  : 'How much shorter? Give a length, for example 10 cm.'),
          partial: m.copyWith(slots: {
            ...m.slots,
            'expected_inputs': Map<String, Object?>.of(base)
          }));
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
