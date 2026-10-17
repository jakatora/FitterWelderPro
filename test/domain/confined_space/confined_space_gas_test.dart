// Gazy w przestrzeni zamkniętej: każdy próg na granicy (równy przechodzi),
// tlen za mało / za dużo, przeliczenie mg/m³ → ppm (20 °C, 101,3 kPa),
// wartość wpisana wyświetla się tak, jak ją wpisano, edycja progów tylko
// w bezpieczną stronę, JSON odczytu i progów.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/confined_space/confined_space_gas.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_sources.dart';

CsReadingState _state(CsGas g, double v, [CsUnit? unit, CsLimits? limits]) =>
    csReadingState(
        g, CsQty(v, unit ?? g.canonical), limits ?? CsLimits.defaults);

void main() {
  group('progi domyślne na granicy', () {
    test('tlen: 19,5 % OK, 19,49 % za mało; 23,5 % OK, 23,51 % za dużo', () {
      expect(_state(CsGas.o2, 19.5), CsReadingState.ok);
      expect(_state(CsGas.o2, 19.49), CsReadingState.low);
      expect(_state(CsGas.o2, 20.9), CsReadingState.ok);
      expect(_state(CsGas.o2, 23.5), CsReadingState.ok);
      expect(_state(CsGas.o2, 23.51), CsReadingState.high);
      // Argon wyparł tlen / nieszczelny wąż tlenowy.
      expect(_state(CsGas.o2, 17).stop, isTrue);
      expect(_state(CsGas.o2, 25).stop, isTrue);
    });

    test('gazy palne: 10 % DGW OK, 10,01 % DGW powyżej progu', () {
      expect(_state(CsGas.lel, 0), CsReadingState.ok);
      expect(_state(CsGas.lel, 10), CsReadingState.ok);
      expect(_state(CsGas.lel, 10.01), CsReadingState.high);
    });

    test('CO: 20 ppm OK (NDS), 20,01 ppm powyżej; 23 mg/m³ OK', () {
      expect(_state(CsGas.co, 20), CsReadingState.ok);
      expect(_state(CsGas.co, 20.01), CsReadingState.high);
      // 23 mg/m³ · 24,05 / 28,01 ≈ 19,75 ppm.
      expect(_state(CsGas.co, 23, CsUnit.mgM3), CsReadingState.ok);
      expect(_state(CsGas.co, 23.4, CsUnit.mgM3), CsReadingState.high);
    });

    test('H₂S: 7 mg/m³ OK (NDS), 7,01 mg/m³ powyżej; 4,9 ppm OK, 5 ppm STOP',
        () {
      expect(_state(CsGas.h2s, 7, CsUnit.mgM3), CsReadingState.ok);
      expect(_state(CsGas.h2s, 7.01, CsUnit.mgM3), CsReadingState.high);
      // 7 mg/m³ · 24,05 / 34,08 ≈ 4,94 ppm.
      expect(_state(CsGas.h2s, 4.9), CsReadingState.ok);
      expect(_state(CsGas.h2s, 5), CsReadingState.high);
    });

    test('brak progu — odczytu nie da się ocenić (ale przekroczenie tlenu '
        'drugiej granicy nadal STOP)', () {
      const none = CsLimits({});
      expect(_state(CsGas.lel, 0, null, none), CsReadingState.noLimit);
      expect(_state(CsGas.co, 0, null, none), CsReadingState.noLimit);
      final onlyMax = CsLimits.defaults.withLimit(CsBound.o2Min, null);
      expect(_state(CsGas.o2, 20.9, null, onlyMax), CsReadingState.noLimit);
      expect(_state(CsGas.o2, 24, null, onlyMax), CsReadingState.high);
    });

    test('brak progu przy niebezpiecznym odczycie — STOP wg twardej granicy',
        () {
      const none = CsLimits({});
      expect(_state(CsGas.o2, 5, null, none), CsReadingState.low);
      expect(_state(CsGas.o2, 25, null, none), CsReadingState.high);
      expect(_state(CsGas.co, 500, null, none), CsReadingState.high);
      expect(_state(CsGas.co, 20, null, none), CsReadingState.noLimit);
      expect(_state(CsGas.lel, 50, null, none), CsReadingState.high);
      expect(_state(CsGas.h2s, 7.01, CsUnit.mgM3, none), CsReadingState.high);
      expect(_state(CsGas.h2s, 7, CsUnit.mgM3, none), CsReadingState.noLimit);
    });
  });

  group('jednostki i przeliczenie', () {
    test('mg/m³ → ppm przy 20 °C i 101,3 kPa (24,05 dm³/mol)', () {
      expect(kCsMolarVolume, 24.05);
      expect(csCanonical(CsGas.h2s, const CsQty(7, CsUnit.mgM3)),
          closeTo(4.94, 0.005));
      expect(csCanonical(CsGas.co, const CsQty(23, CsUnit.mgM3)),
          closeTo(19.75, 0.005));
      expect(csCanonical(CsGas.co, const CsQty(20, CsUnit.ppm)), 20);
    });

    test('wartość wyświetla się tak, jak ją wpisano — bez przeliczeń', () {
      expect(formatCsQty(CsGas.co, const CsQty(23, CsUnit.mgM3), en: false),
          '23 mg/m³');
      expect(formatCsQty(CsGas.h2s, const CsQty(4.9, CsUnit.ppm), en: false),
          '4,9 ppm');
      expect(formatCsQty(CsGas.o2, const CsQty(20.9, CsUnit.pctVol), en: true),
          '20.9 %');
      expect(formatCsQty(CsGas.lel, const CsQty(0, CsUnit.pctLel), en: false),
          '0 % DGW');
      // Do 3 miejsc — 19,495 nie udaje 19,5.
      expect(formatCsNumber(19.495, en: false), '19,495');
      expect(csRound(19.49549), 19.495);
    });

    test('zakres odczytu i dozwolone jednostki gazu', () {
      expect(csQtyInRange(CsGas.o2, const CsQty(100, CsUnit.pctVol)), isTrue);
      expect(csQtyInRange(CsGas.o2, const CsQty(101, CsUnit.pctVol)), isFalse);
      expect(csQtyInRange(CsGas.o2, const CsQty(-1, CsUnit.pctVol)), isFalse);
      expect(csQtyInRange(CsGas.o2, const CsQty(20, CsUnit.ppm)), isFalse);
      expect(csQtyInRange(CsGas.co, const CsQty(500, CsUnit.ppm)), isTrue);
      expect(csQtyInRange(CsGas.lel, const CsQty(5, CsUnit.mgM3)), isFalse);
    });
  });

  group('edycja progów tylko w bezpieczną stronę', () {
    test('tlen: dolny tylko w górę (do 20,9), górny tylko w dół (od 20,9)',
        () {
      bool v(CsBound b, double x) => csLimitValid(b, CsQty(x, CsUnit.pctVol));
      expect(v(CsBound.o2Min, 19.5), isTrue);
      expect(v(CsBound.o2Min, 20), isTrue);
      expect(v(CsBound.o2Min, 19.4), isFalse);
      expect(v(CsBound.o2Min, 18), isFalse);
      expect(v(CsBound.o2Min, 21), isFalse);
      expect(v(CsBound.o2Max, 23.5), isTrue);
      expect(v(CsBound.o2Max, 23), isTrue);
      expect(v(CsBound.o2Max, 23.6), isFalse);
      expect(v(CsBound.o2Max, 20.5), isFalse);
    });

    test('DGW 0–10, CO do 20 ppm, H₂S do 7 mg/m³ (≈ 4,94 ppm)', () {
      expect(csLimitValid(CsBound.lelMax, const CsQty(10, CsUnit.pctLel)),
          isTrue);
      expect(csLimitValid(CsBound.lelMax, const CsQty(0, CsUnit.pctLel)),
          isTrue);
      expect(csLimitValid(CsBound.lelMax, const CsQty(10.01, CsUnit.pctLel)),
          isFalse);
      expect(csLimitValid(CsBound.coMax, const CsQty(20, CsUnit.ppm)), isTrue);
      expect(csLimitValid(CsBound.coMax, const CsQty(21, CsUnit.ppm)), isFalse);
      expect(
          csLimitValid(CsBound.coMax, const CsQty(23, CsUnit.mgM3)), isTrue);
      expect(
          csLimitValid(CsBound.coMax, const CsQty(24, CsUnit.mgM3)), isFalse);
      expect(
          csLimitValid(CsBound.h2sMax, const CsQty(7, CsUnit.mgM3)), isTrue);
      expect(csLimitValid(CsBound.h2sMax, const CsQty(4, CsUnit.ppm)), isTrue);
      expect(csLimitValid(CsBound.h2sMax, const CsQty(5, CsUnit.ppm)), isFalse);
    });

    test('withLimit nie przyjmuje łagodniejszego progu, null usuwa', () {
      final l = CsLimits.defaults;
      expect(l.isDefault, isTrue);
      final stricter = l.withLimit(CsBound.lelMax, const CsQty(5, CsUnit.pctLel));
      expect(stricter[CsBound.lelMax], const CsQty(5, CsUnit.pctLel));
      expect(stricter.isDefault, isFalse);
      final looser =
          stricter.withLimit(CsBound.lelMax, const CsQty(50, CsUnit.pctLel));
      expect(looser[CsBound.lelMax], const CsQty(5, CsUnit.pctLel));
      expect(stricter.withLimit(CsBound.lelMax, null)[CsBound.lelMax], isNull);
    });
  });

  group('JSON', () {
    test('progi tam i z powrotem; niedozwolony próg z zapisu pominięty', () {
      final l = CsLimits.defaults
          .withLimit(CsBound.h2sMax, const CsQty(3, CsUnit.ppm))
          .withLimit(CsBound.o2Min, const CsQty(20, CsUnit.pctVol));
      final back = CsLimits.fromJson(l.toJson());
      expect(back, l);
      final bad = l.toJson()
        ..['lelMax'] = {'v': 50, 'u': 'pctLel'}
        ..['coMax'] = {'v': 20, 'u': 'pctVol'};
      final parsed = CsLimits.fromJson(bad);
      expect(parsed[CsBound.lelMax], isNull);
      expect(parsed[CsBound.coMax], isNull);
      expect(parsed[CsBound.h2sMax], const CsQty(3, CsUnit.ppm));
    });

    test('pomiar tam i z powrotem; uszkodzony odczyt odrzuca cały pomiar', () {
      const m = CsMeasurement(
        time: '10:30',
        at: 1000 * 60 * 30,
        values: {
          CsGas.o2: CsQty(20.9, CsUnit.pctVol),
          CsGas.co: CsQty(23, CsUnit.mgM3),
        },
        place: 'dno',
      );
      expect(CsMeasurement.fromJson(m.toJson()), m);
      expect(CsMeasurement.fromJson({...m.toJson(), 'o2': 'dużo'}), isNull);
      expect(CsMeasurement.fromJson({...m.toJson(), 'at': null}), isNull);
      expect(
          CsMeasurement.fromJson({'time': '10:30', 'at': 5, 'place': ''}),
          isNull);
      expect(CsMeasurement.fromJson('x'), isNull);
    });

    test('pomiar z przyszłości odrzucony; chwila wpisu i identyfikator w JSON',
        () {
      final now = DateTime(2026, 10, 17, 14);
      final m = CsMeasurement(
        id: 'm1',
        time: '14:05',
        at: DateTime(2026, 10, 17, 14, 5).millisecondsSinceEpoch,
        enteredAt: DateTime(2026, 10, 17, 14).millisecondsSinceEpoch,
        values: const {CsGas.o2: CsQty(20.9, CsUnit.pctVol)},
      );
      // 14:05 przy 14:00 mieści się w zapasie 5 min.
      expect(CsMeasurement.fromJson(m.toJson(), now: now), m);
      final far = {
        ...m.toJson(),
        'at': DateTime(2026, 10, 17, 14, 6).millisecondsSinceEpoch,
      };
      expect(CsMeasurement.fromJson(far, now: now), isNull);
      // Bez zegara (np. test domeny) — bez kontroli przyszłości.
      expect(CsMeasurement.fromJson(far), isNotNull);
      expect(m.entered, m.enteredAt);
      expect(const CsMeasurement(time: '', at: 5, values: {}).entered, 5);
    });
  });
}
