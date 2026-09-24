import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_journal/weld_filter.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/domain/weld_journal/weld_repair.dart';

import '../../support/weld_fixtures.dart';

/// Filtr dziennika był tylko po statusie. Inspektor prosi o "linię L-12
/// z maja, spawacz JK-12" albo "wszystko, co czeka na RT" — i dostaje
/// dokładnie ten zbiór w CSV/PDF.
void main() {
  final journal = [
    weld('a', project: 'Blok 4', line: 'L-12', welder: 'JK-12',
        date: '2026-05-10', status: 'OK',
        ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.ok)}),
    weld('b', project: 'blok 4', line: 'L-14', iso: 'ISO-101-0042',
        welder: 'MN-03', rootWelder: 'JK-12', date: '2026-05-31',
        status: 'NOK',
        ndt: {NdtMethod.ut: ndtOf(NdtScope.selected, NdtResult.nok)}),
    weld('c', project: 'Browar', line: 'L-12', welder: 'PR-07',
        date: '2026-06-01',
        ndt: {NdtMethod.rt: ndtOf(NdtScope.required)}),
    weld('d', project: 'Browar', welder: 'PR-07', date: '17.05.2026',
        status: 'OK'),
    weld('e', project: 'Blok 4', date: '2026-05-12', deletedAt: 99),
    weld('f', project: 'Blok 4', date: '2026-05-20', repairs: const [
      WeldRepair(
          id: 'r', weldId: 'f', seq: 1, date: '', reason: '',
          prevStatus: 'NOK', prevNdt: {}, byStamp: '', createdAt: 1),
    ]),
  ];

  List<String> ids(WeldJournalFilter f) =>
      filterWeldEntries(journal, f).map((e) => e.id).toList();

  test('domyślny filtr: wszystkie aktywne, kolejność zachowana', () {
    expect(ids(const WeldJournalFilter()), ['a', 'b', 'c', 'd', 'f']);
  });

  test('status', () {
    expect(ids(const WeldJournalFilter(status: 'NOK')), ['b']);
    expect(ids(const WeldJournalFilter(status: 'OK')), ['a', 'd']);
  });

  test('projekt bez względu na wielkość liter', () {
    expect(ids(const WeldJournalFilter(project: 'BLOK 4')), ['a', 'b', 'f']);
  });

  test('linia / ISO dopasowuje linię albo numer rysunku', () {
    expect(ids(const WeldJournalFilter(line: 'l-12')), ['a', 'c', 'd', 'f']);
    expect(ids(const WeldJournalFilter(line: '0042')), ['b']);
  });

  test('spawacz obejmuje stemple graniówki i lica', () {
    expect(ids(const WeldJournalFilter(welder: 'jk-12')), ['a', 'b', 'f']);
  });

  test('zakres dat jest domknięty; data spoza ISO nie wpada do zakresu', () {
    expect(
      ids(const WeldJournalFilter(dateFrom: '2026-05-10', dateTo: '2026-05-31')),
      ['a', 'b', 'f'],
    );
    expect(ids(const WeldJournalFilter(dateFrom: '2026-06-01')), ['c']);
  });

  test('filtry NDT', () {
    expect(ids(const WeldJournalFilter(ndt: WeldNdtFilter.volumetric)),
        ['a', 'b']);
    expect(ids(const WeldJournalFilter(ndt: WeldNdtFilter.awaiting)), ['c']);
    expect(ids(const WeldJournalFilter(ndt: WeldNdtFilter.rejected)), ['b']);
    expect(ids(const WeldJournalFilter(ndt: WeldNdtFilter.repaired)), ['f']);
    expect(ids(const WeldJournalFilter(ndt: WeldNdtFilter.notExamined)),
        ['c', 'd', 'f']);
  });

  test('usunięte widać tylko w widoku usuniętych', () {
    expect(ids(const WeldJournalFilter(deleted: true)), ['e']);
  });

  test('filtry łączą się (AND)', () {
    expect(
      ids(const WeldJournalFilter(
          project: 'Blok 4', welder: 'JK-12', status: 'OK')),
      ['a'],
    );
  });

  test('wynik jest kopią, nie listą ekranu', () {
    final shown = filterWeldEntries(journal, const WeldJournalFilter());
    shown.clear();
    expect(journal, hasLength(6));
  });

  test('liczba aktywnych filtrów pomija status (ma własne chipy)', () {
    expect(const WeldJournalFilter(status: 'NOK').extraFilterCount, 0);
    expect(
      const WeldJournalFilter(
              project: 'A', dateFrom: '2026-01-01', ndt: WeldNdtFilter.awaiting)
          .extraFilterCount,
      3,
    );
  });

  test('opis filtra trafia do nagłówka PDF', () {
    const f = WeldJournalFilter(
        status: 'NOK', project: 'Blok 4', dateFrom: '2026-05-01');
    final pl = f.describe(en: false);
    expect(pl, contains('NOK'));
    expect(pl, contains('Blok 4'));
    expect(pl, contains('2026-05-01'));
    expect(const WeldJournalFilter().describe(en: false), isEmpty);
  });

  test('znacznik do nazwy pliku jest krótki i bezpieczny', () {
    expect(const WeldJournalFilter().fileTag, '');
    expect(const WeldJournalFilter(status: 'NOK').fileTag, 'NOK');
    expect(const WeldJournalFilter(status: 'NOK', project: 'Blok 4/B').fileTag,
        'Blok_4_B_NOK');
    expect(const WeldJournalFilter(welder: 'JK-12').fileTag, 'FILTR');
  });
}
