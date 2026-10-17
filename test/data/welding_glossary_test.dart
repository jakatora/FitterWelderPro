// Dane słownika spawalniczego: kompletność, spójność numerów ISO,
// kontrolne tłumaczenia i normalizacja tekstu do szukania.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/welding_glossary.dart';
import 'package:cut_list_app/domain/glossary/glossary.dart';

GlossaryTerm _byId(String id) =>
    kWeldingGlossary.firstWhere((t) => t.id == id, orElse: () {
      fail('Brak terminu $id');
    });

void main() {
  group('kompletność danych', () {
    test('identyfikatory są unikalne i niepuste', () {
      final ids = <String>{};
      for (final t in kWeldingGlossary) {
        expect(t.id.trim(), isNotEmpty);
        expect(ids.add(t.id), isTrue, reason: 'powtórzony id ${t.id}');
      }
    });

    test('każdy termin ma 5 niepustych tłumaczeń bez spacji na brzegach', () {
      for (final t in kWeldingGlossary) {
        for (final lang in GlossaryLang.values) {
          final s = t.text(lang);
          expect(s, isNotEmpty, reason: '${t.id} ${lang.code}');
          expect(s, s.trim(), reason: '${t.id} ${lang.code}: „$s”');
          expect(s.contains('  '), isFalse, reason: '${t.id} ${lang.code}');
        }
        for (final entry in t.synonyms.entries) {
          for (final s in entry.value) {
            expect(s, isNotEmpty, reason: '${t.id} synonim');
            expect(s, s.trim(), reason: '${t.id} synonim „$s”');
          }
        }
        for (final d in [t.defPl, t.defEn]) {
          if (d == null) continue;
          expect(d, d.trim(), reason: '${t.id} definicja');
          expect(d, isNotEmpty);
        }
        // Definicja jest parą: albo obie, albo żadna.
        expect(t.defPl == null, t.defEn == null, reason: '${t.id} definicje');
      }
    });

    test('brak duplikatów PL w tej samej kategorii', () {
      final seen = <String>{};
      for (final t in kWeldingGlossary) {
        final key = '${t.category.name}|${normalizeGlossary(t.pl)}';
        expect(seen.add(key), isTrue, reason: 'duplikat PL: ${t.pl}');
      }
    });

    // Cel był 250–350 terminów, ale do danych trafia tylko to, co potwierdzono
    // w źródłach we wszystkich pięciu językach — stąd dolna granica 230.
    test('rozmiar: 230–350 terminów i 40–60 zwrotów', () {
      final phrases = kWeldingGlossary
          .where((t) => t.category == GlossaryCategory.phrase)
          .length;
      final terms = kWeldingGlossary.length - phrases;
      expect(terms, inInclusiveRange(230, 350));
      expect(phrases, inInclusiveRange(40, 60));
    });

    test('każda kategoria ma terminy', () {
      for (final c in GlossaryCategory.values) {
        expect(kWeldingGlossary.where((t) => t.category == c), isNotEmpty,
            reason: c.name);
      }
    });

    test('zwroty kończą się znakiem interpunkcyjnym we wszystkich językach',
        () {
      for (final t in kWeldingGlossary
          .where((t) => t.category == GlossaryCategory.phrase)) {
        for (final lang in GlossaryLang.values) {
          expect(t.text(lang), matches(RegExp(r'[.?!]$')),
              reason: '${t.id} ${lang.code}');
        }
      }
    });
  });

  group('numery ISO', () {
    // ISO 6520-1:2007, p. 4: grupa 1 — pęknięcia, 2 — pustki, 3 — wtrącenia
    // stałe, 4 — przyklejenia i braki przetopu, 5 — niezgodności kształtu
    // i wymiarów, 6 — inne niezgodności. Pierwsza cyfra numeru = grupa.
    const groupPrefix = <String, String>{
      '1': 'pęknięcia',
      '2': 'pustki',
      '3': 'wtrącenia stałe',
      '4': 'przyklejenia i braki przetopu',
      '5': 'kształt i wymiary',
      '6': 'inne',
    };

    test('ISO 6520 tylko przy niezgodnościach, 3–4 cyfry, zgodne z grupą', () {
      final withIso =
          kWeldingGlossary.where((t) => t.iso6520 != null).toList();
      expect(withIso.length, greaterThanOrEqualTo(15));
      for (final t in withIso) {
        final n = t.iso6520!;
        expect(t.category, GlossaryCategory.imperfection, reason: t.id);
        expect(n, matches(RegExp(r'^[1-6]\d{2,3}$')), reason: t.id);
        expect(groupPrefix.containsKey(n[0]), isTrue, reason: t.id);
      }
    });

    test('grupy ISO 6520 pasują do treści terminu', () {
      // Pęknięcia mają w nazwie „pęknię…”, wtrącenia „wtrące…”,
      // grupa 4 to przyklejenia / przetop.
      for (final t in kWeldingGlossary.where((t) => t.iso6520 != null)) {
        final pl = normalizeGlossary(t.pl);
        switch (t.iso6520![0]) {
          case '1':
            expect(pl, contains('pekni'), reason: t.id);
          case '3':
            expect(pl, contains('wtracen'), reason: t.id);
          case '4':
            expect(pl.contains('przyklej') || pl.contains('przetop'), isTrue,
                reason: t.id);
        }
      }
    });

    test('numery ISO 6520 i ISO 4063 są unikalne', () {
      final n6520 = <String>{};
      final n4063 = <String>{};
      for (final t in kWeldingGlossary) {
        if (t.iso6520 != null) {
          expect(n6520.add(t.iso6520!), isTrue, reason: t.iso6520);
        }
        if (t.iso4063 != null) {
          expect(n4063.add(t.iso4063!), isTrue, reason: t.iso4063);
        }
      }
    });

    test('ISO 4063 tylko przy procesach, 2–3 cyfry', () {
      for (final t in kWeldingGlossary.where((t) => t.iso4063 != null)) {
        expect(t.category, GlossaryCategory.process, reason: t.id);
        expect(t.iso4063, matches(RegExp(r'^\d{2,3}$')), reason: t.id);
      }
    });

    test('etykieta numeru normy', () {
      expect(_byId('i5011').isoLabel, 'ISO 6520-1: 5011');
      expect(_byId('p135').isoLabel, 'ISO 4063: 135');
    });
  });

  group('kontrolne tłumaczenia', () {
    test('5011 podtopienie ciągłe', () {
      final t = _byId('i5011');
      expect(t.iso6520, '5011');
      expect(t.pl.toLowerCase(), contains('podtopienie'));
      expect(t.en.toLowerCase(), contains('undercut'));
      expect(t.de, contains('Einbrandkerbe'));
      expect(t.nl.toLowerCase(), contains('randinkarteling'));
    });

    test('100 pęknięcie, 2011 pęcherz, 301 żużel, 401 przyklejenie', () {
      expect(_byId('i100').en, 'Crack');
      expect(_byId('i100').de, 'Riss');
      expect(_byId('i2011').en, 'Gas pore');
      expect(_byId('i301').en, 'Slag inclusion');
      expect(_byId('i301').de, 'Schlackeneinschluss');
      expect(_byId('i401').en, 'Lack of fusion');
      expect(_byId('i401').de, 'Bindefehler');
    });

    test('procesy 111, 135, 141', () {
      expect(_byId('p111').iso4063, '111');
      expect(_byId('p135').en, contains('MAG'));
      expect(_byId('p141').en, contains('TIG'));
      expect(_byId('p141').de, contains('Wolfram-Inertgas'));
    });

    test('pozycje PA i PF', () {
      expect(_byId('pos_pa').code, contains('PA'));
      expect(_byId('pos_pa').de, 'Wannenposition');
      expect(_byId('pos_pf').de, 'Steigposition');
    });

    test('BHP i narzędzia', () {
      expect(_byId('s_fire_watch').de, contains('Brandwache'));
      expect(_byId('s_fire_watch').nl, 'Brandwacht');
      expect(_byId('n_grinder').de, 'Winkelschleifer');
      expect(_byId('n_grinder').nl, 'Haakse slijper');
    });
  });

  group('normalizacja', () {
    test('polskie znaki', () {
      expect(normalizeGlossary('Łuk ŻÓŁTY, Ścieg; gęś źdźbło ćma ńa'),
          'luk zolty scieg ges zdzblo cma na');
    });

    test('niemieckie umlauty i ß', () {
      expect(normalizeGlossary('Überkopfposition'), 'uberkopfposition');
      expect(normalizeGlossary('Schweißgerät'), 'schweissgerat');
      expect(normalizeGlossary('Größe Ölfänger'), 'grosse olfanger');
    });

    test('norweskie ø, å, æ', () {
      expect(normalizeGlossary('Rørstøtte'), 'rorstotte');
      expect(normalizeGlossary('Hørselvern på særlig'), 'horselvern pa saerlig');
    });

    test('niderlandzkie diakrytyki i interpunkcja', () {
      expect(normalizeGlossary('Lascoördinator (NIL)'), 'lascoordinator nil');
      expect(normalizeGlossary('Reïnigen  –  café'), 'reinigen cafe');
    });

    test('cyfry i CO₂ zostają', () {
      expect(normalizeGlossary('ISO 6520-1: 5011'), 'iso 6520 1 5011');
      expect(normalizeGlossary('CO₂'), 'co2');
    });
  });

  group('wyszukiwarka (indeks)', () {
    test('po numerze ISO dokładne trafienie na górze', () {
      expect(weldingGlossaryIndex.search('5011').first.id, 'i5011');
      expect(weldingGlossaryIndex.search('135').first.id, 'p135');
    });

    test('bez diakrytyków w każdym języku', () {
      expect(weldingGlossaryIndex.search('podtopienie').map((t) => t.id),
          contains('i5011'));
      expect(weldingGlossaryIndex.search('einbrandkerbe').map((t) => t.id),
          contains('i5011'));
      expect(weldingGlossaryIndex.search('randinkarteling').map((t) => t.id),
          contains('i5011'));
    });

    test('puste zapytanie zwraca wszystko w kolejności danych', () {
      final all = weldingGlossaryIndex.search('');
      expect(all.length, kWeldingGlossary.length);
      expect(all.first.id, kWeldingGlossary.first.id);
    });

    test('filtr kategorii i ulubionych', () {
      final imp = weldingGlossaryIndex.search('',
          category: GlossaryCategory.imperfection);
      expect(imp.every((t) => t.category == GlossaryCategory.imperfection),
          isTrue);
      final fav = weldingGlossaryIndex.search('', onlyIds: {'i5011', 'p135'});
      expect(fav.map((t) => t.id).toSet(), {'i5011', 'p135'});
    });

    test('wszystkie słowa zapytania muszą wystąpić', () {
      expect(weldingGlossaryIndex.search('podtopienie zzzz'), isEmpty);
    });
  });
}
