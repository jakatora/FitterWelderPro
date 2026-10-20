import '../../../domain/bolting/bolt_torque.dart';
import '../../../services/flange_catalog.dart';
import '../../core/skill.dart';
import '../../core/spoken_numbers.dart' show isInchUnit;
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

Map<String, Object?> _slots(Utterance original) {
  final u = original.withRaw(original.raw
      .replaceAll(RegExp(r'\bB(?:16[.,]5|1[.,]1)\b', caseSensitive: false),
          'flange standard')
      .replaceAllMapped(RegExp(r'(\d+)-(\d+/\d+)'), (m) => '${m[1]} ${m[2]}'));
  final s = <String, Object?>{};
  final grades = kBoltGradeSmysMpa.keys.where((g) => u.hasAny([g])).toList();
  if (grades.isNotEmpty) {
    s['grade'] = grades.length == 1 ? grades.single : 'ambiguous';
  }
  if (RegExp(r'\bb\d+[a-z]?\b', caseSensitive: false)
      .allMatches(u.raw)
      .any((m) => !kBoltGradeSmysMpa.containsKey(m[0]!.toUpperCase()))) {
    s['grade'] = 'unknown';
  }
  final sizes = <double>{};
  for (var i = 0; i + 1 < u.items.length; i++) {
    if (u.items[i].isNumber && isInchUnit(u.items[i + 1].word)) {
      sizes.add(signedQuantity(u, i));
    }
    if (const ['class', 'klasa', 'klasy'].contains(u.items[i].word) &&
        u.items[i + 1].isNumber) {
      final value = signedQuantity(u, i + 1);
      final key =
          s['grade'] == 'B8M' && value <= 2 ? 'bolt_class' : 'flange_class';
      s[key] = s.containsKey(key) && s[key] != value ? double.nan : value;
    }
    if (u.items[i].word == 'k') {
      var j = i + 1;
      if (u.items[j].word == 'minus' && j + 1 < u.items.length) j++;
      if (u.items[j].isNumber) {
        final v = signedQuantity(u, j);
        s['nut_factor'] = s.containsKey('nut_factor') && s['nut_factor'] != v
            ? double.nan
            : v;
      }
    }
  }
  if (sizes.isNotEmpty) {
    s['diameter_in'] = sizes.length == 1 ? sizes.single : double.nan;
  }
  if (u.mentionsDn) s['flange_dn'] = u.dn() ?? double.nan;
  final lubes = <String>{};
  if (u.hasStem(const ['such', 'dry'])) lubes.add('dry');
  if (u.hasStem(const ['olej', 'oil'])) lubes.add('oil');
  if (u.hasStem(const ['miedz', 'copper']) || u.hasAny(const ['cu'])) {
    lubes.add('cu_anti_seize');
  }
  if (u.hasStem(const ['nikl', 'nickel']) || u.hasAny(const ['ni'])) {
    lubes.add('ni_anti_seize');
  }
  if (u.hasStem(const ['molibden', 'moly'])) lubes.add('moly_paste');
  if (lubes.isNotEmpty) {
    s['lube'] = lubes.length == 1 ? lubes.single : 'ambiguous';
  }
  final pct = percentValue(u);
  if (pct != null) s['preload_fraction'] = pct / 100;
  if (RegExp(r'\bm\d+\b', caseSensitive: false).hasMatch(u.raw)) {
    s['metric'] = true;
  }
  return s;
}

