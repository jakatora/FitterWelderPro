import 'package:flutter/foundation.dart' show mapEquals;
import '../../../domain/steel_weight/steel_sections.dart';
import '../../../domain/steel_weight/steel_weight.dart';
import '../../../domain/steel_weight/steel_draft_fields.dart';
import '../../../utils/decimal_parse.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

const _beams = {
  'ipe': SteelShape.ipe,
  'hea': SteelShape.hea,
  'heb': SteelShape.heb,
  'hem': SteelShape.hem,
  'upn': SteelShape.upn,
  'upe': SteelShape.upe
};
Map<String, Object?> _slots(Utterance u, {String? hint}) {
  final out = <String, Object?>{};
  final shapes = <SteelShape>{};
  final sections = <String>{};
  for (final m in RegExp(r'\b(ipe|hea|heb|hem|upn|upe)\s*(\d+(?:[.,]\d+)?)\b',
          caseSensitive: false)
      .allMatches(u.raw)) {
    final shape = _beams[m[1]!.toLowerCase()]!;
    final size = parseDecimal(m[2]!);
    shapes.add(shape);
    if (size != null) {
      sections.add(
          '${shape.name.toUpperCase()} ${size == size.roundToDouble() ? size.toInt() : size}');
    }
  }
  for (var i = 0; i < u.items.length; i++) {
    final shape = _beams[u.items[i].word];
    if (shape == null) continue;
    shapes.add(shape);
    if (i + 1 < u.items.length && u.items[i + 1].isNumber) {
      final size = u.items[i + 1].value!;
      sections.add(
          '${shape.name.toUpperCase()} ${size == size.roundToDouble() ? size.toInt() : size}');
    }
  }
  if (u.hasStem(const ['plaskown']) || u.hasAny(const ['flat bar'])) {
    shapes.add(SteelShape.flat);
  }
  if ((u.hasStem(const ['pret']) && u.hasStem(const ['okrag'])) ||
      u.hasAny(const ['round bar'])) {
    shapes.add(SteelShape.roundBar);
  }
  if ((u.hasStem(const ['pret']) && u.hasStem(const ['kwadrat'])) ||
      u.hasAny(const ['square bar'])) {
    shapes.add(SteelShape.squareBar);
  }
  if (u.hasStem(const ['blach', 'plate'])) shapes.add(SteelShape.plate);
  if ((u.hasStem(const ['profil']) && u.hasStem(const ['zamkniet'])) ||
      u.hasAny(const ['hollow section', 'shs', 'rhs'])) {
    shapes.add(SteelShape.hollow);
  }
  final angle = RegExp(
          r'\bL\s*(\d+(?:[.,]\d+)?)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*[x×]\s*(\d+(?:[.,]\d+)?)',
          caseSensitive: false)
      .firstMatch(u.raw);
  if (angle != null) {
    final a = parseDecimal(angle[1]!),
        b = parseDecimal(angle[2]!),
        t = parseDecimal(angle[3]!);
    if (a != null && b != null && t != null) {
      shapes.add(a == b ? SteelShape.angleEqual : SteelShape.angleUnequal);
      out.addAll({'a_mm': a, 'b_mm': b, 't_mm': t});
    }
  } else if (u.hasStem(const ['katown']) ||
      u.hasAny(const ['equal angle', 'unequal angle'])) {
    shapes.add(u.hasStem(const ['nierown']) || u.hasAny(const ['unequal angle'])
        ? SteelShape.angleUnequal
        : SteelShape.angleEqual);
  }
  if (shapes.isNotEmpty) {
    out['shape'] = shapes.length == 1 ? shapes.single.name : 'ambiguous';
  }
  if (sections.isNotEmpty) {
    out['section'] = sections.length == 1 ? sections.single : 'ambiguous';
  }
  final shape = SteelShape.values
      .where((s) => s.name == (out['shape'] ?? hint))
      .firstOrNull;
  final aLabels = switch (shape) {
    SteelShape.flat || SteelShape.plate => const ['szerokosc', 'width', 'a'],
    SteelShape.roundBar => const ['srednic', 'diameter', 'a'],
    SteelShape.squareBar => const ['bok', 'side', 'a'],
    _ => const ['wysokosc', 'height', 'h', 'a'],
  };
  for (final entry in {
    'a_mm': aLabels,
    'b_mm': const ['szerokosc', 'width', 'b'],
    't_mm': const ['sciank', 'grubosc', 'wall', 'thick', 't'],
    'length_mm': const ['dlugosc', 'length']
  }.entries) {
    final value = lengthNear(u, entry.value);
    if (value != null) out[entry.key] = value;
  }
  final materials = <SteelMaterial>{};
  if (u.hasStem(const ['konstrukcyjn', 'weglow', 'carbon', 'structural']) ||
      u.hasAny(const ['s235', 's355', 'cs', 'stal czarna'])) {
    materials.add(SteelMaterial.carbon);
  }
  if (RegExp(r'\b304\s*l?\b|\b1[.,]4301\b').hasMatch(u.folded)) {
    materials.add(SteelMaterial.stainless304);
  }
  if (RegExp(r'\b316\s*l?\b|\b1[.,]4404\b').hasMatch(u.folded)) {
    materials.add(SteelMaterial.stainless316);
  }
  if (u.hasStem(const ['alumin'])) materials.add(SteelMaterial.aluminium);
  if (materials.isNotEmpty) {
    out['material'] =
        materials.length == 1 ? materials.single.name : 'ambiguous';
  }
  final counts = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!u.items[i].isNumber) continue;
    final prev = i > 0 ? u.items[i - 1].word : '';
    final next = i + 1 < u.items.length ? u.items[i + 1].word : '';
    final key = prev == 'minus' && i > 1 ? u.items[i - 2].word : prev;
    if (const ['ilosc', 'quantity', 'qty'].contains(key) ||
        next.startsWith('szt') ||
        next.startsWith('piece') ||
        next.startsWith('arkusz') ||
        next.startsWith('sheet') ||
        next == 'pcs') {
      counts.add(signedQuantity(u, i));
    }
  }
  if (counts.isNotEmpty) {
    out['quantity'] = counts.length == 1 ? counts.single : double.nan;
  }
  if (RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(u.raw.toLowerCase())) {
    out['length_mm'] = double.nan;
  }
  return out;
}

