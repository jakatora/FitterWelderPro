// Odcinek dłuższy niż sztanga i jedna reguła zaokrąglenia.
//
// Było: 7000 mm na sztangach 6000 dzielone na 6000 + 1000 — po zespawaniu
// z gapem g spool wychodził o g za długi, a ostrzeżenie tylko kazało
// „uwzględnić gap”, choć projekt go zna. Długości na sztangach miały 0
// miejsc po przecinku, tabela segmentów w PDF 1 — CUT 1234,5 widniał raz
// jako „1235”, raz jako „1234.5”.
//
// Jest: części = pełne sztangi + reszta pomniejszona o gap × (n − 1), a
// ostrzeżenie podaje wynik. Wszędzie formatCutMm: 0,1 mm, bez „.0”.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/services/bar_nesting.dart';
import 'package:cut_list_app/services/cut_list_csv.dart';
import 'package:cut_list_app/services/cut_list_summary.dart';

Segment _seg(int seq, double cut, {double dia = 114.3}) => Segment(
      id: 'seg-$seq',
      projectId: 'p',
      seqNo: seq,
      diameterMm: dia,
      wallThicknessMm: 6.02,
      startKind: 'logical',
      startLibraryId: null,
      startValueMm: 0,
      endKind: 'logical',
      endLibraryId: null,
      endValueMm: 0,
      isoRef: 'FACE',
      isoExpr: '',
      isoMm: cut,
      cutMm: cut,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  group('splitCutLengths', () {
    test('7000 na 6000 z gapem 3: 6000 + 997 (po spawaniu 7000)', () {
      final parts = splitCutLengths(7000, stockLengthMm: 6000, joinGapMm: 3);
      expect(parts, [6000.0, 997.0]);
      expect(parts.reduce((a, b) => a + b) + 3 * (parts.length - 1), 7000);
    });
    test('13000 z gapem 3: trzy części, dwie spoiny', () {
      expect(splitCutLengths(13000, stockLengthMm: 6000, joinGapMm: 3),
          [6000.0, 6000.0, 994.0]);
    });
    test('12003 z gapem 3 mieści się w dwóch sztangach', () {
      expect(splitCutLengths(12003, stockLengthMm: 6000, joinGapMm: 3),
          [6000.0, 6000.0]);
    });
    test('reszta ≤ 0 po odjęciu gapu: dwie ostatnie części po równo', () {
      // 6001 z gapem 3 → razem 5998 w dwóch kawałkach.
      expect(splitCutLengths(6001, stockLengthMm: 6000, joinGapMm: 3),
          [2999.0, 2999.0]);
    });
    test('bez gapu i mieszczące się bez zmian', () {
      expect(splitCutLengths(7000, stockLengthMm: 6000, joinGapMm: 0),
          [6000.0, 1000.0]);
      expect(splitCutLengths(5000, stockLengthMm: 6000, joinGapMm: 3),
          [5000.0]);
    });
  });

  test('nesting: części pomniejszone o gap, ostrzeżenie z wynikiem', () {
    final s = summarizeCutList(
      segments: [_seg(1, 7000)],
      stockLengthMm: 6000,
      sawKerfMm: 0,
      joinGapMm: 3,
    );
    final pieces = s.groups.single.plans.expand((p) => p.pieces).toList();
    expect(pieces.map((p) => p.lengthMm), [6000.0, 997.0]);
    final split = s.splitCuts.single;
    expect(
      oversizeCutWarning(split, stockLengthMm: 6000, english: false),
      'S01: odcinek 7000 mm dłuższy niż sztanga 6000 mm — dzielony na '
      '2 części: 6000 + 997 mm (odjęto gap 3 mm dodatkowej spoiny łączącej).',
    );
    expect(
      oversizeCutWarning(split, stockLengthMm: 6000, english: true),
      'S01: piece 7000 mm is longer than the 6000 mm stock bar — split into '
      '2 parts: 6000 + 997 mm (3 mm gap of the extra joining weld taken off).',
    );
  });

  test('ostrzeżenie przy gapie 0 mówi, że nic nie odjęto', () {
    final s = summarizeCutList(
      segments: [_seg(4, 14000)],
      stockLengthMm: 6000,
      sawKerfMm: 0,
    );
    expect(
      oversizeCutWarning(s.splitCuts.single,
          stockLengthMm: 6000, english: false),
      'S04: odcinek 14000 mm dłuższy niż sztanga 6000 mm — dzielony na '
      '3 części: 6000 + 6000 + 2000 mm; 2 dodatkowe spoiny łączące '
      '(gap projektu 0 mm — nic nie odjęto).',
    );
  });

  group('formatCutMm — jedna reguła', () {
    test('0,1 mm, bez zbędnego „.0”', () {
      expect(formatCutMm(1234.5), '1234.5');
      expect(formatCutMm(1234.46), '1234.5');
      expect(formatCutMm(3293), '3293');
      expect(formatCutMm(3292.96), '3293');
      expect(formatCutMm(0.04), '0');
    });

    test('ekran (sztanga), tekst, CSV i tabela segmentów: to samo 1234.5', () {
      final segs = [_seg(1, 1234.5)];
      final s = summarizeCutList(
          segments: segs, stockLengthMm: 6000, sawKerfMm: 3);
      expect(formatBarPieces(s.groups.single.plans.single), 'S01: 1234.5');
      final csv = buildCutListCsv(
        projectName: 'X',
        materialGroup: 'SS',
        stockLengthMm: 6000,
        sawKerfMm: 3,
        segments: segs,
      );
      final row = csv.trim().split('\n').last.split(';');
      expect(row[8], '1234.5', reason: 'kolumna cięcie_mm');
      expect(row[9], formatCutMm(6000 - 1234.5 - 3));
    });
  });

  test('grupowanie z tolerancją: 114,3 i 114,30000000000001 to jedna rura', () {
    final s = summarizeCutList(
      segments: [_seg(1, 2000), _seg(2, 2000, dia: 114.30000000000001)],
      stockLengthMm: 6000,
      sawKerfMm: 3,
    );
    expect(s.groups, hasLength(1));
    expect(s.totalBars, 1);
  });
}
