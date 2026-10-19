// Przelicznik jednostek (lib/domain/fitter/unit_conversion.dart).
//
// Wartości referencyjne przepisane z logiki ekranu
// lib/screens/quick_converter_screen.dart sprzed refaktoru (_ConversionTabState
// ._convert, tabele _lengthFactors / _pressureFactors / _flowFactors /
// _temperatureFloors, kolejność błędów z _error):
//   1 in = 25,4 mm;  1 ft = 304,8 mm
//   100 °C = 373,15 K = 212 °F;  −40 °C = −40 °F
//   10 bar / 0,0689476 = 145,0377… psi  (ekran: „145.038”)
//   10 l/min / 0,4719474 = 21,1888… cfh; l/min ↔ slpm się NIE przelicza
//
// Test „zgodność z dawnym ekranem” porównuje bit w bit z kopią starego kodu.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/unit_conversion.dart';

// ── Kopia logiki ekranu sprzed refaktoru (wyrocznia) ─────────────────────────

const _legacyLength = {
  'mm': 1.0,
  'cm': 10.0,
  'm': 1000.0,
  'in': 25.4,
  'ft': 304.8
};
const _legacyPressure = {
  'bar': 1.0,
  'MPa': 10.0,
  'kPa': 0.01,
  'psi': 0.0689476,
  'atm': 1.01325,
  'kgf/cm²': 0.980665,
  'mbar': 0.001,
};
const _legacyFlow = {
  'l/min': 1.0,
  'slpm': 1.0,
  'cfh': 0.4719474,
  'scfh': 0.4719474
};
const _legacyFloors = {'°C': -273.15, '°F': -459.67, 'K': 0.0};

bool _legacyIsStandard(String unit) => unit == 'slpm' || unit == 'scfh';

Map<String, double> _legacyConvert(String kind, String src, double value) {
  if (kind == 'temperature') {
    final kelvin = switch (src) {
      '°C' => value + 273.15,
      '°F' => (value + 459.67) / 1.8,
      _ => value,
    };
    return {'°C': kelvin - 273.15, '°F': kelvin * 1.8 - 459.67, 'K': kelvin};
  }
  final factors = switch (kind) {
    'length' => _legacyLength,
    'pressure' => _legacyPressure,
    _ => _legacyFlow,
  };
  final base = value * factors[src]!;
  return {
    for (final unit in factors.keys)
      if (kind != 'flow' || _legacyIsStandard(unit) == _legacyIsStandard(src))
        unit: base / factors[unit]!
  };
}

/// Old `_error` order: range (value or any result non-finite) → absolute zero
/// (temperature) → sign (other tabs).
ConversionIssue? _legacyIssue(String kind, String src, double value) {
  final results =
      value.isFinite ? _legacyConvert(kind, src, value) : <String, double>{};
  if (!value.isFinite || results.values.any((v) => !v.isFinite)) {
    return ConversionIssue.outOfRange;
  }
  if (kind == 'temperature') {
    if (value < _legacyFloors[src]!) return ConversionIssue.belowAbsoluteZero;
  } else if (value < 0) {
    return ConversionIssue.negative;
  }
  return null;
}

Map<String, double> _symbols<U extends MeasureUnit>(ConversionTable<U> t) =>
    {for (final e in t.values.entries) e.key.symbol: e.value};

const _grid = <double>[
  0,
  -0.0,
  1,
  2.5,
  25.4,
  100,
  -1,
  -40,
  -273.15,
  -273.16,
  -459.67,
  -459.68,
  -0.001,
  0.000123,
  1e-12,
  123456.789,
  1e9,
  1e300,
  -1e300,
  1e307,
  -1e307,
  1e308,
  double.maxFinite,
  double.infinity,
  double.negativeInfinity,
  double.nan,
];

