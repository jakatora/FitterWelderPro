// Ciężar stali: tabele kształtowników (wartości ze źródeł na sztywno +
// spójność z geometrią przekroju), masy z geometrii, lista materiałowa,
// koszt w groszach, zapas %.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/quotes/quote_calculator.dart';
import 'package:cut_list_app/domain/steel_weight/steel_order_text.dart';
import 'package:cut_list_app/domain/steel_weight/steel_sections.dart';
import 'package:cut_list_app/domain/steel_weight/steel_weight.dart';

SteelSection _s(SteelShape shape, String name) {
  final s = sectionByName(shape, name);
  expect(s, isNotNull, reason: name);
  return s!;
}

/// Pole dwuteownika z wymiarów: 2 stopki + środnik + 4 wyokrąglenia [mm²].
double _iArea(SteelSection s) =>
    2 * s.b * s.tf + (s.h - 2 * s.tf) * s.tw + (4 - math.pi) * s.r1 * s.r1;

/// Ceownik (półki równoległe): 2 stopki + środnik + 2 wyokrąglenia [mm²].
double _channelArea(SteelSection s) =>
    2 * s.b * s.tf + (s.h - 2 * s.tf) * s.tw + (2 - math.pi / 2) * s.r1 * s.r1;

/// Kątownik wg EN 10056-1: t(a + b − t) + (1 − π/4)(r1² − 2 r2²) [mm²].
double _angleArea(SteelSection s) =>
    s.t * (s.h + s.b - s.t) +
    (1 - math.pi / 4) * (s.r1 * s.r1 - 2 * s.r2! * s.r2!);

