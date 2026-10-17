// Generatory pytań egzaminu spawacza: każda poprawna odpowiedź porównana
// z tabelą / funkcją domeny innego modułu (nie z przepisaną kopią),
// dystraktory różne i z tej samej kategorii danych, pomijanie pytań
// niejednoznacznych, deterministyczne losowanie, PL i EN.

import 'package:cut_list_app/data/welding_glossary.dart';
import 'package:cut_list_app/domain/exam/exam_questions.dart';
import 'package:cut_list_app/domain/filler/filler_catalog.dart';
import 'package:cut_list_app/domain/filler/filler_selector.dart';
import 'package:cut_list_app/domain/glossary/glossary.dart';
import 'package:cut_list_app/domain/iso5817/iso5817_limits.dart';
import 'package:cut_list_app/domain/iso5817/iso5817_table.dart';
import 'package:cut_list_app/domain/qualification/iso9606_range.dart';
import 'package:cut_list_app/domain/qualification/weld_process.dart';
import 'package:cut_list_app/domain/weld_symbols/weld_symbol.dart';
import 'package:cut_list_app/domain/weld_symbols/weld_symbol_catalog.dart';
import 'package:cut_list_app/domain/weld_symbols/weld_symbol_description.dart';
import 'package:cut_list_app/domain/welding/electrode_exposure.dart';
import 'package:flutter_test/flutter_test.dart';

GlossaryTerm _term(String id) => kWeldingGlossary.firstWhere((t) => t.id == id);

String _name(GlossaryTerm t, bool en) => en ? t.en : t.pl;

/// Pytania, których id zaczyna się od [prefix].
List<ExamItem> _items(String prefix, {required bool en}) => [
      for (final i in examItems(en: en))
        if (i.id.startsWith(prefix)) i,
    ];

ExamItem _item(String id, {bool en = false}) {
  final i = examItemById(id, en: en);
  expect(i, isNotNull, reason: id);
  return i!;
}

/// Wszystkie odpowiedzi pytania (poprawna + pula dystraktorów).
List<String> _all(ExamItem i) => [i.answer, ...i.distractors];

/// Zbiór pozycji próby — liczony w teście NIEZALEŻNĄ próbką (135, drut lity,
/// zwarciowy, ss nb, FM1) przez funkcję domeny evaluateIso9606.
String _positionsFromDomain(
    Iso9606WeldType type, Iso9606Product product, Iso6947Position pos) {
  final eval = evaluateIso9606(Iso9606Sample(
    product: product,
    weldType: type,
    first: const Iso9606ProcessInput(
      process: Iso9606Process.p135,
      filler: Iso9606Filler.solid,
      transfer: Iso9606Transfer.dip,
      thicknessMm: 6,
    ),
    fm: Iso9606FmGroup.fm1,
    diameterMm: product == Iso9606Product.pipe ? 114.3 : null,
    position: pos,
    backing: type == Iso9606WeldType.bw ? Iso9606Backing.ssNb : null,
    filletLayers: type == Iso9606WeldType.fw ? Iso9606FilletLayers.sl : null,
  ));
  expect(eval.ok, isTrue, reason: '${type.code} ${product.code} ${pos.code}');
  return eval.range!.positions.map((p) => p.code).join(', ');
}

Iso9606WeldType _type(String code) =>
    Iso9606WeldType.values.firstWhere((t) => t.code == code);
Iso9606Product _product(String code) =>
    Iso9606Product.values.firstWhere((p) => p.code == code);
Iso6947Position _position(String code) =>
    Iso6947Position.values.firstWhere((p) => p.code == code);

const _polishLetters = 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ';

