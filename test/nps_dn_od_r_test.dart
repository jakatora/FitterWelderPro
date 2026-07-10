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