void main() {
  group('jednostki = jak na ekranie', () {
    test('kolejność i symbole', () {
      expect(LengthUnit.values.map((u) => u.symbol),
          ['mm', 'cm', 'm', 'in', 'ft']);
      expect(TemperatureUnit.values.map((u) => u.symbol), ['°C', '°F', 'K']);
      expect(PressureUnit.values.map((u) => u.symbol),
          ['bar', 'MPa', 'kPa', 'psi', 'atm', 'kgf/cm²', 'mbar']);
      expect(FlowUnit.values.map((u) => u.symbol),
          ['l/min', 'slpm', 'cfh', 'scfh']);
    });

    test('współczynniki i zera bezwzględne ze starych tabel', () {
      for (final u in LengthUnit.values) {
        expect(u.toMm, _legacyLength[u.symbol], reason: u.symbol);
      }
      for (final u in PressureUnit.values) {
        expect(u.toBar, _legacyPressure[u.symbol], reason: u.symbol);
      }
      for (final u in FlowUnit.values) {
        expect(u.toLpm, _legacyFlow[u.symbol], reason: u.symbol);
        expect(u.standard, _legacyIsStandard(u.symbol), reason: u.symbol);
      }
      for (final u in TemperatureUnit.values) {
        expect(u.absoluteZero, _legacyFloors[u.symbol], reason: u.symbol);
      }
    });

    test('fromSymbol', () {
      expect(LengthUnit.fromSymbol('in'), LengthUnit.inch);
      expect(TemperatureUnit.fromSymbol('°F'), TemperatureUnit.fahrenheit);
      expect(PressureUnit.fromSymbol('kgf/cm²'), PressureUnit.kgfPerCm2);
      expect(FlowUnit.fromSymbol('scfh'), FlowUnit.scfh);
      expect(LengthUnit.fromSymbol('cal'), isNull);
      expect(PressureUnit.fromSymbol(''), isNull);
    });
  });

  group('wartości referencyjne', () {
    test('1″ = 25,4 mm; 1 ft = 304,8 mm; 25,4 mm = 1 in', () {
      expect(convertLength(1, LengthUnit.inch, LengthUnit.mm), 25.4);
      expect(convertLength(1, LengthUnit.ft, LengthUnit.mm), 304.8);
      expect(convertLength(25.4, LengthUnit.mm, LengthUnit.inch), 1.0);
      expect(convertLength(2.5, LengthUnit.m, LengthUnit.cm), 250.0);
    });

    test('100 °C = 212 °F = 373,15 K; −40 °C = −40 °F', () {
      expect(
          convertTemperature(
              100, TemperatureUnit.celsius, TemperatureUnit.fahrenheit),
          closeTo(212, 1e-9));
      expect(
          convertTemperature(
              100, TemperatureUnit.celsius, TemperatureUnit.kelvin),
          closeTo(373.15, 1e-9));
      expect(
          convertTemperature(
              -40, TemperatureUnit.celsius, TemperatureUnit.fahrenheit),
          closeTo(-40, 1e-9));
      expect(
          convertTemperature(
              0, TemperatureUnit.kelvin, TemperatureUnit.celsius),
          -273.15);
    });

    test('10 bar → psi wg stałej ekranu 0,0689476', () {
      final psi = convertPressure(10, PressureUnit.bar, PressureUnit.psi)!;
      expect(psi, 10 * 1.0 / 0.0689476);
      expect(psi, closeTo(145.038, 5e-4));
      expect(convertPressure(1, PressureUnit.mpa, PressureUnit.bar), 10.0);
      expect(convertPressure(2, PressureUnit.bar, PressureUnit.kpa),
          closeTo(200, 1e-9));
      expect(convertPressure(1, PressureUnit.kgfPerCm2, PressureUnit.bar),
          0.980665);
    });

    test('przepływ: l/min ↔ cfh, slpm ↔ scfh, bez mieszania', () {
      expect(convertFlow(10, FlowUnit.lpm, FlowUnit.cfh), 10 / 0.4719474);
      expect(convertFlow(10, FlowUnit.slpm, FlowUnit.scfh), 10 / 0.4719474);
      expect(convertFlow(10, FlowUnit.lpm, FlowUnit.slpm), isNull);
      expect(convertFlow(10, FlowUnit.scfh, FlowUnit.cfh), isNull);
      expect(convertFlowAll(10, FlowUnit.lpm).values.keys,
          [FlowUnit.lpm, FlowUnit.cfh]);
      expect(convertFlowAll(10, FlowUnit.scfh).values.keys,
          [FlowUnit.slpm, FlowUnit.scfh]);
    });

    test('tabela długości w kolejności ekranu', () {
      final t = convertLengthAll(1, LengthUnit.inch);
      expect(t.issue, isNull);
      expect(t.ok, isTrue);
      expect(t.values.keys, LengthUnit.values);
      expect(t.values[LengthUnit.mm], 25.4);
    });

    test('0 jest poprawne (ekran pokazuje 0.000)', () {
      expect(convertLength(0, LengthUnit.mm, LengthUnit.inch), 0.0);
      expect(convertPressure(0, PressureUnit.bar, PressureUnit.psi), 0.0);
      expect(convertLengthAll(0, LengthUnit.mm).issue, isNull);
    });
  });

  group('dane nieprawidłowe → null i powód', () {
    test('ujemne (poza temperaturą)', () {
      expect(convertLength(-1, LengthUnit.mm, LengthUnit.inch), isNull);
      expect(convertPressure(-0.5, PressureUnit.bar, PressureUnit.psi), isNull);
      expect(convertFlow(-2, FlowUnit.lpm, FlowUnit.cfh), isNull);
      final t = convertLengthAll(-1, LengthUnit.mm);
      expect(t.issue, ConversionIssue.negative);
      expect(t.ok, isFalse);
      expect(t.values, isEmpty);
    });

    test('poniżej zera bezwzględnego', () {
      expect(
          convertTemperature(
              -274, TemperatureUnit.celsius, TemperatureUnit.kelvin),
          isNull);
      expect(convertTemperatureAll(-0.01, TemperatureUnit.kelvin).issue,
          ConversionIssue.belowAbsoluteZero);
      expect(convertTemperatureAll(-459.67, TemperatureUnit.fahrenheit).issue,
          isNull);
      expect(convertTemperatureAll(-20, TemperatureUnit.celsius).issue, isNull);
    });

    test('NaN, nieskończoność i przepełnienie', () {
      expect(convertLength(double.nan, LengthUnit.mm, LengthUnit.inch), isNull);
      expect(convertLengthAll(double.nan, LengthUnit.mm).issue,
          ConversionIssue.outOfRange);
      expect(convertPressureAll(double.infinity, PressureUnit.bar).issue,
          ConversionIssue.outOfRange);
      expect(convertLengthAll(1e308, LengthUnit.ft).issue,
          ConversionIssue.outOfRange);
      // Old screen checks range before sign: a huge negative is "range".
      expect(convertLengthAll(-1e307, LengthUnit.ft).issue,
          ConversionIssue.outOfRange);
    });
  });

  group('zgodność z dawnym ekranem (bit w bit)', () {
    test('długość', () {
      for (final from in LengthUnit.values) {
        for (final v in _grid) {
          final t = convertLengthAll(v, from);
          final legacyIssue = _legacyIssue('length', from.symbol, v);
          expect(t.issue, legacyIssue, reason: '$v ${from.symbol}');
          if (legacyIssue == null) {
            expect(_symbols(t), _legacyConvert('length', from.symbol, v),
                reason: '$v ${from.symbol}');
          }
        }
      }
    });

    test('temperatura', () {
      for (final from in TemperatureUnit.values) {
        for (final v in _grid) {
          final t = convertTemperatureAll(v, from);
          final legacyIssue = _legacyIssue('temperature', from.symbol, v);
          expect(t.issue, legacyIssue, reason: '$v ${from.symbol}');
          if (legacyIssue == null) {
            expect(_symbols(t), _legacyConvert('temperature', from.symbol, v),
                reason: '$v ${from.symbol}');
          }
        }
      }
    });

    test('ciśnienie', () {
      for (final from in PressureUnit.values) {
        for (final v in _grid) {
          final t = convertPressureAll(v, from);
          final legacyIssue = _legacyIssue('pressure', from.symbol, v);
          expect(t.issue, legacyIssue, reason: '$v ${from.symbol}');
          if (legacyIssue == null) {
            expect(_symbols(t), _legacyConvert('pressure', from.symbol, v),
                reason: '$v ${from.symbol}');
          }
        }
      }
    });

    test('przepływ', () {
      for (final from in FlowUnit.values) {
        for (final v in _grid) {
          final t = convertFlowAll(v, from);
          final legacyIssue = _legacyIssue('flow', from.symbol, v);
          expect(t.issue, legacyIssue, reason: '$v ${from.symbol}');
          if (legacyIssue == null) {
            expect(_symbols(t), _legacyConvert('flow', from.symbol, v),
                reason: '$v ${from.symbol}');
          }
        }
      }
    });
  });
}