void main() {
  group('generatory — poprawna odpowiedź z danych źródłowych', () {
    for (final en in [false, true]) {
      final lang = en ? 'EN' : 'PL';

      test(
          'procesy ISO 4063: numer ↔ nazwa ze słownika, rodzina z '
          'familyOfIso4063 ($lang)', () {
        final names = _items('proc.name.', en: en);
        final numbers = _items('proc.num.', en: en);
        final families = _items('proc.family.', en: en);
        expect(names, isNotEmpty);
        expect(numbers.length, names.length);
        for (final i in names) {
          final t = _term(i.id.substring('proc.name.'.length));
          expect(t.category, GlossaryCategory.process);
          expect(i.answer, _name(t, en));
          expect(i.prompt, contains(t.iso4063!));
        }
        for (final i in numbers) {
          final t = _term(i.id.substring('proc.num.'.length));
          expect(i.answer, t.iso4063);
          expect(i.prompt, contains(_name(t, en)));
        }
        for (final i in families) {
          final n = int.parse(i.id.substring('proc.family.'.length));
          expect(i.answer, familyOfIso4063(n)!.asmeCode);
        }
        // Przykład z zadania: 135 → MAG drutem litym, GMAW.
        expect(_item('proc.name.p135').answer, 'Spawanie MAG drutem litym');
        expect(_item('proc.num.p136').answer, '136');
        expect(_item('proc.family.141', en: en).answer, 'GTAW');
      });

      test('niezgodności ISO 6520-1: numer ↔ nazwa ze słownika ($lang)', () {
        final names = _items('imp.name.', en: en);
        expect(names, isNotEmpty);
        for (final i in names) {
          final t = _term(i.id.substring('imp.name.'.length));
          expect(i.answer, _name(t, en));
          expect(i.prompt, contains(t.iso6520!));
        }
        for (final i in _items('imp.num.', en: en)) {
          final t = _term(i.id.substring('imp.num.'.length));
          expect(i.answer, t.iso6520);
        }
        expect(_item('imp.name.i5011').answer, 'Podtopienie ciągłe');
        expect(_item('imp.name.i5011', en: true).answer, 'Continuous undercut');
      });

      test(
          'pozycje ISO 6947: kod, nazwa i ASME z pola code słownika '
          '($lang)', () {
        for (final i in _items('pos.code.', en: en)) {
          final t = _term(i.id.substring('pos.code.'.length));
          expect(t.code, startsWith('${i.answer} · ASME '));
          expect(i.prompt, contains(_name(t, en)));
        }
        for (final i in _items('pos.name.', en: en)) {
          final t = _term(i.id.substring('pos.name.'.length));
          expect(i.answer, _name(t, en));
        }
        for (final i in _items('pos.asme.', en: en)) {
          final t = _term(i.id.substring('pos.asme.'.length));
          expect(t.code, endsWith('ASME ${i.answer}'));
        }
        // „Która pozycja to spawanie pionowe z dołu do góry?” → PF.
        expect(_item('pos.code.pos_pf').answer, 'PF');
        expect(_item('pos.code.pos_pf').prompt,
            contains('Pozycja pionowa z dołu do góry'));
      });

      test(
          'ISO 9606-1: pozycje z evaluateIso9606 (tab. 9 / 10), PH na rurze '
          '→ PA, PE, PF, PH ($lang)', () {
        final items = _items('q.pos.', en: en);
        // BW: blacha 5 + rura 6, FW: blacha 7 + rura 6 pozycji próby.
        expect(items.length, 24);
        for (final i in items) {
          final parts = i.id.split('.');
          final type = _type(parts[2]);
          final product = _product(parts[3]);
          final pos = _position(parts.sublist(4).join('.'));
          expect(iso9606TestPositions(type, product), contains(pos));
          expect(i.answer, _positionsFromDomain(type, product, pos),
              reason: i.id);
        }
        expect(_item('q.pos.BW.T.PH').answer, 'PA, PE, PF, PH');
        expect(_item('q.pos.BW.T.PH').source, 'EN ISO 9606-1 tab. 9');
        expect(_item('q.pos.FW.P.PB').source, 'EN ISO 9606-1 tab. 10');
      });

      test(
          'ISO 9606-1: grubość s (tab. 6), t (tab. 8) i średnica D (tab. 7) '
          'z funkcji domeny ($lang)', () {
        for (final s in kExamButtThicknesses) {
          final i = examItems(en: en).firstWhere((x) =>
              x.id.startsWith('q.s.') && double.parse(x.id.substring(4)) == s);
          expect(i.answer, iso9606RangeText(iso9606ButtThickness(s), en: en));
        }
        for (final t in kExamFilletThicknesses) {
          final i = examItems(en: en).firstWhere((x) =>
              x.id.startsWith('q.t.') && double.parse(x.id.substring(4)) == t);
          expect(i.answer, iso9606RangeText(iso9606FilletThickness(t), en: en));
        }
        for (final d in kExamDiameters) {
          final i = examItems(en: en).firstWhere((x) =>
              x.id.startsWith('q.d.') && double.parse(x.id.substring(4)) == d);
          expect(i.answer, iso9606RangeText(iso9606Diameter(d), en: en));
        }
        // „s = 8 mm → zakres…”
        expect(_item('q.s.8').answer, '3–16 mm');
        expect(_item('q.d.60.3').answer, '≥ 30,15 mm');
        expect(_item('q.d.60.3', en: true).answer, '≥ 30.15 mm');
      });

      test('ISO 9606-1: §5.2 procesy i tab. 3 grupy FM ($lang)', () {
        final procs = _items('q.proc.', en: en);
        expect(procs, isNotEmpty);
        for (final i in procs) {
          final parts = i.id.split('.');
          final tested = Iso9606Process.values
              .firstWhere((p) => p.number == int.parse(parts[2]));
          final covered = iso9606ProcessCandidates(tested);
          expect(i.answer, parts[3]);
          expect(covered.map((p) => p.code), contains(i.answer));
          for (final d in i.distractors) {
            expect(covered.map((p) => p.code), isNot(contains(d)),
                reason: '${i.id}: $d');
          }
        }
        expect(_item('q.proc.135.138').answer, '138');
        for (final g in Iso9606FmGroup.values) {
          final i = _item('q.fm.${g.code}', en: en);
          final expected = [
            for (final x in Iso9606FmGroup.values)
              if (kIso9606FmRange[g]!.contains(x)) x.code,
          ].join(', ');
          expect(i.answer, expected);
        }
      });

      test(
          'ISO 5817: najostrzejszy B, najłagodniejszy D, poziomy z reguł '
          'tablicy 1 ($lang)', () {
        final strictest = Iso5817Level.values
            .reduce((a, b) => a.strictness <= b.strictness ? a : b);
        expect(_item('q5817.strict', en: en).answer, strictest.letter);
        expect(_item('q5817.strict', en: en).answer, 'B');
        expect(_item('q5817.mild', en: en).answer, 'D');
        final levels = _items('q5817.lv.', en: en);
        expect(levels, isNotEmpty);
        final texts = en
            ? ['B, C and D', 'Only C and D', 'Only D', 'None (not permitted)']
            : [
                'Na B, C i D',
                'Tylko na C i D',
                'Tylko na D',
                'Na żadnym (niedopuszczalna)',
              ];
        for (final i in levels) {
          final rest = i.id.substring('q5817.lv.'.length);
          final cut = rest.lastIndexOf('.');
          final item =
              kIso5817Items.firstWhere((x) => x.id == rest.substring(0, cut));
          final rangeName = rest.substring(cut + 1);
          final range =
              rangeName == 'thin' ? Iso5817Range.thin : Iso5817Range.thick;
          final permitted = <Iso5817Level>{
            for (final l in Iso5817Level.values)
              if (iso5817RuleFor(item, l, range).kind !=
                  Iso5817RuleKind.notPermitted)
                l,
          };
          final expected = permitted.length == 3
              ? texts[0]
              : permitted.length == 2
                  ? texts[1]
                  : permitted.length == 1
                      ? texts[2]
                      : texts[3];
          expect(i.answer, expected, reason: i.id);
        }
        // Pęknięcie: niedopuszczalne na każdym poziomie.
        expect(_item('q5817.lv.1.1.all', en: en).answer, texts[3]);
        // Podtopienie t > 3 mm: B, C i D (z limitem); 0,5–3 mm: tylko C i D.
        expect(_item('q5817.lv.1.7.thick', en: en).answer, texts[0]);
        expect(_item('q5817.lv.1.7.thin', en: en).answer, texts[1]);
      });

      test(
          'symbole ISO 2553: nazwa z weldKindName, strona z sideAsDrawn '
          '($lang)', () {
        final glyphs = _items('sym.glyph.', en: en);
        expect(glyphs.length, basicSymbolCatalog.length);
        for (final i in glyphs) {
          final kind = WeldKind.values
              .firstWhere((k) => k.name == i.id.substring('sym.glyph.'.length));
          expect(i.glyph, kind);
          expect(i.answer, weldKindName(kind, en: en));
        }
        for (final i in _items('sym.side.', en: en)) {
          final parts = i.id.split('.');
          final system =
              SymbolSystem.values.firstWhere((s) => s.name == parts[2]);
          final side = WeldSide.values.firstWhere((s) => s.name == parts[3]);
          expect(
              i.answer.toLowerCase(), weldSideText(side, en: en).toLowerCase());
          expect(i.prompt, contains(sideAsDrawn(system, side, en: en)));
        }
        expect(_item('sym.side.a.other').answer, 'Po stronie przeciwnej');
      });

      test(
          'elektrody AWS D1.1: limit z ElectrodeClass.limitMinutes, E7018 → '
          '4 h ($lang)', () {
        final limits = _items('el.limit.', en: en);
        expect(limits, isNotEmpty);
        for (final i in limits) {
          final c = ElectrodeClass.values
              .firstWhere((x) => x.name == i.id.substring('el.limit.'.length));
          expect(c.family.perManufacturer, isFalse);
          expect(i.answer, examDuration(c.limitMinutes));
          expect(i.prompt, contains(c.code));
        }
        for (final i in _items('el.class.', en: en)) {
          final c = ElectrodeClass.values
              .firstWhere((x) => x.name == i.id.substring('el.class.'.length));
          expect(i.answer, c.code);
        }
        expect(_item('el.limit.e7018', en: en).answer, '4 h');
        expect(_item('el.limit.e7018R', en: en).answer, '9 h');
        expect(_item('el.limit.e10018X', en: en).answer, '30 min');
      });

      test('gazy EN ISO 14175 i dobór spoiwa z selectFiller ($lang)', () {
        for (final g in GasSymbol.values) {
          expect(_item('gas.sym.${g.code}', en: en).answer,
              g.description.of(english: en));
          expect(_item('gas.code.${g.code}', en: en).answer, g.code);
        }
        final fills = _items('fill.', en: en);
        expect(fills, isNotEmpty);
        for (final i in fills) {
          final parts = i.id.split('.');
          final a = BaseMaterial.values.firstWhere((m) => m.name == parts[1]);
          final b = BaseMaterial.values.firstWhere((m) => m.name == parts[2]);
          final rec = selectFiller(a, b);
          expect(rec.verdict, FillerVerdict.typical);
          expect(i.answer, rec.family!.name.of(english: en));
        }
        expect(
            _item('fill.carbonSteel.ss304L', en: en).answer,
            selectFiller(BaseMaterial.carbonSteel, BaseMaterial.ss304L)
                .family!
                .name
                .of(english: en));
      });

      test('definicje, skróty i tłumaczenia ze słownika ($lang)', () {
        for (final i in _items('def.', en: en)) {
          final t = _term(i.id.substring('def.'.length));
          expect(i.answer, _name(t, en));
          expect(i.prompt, contains(en ? t.defEn! : t.defPl!));
        }
        for (final i in _items('abbr.', en: en)) {
          final t = _term(i.id.substring('abbr.'.length));
          expect(i.prompt, contains(t.code!));
          expect(i.answer, glossaryNameWithoutCode(_name(t, en), t.code));
          expect(i.answer, isNot(contains(t.code!)));
        }
        final vocab = _items('vocab.', en: en);
        expect(vocab, isNotEmpty);
        for (final i in vocab) {
          final parts = i.id.split('.');
          final target =
              GlossaryLang.values.firstWhere((l) => l.name == parts[1]);
          final t = _term(parts.sublist(2).join('.'));
          expect(i.answer, t.text(target));
          expect(i.prompt, contains(_name(t, en)));
          expect(target, isNot(en ? GlossaryLang.en : GlossaryLang.pl));
        }
        expect(_item('abbr.t_vt').answer, 'Badania wizualne');
        expect(_item('vocab.de.n_grinder').answer, _term('n_grinder').de);
      });
    }
  });

  group('dystraktory i niejednoznaczność', () {
    test(
        'każde pytanie: ≥ 3 różne odpowiedzi, dokładnie jedna poprawna, '
        'treść i źródło (PL i EN)', () {
      for (final en in [false, true]) {
        final items = examItems(en: en);
        expect(items.length, greaterThan(500));
        final ids = <String>{};
        for (final i in items) {
          expect(ids.add(i.id), isTrue, reason: 'powtórzone id ${i.id}');
          expect(i.prompt.trim(), isNotEmpty, reason: i.id);
          expect(i.explanation.trim(), isNotEmpty, reason: i.id);
          expect(i.source.trim(), isNotEmpty, reason: i.id);
          expect(i.distractors.length, greaterThanOrEqualTo(2), reason: i.id);
          final keys = _all(i).map(examAnswerKey).toList();
          expect(keys.toSet().length, keys.length, reason: i.id);
          expect(i.distractors.map(examAnswerKey),
              isNot(contains(examAnswerKey(i.answer))),
              reason: i.id);
        }
        for (final c in ExamCategory.values) {
          expect(examItemsIn(c, en: en), isNotEmpty, reason: c.name);
        }
      }
    });

    test('dystraktory z tej samej kategorii danych', () {
      const en = false;
      final processNames = {
        for (final t in kWeldingGlossary)
          if (t.category == GlossaryCategory.process && t.iso4063 != null) t.pl,
      };
      for (final i in _items('proc.name.', en: en)) {
        expect(processNames, containsAll(_all(i)), reason: i.id);
      }
      final impNumbers = {
        for (final t in kWeldingGlossary)
          if (t.iso6520 != null) t.iso6520!,
      };
      for (final i in _items('imp.num.', en: en)) {
        expect(impNumbers, containsAll(_all(i)), reason: i.id);
      }
      final posCodes = {
        for (final t in kWeldingGlossary)
          if (glossaryPositionCodes(t) != null) glossaryPositionCodes(t)!.iso,
      };
      for (final i in _items('pos.code.', en: en)) {
        expect(posCodes, containsAll(_all(i)), reason: i.id);
      }
      // Pozycje ISO 9606-1: dystraktory to zakresy innych pozycji TEJ SAMEJ
      // tabeli (rodzaj spoiny × wyrób).
      for (final i in _items('q.pos.', en: en)) {
        final parts = i.id.split('.');
        final type = _type(parts[2]);
        final product = _product(parts[3]);
        final sameTable = {
          for (final p in iso9606TestPositions(type, product))
            _positionsFromDomain(type, product, p),
        };
        expect(sameTable, containsAll(_all(i)), reason: i.id);
      }
      final awsLimits = {
        for (final c in ElectrodeClass.values)
          if (!c.family.perManufacturer) examDuration(c.limitMinutes),
      };
      for (final i in _items('el.limit.', en: en)) {
        expect(awsLimits, containsAll(_all(i)), reason: i.id);
      }
      final gasCodes = {for (final g in GasSymbol.values) g.code};
      for (final i in _items('gas.code.', en: en)) {
        expect(gasCodes, containsAll(_all(i)), reason: i.id);
      }
      for (final i in _items('sym.glyph.', en: en)) {
        final names = {
          for (final s in basicSymbolCatalog) weldKindName(s.kind, en: en),
        };
        expect(names, containsAll(_all(i)), reason: i.id);
      }
      for (final i in _items('vocab.', en: en)) {
        final parts = i.id.split('.');
        final target =
            GlossaryLang.values.firstWhere((l) => l.name == parts[1]);
        final t = _term(parts.sublist(2).join('.'));
        final sameCategory = {
          for (final o in kWeldingGlossary)
            if (o.category == t.category) o.text(target),
        };
        expect(sameCategory, containsAll(_all(i)), reason: i.id);
      }
    });

    test(
        'pomijane niejednoznaczne: s ≥ 12, reguły słowne ISO 5817, '
        'spokrewnione niezgodności, elektrody o tym samym limicie, spoiwo '
        'z uzasadnienia, synonimy', () {
      const en = false;
      // s ≥ 12 — notka „sprawdź” (EN 287-1 vs ISO 9606-1).
      expect(kExamButtThicknesses.every((s) => s < 12), isTrue);
      for (final i in _items('q.s.', en: en)) {
        expect(double.parse(i.id.substring(4)), lessThan(12));
      }
      // ISO 5817: pozycje z regułą słowną (rozprysk, barwy nalotowe,
      // porowatość grani…) — bez pytania o poziomy.
      for (final item in kIso5817Items) {
        for (final range in Iso5817Range.values) {
          final qualitative = Iso5817Level.values.any((l) =>
              iso5817RuleFor(item, l, range).kind ==
              Iso5817RuleKind.qualitative);
          if (!qualitative) continue;
          expect(
              _items('q5817.lv.${item.id}.', en: en).where(
                  (i) => i.id.endsWith(range.name) || i.id.endsWith('.all')),
              isEmpty,
              reason: item.id);
        }
      }
      expect(examItemById('q5817.lv.1.23.all', en: en), isNull);
      // Niezgodności: grupa „x00” i jej podtypy nie są dla siebie
      // dystraktorami (2011 nie ma „Pustka” 200).
      expect(_item('imp.name.i2011').distractors,
          isNot(contains(_term('i200').pl)));
      expect(_item('imp.num.i301').distractors, isNot(contains('300')));
      for (final i in _items('imp.num.', en: en)) {
        for (final d in i.distractors) {
          expect(iso6520Related(i.answer, d), isFalse, reason: '${i.id}: $d');
        }
      }
      // Elektrody: klasa o tym samym limicie nie jest dystraktorem.
      for (final i in _items('el.class.', en: en)) {
        final c = ElectrodeClass.values
            .firstWhere((x) => x.name == i.id.substring('el.class.'.length));
        for (final d in i.distractors) {
          final other = ElectrodeClass.values.firstWhere((x) => x.code == d);
          expect(other.limitMinutes, isNot(c.limitMinutes), reason: i.id);
        }
      }
      // Dobór spoiwa: spoiwa wymienione w uzasadnieniu / ostrzeżeniach pary
      // (np. 2209 i 309LMo przy stali węglowej + dupleks) nie są
      // dystraktorami.
      final duplex = _item('fill.carbonSteel.duplex2205');
      expect(duplex.distractors.where((d) => d.contains('2209')), isEmpty);
      expect(duplex.distractors.where((d) => d.contains('309LMo')), isEmpty);
      // … ani spoiwa dobierane w tych samych grupach materiałowych (308L
      // przy dwóch austenitach).
      final ss = _item('fill.ss304L.ss304L');
      expect(ss.distractors.where((d) => d.contains('316L')), isEmpty);
      for (final i in _items('fill.', en: en)) {
        final parts = i.id.split('.');
        final a = BaseMaterial.values.firstWhere((m) => m.name == parts[1]);
        final b = BaseMaterial.values.firstWhere((m) => m.name == parts[2]);
        final rec = selectFiller(a, b);
        final texts = [rec.summary, ...rec.warnings]
            .expand((x) => [x.pl, x.en])
            .join(' ');
        for (final d in i.distractors) {
          final family = [
            kFillerCarbon,
            kFillerNi1,
            kFillerMo,
            kFillerCrMo1,
            kFillerCrMo2,
            kFillerCrMo91,
            kFiller308L,
            kFiller316L,
            kFiller347,
            kFiller309L,
            kFiller309LMo,
            kFiller2209,
            kFiller2594,
            kFillerNiCr3,
            kFillerNiCu7,
            kFillerCuNi30,
            kFiller5183,
            kFiller6xxx,
          ].firstWhere((f) => f.name.pl == d);
          for (final token in fillerTokens(family)) {
            expect(texts.contains(token), isFalse, reason: '${i.id}: $d');
          }
        }
      }
      // Tłumaczenia: synonim poprawnej odpowiedzi nie jest dystraktorem.
      for (final i in _items('vocab.', en: en)) {
        final parts = i.id.split('.');
        final target =
            GlossaryLang.values.firstWhere((l) => l.name == parts[1]);
        final t = _term(parts.sublist(2).join('.'));
        final syn = t.synonymsFor(target).map(normalizeGlossary).toSet();
        for (final d in i.distractors) {
          expect(syn, isNot(contains(normalizeGlossary(d))), reason: i.id);
        }
      }
      // Definicje: pojęcie nadrzędne / pokrewne (nazwa w definicji) odpada.
      for (final i in _items('def.', en: en)) {
        final t = _term(i.id.substring('def.'.length));
        for (final d in i.distractors) {
          final other = kWeldingGlossary
              .firstWhere((o) => o.pl == d && o.category == t.category);
          expect(glossaryDefinitionsOverlap(t, other), isFalse,
              reason: '${i.id}: $d');
        }
      }
      expect(examItemById('def.i_imperfection', en: en), isNull);
    });

    test('identyfikatory wspólne dla PL i EN (poza słownictwem)', () {
      Set<String> ids(bool en) => {
            for (final i in examItems(en: en))
              if (!i.id.startsWith('vocab.')) i.id,
          };
      expect(ids(true), ids(false));
    });

    test('EN: treść bez polskich znaków', () {
      for (final i in examItems(en: true)) {
        for (final s in [i.prompt, ..._all(i), i.explanation, i.source]) {
          expect(s.split('').where(_polishLetters.contains), isEmpty,
              reason: '${i.id}: $s');
        }
      }
    });
  });

  group('losowanie', () {
    List<String> snapshot(List<ExamQuestion> qs) => [
          for (final q in qs)
            '${q.id} | ${q.options.join(' | ')} | ${q.correctIndex}',
        ];

    test('ten sam seed → te same pytania i ta sama kolejność odpowiedzi', () {
      for (final en in [false, true]) {
        final a = drawExamQuestions(seed: 42, en: en);
        final b = drawExamQuestions(seed: 42, en: en);
        expect(snapshot(a), snapshot(b));
        final c1 = drawExamQuestions(
            seed: 7, en: en, category: ExamCategory.qualification);
        final c2 = drawExamQuestions(
            seed: 7, en: en, category: ExamCategory.qualification);
        expect(snapshot(c1), snapshot(c2));
      }
      final other = drawExamQuestions(seed: 43, en: false);
      expect(snapshot(other),
          isNot(snapshot(drawExamQuestions(seed: 42, en: false))));
    });

    test('pytanie: poprawna odpowiedź pod correctIndex, maks. 4 odpowiedzi',
        () {
      for (var seed = 0; seed < 30; seed++) {
        for (final q in drawExamQuestions(seed: seed, en: seed.isOdd)) {
          expect(q.options[q.correctIndex], q.answer);
          expect(q.options.length, inInclusiveRange(3, kExamMaxOptions));
          expect(q.options.toSet().length, q.options.length);
          for (final o in q.options) {
            expect(o == q.answer || q.item.distractors.contains(o), isTrue);
          }
        }
      }
    });

    test('szybka sesja: 10 pytań z 10 różnych kategorii', () {
      final qs = drawExamQuestions(seed: 1, en: false);
      expect(qs.length, kExamSessionLength);
      expect(
          qs.map((q) => q.category).toSet().length, ExamCategory.values.length);
      expect(qs.map((q) => q.id).toSet().length, qs.length);
    });

    test('nauka kategorii: tylko pytania z wybranej kategorii, bez powtórek',
        () {
      for (final c in ExamCategory.values) {
        final qs = drawExamQuestions(seed: 3, en: false, category: c);
        expect(qs.length,
            examItemsIn(c, en: false).length.clamp(0, kExamSessionLength));
        expect(qs.every((q) => q.category == c), isTrue, reason: c.name);
        expect(qs.map((q) => q.id).toSet().length, qs.length);
      }
    });

    test('powtórki: tylko wskazane id, nieznane pominięte', () {
      final ids = ['proc.name.p135', 'q.pos.BW.T.PH', 'nie-ma-takiego'];
      final qs = drawExamQuestions(seed: 5, en: false, onlyIds: ids);
      expect(qs.map((q) => q.id).toSet(), {'proc.name.p135', 'q.pos.BW.T.PH'});
    });
  });
}
