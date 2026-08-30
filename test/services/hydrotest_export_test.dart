import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/hydrotest_dao.dart';
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
    test('a short hold is called out against ASME B31.3 § 345.4.2', () {
      final note = hydrotestHoldNote(_rec(holdMinutes: 4));
      expect(note, isNotNull);
      expect(note, contains('4 min'));
      expect(note, contains('345.4.2'));
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

  test('mail subject names the line, the date and the verdict', () {
    final subject = hydrotestProtocolSubject(_rec());
    expect(subject, contains('WFI-101'));
    expect(subject, contains('2026-08-30'));
    expect(subject, contains('PASS'));
  });
}