void main() {
  group('tabele — wartości ze źródeł (kg/m)', () {
    // Wartości przepisane z tablic (EN 10365 / EN 10056-1); patrz komentarze
    // źródeł w steel_sections.dart.
    for (final (shape, name, kg, paint) in const [
      (SteelShape.ipe, 'IPE 80', 6.0, 0.328),
      (SteelShape.ipe, 'IPE 200', 22.4, 0.768),
      (SteelShape.ipe, 'IPE 300', 42.2, 1.160),
      (SteelShape.ipe, 'IPE 600', 122.4, 2.015),
      (SteelShape.hea, 'HEA 200', 42.3, 1.136),
      (SteelShape.hea, 'HEA 1000', 272.3, 3.095),
      (SteelShape.heb, 'HEB 100', 20.4, 0.567),
      (SteelShape.heb, 'HEB 200', 61.3, 1.151),
      (SteelShape.heb, 'HEB 300', 117.0, 1.732),
      (SteelShape.hem, 'HEM 200', 103.1, 1.203),
      (SteelShape.upn, 'UPN 100', 10.6, 0.372),
      (SteelShape.upn, 'UPN 200', 25.3, 0.661),
      (SteelShape.upn, 'UPN 400', 71.8, 1.182),
    ]) {
      test('$name: $kg kg/m, malowanie $paint m²/m', () {
        final s = _s(shape, name);
        expect(s.kgPerM, closeTo(kg, 1e-9));
        expect(s.paintM2PerM, closeTo(paint, 1e-9));
        expect(s.paintSource, PaintSource.table);
      });
    }

    test('wymiary HEB 200: h 200, b 200, tw 9, tf 15, r 18', () {
      final s = _s(SteelShape.heb, 'HEB 200');
      expect([s.h, s.b, s.tw, s.tf, s.r1], [200, 200, 9, 15, 18]);
    });

    for (final (shape, name, kg) in const [
      (SteelShape.upe, 'UPE 200', 22.8),
      (SteelShape.angleEqual, 'L 20×20×3', 0.88),
      (SteelShape.angleEqual, 'L 50×50×5', 3.77),
      (SteelShape.angleEqual, 'L 100×100×10', 15.0),
      (SteelShape.angleEqual, 'L 200×200×20', 59.9),
      (SteelShape.angleUnequal, 'L 60×40×5', 3.76),
      (SteelShape.angleUnequal, 'L 120×80×10', 15.0),
      (SteelShape.angleUnequal, 'L 200×100×10', 23.0),
    ]) {
      test('$name: $kg kg/m', () {
        expect(_s(shape, name).kgPerM, closeTo(kg, 1e-9));
      });
    }

    test('UPN 50 / 65 — źródło nie podaje powierzchni: pusto, nie zgadujemy',
        () {
      expect(_s(SteelShape.upn, 'UPN 50').paintM2PerM, isNull);
      expect(_s(SteelShape.upn, 'UPN 65').paintSource, PaintSource.none);
    });

    test('nazwy w serii są unikalne, serie niepuste i rosnące', () {
      for (final shape in SteelShape.values.where((s) => s.tabulated)) {
        final list = sectionsOf(shape);
        expect(list, isNotEmpty, reason: shape.name);
        expect(list.map((s) => s.name).toSet().length, list.length,
            reason: shape.name);
        for (final s in list) {
          expect(s.kgPerM, greaterThan(0), reason: s.name);
          expect(s.h, greaterThan(0), reason: s.name);
        }
      }
      for (final shape in [
        SteelShape.ipe,
        SteelShape.hea,
        SteelShape.heb,
        SteelShape.hem,
        SteelShape.upn,
        SteelShape.upe,
      ]) {
        final masses = sectionsOf(shape).map((s) => s.kgPerM).toList();
        for (var i = 1; i < masses.length; i++) {
          expect(masses[i], greaterThan(masses[i - 1]),
              reason: '${shape.name} wiersz $i');
        }
      }
    });
  });

  group('tabele — spójność z geometrią (wyłapuje literówki)', () {
    test('IPE / HEA / HEB / HEM: masa = A(h, b, tw, tf, r)·7850 w ±0,5 %', () {
      for (final shape in [
        SteelShape.ipe,
        SteelShape.hea,
        SteelShape.heb,
        SteelShape.hem,
      ]) {
        for (final s in sectionsOf(shape)) {
          final kg = _iArea(s) * 1e-6 * kTableDensity;
          expect(kg, closeTo(s.kgPerM, s.kgPerM * 0.005), reason: s.name);
          // Obwód z wymiarów: 2h + 4b − 2tw − 4·(2 − π/2)·r.
          final p =
              (2 * s.h + 4 * s.b - 2 * s.tw - 4 * (2 - math.pi / 2) * s.r1) /
                  1000;
          expect(p, closeTo(s.paintM2PerM!, s.paintM2PerM! * 0.01),
              reason: '${s.name} obwód');
        }
      }
    });

    test('UPE: masa = A·7850 w ±0,5 %', () {
      for (final s in kUpe) {
        final kg = _channelArea(s) * 1e-6 * kTableDensity;
        expect(kg, closeTo(s.kgPerM, s.kgPerM * 0.005), reason: s.name);
      }
    });

    test('UPN (półki zbieżne): przybliżenie półkami równoległymi w ±3 %', () {
      for (final s in kUpn) {
        final kg = _channelArea(s) * 1e-6 * kTableDensity;
        expect(kg, closeTo(s.kgPerM, s.kgPerM * 0.03), reason: s.name);
      }
    });

    test('kątowniki EN 10056-1: masa = A(a, b, t, r1, r2)·7850 w ±1 %', () {
      for (final s in [...kAngleEqual, ...kAngleUnequal]) {
        final kg = _angleArea(s) * 1e-6 * kTableDensity;
        expect(kg, closeTo(s.kgPerM, s.kgPerM * 0.01), reason: s.name);
        expect(s.r2, closeTo(s.r1 / 2, 1e-9), reason: s.name);
      }
    });

    test('powierzchnia kątownika L 50×50×5 z geometrii ≈ 0,194 m²/m', () {
      final s = _s(SteelShape.angleEqual, 'L 50×50×5');
      expect(s.paintSource, PaintSource.geometry);
      expect(s.paintM2PerM, closeTo(0.194, 0.0005));
    });
  });

  group('profile zamknięte — wzór EN 10219-2', () {
    test('promienie naroży: 2t / 2,5t / 3t', () {
      expect(en10219Radii(4), (ro: 8.0, ri: 4.0));
      expect(en10219Radii(8), (ro: 20.0, ri: 12.0));
      expect(en10219Radii(12.5), (ro: 37.5, ri: 25.0));
    });

    // Masy z tabel EN 10219-2 (eurocodeapplied.com „Cold formed" i SCI Blue
    // Book CFSHS / CFRHS) — wzór musi je odtworzyć w ±0,5 %.
    for (final (h, b, t, kg) in const [
      (20.0, 20.0, 2.0, 1.05),
      (40.0, 40.0, 2.0, 2.31),
      (40.0, 40.0, 4.0, 4.20),
      (60.0, 60.0, 6.3, 9.55),
      (100.0, 100.0, 4.0, 11.7),
      (100.0, 100.0, 10.0, 25.6),
      (200.0, 200.0, 8.0, 46.5),
      (300.0, 300.0, 16.0, 134.1),
      (60.0, 40.0, 3.0, 4.25),
      (80.0, 40.0, 4.0, 6.71),
      (120.0, 80.0, 5.0, 14.4),
      (200.0, 100.0, 6.3, 27.4),
      (400.0, 300.0, 12.5, 127.2),
    ]) {
      test('${h.round()}×${b.round()}×$t: $kg kg/m', () {
        final item = SteelItem(
            shape: SteelShape.hollow, a: h, b: b, t: t, lengthMm: 1000);
        expect(item.kgPerM, closeTo(kg, kg * 0.005));
      });
    }

    test('obwód SHS 20×20×2 = 0,073 m (= kolumna P tabeli)', () {
      expect(hollowPerimeterMm(20, 20, 2) / 1000, closeTo(0.073, 0.0005));
    });

    test('lista wymiarów: każdy da się policzyć', () {
      expect(kHollowSizes.length, greaterThan(100));
      for (final (h, b, t) in kHollowSizes) {
        expect(hollowGeometryOk(h, b, t), isTrue, reason: '$h×$b×$t');
      }
    });

    test('za gruba ścianka — problem zamiast liczby', () {
      const item = SteelItem(
          shape: SteelShape.hollow, a: 20, b: 20, t: 8, lengthMm: 1000);
      expect(item.problem, SteelItemProblem.wallTooThick);
      expect(item.totalKg, 0);
    });
  });

  group('geometria — płaskowniki, pręty, blachy', () {
    test('płaskownik 80×10: 6,28 kg/m = 80·10 mm²·7850', () {
      const item = SteelItem(
          shape: SteelShape.flat, a: 80, t: 10, lengthMm: 6000, count: 2);
      expect(item.kgPerM, closeTo(0.080 * 0.010 * 7850, 1e-9));
      expect(item.kgPerM, closeTo(6.28, 1e-9));
      expect(item.totalKg, closeTo(6.28 * 6 * 2, 1e-9));
      expect(item.paintM2PerM, closeTo(0.18, 1e-9));
    });

    test('pręt Ø20: 2,466 kg/m; pręt kwadratowy 20: 3,14 kg/m', () {
      const round = SteelItem(shape: SteelShape.roundBar, a: 20);
      const square = SteelItem(shape: SteelShape.squareBar, a: 20);
      expect(round.kgPerM, closeTo(math.pi * 0.01 * 0.01 * 7850, 1e-9));
      expect(round.kgPerM, closeTo(2.466, 0.0005));
      expect(square.kgPerM, closeTo(3.14, 1e-9));
    });

    test('blacha 10×1500×3000: 353,25 kg/arkusz, 78,5 kg/m²', () {
      const plate = SteelItem(
          shape: SteelShape.plate, t: 10, a: 1500, lengthMm: 3000, count: 2);
      expect(plate.pieceKg, closeTo(0.010 * 1.5 * 3.0 * 7850, 1e-9));
      expect(plate.pieceKg, closeTo(353.25, 1e-9));
      expect(plate.kgPerM2, closeTo(78.5, 1e-9));
      expect(plate.plateAreaM2, closeTo(9.0, 1e-9));
      expect(plate.totalKg, closeTo(706.5, 1e-9));
    });

    test('materiał: nierdzewka 7900, kwasoodporna 8000, aluminium 2700', () {
      const flat = SteelItem(shape: SteelShape.flat, a: 80, t: 10);
      expect(flat.copyWith(material: SteelMaterial.stainless304).kgPerM,
          closeTo(0.0008 * 7900, 1e-9));
      expect(flat.copyWith(material: SteelMaterial.stainless316).kgPerM,
          closeTo(6.4, 1e-9));
      expect(flat.copyWith(material: SteelMaterial.aluminium).kgPerM,
          closeTo(2.16, 1e-9));
    });

    test('kształtownik z tabeli w innym materiale — × ρ/7850', () {
      const ipe = SteelItem(
          shape: SteelShape.ipe,
          section: 'IPE 200',
          material: SteelMaterial.stainless316);
      expect(ipe.kgPerM, closeTo(22.4 * 8000 / 7850, 1e-9));
    });

    test('HEB 200 × 6 m: 367,8 kg', () {
      const heb =
          SteelItem(shape: SteelShape.heb, section: 'HEB 200', lengthMm: 6000);
      expect(heb.pieceKg, closeTo(367.8, 1e-9));
      expect(heb.totalPaintM2, closeTo(1.151 * 6, 1e-9));
      expect(heb.label(), 'HEB 200');
    });

    test('brak wymiaru / długości / sztuk — problem, masa 0', () {
      expect(const SteelItem(shape: SteelShape.ipe, section: 'IPE 999').problem,
          SteelItemProblem.noSection);
      expect(const SteelItem(shape: SteelShape.flat, a: 80).problem,
          SteelItemProblem.badDimensions);
      expect(
          const SteelItem(
                  shape: SteelShape.heb, section: 'HEB 200', lengthMm: 0)
              .problem,
          SteelItemProblem.noLength);
      const none =
          SteelItem(shape: SteelShape.heb, section: 'HEB 200', count: 0);
      expect(none.problem, SteelItemProblem.noCount);
      expect(none.totalKg, 0);
    });
  });

  group('lista materiałowa', () {
    const heb6 = SteelItem(
        shape: SteelShape.heb, section: 'HEB 200', lengthMm: 6000, count: 2);
    const heb3 = SteelItem(
        shape: SteelShape.heb, section: 'HEB 200', lengthMm: 3000, count: 1);
    const flat = SteelItem(
        shape: SteelShape.flat, a: 80, t: 10, lengthMm: 1200, count: 10);

    test('suma masy, długość per profil, grupowanie tego samego profilu', () {
      const order = SteelOrder(items: [heb6, flat, heb3], wastePct: 0);
      final s = summarizeOrder(order);
      expect(s.netKg, closeTo(61.3 * 15 + 6.28 * 12, 1e-9));
      expect(s.orderKg, closeTo(s.netKg, 1e-9));
      expect(s.totalLengthM, closeTo(27, 1e-9));
      expect(s.groups.map((g) => g.label), ['HEB 200', 'Płaskownik 80×10']);
      final heb = s.groups.first;
      expect(heb.pieces, 3);
      expect(heb.lengthM, closeTo(15, 1e-9));
      expect(heb.kg, closeTo(61.3 * 15, 1e-9));
    });

    test('ten sam profil w innym materiale to osobna grupa', () {
      final order = SteelOrder(items: [
        flat,
        flat.copyWith(material: SteelMaterial.stainless304),
      ]);
      final s = summarizeOrder(order);
      expect(s.groups.map((g) => g.label),
          ['Płaskownik 80×10', 'Płaskownik 80×10 · 1.4301']);
    });

    test('zapas 5 %: masa i koszt w groszach', () {
      const order = SteelOrder(items: [heb6], pricePerKg: 5.2, wastePct: 5);
      final s = summarizeOrder(order);
      // 61,3 kg/m · 12 m = 735,6 kg; 735,6 · 5,20 = 3825,12 zł.
      expect(s.netKg, closeTo(735.6, 1e-9));
      expect(s.wasteKg, closeTo(36.78, 1e-9));
      expect(s.orderKg, closeTo(772.38, 1e-9));
      expect(s.netGrosze, 382512);
      expect(s.wasteGrosze, 19126); // 5 % z 382 512 gr = 19 125,6 → 19 126
      expect(s.orderGrosze, 382512 + 19126);
      expect(formatPln(s.orderGrosze!, withUnit: false), '4\u00a0016,38');
    });

    test('koszt: cena pozycji zł/m i zł/kg wygrywa z ceną listy', () {
      final perM = heb6.copyWith(unitPrice: 300, priceUnit: PriceUnit.perM);
      final perKg = flat.copyWith(unitPrice: 9.99);
      expect(itemCostGrosze(perM, 5.2), costGrosze(12, 300));
      expect(itemCostGrosze(perM, 5.2), 360000);
      expect(itemCostGrosze(perKg, 5.2), costGrosze(6.28 * 12, 9.99));
      expect(itemCostGrosze(heb6, null), isNull);
      final s = summarizeOrder(
          SteelOrder(items: [perM, heb3], pricePerKg: null, wastePct: 10));
      expect(s.netGrosze, 360000);
      expect(s.unpricedItems, 1);
      expect(s.orderGrosze, 396000);
    });

    test('bez żadnej ceny — koszt null, masa liczona', () {
      final s = summarizeOrder(const SteelOrder(items: [heb6]));
      expect(s.netGrosze, isNull);
      expect(s.orderGrosze, isNull);
      expect(s.orderKg, closeTo(735.6 * 1.05, 1e-9));
    });

    test('malowanie: suma pozycji; UPN 50 liczony jako brak powierzchni', () {
      const upn50 =
          SteelItem(shape: SteelShape.upn, section: 'UPN 50', lengthMm: 1000);
      final s = summarizeOrder(const SteelOrder(items: [heb6, upn50]));
      expect(s.paintM2, closeTo(1.151 * 12, 1e-9));
      expect(s.unpaintedItems, 1);
    });

    test('JSON: zapis i odczyt bez strat; śmieci pomijane', () {
      final order = SteelOrder(items: [
        heb6,
        flat.copyWith(
            material: SteelMaterial.aluminium,
            unitPrice: 12.5,
            priceUnit: PriceUnit.perM),
        const SteelItem(
            shape: SteelShape.plate, t: 8, a: 1250, lengthMm: 2500, count: 3),
        const SteelItem(
            shape: SteelShape.hollow, a: 30, b: 20, t: 2, lengthMm: 6000),
      ], pricePerKg: 5.49, wastePct: 7.5);
      final back = SteelOrder.fromJson(
          jsonDecode(jsonEncode(order.toJson())) as Map<String, dynamic>);
      expect(back.pricePerKg, 5.49);
      expect(back.wastePct, 7.5);
      expect(back.items.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(back.items[i].label(), order.items[i].label());
        expect(back.items[i].totalKg, closeTo(order.items[i].totalKg, 1e-9));
        expect(back.items[i].unitPrice, order.items[i].unitPrice);
        expect(back.items[i].priceUnit, order.items[i].priceUnit);
      }
      final junk = SteelOrder.fromJson({
        'items': [
          {'shape': 'kosmos'},
          {'shape': 'ipe', 'section': 'IPE 999', 'len': 1000, 'n': 1},
          'x',
          heb3.toJson(),
        ],
        'waste': -3,
      });
      expect(junk.items.map((i) => i.label()), ['HEB 200']);
      expect(junk.wastePct, 5);
      expect(SteelOrder.fromJson('nie mapa').items, isEmpty);
    });
  });

  group('tekst do udostępnienia', () {
    test('pozycje, sumy wg profili, zapas i koszt', () {
      const order = SteelOrder(items: [
        SteelItem(
            shape: SteelShape.heb,
            section: 'HEB 200',
            lengthMm: 6000,
            count: 2),
        SteelItem(
            shape: SteelShape.plate, t: 10, a: 1500, lengthMm: 3000, count: 1),
      ], pricePerKg: 5.2, wastePct: 5);
      final text = steelOrderText(order, date: DateTime(2026, 10, 17));
      expect(text, contains('Lista materiałowa — stal'));
      expect(text, contains('2026-10-17'));
      expect(text,
          contains('1. HEB 200 — 2 × 6000 mm = 12 m · 61,30 kg/m · 735,6 kg'));
      expect(text, contains('2. Blacha 10×1500×3000 — 1 szt.'));
      expect(text, contains('• HEB 200 — 12 m (2 szt.) — 735,6 kg'));
      expect(text, contains('Masa netto: 1\u00a0089 kg'));
      expect(text, contains('Zapas 5 %: +54,4 kg'));
      expect(text, contains('Do zamówienia: 1\u00a0143 kg'));
      expect(text, contains('Koszt netto (5,20 zł/kg): '));
      expect(text, contains('EN 10365'));
    });

    test('po angielsku', () {
      const order = SteelOrder(items: [
        SteelItem(shape: SteelShape.roundBar, a: 20, lengthMm: 6000, count: 3),
      ]);
      final text = steelOrderText(order, english: true);
      expect(text, contains('Material list — steel'));
      expect(text, contains('Round bar Ø20 — 3 × 6000 mm = 18 m'));
      expect(text, contains('Net mass: 44.4 kg'));
      expect(text, contains('Allowance 5 %: +2.22 kg'));
    });
  });

  group('formatowanie', () {
    test('fmtKg: dokładność rośnie dla małych mas, spacja co 3 cyfry', () {
      expect(fmtKg(0.88), '0,88');
      expect(fmtKg(22.4), '22,4');
      expect(fmtKg(1234.6), '1\u00a0235');
      expect(fmtKg(12.5, english: true), '12.5');
      expect(fmtDim(6.3), '6,3');
      expect(fmtDim(100), '100');
    });
  });
}
