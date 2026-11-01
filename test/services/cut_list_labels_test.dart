// Etykiety segmentów w podsumowaniu CUT LIST (ekran, PDF, tekst do
// udostępnienia) i ostrzeżenie o cięciu dłuższym od sztangi.
// Ścianka fixture 6,02 mm ma zachować pełną dokładność także w tekście.
//
// Oczekiwane wartości policzone ręcznie (sztanga 6000 mm, rzaz 3 mm):
//   S01 3293 + S02 2500 → reszta 6000 − 5793 − 6 = 201 mm
//   S03 1200            → reszta 6000 − 1200 − 3 = 4797 mm
//   S01 7000 → 6000 (1/2) + 1000 (2/2); S02 4000 dzieli sztangę z 1000:
//     sztanga 1: 6000, 0 cięć, reszta 0
//     sztanga 2: 4000 + 1000, 2 cięcia → 6000 − 5000 − 6 = 994 mm

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/services/cut_list_summary.dart';

Segment _seg(int seqNo, double cutMm,
    {double diameterMm = 114.3, double wallMm = 6.02, String isoExpr = ''}) {
  return Segment(
    id: 'seg-$seqNo',
    projectId: 'p',
    seqNo: seqNo,
    diameterMm: diameterMm,
    wallThicknessMm: wallMm,
    startKind: 'logical',
    startLibraryId: null,
    startValueMm: 0,
    endKind: 'logical',
    endLibraryId: null,
    endValueMm: 0,
    isoRef: 'FACE',
    isoExpr: isoExpr,
    isoMm: cutMm,
    cutMm: cutMm,
    createdAt: 0,
    updatedAt: 0,
  );
}

CutListSummary _summary(List<Segment> segs) =>
    summarizeCutList(segments: segs, stockLengthMm: 6000, sawKerfMm: 3);

