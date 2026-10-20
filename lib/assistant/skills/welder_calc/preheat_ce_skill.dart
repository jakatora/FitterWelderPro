import '../../../domain/welding/preheat.dart';
import '../../../services/material_catalog.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

const _elements = {
  'c': 'C',
  'mn': 'Mn',
  'cr': 'Cr',
  'mo': 'Mo',
  'v': 'V',
  'ni': 'Ni',
  'cu': 'Cu'
};
Map<String, Object?> _slots(Utterance u) {
  final s = <String, Object?>{};
  final grades = MaterialCatalog.all
      .where((m) => m.key.split('/').any((part) => u.hasAny([part.trim()])))
      .toList();
  if (grades.isNotEmpty) {
    s['grade_key'] = grades.length == 1 ? grades.single.key : 'ambiguous';
  }
  if (u.hasAny(const [
    'pozostałe zero',
    'pozostale zero',
    'pozostale 0',
    'pozostałe pierwiastki zero',
    'rest zero',
    'rest 0',
    'remaining zero'
  ])) {
    s['remainder_zero'] = true;
  }
  for (final e in _elements.keys) {
    final values = <double>{};
    for (var i = 0; i + 1 < u.items.length; i++) {
      if (u.items[i].word != e) continue;
      var j = i + 1;
      if (u.items[j].word == 'minus' && j + 1 < u.items.length) j++;
      if (u.items[j].isNumber) {
        values.add(j + 1 < u.items.length &&
                const ['g', 'kg', 'mg', 'ppm'].contains(u.items[j + 1].word)
            ? double.nan
            : signedQuantity(u, j));
      }
    }
    if (values.isNotEmpty) {
      s['${e}_pct'] = values.length == 1 ? values.single : double.nan;
    }
  }
  final t = lengthNear(u, const ['grubosc', 'sciank', 'thickness', 'wall']);
  if (t != null) s['thickness_mm'] = t;
  return s;
}