class BoltTorqueSkill extends AssistantSkill {
  @override
  String get id => 'bolt.torque';
  @override
  String get toolId => 'bolt_torque';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz moment dokręcania 5/8 cala B7 smar miedziany preload 50%',
            'Calculate bolt torque 5/8 inch B7 copper anti-seize preload 50%'),
        SkillExample('Moment śruby 3/4 cala B7M sucho preload 60%',
            'Bolt torque 3/4 inch B7M dry preload 60%'),
        SkillExample('Oblicz moment dokręcania', 'Calculate bolt torque'),
        SkillExample('Moment śrub DN50 Class 150 B7 smar niklowy preload 50%',
            'Bolt torque DN50 Class 150 B7 nickel anti-seize preload 50%'),
        SkillExample('Moment śruby 1-1/8 cala B16 olej preload 75%',
            'Bolt torque 1-1/8 inch B16 oil preload 75%'),
        SkillExample(
            'Moment śruby 1/2 cala B8M klasa 1 pasta molibdenowa preload 30%',
            'Bolt torque 1/2 inch B8M class 1 moly paste preload 30%'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz moment dokręcania', routesTo: 'tool.open'),
        SkillRejection('oblicz CE C 0,2 Mn 1 pozostałe zero grubość 15 mm',
            routesTo: 'preheat.ce'),
        SkillRejection('oblicz masę rury OD 60,3 mm ścianka 3 mm stal węglowa',
            routesTo: 'pipe.weight'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        kOpenVerbAtStartRe.hasMatch(u.folded) ||
        u.hasStem(const ['kalibr', 'calibr'])) {
      return null;
    }
    if (!u.hasStem(const ['torque']) &&
        !(u.hasStem(const ['moment']) && u.hasStem(const ['dokrec', 'srub']))) {
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
    if (slot == 'size' && s.containsKey('diameter_in')) {
      return {'flange_dn': null, 'flange_class': null, ...s};
    }
    if (slot == 'size' &&
        (s.containsKey('flange_dn') || s.containsKey('flange_class'))) {
      return {'diameter_in': null, ...s};
    }
    if (s.containsKey(slot)) return s;
    if (const ['bolt_class', 'flange_dn', 'flange_class'].contains(slot) &&
        u.items.length == 1 &&
        u.items.single.isNumber) {
      final v = u.items.single.value!;
      return {slot: v.isFinite && v == v.roundToDouble() ? v.toInt() : v};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    if (m.slots['metric'] == true) {
      return const FailedResult(
          AssistantText(
              'Ten kalkulator ma śruby calowe UNC/8UN, nie metryczne. Brak modelu metrycznego.',
              'This calculator has inch UNC/8UN bolts, not metric bolts. No metric model is available.'),
          reportMissingCapability: true);
    }
    final dn = m.slots['flange_dn'],
        cls = m.slots['flange_class'],
        diameter = m.slots['diameter_in'];
    FlangeBolting? preset;
    if (dn != null || cls != null) {
      if (dn is! int || dn <= 0) {
        return ask('flange_dn', 'Jakie DN kołnierza?', 'What flange DN?');
      }
      if (cls is! num ||
          !cls.isFinite ||
          cls <= 0 ||
          cls != cls.roundToDouble()) {
        return ask(
            'flange_class',
            'Jaka Class kołnierza: 150, 300, 600, 900 lub 1500?',
            'What flange Class: 150, 300, 600, 900 or 1500?');
      }
      preset = FlangeCatalog.lookup(dn, cls.toInt());
      if (preset == null) {
        return const FailedResult(
            AssistantText(
                'Brak tego DN × Class w katalogu aplikacji. Podaj rozmiar śruby ręcznie wg dokumentacji.',
                'This DN × Class is missing from the app catalogue. Give the bolt size manually from the documentation.'),
            reportMissingCapability: true);
      }
    }
    final size = preset == null
        ? (diameter is num && diameter.isFinite
            ? kFlangeBoltSizes
                .where((s) => (s.diameterIn - diameter).abs() < .000001)
                .firstOrNull
            : null)
        : flangeBoltSize(preset.boltSize);
    if (size == null ||
        preset != null &&
            diameter != null &&
            (diameter is! num ||
                !diameter.isFinite ||
                (size.diameterIn - diameter).abs() > .000001)) {
      if (preset == null &&
          diameter is num &&
          diameter.isFinite &&
          diameter > 0) {
        return const FailedResult(
            AssistantText(
                'Tego rozmiaru śruby calowej nie ma w tabeli aplikacji (1/2–2 cale).',
                'This inch bolt size is missing from the app table (1/2–2 inches).'),
            reportMissingCapability: true);
      }
      return ask(
          'size',
          'Podaj jeden zgodny rozmiar śruby w calach (np. 5/8 cala) albo DN i Class kołnierza. Nie przyjmuję domyślnej śruby.',
          'Give one consistent inch bolt size (e.g. 5/8 inch) or flange DN and Class. No default bolt is assumed.');
    }
    final grade = m.slots['grade'],
        lube = m.slots['lube'],
        frac = m.slots['preload_fraction'];
    if (grade == 'unknown') {
      return const FailedResult(
          AssistantText(
              'Tego gatunku śruby nie ma w danych kalkulatora. Nie zastępuję go B7.',
              'This bolt grade is missing from the calculator data. I will not replace it with B7.'),
          reportMissingCapability: true);
    }
    if (!kBoltGradeSmysMpa.containsKey(grade)) {
      return ask('grade', 'Jaki gatunek: B7, B7M, B16 lub B8M (model klasy 1)?',
          'Which grade: B7, B7M, B16 or B8M (Class 1 model)?');
    }
    if (grade == 'B8M' && m.slots['bolt_class'] != 1) {
      if (m.slots['bolt_class'] != null) {
        return const FailedResult(
            AssistantText(
                'B8M ma tutaj model 207 MPa klasy 1; brak innych klas B8M.',
                'B8M uses a 207 MPa Class 1 model here; other B8M classes are unavailable.'),
            reportMissingCapability: true);
      }
      return ask(
          'bolt_class',
          'B8M: potwierdź klasę śruby. W aplikacji jest model klasy 1, SMYS 207 MPa.',
          'B8M: confirm bolt class. The app has a Class 1 model, SMYS 207 MPa.');
    }
    final k = m.slots['nut_factor'];
    if (k != null && (k is! num || !k.isFinite || k <= 0 || k >= 1)) {
      return ask('nut_factor', 'K musi być dodatnie i mniejsze od 1.',
          'K must be positive and below 1.');
    }
    if (k != null && !kBoltNutFactors.containsKey(lube)) {
      return const FailedResult(
          AssistantText(
              'Ekran ma tylko nazwane presety smarowania; brak pola własnego K. Wybierz preset z potwierdzonym K.',
              'The screen only has named lubrication presets; custom K is unavailable. Choose a preset with confirmed K.'),
          reportMissingCapability: true);
    }
    if (!kBoltNutFactors.containsKey(lube)) {
      return ask(
          'lube',
          'Jakie smarowanie: sucho, olej, pasta miedziana, niklowa czy molibdenowa? K z presetów jest orientacyjne.',
          'Which lubrication: dry, oil, copper, nickel or moly paste? Preset K is indicative.');
    }
    if (k != null && ((k as num) - kBoltNutFactors[lube]!).abs() > .000001) {
      return const FailedResult(AssistantText(
          'Podane K jest sprzeczne z wybranym presetem. Nie podmieniam współczynnika.',
          'Supplied K conflicts with the selected preset. I will not replace the coefficient.'));
    }
    if (frac is! num || !frac.isFinite || frac < .30 || frac > .75) {
      return ask(
          'preload_fraction',
          'Jaki docelowy preload w % SMYS (zakres ekranu 30–75%)? Podaj wartość z procedury.',
          'What target preload in % SMYS (screen range 30–75%)? Give the procedure value.');
    }
    final result = boltTorque(
        size: size,
        smysMpa: kBoltGradeSmysMpa[grade]!.toDouble(),
        nutFactor: kBoltNutFactors[lube]!,
        preloadFraction: frac.toDouble());
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Moment na jedną śrubę ${size.threadDesignation}, $grade: ${fmt(result.torqueNm, ctx.lang)} N·m (${fmt(result.torqueFtLb, ctx.lang)} ft·lbf), preload ${fmt(result.preloadKN, ctx.lang)} kN. SMYS ${kBoltGradeSmysMpa[grade]} MPa, K=${kBoltNutFactors[lube]}, cel ${fmt(frac.toDouble() * 100, ctx.lang)}% SMYS. ${preset == null ? '' : 'Kołnierz DN$dn Class $cls: ${preset.boltCount} śrub. '}To szacunek z modelu K×F×d; porównaj z procedurą montażu i kartą producenta uszczelki/smaru.',
                'Torque per bolt ${size.threadDesignation}, $grade: ${fmt(result.torqueNm, ctx.lang)} N·m (${fmt(result.torqueFtLb, ctx.lang)} ft·lbf), preload ${fmt(result.preloadKN, ctx.lang)} kN. SMYS ${kBoltGradeSmysMpa[grade]} MPa, K=${kBoltNutFactors[lube]}, target ${fmt(frac.toDouble() * 100, ctx.lang)}% SMYS. ${preset == null ? '' : 'Flange DN$dn Class $cls: ${preset.boltCount} bolts. '}Estimate from K×F×d; compare with the assembly procedure and gasket/lubricant manufacturer data.'),
            source: const AssistantText.same(
                'App K×F×d model; ASME B1.1 UN stress area / B16.5 bolting presets; grade and lubricant reference presets')),
        show: ShowInModule(toolId, {
          'bolt_size': size.label,
          'grade': grade,
          'lube': lube,
          'preload_fraction': frac.toDouble(),
          if (preset != null) 'flange_dn': dn,
          if (preset != null) 'flange_class': (cls as num).toInt()
        }));
  }
}
