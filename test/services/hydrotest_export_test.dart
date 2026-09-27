import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/hydrotest_dao.dart';
import 'package:cut_list_app/domain/pressure_test/hydrotest_protocol_meta.dart';
import 'package:cut_list_app/domain/pressure_test/test_pressure.dart';
import 'package:cut_list_app/services/hydrotest_export.dart';

/// Builds a record with only the fields a test cares about. Defaults describe
/// a clean, complete PASS so every test can state exactly the one thing it is
/// breaking.
HydrotestRecord _rec({
  String systemName = 'WFI-101',
  String date = '2026-08-30',
  String gauge = 'M-12 / kal. 2026-03',
  double? pressureStartBar = 15.0,
  double? pressureEndBar = 15.0,
  double? temperatureC = 12.0,
  double? holdMinutes = 10.0,
  String result = kHydrotestPass,
  String witness = 'J. Kowalski',
  double? odMm = 60.3,
  double? wallMm = 3.91,
  double? lineLengthMm = 120000,
  double? designBar = 10.0,
  double? factor = 1.5,
  double? testPressureBar = 15.0,
  double? volumeL = 259.4,
  String notes = '',
  HydrotestProtocolMeta meta = const HydrotestProtocolMeta(),
}) =>
    HydrotestRecord(
      id: 'r1',
      systemName: systemName,
      date: date,
      gauge: gauge,
      pressureStartBar: pressureStartBar,
      pressureEndBar: pressureEndBar,
      temperatureC: temperatureC,
      holdMinutes: holdMinutes,
      result: result,
      witness: witness,
      odMm: odMm,
      wallMm: wallMm,
      lineLengthMm: lineLengthMm,
      designBar: designBar,
      factor: factor,
      testPressureBar: testPressureBar,
      volumeL: volumeL,
      notes: notes,
      meta: meta,
      createdAt: 1756512000000,
    );