class PreheatCeSkill extends AssistantSkill {
  @override
  String get id => 'preheat.ce';
  @override
  String get toolId => 'heat_input';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz CE C 0,2 Mn 1 Cr 0 Mo 0 V 0 Ni 0 Cu 0 grubość 15 mm',
            'Calculate CE C 0.2 Mn 1 Cr 0 Mo 0 V 0 Ni 0 Cu 0 thickness 15 mm'),
        SkillExample('Podgrzewanie A106 B grubość 15 mm',
            'Preheat A106 B thickness 15 mm'),
        SkillExample('Oblicz równoważnik węgla', 'Calculate carbon equivalent'),
        SkillExample('Oblicz CE C 0,2 Mn 1 pozostałe zero grubość 30 mm',
            'Calculate CE C 0.2 Mn 1 rest zero thickness 30 mm'),
        SkillExample(
            'Podgrzewanie P91 grubość 20 mm', 'Preheat P91 thickness 20 mm'),
        SkillExample(
            'Podgrzewanie 304L grubość 10 mm', 'Preheat 304L thickness 10 mm'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz heat input', routesTo: 'tool.open'),
        SkillRejection('oblicz energię liniową TIG EN 12 V 100 A 100 mm/min',
            routesTo: 'heat.input'),
        SkillRejection(
            'oblicz t8/5 Q 1 kJ/mm temperatura 100 C grubość 20 mm wypełnienie',
            routesTo: 'cooling.t85'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        kOpenVerbAtStartRe.hasMatch(u.folded) ||
        requestsCoolingTime(u)) {
      return null;
    }
    if (!u.hasAny(const [
          'ce',
          'równoważnik węgla',
          'rownowaznik wegla',
          'carbon equivalent',
          'preheat'
        ]) &&
        !u.hasStem(const ['podgrzew'])) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'calculate']) ? .96 : .65,
        slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (slot == 'chemistry_source') {
      if (u.hasAny(const ['katalog', 'catalog', 'use grade'])) {
        return {
          for (final e in _elements.keys) '${e}_pct': null,
          'remainder_zero': null,
          'chemistry_source': 'catalog',
          ...s
        };
      }
      if (u.hasAny(
          const ['własny skład', 'wlasny sklad', 'custom chemistry', 'mtr'])) {
        return {'grade_key': null, 'chemistry_source': 'custom', ...s};
      }
    }
    if (s.containsKey(slot)) return s;
    if (slot.endsWith('_pct') && s['remainder_zero'] == true) return s;
    if (slot.endsWith('_pct') &&
        u.items.where((i) => i.isNumber).length == 1 &&
        u.items.every((i) =>
            i.isNumber ||
            i.word == 'minus' ||
            i.word.startsWith('procent') ||
            i.word.startsWith('percent'))) {
      final i = u.items.indexWhere((i) => i.isNumber);
      return {slot: signedQuantity(u, i)};
    }
    if (slot == 'thickness_mm') {
      final values = <double>{};
      for (var i = 0; i + 1 < u.items.length; i++) {
        final scale = lengthUnitScale(u.items[i + 1].word);
        if (u.items[i].isNumber && scale != null) {
          values.add(signedQuantity(u, i) * scale);
        }
      }
      if (values.length == 1) return {slot: values.single};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    final gradeKey = m.slots['grade_key'];
    final grade =
        MaterialCatalog.all.where((g) => g.key == gradeKey).firstOrNull;
    if (gradeKey != null && grade == null) {
      return ask(
          'grade_key',
          'Podaj jeden gatunek z katalogu albo własny skład chemiczny.',
          'Give one catalog grade or a custom chemical composition.');
    }
    if (grade != null &&
        (_elements.keys.any((e) => m.slots['${e}_pct'] != null) ||
            m.slots['remainder_zero'] == true)) {
      return ask(
          'chemistry_source',
          'Podano gatunek i własną chemię. Wybierz „katalog” albo „własny skład”.',
          'Both a grade and custom chemistry were supplied. Choose “catalog” or “custom chemistry”.');
    }
    final chem = grade == null
        ? <String, double>{}
        : {
            'c': grade.c,
            'mn': grade.mn,
            'cr': grade.cr,
            'mo': grade.mo,
            'v': grade.v,
            'ni': grade.ni,
            'cu': grade.cu
          };
    if (grade == null) {
      for (final e in _elements.entries) {
        final value = m.slots['${e.key}_pct'] ??
            (m.slots['remainder_zero'] == true ? 0.0 : null);
        if (value is! num || !value.isFinite || value < 0 || value > 100) {
          return ask(
              '${e.key}_pct',
              'Podaj ${e.value} w % masowych z atestu, np. ${e.value} 0,2. Dla brakujących pierwiastków podaj jawnie zero lub „pozostałe zero”.',
              'Give ${e.value} in mass percent from the certificate, e.g. ${e.value} 0.2. Explicitly give zero for absent elements or say “rest zero”.');
        }
        chem[e.key] = value.toDouble();
      }
    }
    if (chem.values.fold<double>(0, (a, b) => a + b) > 100) {
      return const FailedResult(AssistantText(
          'Suma składników przekracza 100%. Sprawdź skład.',
          'Composition exceeds 100%. Check the chemistry.'));
    }
    final thickness = m.slots['thickness_mm'];
    if (thickness is! num || !thickness.isFinite || thickness <= 0) {
      return ask(
          'thickness_mm',
          'Podaj grubość grubszego elementu złącza z jednostką, np. 15 mm.',
          'Give the thicker joint member thickness with a unit, e.g. 15 mm.');
    }
    final stainless = isStainlessComposition(cr: chem['cr']!),
        crMo = grade == null
            ? isCrMoComposition(cr: chem['cr']!, mo: chem['mo']!)
            : isCrMoPNo(grade.pNo);
    final code = grade == null
        ? null
        : b313CurrentMinPreheatC(
            pNo: grade.pNo,
            thicknessMm: thickness.toDouble(),
            smtsMpa: grade.smtsMpa,
            carbonPct: chem['c'],
            chromiumPct: chem['cr']);
    final basis = grade == null
        ? const AssistantText(
            'Skład z atestu użytkownika.', 'User certificate chemistry.')
        : AssistantText(
            'Skład typowy z katalogu ${grade.key}, nie analiza wytopowa.',
            'Typical catalog chemistry for ${grade.key}, not a heat analysis.');
    String pl, en;
    if (stainless || crMo) {
      pl =
          '${basis.pl} Dla tej stali metody CE/Seferiana nie są przeznaczone. Wiąże temperatura z WPS.';
      en =
          '${basis.en} CE/Seferian methods are not intended for this steel. The WPS temperature governs.';
    } else {
      final ce = carbonEquivalentIiw(
          c: chem['c']!,
          mn: chem['mn']!,
          cr: chem['cr']!,
          mo: chem['mo']!,
          v: chem['v']!,
          ni: chem['ni']!,
          cu: chem['cu']!);
      final rule = ceRuleOfThumb(ce: ce, thicknessMm: thickness.toDouble());
      final seferian = seferianPreheat(
          c: chem['c']!,
          mn: chem['mn']!,
          cr: chem['cr']!,
          mo: chem['mo']!,
          ni: chem['ni']!,
          thicknessMm: thickness.toDouble())!;
      if (!ce.isFinite ||
          !seferian.preheatC.isFinite ||
          !seferian.totalCe.isFinite) {
        return const FailedResult(AssistantText(
            'Wynik poza zakresem. Sprawdź grubość i skład.',
            'Result out of range. Check thickness and chemistry.'));
      }
      pl =
          '${basis.pl} CE (IIW) = ${fmt(ce, ctx.lang)}%. Seferian: ${fmt(seferian.preheatC, ctx.lang)}°C; reguła CE: orientacyjnie ${fmt(rule.preheatC, ctx.lang)}°C. To szacunki, nie temperatura wymagana. Wiąże WPS; metoda B wymaga wodoru HD i energii Q.';
      en =
          '${basis.en} CE (IIW) = ${fmt(ce, ctx.lang)}%. Seferian: ${fmt(seferian.preheatC, ctx.lang)}°C; CE rule of thumb: approximately ${fmt(rule.preheatC, ctx.lang)}°C. These are estimates, not required temperatures. The WPS governs; method B needs hydrogen HD and heat input Q.';
    }
    if (code != null) {
      pl +=
          ' Minimum kodowe B31.3 ≥ 2014: $code°C (P-No ${grade!.pNo}); sprawdź wydanie projektu.';
      en +=
          ' B31.3 ≥ 2014 code minimum: $code°C (P-No ${grade.pNo}); check the project edition.';
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(pl, en),
            source: const AssistantText.same(
                'CE IIW; Seferian; ASME B31.3 Table 330.1.1 (≥ 2014)')),
        show: ShowInModule(toolId, {
          for (final e in chem.entries) '${e.key}_pct': e.value,
          'thickness_mm': thickness.toDouble(),
          if (grade != null) 'grade_key': grade.key
        }));
  }
}
