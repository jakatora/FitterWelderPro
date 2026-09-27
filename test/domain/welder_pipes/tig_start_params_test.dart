// Rury → AMP / Startowe / Wolfram: jedno źródło prądu, elektrody i gazu.
//
// Liczby ręcznie (seed `approved_weld_params` w lib/database/db.dart):
//  • SS bez drutu Ø60 × 2,0 → 80 A (seed), więc Ø60,3 × 2,0 (OD ±2 %) → 80 A;
//    dawniej kalkulator AMP dawał 50 A.
//  • SS z drutem Ø60 × 3,0 → 110 A; CS z drutem Ø60 × 3,0 → 120 A.
//  • SS z drutem Ø60,3 × 2,0 → 60 A (seed APPROVED_PIPE_TIGWIRE_60_2).
//  • SS z drutem Ø88,9 × 2,0: ścianka 2,0 ma dane tylko do Ø60,3, więc
//    z najbliższej ścianki 3,0 proporcjonalnie × 2/3 — „scaledByWall”.
//  • CS: gdy własne punkty dają mniej niż SS tej samej rury (sprzeczne
//    seedy) albo tylko skalowanie po ściance → SS / 0,9.
//  • SS bez drutu Ø45 × 2,0: seed 73 A (ssAutogen); Ø42,5 × 2,0 między
//    Ø40 (70 A) a Ø45 (73 A): 70 + 3·(2,5/5) = 71,5 A.
//  • CS bez drutu nie ma punktów → nierdzewna / 0,9 (SS ≈ 10 % mniej prądu,
//    mig-welding.co.uk): Ø60 × 2,0 → 80/0,9 = 88,9 A.
//  • Elektroda: pasma DC− z lib/data/tungsten.dart; 70–80 A (zakładka
//    1,0/1,6) → 1,6 mm. Gaz palnika: 1,6 mm → 8–10 L/min, 2,4 → 10–12.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/tungsten.dart';
import 'package:cut_list_app/database/approved_weld_param_dao.dart';
import 'package:cut_list_app/domain/welder_pipes/tig_start_params.dart';

import '../../support/test_database.dart';

void main() {
  useTestDatabase();

  late List<PipeStartPoint> pts;
  setUpAll(() async {
    pts = [
      for (final p in await ApprovedWeldParamDao().listAll())
        PipeStartPoint(
          material: p.baseMaterial,
          method: p.method,
          odMm: p.diameterMm,
          wallMm: p.wallThicknessMm,
          amps: p.amps,
        ),
    ];
  });

  double? amps(String mat, String method, double od, double t) =>
      pipeStartCurrent(
              points: pts, material: mat, method: method, odMm: od, wallMm: t)
          .amps;

  test('ta sama rura: kalkulator = lista „Startowe” (każdy punkt)', () {
    expect(pts, isNotEmpty);
    for (final p in pts) {
      final r = pipeStartCurrent(
          points: pts,
          material: p.material,
          method: p.method,
          odMm: p.odMm,
          wallMm: p.wallMm);
      expect(r.source, PipeCurrentSource.exact,
          reason: '${p.material} ${p.method} ${p.odMm}×${p.wallMm}');
      // Duplikaty tej samej rury w seedzie (np. ssWire 219×3 i starsze wpisy)
      // mają ten sam prąd albo kalkulator bierze pierwszy — sprawdzamy, że
      // wynik jest jednym z prądów tej rury.
      final same = pts
          .where((q) =>
              q.material == p.material &&
              q.method == p.method &&
              (q.odMm - p.odMm).abs() < 1e-9 &&
              (q.wallMm - p.wallMm).abs() < 1e-9)
          .map((q) => q.amps);
      expect(same, contains(r.amps));
    }
  });

  test('liczby z komentarza', () {
    expect(amps('SS', 'TIG_AUTOGEN', 60.3, 2.0), 80);
    expect(amps('SS', 'TIG_WIRE', 60.3, 3.0), 110);
    expect(amps('CS', 'TIG_WIRE', 60.3, 3.0), 120);
    expect(amps('SS', 'TIG_WIRE', 60.3, 2.0), 60);
    final scaled = pipeStartCurrent(
        points: pts,
        material: 'SS',
        method: 'TIG_WIRE',
        odMm: 88.9,
        wallMm: 2.0);
    expect(scaled.source, PipeCurrentSource.scaledByWall);
    // Ścianka 3,0 przy Ø88,9: między Ø80 (120 A) a Ø219 (130 A):
    // 120 + 10·8,9/139 = 120,640 A → × 2/3 = 80,427 A.
    expect(scaled.amps, closeTo((120 + 10 * 8.9 / 139) * 2 / 3, 1e-9));
    expect(amps('SS', 'TIG_AUTOGEN', 42.5, 2.0), closeTo(71.5, 1e-9));
    final cs = pipeStartCurrent(
        points: pts,
        material: 'CS',
        method: 'TIG_AUTOGEN',
        odMm: 60.3,
        wallMm: 2.0);
    expect(cs.source, PipeCurrentSource.fromStainless);
    expect(cs.amps, closeTo(80 / 0.9, 1e-9));
  });

  // Zakres kalkulatora AMP: ręczny TIG jednoprzejściowy, t ≤ 3 mm.
  test('CS nigdy nie dostaje mniej prądu niż SS (ta sama rura i metoda)', () {
    const ods = [21.3, 26.9, 33.7, 42.4, 48.3, 60.3, 76.1, 88.9, 114.3, 168.3];
    const walls = [1.5, 2.0, 2.5, 3.0];
    var compared = 0;
    for (final method in ['TIG_WIRE', 'TIG_AUTOGEN']) {
      for (final od in ods) {
        for (final t in walls) {
          final ss = amps('SS', method, od, t);
          final cs = amps('CS', method, od, t);
          if (ss == null || cs == null) continue;
          compared++;
          expect(cs, greaterThanOrEqualTo(ss), reason: '$method Ø$od × $t');
        }
      }
    }
    expect(compared, greaterThan(20));
  });

  test('poza danymi: brak liczby', () {
    expect(amps('SS', 'TIG_AUTOGEN', 1000, 2.0), isNull);
    expect(amps('DUPLEX', 'TIG_WIRE', 60.3, 2.0), isNull,
        reason: 'brak punktów Duplex z drutem');
    expect(amps('SS', 'TIG_WIRE', 60.3, 0), isNull);
  });

  test('elektroda i gaz: te same tabele co ekran Wolfram', () {
    for (final a in [20.0, 45.0, 75.0, 80.0, 110.0, 150.0, 200.0, 300.0]) {
      final e = pipeElectrodeMm(a);
      expect(e, sizeForCurrent(a)!.diaMm, reason: '$a A');
      final g = pipeTorchGasLpm(e);
      final x = tungstenExtrasFor(e)!;
      expect((g.min, g.max), (x.argonMinLpm, x.argonMaxLpm), reason: '$a A');
    }
    expect(pipeElectrodeMm(75), 1.6, reason: 'zakładka 70–80 A → większa');
    expect(pipeTorchGasLpm(1.6), (min: 8, max: 10));
    expect(pipeTorchGasLpm(2.4), (min: 10, max: 12));
  });
}
