import '../../../domain/fitter/fitter_calcs.dart';
import '../../../domain/fitter/pipe_weight.dart';
import '../../../domain/fitter/pipe_size_lookup.dart' show odForDn;
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final s = <String, Object?>{};
  for (final entry in {
    'od_mm': ['od', 'srednic', 'diameter'],
    'wall_mm': ['sciank', 'grubosc', 'wall', 'thick'],
    'length_mm': ['dlugosc', 'length'],
  }.entries) {
    final v = lengthNear(u, entry.value);
    if (v != null) s[entry.key] = v;
  }
  final dn = u.dn();
  if (dn != null) s['dn'] = dn;
  final materials = <PipeMaterial>{};
  if (RegExp(r'\b304\s*l?\b').hasMatch(u.folded)) {
    materials.add(PipeMaterial.ss304);
  }
  if (RegExp(r'\b316\s*l?\b').hasMatch(u.folded)) {
    materials.add(PipeMaterial.ss316);
  }
  if (u.hasStem(const ['weglow', 'carbon']) || u.hasAny(const ['cs'])) {
    materials.add(PipeMaterial.cs);
  }
  if (u.hasStem(const ['alumin'])) materials.add(PipeMaterial.al);
  if (materials.isNotEmpty) {
    s['material'] = materials.length == 1 ? materials.single.name : 'ambiguous';
  }
  final quantities = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!u.items[i].isNumber) continue;
    final prev = i > 0 ? u.items[i - 1].word : '';
    final next = i + 1 < u.items.length ? u.items[i + 1].word : '';
    if (prev == 'dn') continue;
    if (const ['ilosc', 'quantity', 'qty'].contains(prev) ||
        (prev == 'minus' &&
            i > 1 &&
            const ['ilosc', 'quantity', 'qty'].contains(u.items[i - 2].word)) ||
        next.startsWith('szt') ||
        next.startsWith('piece') ||
        next == 'pcs' ||
        next.startsWith('rur') ||
        next == 'pipes') {
      quantities.add(signedQuantity(u, i));
    }
  }
  if (quantities.isNotEmpty) {
    s['quantity'] = quantities.length == 1 ? quantities.single : double.nan;
  }
  return s;
}