void main() {
  group('value formatting', () {
    test('a value that was never measured prints as an em dash, not zero', () {
      // The whole point of the nullable fields: "0.00 bar" would read as a
      // measurement of zero, which for a pressure is a failed test rather than
      // a missing one.
      expect(formatHydrotestValue(null), '—');
      expect(formatHydrotestValue(null, unit: 'bar'), '—');
      expect(formatHydrotestHold(null), '—');
      expect(formatHydrotestLength(null), '—');
      expect(formatHydrotestPressure(null), '—');
    });

    test('values round to the requested precision and carry their unit', () {
      expect(formatHydrotestValue(12.345), '12.35');
      expect(formatHydrotestValue(12.345, decimals: 1), '12.3');
      expect(formatHydrotestValue(12.0, unit: 'mm'), '12.00 mm');
      expect(formatHydrotestValue(0), '0.00');
    });

    test('pressure prints bar plus both conversions', () {
      // 15 bar = 1.5 MPa = 217.557 psi. The inspector must not have to
      // convert by hand; a hand conversion is a discrepancy waiting to happen.
      expect(formatHydrotestPressure(15.0),
          '15.00 bar  (1.500 MPa · 218 psi)');
    });

    test('hold time drops a meaningless trailing .0', () {
      expect(formatHydrotestHold(10), '10 min');
      expect(formatHydrotestHold(12.5), '12.5 min');
    });

    test('line length comes back out in metres, the unit it was measured in',
        () {
      // Stored in millimetres like every other length in the app.
      expect(formatHydrotestLength(120000), '120.0 m');
      expect(formatHydrotestLength(1500), '1.5 m');
    });
  });

  group('record arithmetic', () {
    test('pressure drop needs both readings', () {
      expect(_rec(pressureStartBar: 15, pressureEndBar: 14.2).pressureDropBar,
          closeTo(0.8, 1e-9));
      expect(_rec(pressureEndBar: null).pressureDropBar, isNull);
      expect(_rec(pressureStartBar: null).pressureDropBar, isNull);
    });

    test('two identical readings are not a drop', () {
      // Guards the floating-point case: 15.0 - 15.0 must not surface as a leak.
      final r = _rec(pressureStartBar: 15.0, pressureEndBar: 15.0);
      expect(r.pressureDropBar, 0.0);
      expect(r.hasPressureDrop, isFalse);
    });

    test('a reading below gauge noise is not a drop either', () {
      expect(_rec(pressureStartBar: 15.0, pressureEndBar: 14.995).hasPressureDrop,
          isFalse);
      expect(_rec(pressureStartBar: 15.0, pressureEndBar: 14.9).hasPressureDrop,
          isTrue);
    });

    test('an unrecorded hold does not satisfy the code minimum', () {
      // "Unknown" must never read as "compliant".
      expect(_rec(holdMinutes: null).meetsMinimumHold, isFalse);
      expect(_rec(holdMinutes: 9.9).meetsMinimumHold, isFalse);
      expect(_rec(holdMinutes: 10).meetsMinimumHold, isTrue);
      expect(_rec(holdMinutes: 30).meetsMinimumHold, isTrue);
    });

    test('line length converts back to metres for display', () {
      expect(_rec(lineLengthMm: 120000).lineLengthM, 120.0);
      expect(_rec(lineLengthMm: null).lineLengthM, isNull);
    });
  });

  group('audit notes printed on the protocol', () {
    test('a short hold is called out against ASME B31.3 § 345.2.2(a)', () {
      // The 10-min minimum lives in § 345.2.2(a) ("Other Test
      // Requirements"); § 345.4.2 is the hydrostatic test PRESSURE. The old
      // note cited § 345.4.2.
      final note = hydrotestHoldNote(_rec(holdMinutes: 4));
      expect(note, isNotNull);
      expect(note, contains('4 min'));
      expect(note, contains('§345.2.2(a)'));
      expect(note, isNot(contains('345.4.2')));
      // Bilingual, like every other string that ends up on paper.
      expect(note, contains('WARNING'));
    });

    test('a compliant or unrecorded hold gets no note', () {
      expect(hydrotestHoldNote(_rec(holdMinutes: 10)), isNull);
      expect(hydrotestHoldNote(_rec(holdMinutes: 45)), isNull);
      // A missing hold is reported by hydrotestMissingNote instead — printing
      // both would say the same thing twice.
      expect(hydrotestHoldNote(_rec(holdMinutes: null)), isNull);
    });

    test('PASS with a measured pressure drop is flagged', () {
      // The single most common way a filed test falls apart under review.
      final note = hydrotestDropNote(
          _rec(pressureStartBar: 15, pressureEndBar: 14.2));
      expect(note, isNotNull);
      expect(note, contains('0.80'));
    });

    test('FAIL with a drop is not flagged — that is the expected outcome', () {
      expect(
        hydrotestDropNote(_rec(
            result: kHydrotestFail, pressureStartBar: 15, pressureEndBar: 10)),
        isNull,
      );
    });

    test('PASS that actually held gets no drop note', () {
      expect(hydrotestDropNote(_rec()), isNull);
    });

    test('a complete record produces no "incomplete" note', () {
      expect(hydrotestMissingNote(_rec()), isNull);
    });

    test('every unfilled witnessed field is named on the paper', () {
      final note = hydrotestMissingNote(_rec(
        gauge: '',
        temperatureC: null,
        witness: '   ',
      ));
      expect(note, isNotNull);
      expect(note, contains('manometr'));
      expect(note, contains('temperatura'));
      expect(note, contains('świadek'));
      // Fields that WERE filled must not be listed.
      expect(note, isNot(contains('czas wytrzymania')));
    });
  });

  group('file name', () {
    test('names the file after the system and the date', () {
      expect(
        hydrotestProtocolFileName(
          extension: 'pdf',
          generatedAt: DateTime(2026, 8, 30),
          systemName: 'WFI-101',
        ),
        'Protokol_proby_WFI_101_2026-08-30.pdf',
      );
    });

    test('drops the tag entirely when there is no system', () {
      expect(
        hydrotestProtocolFileName(
          extension: 'pdf',
          generatedAt: DateTime(2026, 1, 5),
        ),
        'Protokol_proby_2026-01-05.pdf',
      );
      // A tag made only of punctuation folds away to nothing rather than
      // leaving a dangling separator.
      expect(
        hydrotestProtocolFileName(
          extension: 'pdf',
          generatedAt: DateTime(2026, 1, 5),
          systemName: ' /// ',
        ),
        'Protokol_proby_2026-01-05.pdf',
      );
    });

    test('caps a pasted line description so the name stays usable', () {
      final name = hydrotestProtocolFileName(
        extension: 'pdf',
        generatedAt: DateTime(2026, 8, 30),
        systemName: 'A' * 80,
      );
      expect(name, 'Protokol_proby_${'A' * 32}_2026-08-30.pdf');
    });
  });

  group('protocol metadata (schema v19 columns)', () {
    const meta = HydrotestProtocolMeta(
      company: 'Montaż Rur Sp. z o.o.',
      testMedium: 'Woda',
      presetId: 'en13480_ped_hydro',
      stressRatio: 1.2,
      metalTempC: 14.0,
      gaugeCalibrationDue: '2026-12-31',
      protocolNo: 'HT-017',
      revision: 'A',
    );

    test('a record with metadata reports its preset', () {
      final r = _rec(notes: 'Korki 2×.', meta: meta);
      expect(r.notes, 'Korki 2×.');
      expect(hydrotestMeta(r), meta);
      expect(hydrotestPreset(r), PressureTestPreset.en13480Hydro);
    });

    test('a record without metadata is treated as the old B31.3 calculator',
        () {
      final r = _rec(notes: 'Przeciek na kołnierzu.');
      expect(hydrotestMeta(r), isNull);
      expect(hydrotestPreset(r), PressureTestPreset.b313Hydro);
      expect(hydrotestMinHoldMinutes(r), 10);
    });

    test('EN 13480-5 preset holds the record to 30 min, not 10', () {
      final r = _rec(holdMinutes: 15, meta: meta);
      expect(hydrotestMeetsMinimumHold(r), isFalse);
      final note = hydrotestHoldNote(r);
      expect(note, contains('30 min'));
      expect(note, contains('EN 13480-5'));
      expect(
          hydrotestMeetsMinimumHold(
              _rec(holdMinutes: 30, meta: meta)),
          isTrue);
    });

    test('ASME VIII-1 has no minimum in the app — no hold note', () {
      final r = _rec(
          holdMinutes: 1,
          meta: const HydrotestProtocolMeta(presetId: 'asme_viii_1_hydro'));
      expect(hydrotestHoldNote(r), isNull);
      expect(hydrotestMeetsMinimumHold(r), isTrue);
    });

    test('an expired gauge calibration is flagged against the test date', () {
      final expired = _rec(
        date: '2026-08-30',
        meta: const HydrotestProtocolMeta(gaugeCalibrationDue: '2026-08-29'),
      );
      expect(hydrotestCalibrationNote(expired), contains('2026-08-29'));
      final valid = _rec(
        date: '2026-08-30',
        meta: const HydrotestProtocolMeta(gaugeCalibrationDue: '2026-08-30'),
      );
      expect(hydrotestCalibrationNote(valid), isNull);
      // Not an ISO date → no judgement.
      expect(
          hydrotestCalibrationNote(_rec(
              meta: const HydrotestProtocolMeta(
                  gaugeCalibrationDue: '03/2026'))),
          isNull);
      expect(hydrotestCalibrationNote(_rec()), isNull);
    });

    test('new records must name the medium and the metal temperature', () {
      final r =
          _rec(meta: const HydrotestProtocolMeta(presetId: 'b31_3_hydro'));
      final note = hydrotestMissingNote(r);
      expect(note, contains('medium'));
      expect(note, contains('temperatura metalu'));
      expect(note, isNot(contains('zaworu')));
    });

    test('a pneumatic test without a relief valve set pressure is incomplete',
        () {
      final r = _rec(
          meta: const HydrotestProtocolMeta(
              presetId: 'b31_3_pneumatic', testMedium: 'Azot', metalTempC: 12));
      expect(hydrotestMissingNote(r), contains('zaworu bezpieczeństwa'));
    });

    test('test type and stress ratio labels', () {
      expect(hydrotestTestTypeLabel(PressureTestPreset.b313Pneumatic),
          'Pneumatyczna / Pneumatic — ASME B31.3 §345.5.4');
      expect(formatHydrotestStressRatio(PressureTestPreset.b313Hydro, 1.2),
          'ST/S = 1.20');
      expect(formatHydrotestStressRatio(PressureTestPreset.b313Hydro, 8),
          'ST/S = 8.00 → 6.50 (limit)');
      expect(formatHydrotestStressRatio(PressureTestPreset.b311Hydro, 1.2),
          startsWith('—'));
    });

    test('mail subject carries the protocol number', () {
      final r = _rec(meta: meta);
      expect(hydrotestProtocolSubject(r), contains('HT-017'));
    });
  });

  test('mail subject names the line, the date and the verdict', () {
    final subject = hydrotestProtocolSubject(_rec());
    expect(subject, contains('WFI-101'));
    expect(subject, contains('2026-08-30'));
    expect(subject, contains('PASS'));
  });

  // Przegląd G4: PASS przy ciśnieniu początkowym < Pt przechodził bez słowa.
  group('ciśnienie początkowe vs Pt', () {
    test('start 12 < Pt 15 przy PASS → uwaga i oznaczenie niezgodności', () {
      final r = _rec(pressureStartBar: 12, pressureEndBar: 12);
      expect(hydrotestPassNotCompliant(r), isTrue);
      final n = hydrotestStartPressureNote(r)!;
      expect(n, contains('12.00 bar < ciśnienie próby Pt 15.00 bar'));
      expect(n, contains('NIE SPEŁNIA'));
      expect(n, contains('DOES NOT MEET'));
    });
    test('FAIL z niskim ciśnieniem: uwaga bez „PASS nie spełnia”', () {
      final r = _rec(pressureStartBar: 12, result: kHydrotestFail);
      expect(hydrotestPassNotCompliant(r), isFalse);
      expect(hydrotestStartPressureNote(r), isNot(contains('NIE SPEŁNIA')));
    });
    test('start = Pt → brak uwagi', () {
      expect(hydrotestStartPressureNote(_rec()), isNull);
      expect(hydrotestPassNotCompliant(_rec()), isFalse);
    });
    test('pneumatyczna: start 14 > 1,33·P = 13,30', () {
      final r = _rec(
        pressureStartBar: 14,
        pressureEndBar: 14,
        testPressureBar: 11,
        factor: 1.1,
        meta: const HydrotestProtocolMeta(presetId: 'b31_3_pneumatic'),
      );
      expect(hydrotestPassNotCompliant(r), isTrue);
      expect(hydrotestStartPressureNote(r), contains('13.30 bar'));
    });
  });
}
