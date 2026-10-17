// Kod kolorów pasów EN 1492-1/-2 i teksty / liczby modułu zawiesi.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/rigging/rigging_calc.dart';
import 'package:cut_list_app/domain/rigging/rigging_colors.dart';
import 'package:cut_list_app/domain/rigging/rigging_sources.dart';
import 'package:cut_list_app/domain/rigging/rigging_text.dart';

void main() {
  test('kod kolorów: fiolet 1 t … niebieski 8 t, pomarańcz od 10 t', () {
    expect({
      for (final c in SlingColour.values) c: c.nominalT
    }, {
      SlingColour.violet: 1,
      SlingColour.green: 2,
      SlingColour.yellow: 3,
      SlingColour.grey: 4,
      SlingColour.red: 5,
      SlingColour.brown: 6,
      SlingColour.blue: 8,
      SlingColour.orange: 10,
      SlingColour.other: null,
    });
    expect(SlingColour.orange.orAbove, isTrue);
    expect(SlingColour.blue.orAbove, isFalse);
  });

  test('zgodność koloru z WLL z etykiety', () {
    expect(colourMatchesWll(SlingColour.green, 2000), isTrue);
    expect(colourMatchesWll(SlingColour.green, 3000), isFalse);
    expect(colourMatchesWll(SlingColour.green, 1500), isFalse);
    expect(colourMatchesWll(SlingColour.orange, 10000), isTrue);
    expect(colourMatchesWll(SlingColour.orange, 20000), isTrue);
    expect(colourMatchesWll(SlingColour.orange, 8000), isFalse);
    expect(colourMatchesWll(SlingColour.other, 2000), isNull);
    expect(colourMatchesWll(SlingColour.green, double.nan), isNull);
  });

  test('liczby PL i EN', () {
    expect(rigNum(1600, decimals: 0, en: false), '1 600');
    expect(rigNum(1600, decimals: 0, en: true), '1,600');
    expect(rigNum(1.6, en: false), '1,6');
    expect(rigNum(1.6, en: true), '1.6');
    expect(rigNum(12345.5, decimals: 1, en: false), '12 345,5');
    expect(kgText(2800, en: false), '2 800 kg');
    expect(tText(1601, en: false), '1,601 t');
    expect(tText(2000, en: true), '2 t');
    expect(massInUnit(1600, MassUnit.t, en: false), '1,6 t (1 600 kg)');
    expect(massInUnit(1600, MassUnit.kg, en: true), '1,600 kg (1.6 t)');
    expect(factorText(1.12, en: false), '×1,12');
    expect(factorText(1.0, en: false), '×1,0');
    expect(factorText(2.0, en: true), '×2.0');
    expect(rigNum(double.nan, en: false), '—');
  });

  test('każdy werdykt i brak ma tekst PL i EN; STOP zaczyna się od „STOP”', () {
    for (final v in RiggingVerdict.values) {
      for (final en in [false, true]) {
        final t = verdictTitle(v, en: en);
        expect(t, isNotEmpty);
        expect(t.startsWith('STOP'), v.isStop, reason: '$v en=$en');
      }
    }
    for (final i in RiggingIssue.values) {
      expect(issueText(i, en: false), isNot(issueText(i, en: true)));
    }
  });

  test('źródła i „przyjęte w aplikacji” mają obie wersje językowe', () {
    for (final s in [...kRiggingSources, ...kRiggingAdopted]) {
      expect(s.pl, isNotEmpty);
      expect(s.en, isNotEmpty);
      expect(s.pl, isNot(s.en));
    }
    expect(kRiggingAdopted.map((s) => s.pl).join(),
        allOf(contains('45°'), contains('Łańcuch w koszowym')));
  });
}