class SteelWeightSkill extends AssistantSkill {
  @override
  bool get currentFormEditsNeedAi => true;

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    if (referencesInstruction(original) ||
        isNegatedCommand(original) ||
        pendingReplyNeedsInterpretation(original) ||
        requestsCurrentFormEdit(original)) {
      return false;
    }
    final source = _slots(original), target = _slots(command);
    return source.isNotEmpty && target.isNotEmpty && mapEquals(source, target);
  }

  @override
  String get id => 'steel.weight';
  @override
  String get toolId => 'steel_weight';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz masę IPE 200 długość 6 m ilość 2 stal konstrukcyjna',
            'Calculate weight IPE 200 length 6 m quantity 2 structural steel'),
        SkillExample('Ile waży HEB 200 długość 1 m ilość 1 stal węglowa',
            'Weight HEB 200 length 1 m quantity 1 carbon steel'),
        SkillExample(
            'Masa blachy grubość 10 mm szerokość 1500 mm długość 3000 mm ilość 1 stal węglowa',
            'Plate weight thickness 10 mm width 1500 mm length 3000 mm quantity 1 carbon steel'),
        SkillExample(
            'Masa płaskownika szerokość 80 mm grubość 10 mm długość 6 m ilość 2 aluminium',
            'Flat bar weight width 80 mm thickness 10 mm length 6 m quantity 2 aluminium'),
        SkillExample(
            'Masa pręta okrągłego średnica 20 mm długość 1 m ilość 1 316L',
            'Round bar weight diameter 20 mm length 1 m quantity 1 316L'),
        SkillExample(
            'Masa profilu zamkniętego wysokość 100 mm szerokość 100 mm ścianka 4 mm długość 6 m ilość 2 stal węglowa',
            'Hollow section weight height 100 mm width 100 mm wall 4 mm length 6 m quantity 2 carbon steel'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz ciężar stali', routesTo: 'tool.open'),
        SkillRejection('masa rury DN50 ścianka 3 mm stal węglowa',
            routesTo: 'pipe.weight'),
        SkillRejection('zapisz TIG 304L 90 A ścianka 2 mm',
            routesTo: 'legacy.save'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded) ||
        !mentionsWeight(u) ||
        u.hasStem(const ['rur', 'pipe'])) {
      return null;
    }
    final slots = _slots(u);
    if (!slots.containsKey('shape') &&
        !u.hasStem(const ['stal', 'steel', 'profil', 'section'])) {
      return null;
    }
    return SkillMatch(
        this,
        slots.isNotEmpty ||
                u.hasStem(const ['oblicz', 'policz', 'calculate']) ||
                u.hasAny(const ['ile wazy', 'how much'])
            ? .94
            : .65,
        slots: slots,
        utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u, hint: ctx.recentSlot('shape') as String?);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = slotsFrom(u, ctx);
    if (s.containsKey(slot)) return s;
    if (const ['a_mm', 'b_mm', 't_mm', 'length_mm'].contains(slot)) {
      final values = <double>{};
      for (var i = 0; i + 1 < u.items.length; i++) {
        final scale = lengthUnitScale(u.items[i + 1].word);
        if (u.items[i].isNumber && scale != null) {
          values.add(signedQuantity(u, i) * scale);
        }
      }
      if (values.length == 1) return {slot: values.single};
    }
    if (slot == 'quantity') {
      final n = [
        for (var i = 0; i < u.items.length; i++)
          if (u.items[i].isNumber) signedQuantity(u, i)
      ];
      if (n.length == 1 &&
          u.items.every((i) => i.isNumber || i.word == 'minus')) {
        return {slot: n.single};
      }
    }
    if (slot == 'section' && u.items.length == 1 && u.items.single.isNumber) {
      return {'section': u.items.single.value};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    final s = Map<String, Object?>.of(m.slots);
    final shape =
        SteelShape.values.where((v) => v.name == s['shape']).firstOrNull;
    if (shape == null) {
      return ask(
          'shape',
          'Jaki wyrób: IPE, HEA, HEB, HEM, UPN, UPE, kątownik, profil zamknięty, płaskownik, pręt czy blacha?',
          'Which product: IPE, HEA, HEB, HEM, UPN, UPE, angle, hollow section, flat bar, round bar, square bar or plate?');
    }
    double? n(String k) => s[k] is num ? (s[k] as num).toDouble() : null;
    final dims = shape == SteelShape.hollow ||
            shape == SteelShape.angleEqual ||
            shape == SteelShape.angleUnequal
        ? ['a_mm', 'b_mm', 't_mm']
        : shape == SteelShape.flat || shape == SteelShape.plate
            ? ['a_mm', 't_mm']
            : !shape.tabulated
                ? ['a_mm']
                : <String>[];
    for (final key in dims) {
      final value = n(key);
      if (value == null || !value.isFinite || value <= 0) {
        final pl = switch (key) {
          'a_mm' => shape == SteelShape.roundBar
              ? 'średnicę'
              : shape == SteelShape.flat || shape == SteelShape.plate
                  ? 'szerokość'
                  : 'wysokość / pierwszy bok',
          'b_mm' => 'szerokość / drugi bok',
          _ => 'grubość / ściankę'
        };
        return ask(
            key,
            'Podaj $pl z jednostką, np. 20 mm.',
            'Give ${key == 'a_mm' ? 'the first dimension' : key == 'b_mm' ? 'the second dimension' : 'the thickness'} with a unit, e.g. 20 mm.');
      }
    }
    if (shape == SteelShape.angleEqual || shape == SteelShape.angleUnequal) {
      final section = sectionsOf(shape)
          .where((r) =>
              (r.h - n('a_mm')!).abs() < .00001 &&
              (r.b - n('b_mm')!).abs() < .00001 &&
              (r.t - n('t_mm')!).abs() < .00001)
          .firstOrNull;
      if (section != null) s['section'] = section.name;
    }
    final sectionNumber = s['section'];
    if (sectionNumber is num) {
      s['section'] = _beams.values.contains(shape) &&
              sectionNumber.isFinite &&
              sectionNumber > 0 &&
              sectionNumber == sectionNumber.roundToDouble()
          ? '${shape.name.toUpperCase()} ${sectionNumber.toInt()}'
          : null;
    }
    if (shape.tabulated &&
        sectionByName(shape, s['section'] as String?) == null) {
      return ask(
          'section',
          'Brak tego wymiaru w tabeli. Podaj pełny profil, np. IPE 200 lub L 50×50×5.',
          'Size not found in the table. Give a full section, e.g. IPE 200 or L 50×50×5.');
    }
    final length = n('length_mm');
    if (length == null || !length.isFinite || length <= 0) {
      return ask(
          'length_mm',
          'Jaka jest długość jednej sztuki? Podaj jednostkę, np. 6 m.',
          'What is one piece length? Include a unit, e.g. 6 m.');
    }
    final qty = n('quantity');
    if (qty == null ||
        !qty.isFinite ||
        qty <= 0 ||
        qty != qty.roundToDouble() ||
        qty > 2147483647) {
      return ask('quantity', 'Ile sztuk? Podaj dodatnią liczbę całkowitą.',
          'How many pieces? Give a positive whole number.');
    }
    final material =
        SteelMaterial.values.where((v) => v.name == s['material']).firstOrNull;
    if (material == null) {
      return ask(
          'material',
          'Jaki materiał: stal konstrukcyjna, 304, 316L czy aluminium?',
          'Which material: structural steel, 304, 316L or aluminium?');
    }
    final fields = <String, Object?>{
      for (final entry in s.entries)
        if (steelDraftFields.contains(entry.key)) entry.key: entry.value
    };
    final item = steelDraftFromFields(fields);
    if (item == null) {
      return const FailedResult(AssistantText(
          'Wymiary są nieprawidłowe dla tego przekroju albo wynik przekracza zakres. Sprawdź wymiary i ściankę.',
          'Dimensions are invalid for this section or the result exceeds the range. Check dimensions and wall thickness.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                '${item.label()}: ${fmt(shape == SteelShape.plate ? item.kgPerM2 : item.kgPerM, ctx.lang)} ${shape == SteelShape.plate ? 'kg/m²' : 'kg/m'}. Jedna sztuka ${fmt(item.pieceKg, ctx.lang)} kg, razem ${item.count} szt.: ${fmt(item.totalKg, ctx.lang)} kg. Uzupełniam kalkulator; pozycja nie została dodana do listy materiałowej.',
                '${item.label(english: true)}: ${fmt(shape == SteelShape.plate ? item.kgPerM2 : item.kgPerM, ctx.lang)} ${shape == SteelShape.plate ? 'kg/m²' : 'kg/m'}. One piece ${fmt(item.pieceKg, ctx.lang)} kg, total ${item.count} pieces: ${fmt(item.totalKg, ctx.lang)} kg. Filling the calculator; no item was added to the material list.'),
            source: AssistantText.same(
                '${standardOf(shape)}; ρ = ${material.density} kg/m³')),
        show: ShowInModule(toolId, fields));
  }
}
