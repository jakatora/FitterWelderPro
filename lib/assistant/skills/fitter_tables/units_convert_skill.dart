import '../../../domain/fitter/unit_conversion.dart';
import '../../core/skill.dart';
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

({String kind, String symbol})? _unit(String word) {
  if (word == 'mm' ||
      word.startsWith('milimetr') ||
      word.startsWith('millimet')) {
    return (kind: 'length', symbol: 'mm');
  }
  if (word == 'cm' ||
      word.startsWith('centymetr') ||
      word.startsWith('centimet')) {
    return (kind: 'length', symbol: 'cm');
  }
  if (word == 'm' ||
      word.startsWith('metr') ||
      word == 'meters' ||
      word == 'metres') {
    return (kind: 'length', symbol: 'm');
  }
  if (word == 'in' || word.startsWith('cal') || word.startsWith('inch')) {
    return (kind: 'length', symbol: 'in');
  }
  if (word == 'ft' ||
      word == 'feet' ||
      word == 'foot' ||
      word == 'stop' ||
      word == 'stopy' ||
      word == 'stopa') {
    return (kind: 'length', symbol: 'ft');
  }
  if (word == 'c' || word.startsWith('cels')) {
    return (kind: 'temperature', symbol: '°C');
  }
  if (word == 'f' || word.startsWith('fahren')) {
    return (kind: 'temperature', symbol: '°F');
  }
  if (word == 'k' || word.startsWith('kelwin') || word.startsWith('kelvin')) {
    return (kind: 'temperature', symbol: 'K');
  }
  if (word == 'bar' || word == 'bary' || word == 'barow') {
    return (kind: 'pressure', symbol: 'bar');
  }
  if (word == 'mpa' ||
      word.startsWith('megapask') ||
      word.startsWith('megapasc')) {
    return (kind: 'pressure', symbol: 'MPa');
  }
  if (word == 'kpa' ||
      word.startsWith('kilopask') ||
      word.startsWith('kilopasc')) {
    return (kind: 'pressure', symbol: 'kPa');
  }
  if (word == 'psi' || word == 'atm' || word == 'mbar') {
    return (kind: 'pressure', symbol: word);
  }
  if (const ['lpm', 'slpm', 'cfh', 'scfh'].contains(word)) {
    return (kind: 'flow', symbol: word == 'lpm' ? 'l/min' : word);
  }
  return null;
}

Map<String, Object?> _slots(Utterance u) {
  final numbers = <double>[];
  final units = <({String kind, String symbol})>[];
  for (var i = 0; i < u.items.length; i++) {
    if (u.items[i].isNumber) numbers.add(signedQuantity(u, i));
    final word = u.items[i].word;
    if ((word == 'l' || word.startsWith('litr') || word.startsWith('liter')) &&
        i + 1 < u.items.length) {
      final rest = u.items.skip(i + 1).take(2).map((e) => e.word).join(' ');
      if (rest == 'min' ||
          rest.startsWith('min ') ||
          rest.startsWith('minut') ||
          rest.startsWith('na minut') ||
          rest.startsWith('per minut')) {
        units.add((kind: 'flow', symbol: 'l/min'));
        continue;
      }
    }
    final unit = _unit(word);
    if (unit != null) units.add(unit);
  }
  return {
    if (numbers.isNotEmpty)
      'value': numbers.length == 1 ? numbers.single : double.nan,
    if (units.isNotEmpty) 'kind': units.first.kind,
    if (units.isNotEmpty) 'from': units.first.symbol,
    if (units.length >= 2) 'to': units[1].symbol,
    if (units.length >= 2) 'target_kind': units[1].kind,
    if (units.length > 2) 'ambiguous_units': true,
  };
}

class UnitsConvertSkill extends AssistantSkill {
  @override
  String get id => 'units.convert';
  @override
  String get toolId => 'unit_converter';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Przelicz 2 cale na mm', 'Convert 2 inches to mm'),
        SkillExample('Przelicz 3 metry na stopy', 'Convert 3 meters to feet'),
        SkillExample('Przelicz 100 kPa na bar', 'Convert 100 kPa to bar'),
        SkillExample('Przelicz minus 40 stopni Celsjusza na Fahrenheita',
            'Convert minus 40 Celsius to Fahrenheit'),
        SkillExample('Przelicz 5 bar na psi', 'Convert 5 bar to psi'),
        SkillExample('Przelicz 10 l/min na cfh', 'Convert 10 l/min to cfh'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz konwerter jednostek', routesTo: 'tool.open'),
        SkillRejection('oblicz spadek 1% na 6 metrów'),
        SkillRejection('przelicz wagę rury DN50'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!u.hasStem(const ['przelicz', 'convert'])) return null;
    final slots = _slots(u);
    if (!slots.containsKey('from')) return null;
    return SkillMatch(this, .93, slots: slots, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (slot == 'to' && s.containsKey('from') && !s.containsKey('to')) {
      return {'to': s['from'], 'target_kind': s['kind']};
    }
    return s.containsKey(slot) ? s : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String slot, String pl, String en) =>
        AskResult(slot, AssistantText(pl, en), partial: m);
    final s = m.slots;
    if (m.utterance?.hasStem(const ['roznic', 'delta', 'difference']) == true) {
      return const FailedResult(AssistantText(
          'Ten konwerter przelicza temperaturę, a nie różnicę temperatur. Dla różnicy potrzebne jest osobne przeliczenie.',
          'This converter handles temperatures, not temperature differences. A difference needs a separate conversion.'));
    }
    if (s['ambiguous_units'] == true) {
      return const FailedResult(AssistantText(
          'Podaj jedną jednostkę źródłową i jedną docelową.',
          'Give one source unit and one target unit.'));
    }
    final value = s['value'];
    if (value is! num || !value.isFinite) {
      return ask('value', 'Jaką jedną wartość przeliczyć?',
          'What single value should I convert?');
    }
    final kind = s['kind'] as String?;
    final from = s['from'] as String?;
    if (kind == null || from == null) {
      return ask(
          'from', 'Z jakiej jednostki przeliczyć?', 'Which source unit?');
    }
    final to = s['to'] as String?;
    if (to == null) {
      return ask('to', 'Na jaką jednostkę przeliczyć?', 'Which target unit?');
    }
    if (kind != s['target_kind']) {
      return const FailedResult(AssistantText(
          'Te jednostki opisują różne wielkości. Wybierz jednostki tego samego rodzaju.',
          'These units measure different quantities. Choose units of the same kind.'));
    }
    final table = conversionBySymbol(kind, value.toDouble(), from);
    if (table == null || !table.ok) {
      return ask(
          'value',
          'Wartość poza zakresem tej jednostki. Podaj poprawną wartość.',
          'Value outside the range for this unit. Give a valid value.');
    }
    final results = table.values.entries.where((e) => e.key.symbol == to);
    if (results.isEmpty) {
      return const FailedResult(AssistantText(
          'Przepływ rzeczywisty i znormalizowany wymagają danych gazu, temperatury, ciśnienia i warunków odniesienia. Nie przeliczę ich przez samą zmianę jednostki.',
          'Actual and standard flow require gas, temperature, pressure and reference conditions. They cannot be converted by changing the unit alone.'));
    }
    final result = results.single.value;
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                '${fmt(value.toDouble(), ctx.lang)} $from = ${fmt(result, ctx.lang)} $to.',
                '${fmt(value.toDouble(), ctx.lang)} $from = ${fmt(result, ctx.lang)} $to.')),
        show:
            ShowInModule(toolId, {'kind': kind, 'value': value, 'from': from}));
  }
}