void main() {
  test('segmentLabel: S + numer segmentu, min. dwie cyfry', () {
    expect(segmentLabel(_seg(3, 1)), 'S03');
    expect(segmentLabel(_seg(12, 1)), 'S12');
    expect(segmentLabel(_seg(123, 1)), 'S123');
  });

  test('sztuki na sztangach mają etykiety segmentów i odniesienie ISO', () {
    final s = _summary([
      _seg(1, 3293, isoExpr: '3000+525-80'),
      _seg(2, 2500, isoExpr: '2500'),
      _seg(3, 1200),
    ]);
    final plans = s.groups.single.plans;
    expect(plans.map((p) => p.pieces.map((x) => x.tag).toList()), [
      ['S01', 'S02'],
      ['S03'],
    ]);
    expect(plans[0].pieces[0].reference, '3000+525-80');
    expect(plans[0].pieces[1].reference, '2500');
    // Puste wyrażenie ISO nie udaje odniesienia.
    expect(plans[1].pieces[0].reference, isNull);
    expect(s.groups.single.pieces.map((p) => p.label), ['S01', 'S02', 'S03']);
    expect(s.splitCuts, isEmpty);
  });

  test('formatBarPieces: „S01: 3293 + S02: 2500”', () {
    final s = _summary([_seg(1, 3293), _seg(2, 2500), _seg(3, 1200)]);
    expect(formatBarPieces(s.groups.single.plans[0]), 'S01: 3293 + S02: 2500');
    expect(formatBarPieces(s.groups.single.plans[1]), 'S03: 1200');
  });

  test('barsByLabel: numery sztang (w grupie), na których leży segment', () {
    final s = _summary([_seg(1, 7000), _seg(2, 4000)]);
    expect(s.groups.single.barsByLabel, {
      'S01': [1, 2],
      'S02': [2],
    });
  });

  group('cięcie dłuższe niż sztanga', () {
    test('7000 mm: dwie części i jedna dodatkowa spoina', () {
      final s = _summary([_seg(1, 7000), _seg(2, 4000)]);
      final plans = s.groups.single.plans;
      expect(plans.map((p) => p.pieces.map((x) => x.tag).toList()), [
        ['S01 (1/2)'],
        ['S02', 'S01 (2/2)'],
      ]);
      expect(plans[1].remainingMm, closeTo(994, 1e-9));

      expect(s.splitCuts, hasLength(1));
      final split = s.splitCuts.single;
      expect(split.label, 'S01');
      expect(split.partCount, 2);
      expect(split.sourceLengthMm, 7000);

      expect(
        oversizeCutWarning(split, stockLengthMm: 6000, english: false),
        'S01: odcinek 7000 mm dłuższy niż sztanga 6000 mm — dzielony na '
        '2 części: 6000 + 1000 mm; dodatkowa spoina łącząca (gap projektu 0 mm — '
        'nic nie odjęto).',
      );
      expect(
        oversizeCutWarning(split, stockLengthMm: 6000, english: true),
        'S01: piece 7000 mm is longer than the 6000 mm stock bar — split into '
        '2 parts: 6000 + 1000 mm; an extra joining weld (project gap 0 mm — '
        'nothing taken off).',
      );
      expect(
        oversizeCutWarning(split,
            stockLengthMm: 6000, english: false, withLabel: false),
        'odcinek 7000 mm dłuższy niż sztanga 6000 mm — dzielony na 2 części: '
        '6000 + 1000 mm; dodatkowa spoina łącząca (gap projektu 0 mm — nic nie '
        'odjęto).',
      );
    });

    test('14000 mm: trzy części, dwie spoiny (odmiana PL i EN)', () {
      final s = _summary([_seg(4, 14000)]);
      final split = s.splitCuts.single;
      expect(split.partCount, 3);
      expect(
        oversizeCutWarning(split, stockLengthMm: 6000, english: false),
        'S04: odcinek 14000 mm dłuższy niż sztanga 6000 mm — dzielony na '
        '3 części: 6000 + 6000 + 2000 mm; 2 dodatkowe spoiny łączące (gap '
        'projektu 0 mm — nic nie odjęto).',
      );
      expect(
        oversizeCutWarning(split, stockLengthMm: 6000, english: true),
        'S04: piece 14000 mm is longer than the 6000 mm stock bar — split into '
        '3 parts: 6000 + 6000 + 2000 mm; 2 extra joining welds (project gap '
        '0 mm — nothing taken off).',
      );
    });

    test('sześć części: pięć dodatkowych spoin (dopełniacz)', () {
      final s = _summary([_seg(5, 35000)]);
      expect(
        oversizeCutWarning(s.splitCuts.single,
            stockLengthMm: 6000, english: false),
        'S05: odcinek 35000 mm dłuższy niż sztanga 6000 mm — dzielony na '
        '6 części: 6000 + 6000 + 6000 + 6000 + 6000 + 5000 mm; 5 dodatkowych '
        'spoin łączących (gap projektu 0 mm — nic nie odjęto).',
      );
    });
  });

  group('buildCutListText (udostępnianie jako tekst)', () {
    test('PL: sztangi z etykietami segmentów', () {
      final s = _summary([_seg(1, 3293), _seg(2, 2500), _seg(3, 1200)]);
      expect(
        buildCutListText(
          projectName: 'Linia DN100',
          materialGroup: 'CS',
          stockLengthMm: 6000,
          sawKerfMm: 3,
          summary: s,
          english: false,
        ),
        'CUT LIST — Linia DN100\n'
        'Materiał: CS  Sztanga: 6000 mm  Rzaz: 3.0 mm\n'
        '\n'
        'Ø114.3 × 6.02:\n'
        '  Sztanga 1: S01: 3293 + S02: 2500  (zostaje 201 mm)\n'
        '  Sztanga 2: S03: 1200  (zostaje 4797 mm)\n',
      );
    });

    test('EN z ostrzeżeniem o podzielonym cięciu', () {
      final s = _summary([_seg(1, 7000), _seg(2, 4000)]);
      expect(
        buildCutListText(
          projectName: 'Line 7',
          materialGroup: 'SS',
          stockLengthMm: 6000,
          sawKerfMm: 3,
          summary: s,
          english: true,
        ),
        'CUT LIST — Line 7\n'
        'Material: SS  Stock: 6000 mm  Kerf: 3.0 mm\n'
        '\n'
        'WARNING: S01: piece 7000 mm is longer than the 6000 mm stock bar — '
        'split into 2 parts: 6000 + 1000 mm; an extra joining weld (project gap '
        '0 mm — nothing taken off).\n'
        '\n'
        'Ø114.3 × 6.02:\n'
        '  Bar 1: S01 (1/2): 6000  (remaining 0 mm)\n'
        '  Bar 2: S02: 4000 + S01 (2/2): 1000  (remaining 994 mm)\n',
      );
    });

    test('v22: linia / ISO pod tytułem, oznaczenie sztuki obok S01', () {
      final marked = Segment(
        id: 'seg-1',
        projectId: 'p',
        seqNo: 1,
        diameterMm: 114.3,
        wallThicknessMm: 6.02,
        startKind: 'logical',
        startLibraryId: null,
        startValueMm: 0,
        endKind: 'logical',
        endLibraryId: null,
        endValueMm: 0,
        isoRef: 'FACE',
        isoExpr: '',
        isoMm: 3293,
        cutMm: 3293,
        createdAt: 0,
        updatedAt: 0,
        label: 'SP02-03',
      );
      final s = _summary([marked, _seg(2, 2500)]);
      expect(s.groups.single.barsByLabel.keys, ['S01 SP02-03', 'S02']);
      expect(
        buildCutListText(
          projectName: 'Linia DN100',
          materialGroup: 'CS',
          stockLengthMm: 6000,
          sawKerfMm: 3,
          summary: s,
          english: false,
          identity: const ProjectIdentity(
              lineNo: 'DN100-CWS-1234', isoNo: 'ISO-7', isoRev: 'B'),
        ),
        'CUT LIST — Linia DN100\n'
        'Linia: DN100-CWS-1234 · ISO: ISO-7 rew. B\n'
        'Materiał: CS  Sztanga: 6000 mm  Rzaz: 3.0 mm\n'
        '\n'
        'Ø114.3 × 6.02:\n'
        '  Sztanga 1: S01 SP02-03: 3293 + S02: 2500  (zostaje 201 mm)\n',
      );
    });
  });
}
