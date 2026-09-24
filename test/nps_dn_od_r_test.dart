import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/data/nps_dn_od_r.dart';

void main() {
  group('kNpsTable — spójność DN/NPS/OD wg ASME B36.10', () {
    NpsRow rowForDn(int dn) => kNpsTable.firstWhere((r) => r.dn == dn);

    test('DN500 istnieje i ma OD 508.0 mm (NPS 20")', () {
      final r = rowForDn(500);
      expect(r.odMm, 508.0);
      expect(r.nps, '20"');
    });

    test('DN550 → OD 558.8 mm (NPS 22")', () {
      final r = rowForDn(550);
      expect(r.odMm, 558.8);
      expect(r.nps, '22"');
    });

    test('DN600 → OD 609.6 mm (NPS 24")', () {
      final r = rowForDn(600);
      expect(r.odMm, 609.6);
      expect(r.nps, '24"');
    });

    test('każdy wiersz ma odMm > 0', () {
      for (final r in kNpsTable) {
        expect(r.odMm, greaterThan(0), reason: 'odMm dla ${r.nps}/DN${r.dn}');
      }
    });

    // ASME B36.10M / B16.9 (OD at bevel): NPS 4 = 4.500 in = 114.3 mm; to
    // także EN 10220 / ISO 4200 seria 1. Wcześniej DN100 miał w tabeli tylko
    // 104,0 i 108,0 — ekran DN-MM nie pokazywał podstawowej średnicy DN100.
    test('DN100 ma OD 114.3 mm (NPS 4", ASME B36.10 i EN 10220 s.1)', () {
      final rows = kNpsTable.where((r) => r.dn == 100).toList();
      final r = rows.singleWhere((r) => r.odMm == 114.3);
      expect(r.nps, '4"');
      expect(r.series, OdSeries.asmeAndEn1);
      expect(r.hasB169Elbows, isTrue);
    });

    test('brakujące średnice: 33.7 (DN25), 139.7 i 141.3 (DN125), 26.7, 42.2',
        () {
      expect(kNpsTable.singleWhere((r) => r.odMm == 33.7).dn, 25);
      expect(kNpsTable.singleWhere((r) => r.odMm == 139.7).dn, 125);
      expect(kNpsTable.singleWhere((r) => r.odMm == 141.3).dn, 125);
      expect(kNpsTable.singleWhere((r) => r.odMm == 26.7).dn, 20);
      expect(kNpsTable.singleWhere((r) => r.odMm == 42.2).dn, 32);
    });

    // ASME B36.10M: NPS 3 1/2 = DN90, OD 4.000 in = 101.6 mm (nie DN80).
    test('NPS 3 1/2" (OD 101.6) to DN90', () {
      final r = kNpsTable.singleWhere((r) => r.odMm == 101.6);
      expect(r.nps, '3 1/2"');
      expect(r.dn, 90);
    });

    // Promień kolana ~1,5D (A kolana 90° LR):
    //   ASME B16.9-2018 Tab. 6.1-1: NPS 1/2 i 3/4 → 38 mm (1.50 in),
    //                               NPS 12 → 457 mm (18.00 in);
    //   EN 10253-2:2007 Tab. 11 (model 3D): 21,3 → 38; 26,9 → 38;
    //                               323,9 → 457.
    // Tabela miała 28 / 29 / 455 — wartości z żadnej z tych norm.
    test('R dla 21.3 / 26.9 / 323.9 zgodny z B16.9 i EN 10253-2', () {
      double r(double od) => kNpsTable.singleWhere((x) => x.odMm == od).rMm;
      expect(r(21.3), closeTo(38.1, 0.1));
      expect(r(26.9), closeTo(38.1, 0.1));
      expect(r(323.9), closeTo(457.2, 0.3));
      expect(r(114.3), closeTo(152.4, 0.1));
    });

    test('b169RowForOd: OD rury → wiersz z kolanami B16.9 / EN 10253', () {
      expect(b169RowForOd(60.3)!.dn, 50);
      expect(b169RowForOd(114.3)!.dn, 100);
      expect(b169RowForOd(76.1)!.dn, 65); // EN s.1
      expect(b169RowForOd(73.0)!.dn, 65); // ASME 2.875 in
      expect(b169RowForOd(323.8)!.dn, 300); // ASME 12.75 in vs EN 323.9
      expect(b169RowForOd(610)!.dn, 600);
      // Średnice spoza ASME / EN s.1 (rury higieniczne, EN s.2/s.3) — bez
      // zgadywania.
      expect(b169RowForOd(108.0), isNull);
      expect(b169RowForOd(104.0), isNull);
      expect(b169RowForOd(100.0), isNull);
    });

    test('odMm rośnie ściśle w całej tabeli', () {
      for (var i = 1; i < kNpsTable.length; i++) {
        expect(
          kNpsTable[i].odMm,
          greaterThan(kNpsTable[i - 1].odMm),
          reason:
              'wiersz $i (${kNpsTable[i].nps}/DN${kNpsTable[i].dn}) nie jest większy od poprzedniego',
        );
      }
    });
  });
}
