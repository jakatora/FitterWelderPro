// Publiczne funkcje rozmiarów rur (DN / NPS → OD) — jedyne źródło liczb
// asystenta dla pytań „jaka średnica DN40". Wartości z tabeli „DN ↔ mm"
// (lib/data/nps_dn_od_r.dart) i „Grubości ścianek" (pipe_schedules.dart).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/nps_dn_od_r.dart';
import 'package:cut_list_app/data/pipe_schedules.dart';
import 'package:cut_list_app/domain/fitter/pipe_size_lookup.dart';

void main() {
  group('odForDn — seria główna', () {
    test('DN40 → 48,3 (ASME + EN seria 1)', () {
      expect(odForDn(40), 48.3);
    });
    test('DN50 → 60,3', () => expect(odForDn(50), 60.3));
    test('DN20 → 26,7 (ASME przed EN 1)', () => expect(odForDn(20), 26.7));
    test('DN125 → 141,3 (ASME przed EN 1, choć EN 1 jest pierwszy w tabeli)',
        () => expect(odForDn(125), 141.3));
    test('nieznane DN → null (nie zgadujemy)', () {
      expect(odForDn(999), isNull);
      expect(odForDn(45), isNull);
      expect(odForDn(0), isNull);
    });
  });

  group('odSeriesForDn', () {
    test('DN40 → [48,3 asmeAndEn1, 44,5 en3]', () {
      final s = odSeriesForDn(40);
      expect(s.map((o) => o.odMm).toList(), [48.3, 44.5]);
      expect(s.map((o) => o.series).toList(),
          [OdSeries.asmeAndEn1, OdSeries.en3]);
    });
    test('główna pierwsza, reszta w kolejności serii (EN 1 przed EN 3)', () {
      expect(odSeriesForDn(25).map((o) => o.odMm).toList(), [33.4, 33.7, 30.0]);
    });
    test('każda seria główna = odForDn', () {
      for (final dn in {for (final r in kNpsTable) r.dn}) {
        expect(odSeriesForDn(dn).first.odMm, odForDn(dn), reason: 'DN$dn');
      }
    });
    test('nieznane DN → pusta lista', () => expect(odSeriesForDn(999), isEmpty));
  });

  group('NPS', () {
    test('odForNps(2) == 60,3', () => expect(odForNps(2), 60.3));
    test('odForNps(0,75) == 26,7 (ASME)', () => expect(odForNps(0.75), 26.7));
    test('odForNps(1,5) == 48,3', () => expect(odForNps(1.5), 48.3));
    test('rozmiar spoza tabeli → null', () {
      expect(odForNps(2.75), isNull);
      expect(odForNps(0), isNull);
    });
    test('dnForNps / npsForDn', () {
      expect(dnForNps(1.5), 40);
      expect(dnForNps(2), 50);
      expect(dnForNps(2.75), isNull);
      expect(npsForDn(40), '1 1/2"');
      expect(npsForDn(999), isNull);
    });
    test('npsInchesOf czyta zapis z tabeli', () {
      expect(npsInchesOf('1 1/4"'), 1.25);
      expect(npsInchesOf('3/4"'), 0.75);
      expect(npsInchesOf('12"'), 12);
      expect(npsInchesOf('abc'), isNull);
    });
  });

  group('pipeRowForDn', () {
    test('DN50 → OD 60,3', () => expect(pipeRowForDn(50)!.od, 60.3));
    test('DN40 Sch 40 → 3,68', () => expect(pipeRowForDn(40)!.walls['40'], 3.68));
    test('nieznane DN → null', () => expect(pipeRowForDn(45), isNull));
  });

  test('etykieta źródła DN → OD (nie ISO 6708)', () {
    expect(kDnOdSourcePl, 'EN 10220 / ISO 4200 seria 1, ASME B36.10M');
    expect(kDnOdSourceEn, 'EN 10220 / ISO 4200 series 1, ASME B36.10M');
    expect(kDnOdSourcePl.contains('6708'), isFalse);
  });
}
