// „Tolerancje spoola” — ocena pozycji i protokołu: tolerancje PFI ES-3
// (pasma DN, obrót otworów, wyrównanie czoła), zestawy wpisywane
// (EN 13480-4, projekt), granica włącznie, brak danych = brak werdyktu,
// kumulacja w protokole, kalkulatory, JSON i „następny spool”.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/spool_check/spool_check.dart';

SpoolCheck _check({
  int? dn = 150,
  SpoolToleranceSet? set = SpoolToleranceSet.pfiEs3,
  SpoolUnit unit = SpoolUnit.mm,
  List<SpoolItem> items = const [],
}) =>
    SpoolCheck(
      id: 'c1',
      spoolNo: '100-P-1203-S02',
      date: '2026-10-18',
      dn: dn,
      unit: unit,
      toleranceSet: set,
      items: items,
    );

SpoolItem _ff(double? drawing, double? measured,
        {String id = 'i1', int? dn, double? tol}) =>
    SpoolItem(
      id: id,
      kind: SpoolItemKind.faceToFace,
      drawingMm: drawing,
      measuredMm: measured,
      dn: dn,
      toleranceMm: tol,
    );

SpoolItemResult _one(SpoolCheck c) => c.evaluate().items.single;

void main() {
  test('ES-3 długości: DN150 ±3 mm (ostrzejsza z 1/8″ i 3,0 mm) — 3,0 mm '
      'w tolerancji, 3,001 mm poza', () {
    final ok = _one(_check(items: [_ff(1250, 1253)]));
    expect(ok.tolerance.mm, 3.0);
    expect(ok.tolerance.basis, SpoolToleranceBasis.es3Linear);
    expect(ok.deviationMm, 3.0);
    expect(ok.signedDeviationMm, 3.0);
    expect(ok.verdict, SpoolVerdict.ok);

    final short = _one(_check(items: [_ff(1250, 1247)]));
    expect(short.signedDeviationMm, -3.0);
    expect(short.verdict, SpoolVerdict.ok);

    expect(_one(_check(items: [_ff(1250, 1253.001)])).verdict,
        SpoolVerdict.out);
    expect(_one(_check(items: [_ff(1250, 1253.5)])).verdict, SpoolVerdict.out);
  });

  test('ES-3 pasma: DN300–600 ±4,7625 mm (3/16″ ostrzejsze od 5,0 mm), '
      'DN650–900 ±6 mm (6,0 ostrzejsze od 1/4″), DN pośrednie do niższego '
      'pasma', () {
    expect(es3LinearBandFor(250)!.mm, 3.0);
    expect(es3LinearBandFor(275)!.mm, 3.0);
    expect(es3LinearBandFor(300)!.mm, 4.7625);
    expect(es3LinearBandFor(600)!.mm, 4.7625);
    expect(es3LinearBandFor(625)!.mm, 4.7625);
    expect(es3LinearBandFor(650)!.mm, 6.0);
    expect(es3LinearBandFor(900)!.mm, 6.0);
    expect(es3LinearBandFor(950), isNull);
    // DN pozycji zastępuje DN spoola.
    final r = _one(_check(dn: 150, items: [_ff(2000, 2004.5, dn: 400)]));
    expect(r.tolerance.mm, 4.7625);
    expect(r.tolerance.dn, 400);
    expect(r.verdict, SpoolVerdict.ok);
    expect(_one(_check(dn: 400, items: [_ff(2000, 2004.8)])).verdict,
        SpoolVerdict.out);
  });

  test('ES-3 bez DN albo powyżej DN 900 — brak werdyktu, nie OK', () {
    final noDn = _one(_check(dn: null, items: [_ff(1250, 1250)]));
    expect(noDn.verdict, SpoolVerdict.none);
    expect(noDn.gaps, [SpoolGap.noDn]);
    final big = _one(_check(dn: 1000, items: [_ff(1250, 1250)]));
    expect(big.verdict, SpoolVerdict.none);
    expect(big.gaps, [SpoolGap.dnBeyondEs3]);
    // Tolerancja z rysunku przy pozycji daje werdykt także dla DN 1000.
    final own = _one(_check(dn: 1000, items: [_ff(1250, 1254, tol: 5)]));
    expect(own.verdict, SpoolVerdict.ok);
    expect(own.tolerance.basis, SpoolToleranceBasis.drawing);
  });

  test('cale: odchyłka dokładnie 1/8″ wobec tolerancji z rysunku 1/8″ — na '
      'granicy, w tolerancji; o 1/64″ więcej — poza', () {
    final tol = spoolToleranceToMm(1 / 8, SpoolUnit.inch);
    final drawing = parseSpoolLength('98 1/2', SpoolUnit.inch)!;
    final at = parseSpoolLength('98 5/8', SpoolUnit.inch)!;
    final over = parseSpoolLength('98 41/64', SpoolUnit.inch)!;
    final c = _check(unit: SpoolUnit.inch, items: [
      _ff(drawing, at, id: 'a', tol: tol),
      _ff(drawing, over, id: 'b', tol: tol),
    ]);
    final r = c.evaluate().items;
    expect(r[0].deviationMm, 3.175);
    expect(r[0].verdict, SpoolVerdict.ok);
    expect(r[1].verdict, SpoolVerdict.out);
    // Wobec ES-3 (3,0 mm — ostrzejsze od 1/8″) ta sama odchyłka jest poza.
    final es3 = _one(_check(unit: SpoolUnit.inch, items: [_ff(drawing, at)]));
    expect(es3.tolerance.mm, 3.0);
    expect(es3.verdict, SpoolVerdict.out);
  });

  test('werdykt niezależny od jednostki wyświetlania (mm ↔ cale)', () {
    final items = [
      _ff(1250, 1253, id: 'a'),
      _ff(1250, 1253.5, id: 'b'),
      const SpoolItem(
          id: 'c', kind: SpoolItemKind.faceTilt, measuredMm: 1.1, baseMm: 300),
      const SpoolItem(
          id: 'd', kind: SpoolItemKind.boltRotation, measuredMm: 1.6),
    ];
    final mm = _check(unit: SpoolUnit.mm, items: items).evaluate();
    final inch = _check(unit: SpoolUnit.inch, items: items).evaluate();
    expect([for (final r in inch.items) r.verdict],
        [for (final r in mm.items) r.verdict]);
    expect([for (final r in inch.items) r.deviationMm],
        [for (final r in mm.items) r.deviationMm]);
    expect([for (final r in inch.items) r.tolerance.mm],
        [for (final r in mm.items) r.tolerance.mm]);
    expect(inch.overall, mm.overall);
    expect(mm.overall, SpoolOverall.out);
    // Zmiana jednostki nie zmienia zapisanych wartości.
    final c = _check(items: items);
    final switched = c.copyWith(unit: SpoolUnit.inch);
    expect(jsonEncode(switched.items.map((i) => i.toJson()).toList()),
        jsonEncode(c.items.map((i) => i.toJson()).toList()));
  });

  test('ES-3 skręt otworów: 1/16″ = 1,5875 mm na granicy; kąt na średnicy '
      'podziałowej → przesunięcie po obwodzie', () {
    SpoolItem rot(String id, double? mm) =>
        SpoolItem(id: id, kind: SpoolItemKind.boltRotation, measuredMm: mm);
    final r = _check(items: [rot('a', 1.5875), rot('b', 1.6)]).evaluate();
    expect(r.items[0].tolerance.mm, 1.5875);
    expect(r.items[0].verdict, SpoolVerdict.ok);
    expect(r.items[1].verdict, SpoolVerdict.out);

    // 0,5° na PCD 241,3 mm (DN150 CL150) → π·241,3·0,5/360 = 1,0529 mm.
    expect(boltArcFromAngle(0.5, 241.3), 1.053);
    expect(boltAngleFromArc(1.053, 241.3), closeTo(0.5, 0.001));
    final byAngle = _one(_check(items: [
      const SpoolItem(
          id: 'x',
          kind: SpoolItemKind.boltRotation,
          rotationByAngle: true,
          angleDeg: 0.5,
          baseMm: 241.3),
    ]));
    expect(byAngle.deviationMm, 1.053);
    expect(byAngle.verdict, SpoolVerdict.ok);
    // Kąt bez średnicy podziałowej — brak werdyktu.
    final noPcd = _one(_check(items: [
      const SpoolItem(
          id: 'y',
          kind: SpoolItemKind.boltRotation,
          rotationByAngle: true,
          angleDeg: 0.5),
    ]));
    expect(noPcd.verdict, SpoolVerdict.none);
    expect(noPcd.gaps, contains(SpoolGap.noPcd));
  });

  test('ES-3 nachylenie czoła: 3/64″ na stopę lub 1/32″ — co większe; brak '
      'średnicy → brak werdyktu', () {
    // Ø 150 mm: 3/64″/stopę × 150 = 0,586 mm < 1/32″ → 0,79375 mm.
    expect(es3FaceAlignmentLimitMm(150), 0.79375);
    // Ø 300 mm: 0,00390625 × 300 = 1,171875 mm.
    expect(es3FaceAlignmentLimitMm(300), 1.171875);
    // Ø 12″ = 304,8 mm → dokładnie 3/64″.
    expect(es3FaceAlignmentLimitMm(304.8), spoolToleranceFromInch(3 / 64));
    SpoolItem tilt(String id, double dev, double? d) => SpoolItem(
        id: id, kind: SpoolItemKind.faceTilt, measuredMm: dev, baseMm: d);
    final r = _check(items: [
      tilt('a', 0.79375, 150),
      tilt('b', 0.8, 150),
      tilt('c', 1.171875, 300),
      tilt('d', 0.5, null),
    ]).evaluate();
    expect(r.items[0].verdict, SpoolVerdict.ok);
    expect(r.items[1].verdict, SpoolVerdict.out);
    expect(r.items[2].verdict, SpoolVerdict.ok);
    expect(r.items[3].verdict, SpoolVerdict.none);
    expect(r.items[3].gaps, [SpoolGap.noDiameter]);
  });

  test('kalkulator nachylenia: szczeliny 0,9 i 0,3 mm na Ø 300 → 0,6 mm, '
      '0,115°, 2 mm/m; przeliczenie na inną średnicę w górę', () {
    final t = faceTiltFromGaps(0.9, 0.3, 300)!;
    expect(t.deviationMm, 0.6);
    expect(t.angleDeg, closeTo(0.11459, 0.00001));
    expect(t.mmPerM, closeTo(2.0, 1e-9));
    expect(faceTiltFromGaps(0.9, null, 300), isNull);
    expect(faceTiltFromGaps(0.9, 0.3, 0), isNull);
    // 0,6 mm na Ø 300 → na Ø 350: 0,7 mm.
    expect(spoolScaleDeviation(0.6, 300, 350), 0.7);
    expect(spoolScaleDeviation(0.6, 300, 333), 0.666);
    expect(spoolScaleDeviation(0.6, 300, 334), 0.668);
  });

  test('ES-3 nie podaje przesunięcia bocznego i prostoliniowości — brak '
      'werdyktu bez tolerancji z projektu', () {
    final r = _check(items: [
      const SpoolItem(
          id: 'a', kind: SpoolItemKind.branchOffset, measuredMm: 0.5),
      const SpoolItem(
          id: 'b', kind: SpoolItemKind.straightness, measuredMm: 2),
      const SpoolItem(
          id: 'c',
          kind: SpoolItemKind.straightness,
          measuredMm: 2,
          baseMm: 6000,
          toleranceMm: 3),
    ]).evaluate();
    expect(r.items[0].verdict, SpoolVerdict.none);
    expect(r.items[0].gaps, [SpoolGap.notInEs3]);
    expect(r.items[1].verdict, SpoolVerdict.none);
    expect(r.items[2].verdict, SpoolVerdict.ok);
    expect(r.items[2].tolerance.basis, SpoolToleranceBasis.drawing);
  });

  test('EN 13480-4 i „z projektu”: bez wpisanej tolerancji brak werdyktu; '
      'z wpisaną — werdykt i podstawa oceny', () {
    for (final set in [SpoolToleranceSet.en13480, SpoolToleranceSet.project]) {
      final none = _one(_check(set: set, items: [_ff(1250, 1250)]));
      expect(none.verdict, SpoolVerdict.none, reason: set.name);
      expect(none.gaps, [SpoolGap.noTolerance], reason: set.name);
      final r = _check(set: set, items: [
        _ff(1250, 1252, id: 'a', tol: 2),
        _ff(1250, 1252.5, id: 'b', tol: 2),
      ]).evaluate();
      expect(r.items[0].verdict, SpoolVerdict.ok, reason: set.name);
      expect(r.items[1].verdict, SpoolVerdict.out, reason: set.name);
      expect(
          r.items[0].tolerance.basis,
          set == SpoolToleranceSet.en13480
              ? SpoolToleranceBasis.en13480
              : SpoolToleranceBasis.project);
    }
  });

  test('brak wymiaru z rysunku albo pomiaru — brak werdyktu, nie OK', () {
    final noDrawing = _one(_check(items: [_ff(null, 1250)]));
    expect(noDrawing.verdict, SpoolVerdict.none);
    expect(noDrawing.gaps, [SpoolGap.noDrawing]);
    final noMeasured = _one(_check(items: [_ff(1250, null)]));
    expect(noMeasured.verdict, SpoolVerdict.none);
    expect(noMeasured.gaps, [SpoolGap.noMeasured]);
    expect(noMeasured.deviationMm, isNull);
    final noDev = _one(_check(items: [
      const SpoolItem(id: 'r', kind: SpoolItemKind.boltRotation),
    ]));
    expect(noDev.verdict, SpoolVerdict.none);
    expect(noDev.gaps, [SpoolGap.noMeasured]);
  });

  test('kumulacja: spool OK tylko, gdy wszystkie pozycje mają werdykt i są '
      'w tolerancji; jedna poza — spool poza', () {
    final allOk = _check(items: [
      _ff(1250, 1252, id: 'a'),
      _ff(800, 799, id: 'b'),
      const SpoolItem(
          id: 'c', kind: SpoolItemKind.boltRotation, measuredMm: 1),
    ]).evaluate();
    expect(allOk.overall, SpoolOverall.ok);
    expect(allOk.count(SpoolVerdict.ok), 3);

    final oneMissing = _check(items: [
      _ff(1250, 1252, id: 'a'),
      _ff(800, null, id: 'b'),
    ]).evaluate();
    expect(oneMissing.overall, SpoolOverall.incomplete);

    final oneOut = _check(items: [
      _ff(1250, 1252, id: 'a'),
      _ff(800, null, id: 'b'),
      _ff(600, 605, id: 'c'),
    ]).evaluate();
    expect(oneOut.overall, SpoolOverall.out);
    expect(oneOut.count(SpoolVerdict.out), 1);
  });

  test('pusty protokół — brak pozycji, nie OK; pusty nie jest zapisywany', () {
    final c = SpoolCheck.blank(id: 'n', now: DateTime(2026, 10, 18, 9));
    expect(c.evaluate().overall, SpoolOverall.empty);
    expect(c.isBlank, isTrue);
    expect(c.date, '2026-10-18');
    expect(c.toleranceSet, SpoolToleranceSet.pfiEs3);
    expect(c.copyWith(spoolNo: 'S1').isBlank, isFalse);
  });

  test('własna tolerancja poza zakresem (0 albo ponad 50 mm) — brak werdyktu',
      () {
    expect(spoolToleranceValid(0), isFalse);
    expect(spoolToleranceValid(50), isTrue);
    expect(spoolToleranceValid(50.1), isFalse);
    final r = _one(_check(items: [_ff(1250, 1250, tol: 60)]));
    expect(r.verdict, SpoolVerdict.none);
    expect(r.gaps, [SpoolGap.toleranceInvalid]);
  });

  test('JSON: zapis i odczyt bez strat', () {
    final c = _check(set: SpoolToleranceSet.en13480, items: [
      _ff(1250, 1252.5, id: 'a', dn: 200, tol: 2),
      const SpoolItem(
          id: 'b',
          kind: SpoolItemKind.boltRotation,
          rotationByAngle: true,
          angleDeg: 0.25,
          baseMm: 241.3,
          label: 'F2',
          note: 'po obróceniu'),
    ]).copyWith(
        isoNo: 'ISO-1203',
        drawingNo: 'D-77',
        revision: 'C',
        inspector: 'J. Kowalski',
        enGrade: '2',
        notes: 'uwagi');
    final raw = jsonDecode(jsonEncode(spoolChecksToJson([c])));
    final parsed = spoolChecksParse(raw);
    expect(parsed.damaged, isFalse);
    final back = parsed.checks.single;
    expect(jsonEncode(back.toJson()), jsonEncode(c.toJson()));
    expect(back.items[1].rotationByAngle, isTrue);
    expect(back.enGrade, '2');
  });

  test('JSON: nieczytelna tolerancja nie jest zastępowana normą — brak '
      'werdyktu i znacznik uszkodzenia', () {
    final json = _check(items: [_ff(1250, 1251, tol: 2)]).toJson();
    ((json['items'] as List).single as Map)['tolMm'] = 'dwa';
    final parsed = spoolChecksParse([json]);
    expect(parsed.damaged, isTrue);
    final c = parsed.checks.single;
    expect(c.damagedOnLoad, 1);
    final r = _one(c);
    expect(r.item.toleranceDamaged, isTrue);
    expect(r.verdict, SpoolVerdict.none);
    expect(r.gaps, [SpoolGap.toleranceDamaged]);
    // Znacznik przeżywa zapis — dopóki monter nie wpisze tolerancji.
    final again = SpoolCheck.fromJson(jsonDecode(jsonEncode(c.toJson())))!;
    expect(again.items.single.toleranceDamaged, isTrue);
    expect(again.damagedOnLoad, 0);
    final fixed = c.items.single.copyWith(toleranceMm: 2.5);
    expect(fixed.toleranceDamaged, isFalse);
    expect(_one(c.withItem(fixed)).verdict, SpoolVerdict.ok);
  });

  test('JSON: nieznany rodzaj pozycji i wpis bez id pominięte i policzone; '
      'nieczytelny zestaw → brak werdyktu', () {
    final good = _check(items: [_ff(1250, 1251)]).toJson();
    final badKind = {
      ...good,
      'id': 'c2',
      'items': [
        {'id': 'x', 'kind': 'kolano'},
        _ff(1250, 1251, id: 'y').toJson(),
      ],
    };
    final badSet = {...good, 'id': 'c3', 'set': 'ISO'};
    final parsed = spoolChecksParse([good, badKind, badSet, {'date': 'x'}]);
    expect(parsed.droppedChecks, 1);
    expect(parsed.damagedEntries, 2);
    expect(parsed.checks.map((c) => c.id), ['c1', 'c2', 'c3']);
    expect(parsed.checks[1].items.single.id, 'y');
    final unreadable = parsed.checks[2];
    expect(unreadable.toleranceSet, isNull);
    expect(_one(unreadable).verdict, SpoolVerdict.none);
    expect(_one(unreadable).gaps, contains(SpoolGap.setUnreadable));
    expect(() => spoolChecksParse({'not': 'a list'}), throwsFormatException);
  });

  test('następny spool z serii: wymiary z rysunku i tolerancje zostają, '
      'pomiary nie; numer +1', () {
    final c = _check(set: SpoolToleranceSet.project, items: [
      _ff(1250, 1252, id: 'a', tol: 2),
      const SpoolItem(
          id: 'b',
          kind: SpoolItemKind.faceTilt,
          measuredMm: 0.4,
          baseMm: 300,
          toleranceMm: 1),
    ]).copyWith(inspector: 'J. Kowalski', notes: 'stare uwagi');
    var n = 0;
    final d = c.duplicateFor(
        newId: 'c9', now: DateTime(2026, 10, 19), itemId: (_) => 'n${n++}');
    expect(d.id, 'c9');
    expect(d.spoolNo, '100-P-1203-S03');
    expect(d.date, '2026-10-19');
    expect(d.inspector, 'J. Kowalski');
    expect(d.toleranceSet, SpoolToleranceSet.project);
    expect(d.notes, isEmpty);
    expect(d.items.map((i) => i.id), ['n0', 'n1']);
    expect(d.items[0].drawingMm, 1250);
    expect(d.items[0].toleranceMm, 2);
    expect(d.items.map((i) => i.measuredMm), everyElement(isNull));
    expect(d.items[1].baseMm, 300);
    expect(d.evaluate().overall, SpoolOverall.incomplete);
  });
}
