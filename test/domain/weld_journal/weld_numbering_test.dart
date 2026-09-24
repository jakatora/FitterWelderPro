import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_numbering.dart';

/// Numery spoin: sortowanie naturalne, podpowiedź następnego numeru
/// (ostatni człon liczbowy, prefiks i zera zostają) i ostrzeżenie
/// o duplikacie w tym samym projekcie.
WeldEntry _w(
  String no, {
  String project = 'Blok 4',
  String? id,
  int? deletedAt,
}) =>
    WeldEntry(
      id: id ?? no,
      weldNo: no,
      projectName: project,
      pipeName: '',
      material: '',
      od: '',
      t: '',
      method: 'TIG',
      welder: '',
      date: '',
      notes: '',
      status: 'PENDING',
      deletedAt: deletedAt,
    );

void main() {
  group('sortowanie naturalne', () {
    test('W9 przed W10 (tekstowo było odwrotnie)', () {
      final nos = ['W10', 'W9', 'W1', 'W100', 'W2']..sort(compareWeldNos);
      expect(nos, ['W1', 'W2', 'W9', 'W10', 'W100']);
    });

    test('numery wieloczłonowe porównywane człon po członie', () {
      final nos = [
        'SP-002-W001',
        'SP-001-W010',
        'SP-001-W002',
        'SP-010-W001',
        'SP-001-W1',
      ]..sort(compareWeldNos);
      expect(nos, [
        'SP-001-W1',
        'SP-001-W002',
        'SP-001-W010',
        'SP-002-W001',
        'SP-010-W001',
      ]);
    });

    test('wielkość liter nie rozdziela numerów', () {
      final nos = ['w6', 'W5', 'w4']..sort(compareWeldNos);
      expect(nos, ['w4', 'W5', 'w6']);
    });

    test('bardzo długie ciągi cyfr nie przepełniają int', () {
      final nos = ['W99999999999999999999999', 'W100000000000000000000000']
        ..sort(compareWeldNos);
      expect(nos.first, 'W99999999999999999999999');
    });

    test('sortWeldEntries daje kolejność naturalną', () {
      final sorted = sortWeldEntries([_w('W10'), _w('W9'), _w('W11')]);
      expect(sorted.map((e) => e.weldNo), ['W9', 'W10', 'W11']);
    });
  });

  group('inkrementacja ostatniego członu liczbowego', () {
    test('SP-001-W005 → SP-001-W006 (prefiks i zera zostają)', () {
      expect(incrementWeldNo('SP-001-W005'), 'SP-001-W006');
    });
    test('przeniesienie cyfr zachowuje szerokość', () {
      expect(incrementWeldNo('W-009'), 'W-010');
    });
    test('szerokość rośnie, gdy zabraknie miejsca', () {
      expect(incrementWeldNo('W-999'), 'W-1000');
    });
    test('przyrostek po liczbie zostaje', () {
      expect(incrementWeldNo('W-005A'), 'W-006A');
    });
    test('sama liczba', () {
      expect(incrementWeldNo('12'), '13');
    });
    test('bez cyfr nie ma czego zwiększać', () {
      expect(incrementWeldNo('ABC'), isNull);
      expect(incrementWeldNo(''), isNull);
    });
  });

  group('podpowiedź następnego numeru', () {
    test('audyt: SP-001-W005 nie skleja cyfr w W-1006', () {
      final next = suggestNextWeldNo([_w('SP-001-W005')], projectName: 'Blok 4');
      expect(next, 'SP-001-W006');
    });

    test('bierze naturalnie największy numer projektu', () {
      // Tekstowo "W9" > "W10" i podpowiedź dawała W10 — duplikat.
      final next = suggestNextWeldNo([_w('W9'), _w('W10')], projectName: 'Blok 4');
      expect(next, 'W11');
    });

    test('usunięta spoina nadal blokuje swój numer', () {
      final next = suggestNextWeldNo(
        [_w('W-001'), _w('W-002', deletedAt: 1000)],
        projectName: 'Blok 4',
      );
      expect(next, 'W-003');
    });

    test('nowy projekt zaczyna od W-001', () {
      final next = suggestNextWeldNo([_w('W-050', project: 'A')], projectName: 'B');
      expect(next, 'W-001');
    });

    test('projekt dopasowany bez względu na wielkość liter i spacje', () {
      final next = suggestNextWeldNo([_w('W-007', project: 'Blok 4')],
          projectName: '  blok 4 ');
      expect(next, 'W-008');
    });

    test('pusty dziennik → W-001', () {
      expect(suggestNextWeldNo(const [], projectName: ''), 'W-001');
    });

    test('numery równoważne (W-010 / W-10) nie mylą podpowiedzi', () {
      // W-010 i W-10 mają tę samą wartość; największy jest W-11 → W-12.
      final next = suggestNextWeldNo(
        [_w('W-010'), _w('W-10', id: 'x'), _w('W-11', id: 'y')],
        projectName: 'Blok 4',
      );
      expect(next, 'W-12');
    });
  });

  group('duplikaty w projekcie', () {
    test('ten sam numer w tym samym projekcie = duplikat', () {
      final journal = [_w('W-005', id: 'a'), _w('W-006', id: 'b')];
      final dups = findDuplicateWeldNos(journal, _w(' w-005 ', id: 'new'));
      expect(dups.map((e) => e.id), ['a']);
    });

    test('ten sam wpis (edycja) nie jest swoim duplikatem', () {
      final journal = [_w('W-005', id: 'a')];
      expect(findDuplicateWeldNos(journal, _w('W-005', id: 'a')), isEmpty);
    });

    test('inny projekt i usunięte wpisy nie liczą się', () {
      final journal = [
        _w('W-005', id: 'a', project: 'Inny'),
        _w('W-005', id: 'b', deletedAt: 5),
      ];
      expect(findDuplicateWeldNos(journal, _w('W-005', id: 'new')), isEmpty);
    });
  });
}