class PipeWeightSkill extends AssistantSkill {
  @override
  String get id => 'pipe.weight';
  @override
  String get toolId => 'pipe_weight';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile waży rura DN50 ścianka 3 mm długość 6 m stal węglowa',
            'How much does pipe DN50 wall 3 mm length 6 m carbon steel weigh'),
        SkillExample(
            'Oblicz masę rury OD 60,3 mm ścianka 3,91 mm długość 1 m 316L ilość 2',
            'Calculate pipe weight OD 60.3 mm wall 3.91 mm length 1 m 316L quantity 2'),
        SkillExample('Masa rury OD 100 mm ścianka 2 mm aluminium',
            'Pipe weight OD 100 mm wall 2 mm aluminium'),
        SkillExample('Ciężar rury DN40 ścianka 2 mm 304L',
            'Pipe weight DN40 wall 2 mm 304L'),
        SkillExample('Oblicz wagę rury', 'Calculate pipe weight'),
        SkillExample(
            'Masa rury OD 50 mm ścianka 2 mm długość 200 cm stal węglowa',
            'Pipe weight OD 50 mm wall 2 mm length 200 cm carbon steel'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz ciężar rury', routesTo: 'tool.open'),
        SkillRejection('waga profilu stalowego 100 na 100'),
        SkillRejection('średnica rury DN50', routesTo: 'pipe.od'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!mentionsWeight(u) || !u.hasStem(const ['rur', 'pipe'])) return null;
    final s = _slots(u);
    return SkillMatch(
        this,
        s.isNotEmpty ||
                u.hasStem(const ['oblicz', 'policz', 'calculate']) ||
                u.hasAny(const ['ile wazy', 'how much'])
            ? .93
            : .65,
        slots: s,
        utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot) || slot == 'od_mm' && s.containsKey('dn')) return s;
    if (const ['od_mm', 'wall_mm', 'length_mm'].contains(slot)) {
      final v = <double>{};
      for (var i = 0; i + 1 < u.items.length; i++) {
        final scale = lengthUnitScale(u.items[i + 1].word);
        if (u.items[i].isNumber && scale != null) {
          v.add(signedQuantity(u, i) * scale);
        }
      }
      if (v.length == 1) return {slot: v.single};
    }
    if (slot == 'quantity') {
      final values = [
        for (var i = 0; i < u.items.length; i++)
          if (u.items[i].isNumber) signedQuantity(u, i)
      ];
      if (values.length == 1 &&
          u.items.every((item) =>
              item.isNumber ||
              const ['minus', 'sztuk', 'pieces', 'pcs'].contains(item.word))) {
        return {slot: values.single};
      }
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    final s = m.slots;
    double? n(String k) => s[k] is num ? (s[k] as num).toDouble() : null;
    final dn = s['dn'] as int?;
    final tableOd = dn == null ? null : odForDn(dn);
    final od = n('od_mm') ?? tableOd;
    if (od == null || !od.isFinite || od <= 0) {
      return ask(
          'od_mm',
          'Podaj średnicę zewnętrzną z jednostką (np. OD 60,3 mm) lub DN z tabeli.',
          'Give outside diameter with a unit (e.g. OD 60.3 mm) or a DN from the table.');
    }
    if (dn != null && (tableOd == null || (tableOd - od).abs() > 0.00001)) {
      return const FailedResult(AssistantText(
          'Podane DN i OD nie pasują do głównej serii tabeli. Podaj rzeczywiste OD bez DN.',
          'DN and OD disagree with the main table series. Give the actual OD without DN.'));
    }
    final wall = n('wall_mm');
    if (wall == null || !wall.isFinite || wall <= 0 || wall >= od / 2) {
      return ask(
          'wall_mm',
          'Jaka grubość ścianki? Podaj mm, mniej niż połowa OD.',
          'What wall thickness? Give mm, less than half the OD.');
    }
    final material =
        PipeMaterial.values.where((v) => v.name == s['material']).firstOrNull;
    if (material == null) {
      return ask(
          'material',
          'Jaki materiał: 304L, 316L, stal węglowa czy aluminium?',
          'Which material: 304L, 316L, carbon steel or aluminium?');
    }
    final length = n('length_mm'), qty = n('quantity');
    if (s.containsKey('length_mm') &&
            (length == null || !length.isFinite || length <= 0) ||
        qty != null && length == null) {
      return ask(
          'length_mm',
          'Jaka jest długość jednej sztuki? Podaj jednostkę, np. 6 m.',
          'What is the length of one piece? Include a unit, e.g. 6 m.');
    }
    if (qty != null &&
        (!qty.isFinite ||
            qty <= 0 ||
            qty != qty.roundToDouble() ||
            qty > 2147483647)) {
      return ask('quantity', 'Podaj dodatnią całkowitą liczbę sztuk.',
          'Give a positive whole number of pieces.');
    }
    final r = pipeWeight(
        odMm: od,
        wallMm: wall,
        material: material,
        lengthMm: length,
        quantity: qty);
    if (r == null) {
      return const FailedResult(AssistantText(
          'Wynik poza zakresem. Sprawdź wymiary i ilość.',
          'Result out of range. Check dimensions and quantity.'));
    }
    final pl = StringBuffer('Masa rury: ${fmt(r.kgPerM, ctx.lang)} kg/m.');
    final en = StringBuffer('Pipe mass: ${fmt(r.kgPerM, ctx.lang)} kg/m.');
    if (r.kgPerPiece != null) {
      pl.write(
          ' Jedna sztuka długości ${fmt(length!, ctx.lang)} mm: ${fmt(r.kgPerPiece!, ctx.lang)} kg.');
      en.write(
          ' One piece ${fmt(length, ctx.lang)} mm long: ${fmt(r.kgPerPiece!, ctx.lang)} kg.');
    }
    if (r.kgTotal != null) {
      pl.write(
          ' Łącznie ${fmt(qty!, ctx.lang)} szt.: ${fmt(r.kgTotal!, ctx.lang)} kg.');
      en.write(
          ' Total for ${fmt(qty, ctx.lang)} pieces: ${fmt(r.kgTotal!, ctx.lang)} kg.');
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(pl.toString(), en.toString()),
            source: AssistantText(
                'Gęstość ${kPipeDensityKgM3[material]} kg/m³; masa geometryczna bez tolerancji i powłok. DN→OD: główna seria EN 10220 / ASME B36.10M.',
                'Density ${kPipeDensityKgM3[material]} kg/m³; geometric mass excluding tolerances and coatings. DN→OD: main EN 10220 / ASME B36.10M series.')),
        show: ShowInModule(toolId, {
          'od_mm': od,
          'wall_mm': wall,
          'material': material.name,
          if (length != null) 'length_mm': length,
          if (qty != null) 'quantity': qty
        }));
  }
}
