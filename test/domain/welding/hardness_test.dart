// Twardość: tablica ISO 18265 A.1 (wiersze kontrolne), interpolacja, brak
// ekstrapolacji, spójność w obie strony, ocena względem limitu (równość =
// OK, poza tablicą ≠ OK), presety ze źródłami, formatowanie w stronę
// werdyktu.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/hardness.dart';

double? _c(double v, HardnessScale from, HardnessScale to) =>
    convertHardness(v, from: from, to: to);

const _hv = HardnessScale.hv;
const _hb = HardnessScale.hb;
const _hrc = HardnessScale.hrc;
const _hrb = HardnessScale.hrb;

HardnessReading _r(double? v, HardnessScale s, {bool blank = false}) =>
    HardnessReading(location: 'x', value: v, scale: s, blank: blank);

void main() {
  group('tablica ISO 18265 A.1', () {
    test('wiersze kontrolne dokładnie jak w tablicy', () {
      // 250 HV: 238 HB, 22,2 HRC, 99,5 HRB, Rm 800 MPa.
      expect(_c(250, _hv, _hb), 238);
      expect(_c(250, _hv, _hrc), 22.2);
      expect(_c(250, _hv, _hrb), 99.5);
      expect(estimateTensileStrengthMpa(250, _hv), 800);
      // 100 HV: 95,0 HB, 56,2 HRB, Rm 320; HRC — kreska.
      expect(_c(100, _hv, _hb), 95.0);
      expect(_c(100, _hv, _hrb), 56.2);
      expect(estimateTensileStrengthMpa(100, _hv), 320);
      expect(_c(100, _hv, _hrc), isNull);
      // Krańce: 80 HV = 76,0 HB, Rm 255; 940 HV = 68,0 HRC.
      expect(_c(80, _hv, _hb), 76.0);
      expect(estimateTensileStrengthMpa(80, _hv), 255);
      expect(_c(940, _hv, _hrc), 68.0);
      // Odwrotnie: 20,3 HRC = 240 HV; 41,0 HRB = 85 HV; 618 HB = 650 HV.
      expect(_c(20.3, _hrc, _hv), 240);
      expect(_c(41.0, _hrb, _hv), 85);
      expect(_c(618, _hb, _hv), 650);
      // Rozstrzygnięte rozbieżności przedruków: 160 HV → 81,7 HRB,
      // 720 HV → 61,0 HRC.
      expect(_c(160, _hv, _hrb), 81.7);
      expect(_c(720, _hv, _hrc), 61.0);
    });

    test('każda kolumna rośnie razem z HV (warunek interpolacji odwrotnej)',
        () {
      for (final s in HardnessScale.values) {
        double? prev;
        for (final row in kIso18265TableA1) {
          final v = row.value(s);
          if (v == null) continue;
          if (prev != null) expect(v, greaterThan(prev), reason: '${s.label} $v');
          prev = v;
        }
      }
      double? prevRm;
      for (final row in kIso18265TableA1) {
        if (row.rm == null) continue;
        if (prevRm != null) expect(row.rm, greaterThan(prevRm));
        prevRm = row.rm;
      }
    });

    test('zakresy tablicy', () {
      expect(hardnessTableRange(_hv), (min: 80.0, max: 940.0));
      expect(hardnessTableRange(_hb), (min: 76.0, max: 618.0));
      expect(hardnessTableRange(_hrc), (min: 20.3, max: 68.0));
      expect(hardnessTableRange(_hrb), (min: 41.0, max: 99.5));
    });
  });

  group('interpolacja', () {
    test('liniowa między sąsiednimi wierszami', () {
      // 245 HV → 21,3; 250 HV → 22,2 → środek 21,75.
      expect(_c(247.5, _hv, _hrc), closeTo(21.75, 1e-12));
      // HRB co drugi wiersz: 100 → 56,2; 110 → 62,3 → 105 HV = 59,25.
      expect(_c(105, _hv, _hrb), closeTo(59.25, 1e-12));
      // 22 HRC = 245 + 5 · 0,7/0,9 = 248,89 HV (ASTM E140: 248 HV).
      expect(_c(22, _hrc, _hv), closeTo(248.8889, 1e-4));
      // 240 HB między 238 (250 HV) a 242 (255 HV) → 252,5 HV.
      expect(_c(240, _hb, _hv), closeTo(252.5, 1e-12));
      // HB ↔ HRC bezpośrednio z par: 238 HB = 22,2 HRC.
      expect(_c(238, _hb, _hrc), 22.2);
    });

    test('bez ekstrapolacji — poza tablicą null', () {
      expect(_c(79.9, _hv, _hb), isNull);
      expect(_c(940.1, _hv, _hrc), isNull);
      expect(_c(20.2, _hrc, _hv), isNull);
      expect(_c(68.1, _hrc, _hv), isNull);
      expect(_c(40.9, _hrb, _hv), isNull);
      expect(_c(99.6, _hrb, _hv), isNull);
      // HRC zaczyna się od 240 HV, HB i Rm kończą na 650 HV.
      expect(_c(230, _hv, _hrc), isNull);
      expect(_c(660, _hv, _hb), isNull);
      expect(estimateTensileStrengthMpa(660, _hv), isNull);
      expect(_c(double.nan, _hv, _hb), isNull);
      expect(_c(double.infinity, _hv, _hv), isNull);
    });

    test('w obie strony spójnie (HV → X → HV)', () {
      for (final to in [_hb, _hrc, _hrb]) {
        final r = hardnessTableRange(to);
        final lo = convertHardness(r.min, from: to, to: _hv)!;
        final hi = convertHardness(r.max, from: to, to: _hv)!;
        for (var v = lo; v <= hi; v += 0.37) {
          final x = convertHardness(v, from: _hv, to: to)!;
          // Wynik ucięty do 1e-9, nachylenie tablicy do ~7 → błąd < 1e-7.
          expect(convertHardness(x, from: to, to: _hv), closeTo(v, 1e-7),
              reason: '${to.label} @ $v HV');
        }
      }
      // HRC ↔ HB też w obie strony.
      for (var c = 20.3; c <= 57.8; c += 0.29) {
        final hb = _c(c, _hrc, _hb)!;
        expect(_c(hb, _hb, _hrc), closeTo(c, 1e-7));
      }
    });
  });

  group('ocena pomiaru', () {
    const lim250 = HardnessLimit(_hv, 250);
    const lim22c = HardnessLimit(_hrc, 22);

    test('na granicy: równość = OK, powyżej = przekroczony', () {
      expect(checkHardnessReading(_r(250, _hv), lim250).status,
          ReadingStatus.ok);
      expect(checkHardnessReading(_r(250.04, _hv), lim250).status,
          ReadingStatus.exceeded);
      // 22,2 HRC trafia dokładnie w wiersz 250 HV.
      final c = checkHardnessReading(_r(22.2, _hrc), lim250);
      expect(c.status, ReadingStatus.ok);
      expect(c.inLimitScale, 250);
      expect(c.converted, isTrue);
      expect(checkHardnessReading(_r(22.21, _hrc), lim250).status,
          ReadingStatus.exceeded);
    });

    test('werdykt nie zależy od zaokrąglenia — 250,04 HV to przekroczenie',
        () {
      // Do całych 250,04 wygląda jak 250, a jednak > 250.
      expect(250.04.round(), 250);
      expect(checkHardnessReading(_r(250.04, _hv), lim250).isExceeded, isTrue);
    });

    test('przeliczenie poza kolumną limitu — porównanie w skali pomiaru',
        () {
      // 200 HV nie ma odpowiednika HRC (od 240 HV), ale 22 HRC = 248,9 HV.
      final c = checkHardnessReading(_r(200, _hv), lim22c);
      expect(c.status, ReadingStatus.ok);
      expect(c.inLimitScale, isNull);
      expect(c.limitInReadingScale, closeTo(248.8889, 1e-4));
      expect(c.converted, isTrue);
      // 60 HRB ≤ 22 HRC (= 99,35 HRB).
      expect(checkHardnessReading(_r(60, _hrb), lim22c).status,
          ReadingStatus.ok);
      // 260 HV = 24,0 HRC > 22.
      final over = checkHardnessReading(_r(260, _hv), lim22c);
      expect(over.status, ReadingStatus.exceeded);
      expect(over.inLimitScale, 24.0);
    });

    test('poza zakresem tablicy ≠ OK', () {
      // 15 HRC (tablica od 20,3) — nawet jeśli „na oko” miękko.
      expect(checkHardnessReading(_r(15, _hrc), lim250).status,
          ReadingStatus.outOfRange);
      expect(checkHardnessReading(_r(1000, _hv), lim22c).status,
          ReadingStatus.outOfRange);
      expect(checkHardnessReading(_r(70, _hv), const HardnessLimit(_hb, 187))
          .status, ReadingStatus.outOfRange);
    });

    test('stal nierdzewna: inna skala niż limit — bez oceny', () {
      expect(
          checkHardnessReading(_r(20, _hrc), lim250,
                  material: HardnessMaterial.stainless)
              .status,
          ReadingStatus.notConvertible);
      // Ta sama skala — wolno porównać.
      expect(
          checkHardnessReading(_r(240, _hv), lim250,
                  material: HardnessMaterial.stainless)
              .status,
          ReadingStatus.ok);
    });

    test('pusty, nieczytelny, ≤ 0, niefizyczny ≠ OK', () {
      expect(checkHardnessReading(_r(null, _hv, blank: true), lim250).status,
          ReadingStatus.blank);
      expect(checkHardnessReading(_r(null, _hv), lim250).status,
          ReadingStatus.invalid);
      expect(checkHardnessReading(_r(0, _hv), lim250).status,
          ReadingStatus.invalid);
      expect(checkHardnessReading(_r(-5, _hv), lim250).status,
          ReadingStatus.invalid);
      expect(checkHardnessReading(_r(double.nan, _hv), lim250).status,
          ReadingStatus.invalid);
      // 150 HRC — skala C kończy się na 100: to wpis HV w złej skali.
      expect(checkHardnessReading(_r(150, _hrc), lim22c).status,
          ReadingStatus.invalid);
    });

    test('limit ≤ 0, NaN albo spoza skali — brak werdyktu', () {
      for (final bad in [
        const HardnessLimit(_hv, 0),
        const HardnessLimit(_hv, -250),
        const HardnessLimit(_hv, double.nan),
        const HardnessLimit(_hv, double.infinity),
        const HardnessLimit(_hrc, 150),
      ]) {
        expect(bad.isValid, isFalse);
        expect(checkHardnessReading(_r(10, _hv), bad).status,
            ReadingStatus.noLimit);
        expect(evaluateHardnessSeries([_r(10, _hv)], bad).verdict,
            SeriesVerdict.invalidLimit);
      }
    });
  });

  group('seria', () {
    const lim250 = HardnessLimit(_hv, 250);

    test('wszystko OK → pass; max i średnia w skali limitu', () {
      final r = evaluateHardnessSeries(
          [_r(240, _hv), _r(245, _hv), _r(22, _hrc)], lim250);
      expect(r.verdict, SeriesVerdict.pass);
      expect(r.max, closeTo(248.8889, 1e-4));
      expect(r.mean, closeTo((240 + 245 + 248.8889) / 3, 1e-4));
      expect(r.statsCount, 3);
      expect(r.convertedCount, 1);
    });

    test('jedno przekroczenie → fail', () {
      final r = evaluateHardnessSeries(
          [_r(240, _hv), _r(260, _hv), _r(22, _hrc)], lim250);
      expect(r.verdict, SeriesVerdict.fail);
      expect(r.exceededCount, 1);
      expect(r.max, 260);
    });

    test('pusty albo poza tablicą wśród OK → incomplete, nie pass', () {
      expect(
          evaluateHardnessSeries(
              [_r(240, _hv), _r(null, _hv, blank: true)], lim250).verdict,
          SeriesVerdict.incomplete);
      expect(
          evaluateHardnessSeries([_r(240, _hv), _r(15, _hrc)], lim250)
              .verdict,
          SeriesVerdict.incomplete);
      // Przekroczenie wygrywa z brakiem oceny.
      expect(
          evaluateHardnessSeries([_r(260, _hv), _r(15, _hrc)], lim250)
              .verdict,
          SeriesVerdict.fail);
    });

    test('same puste / brak pomiarów → empty', () {
      expect(
          evaluateHardnessSeries([_r(null, _hv, blank: true)], lim250).verdict,
          SeriesVerdict.empty);
      expect(evaluateHardnessSeries([], lim250).verdict, SeriesVerdict.empty);
    });

    test('przekroczenie spoza kolumny limitu: max „> limit”', () {
      // 900 HV nie ma HB (tablica do 650 HV); 450 HB ≈ 473 HV < 900.
      final r = evaluateHardnessSeries(
          [_r(200, _hb), _r(900, _hv)], const HardnessLimit(_hb, 450));
      expect(r.verdict, SeriesVerdict.fail);
      expect(r.maxAboveLimitUnknown, isTrue);
      expect(r.max, 200);
    });
  });

  group('formatowanie w stronę werdyktu', () {
    test('powyżej limitu w górę, w limicie w dół', () {
      expect(formatAgainstLimit(250.04, 250), '250,1');
      expect(formatAgainstLimit(249.96, 250), '249,9');
      expect(formatAgainstLimit(250, 250), '250,0');
      expect(formatAgainstLimit(250.04, 250, en: true), '250.1');
      // O włos ponad limit (porównanie ścisłe) — i tak widać „ponad”,
      // nie „250,0”: miejsc po przecinku przybywa.
      expect(hardnessWithinLimit(250.0000001, 250), isFalse);
      expect(double.parse(formatAgainstLimit(250.0000001, 250, en: true)),
          greaterThan(250));
      // Wartość „okrągła” nie traci dziesiątej: 22,3 → „22,3”.
      expect(formatAgainstLimit(22.3, 22), '22,3');
      expect(formatAgainstLimit(21.7, 22), '21,7');
    });

    test('limit przeliczony na skalę pomiaru', () {
      // OK: pomiar ≤ pokazany limit (w górę).
      expect(formatLimitEquivalent(248.8889, 200), '248,9');
      // Przekroczenie: pomiar > pokazany limit (w dół).
      expect(formatLimitEquivalent(248.8889, 248.89), '248,8');
    });

    test('wartość wpisana — bez zbędnych zer', () {
      expect(formatHardnessExact(250), '250');
      expect(formatHardnessExact(250.04), '250,04');
      expect(formatHardnessExact(22.5, en: true), '22.5');
      // Bez zaokrąglania — „250” obok „przekroczony” byłoby sprzecznością.
      expect(formatHardnessExact(250.00001), '250,00001');
    });
  });

  group('presety limitów', () {
    test('każdy ma źródło, tytuł i prawidłowy limit; identyfikatory unikalne',
        () {
      final ids = <String>{};
      for (final p in kHardnessLimitPresets) {
        expect(ids.add(p.id), isTrue, reason: 'duplikat ${p.id}');
        expect(p.id, isNot(kHardnessCustomLimitId));
        expect(p.limit.isValid, isTrue, reason: p.id);
        for (final s in [p.titlePl, p.titleEn, p.sourcePl, p.sourceEn]) {
          expect(s.trim(), isNotEmpty, reason: p.id);
        }
        // Źródło wskazuje normę z wydaniem (rok).
        expect(p.sourcePl, matches(RegExp(r'(15156|15614|B31\.3).*\d{4}')),
            reason: p.id);
        expect(hardnessPresetById(p.id), same(p));
      }
    });

    test('wartości zweryfikowane w normach', () {
      HardnessLimit l(String id) => hardnessPresetById(id)!.limit;
      // ISO 15156-2:2020 tab. A.1: 250 HV (spoina), 275 HV (lico), 22 HRC.
      expect(l('iso15156_weld').scale, _hv);
      expect(l('iso15156_weld').value, 250);
      expect(l('iso15156_cap').value, 275);
      expect(l('iso15156_hrc').scale, _hrc);
      expect(l('iso15156_hrc').value, 22);
      expect(l('iso15156_a105').value, 187);
      expect(l('iso15156_a234').value, 197);
      // EN ISO 15614-1: gr. 1–2 380/320 HV10, gr. 4–5 po OC 350 (wyd. 2017).
      expect(l('iso15614_g12_aw').value, 380);
      expect(l('iso15614_g12_ht').value, 320);
      expect(l('iso15614_g45_ht').value, 350);
      // ASME B31.3-2008…2012 tab. 331.1.1: P-No 5A/5B/5C/6 — 241 HB.
      expect(l('b313_p5_p6').scale, _hb);
      expect(l('b313_p5_p6').value, 241);
      expect(l('b313_p3_p4').value, 225);
    });
  });
}
