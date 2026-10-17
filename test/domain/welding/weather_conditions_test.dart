// Warunki do spawania: punkt rosy (Magnus, Alduchov–Eskridge 1996), progi
// wiatru i temperatury na granicach, MMA vs MAG przy wietrze, osłony, opad,
// mróz, przeliczenia jednostek, JSON historii i progów (także uszkodzony).
//
// Wartości punktu rosy policzone niezależnie (Python, te same stałe):
//   20 °C / 50 %  → 9,261 °C       (Lawrence 2005, tab. 1: ≈ 9,3 °C)
//   15 °C / 50 %  → 4,658 °C
//   10 °C / 80 %  → 6,708 °C
//   -5 °C / 80 %  → rosa -7,916 °C, szron -7,024 °C (lód: Buck 1996)
//   -10 °C / 80 % → rosa -12,795 °C, szron -11,400 °C

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/weather_conditions.dart';

WeatherInput _in({
  double ambientC = 15,
  double rhPct = 50,
  double? surfaceC,
  double windMs = 1,
  Precipitation precipitation = Precipitation.none,
  WeatherProcess process = WeatherProcess.mma111,
  WeatherShelter shelter = WeatherShelter.none,
  WeatherMaterial material = WeatherMaterial.carbonSteel,
  double? wpsPreheatC,
}) =>
    WeatherInput(
      ambientC: ambientC,
      rhPct: rhPct,
      surfaceC: surfaceC,
      windMs: windMs,
      precipitation: precipitation,
      process: process,
      shelter: shelter,
      material: material,
      wpsPreheatC: wpsPreheatC,
    );

WeatherAssessment _a(WeatherInput i,
        [WeatherThresholds t = WeatherThresholds.defaults]) =>
    assessWeather(i, t)!;

FindingSeverity? _sev(WeatherAssessment a, String code) {
  for (final f in a.findings) {
    if (f.code == code) return f.severity;
  }
  return null;
}

void main() {
  group('punkt rosy', () {
    test('20 °C / 50 % ≈ 9,3 °C', () {
      final d = dewPointC(airC: 20, rhPct: 50)!;
      expect(d, closeTo(9.261, 0.001));
      expect(weatherNum(d), '9,3');
      expect(weatherNum(d, english: true), '9.3');
    });

    test('znane przykłady', () {
      expect(dewPointC(airC: 15, rhPct: 50), closeTo(4.658, 0.001));
      expect(dewPointC(airC: 10, rhPct: 80), closeTo(6.708, 0.001));
      expect(dewPointC(airC: 30, rhPct: 90), closeTo(28.179, 0.001));
    });

    test('RH 100 % → punkt rosy = temperatura powietrza', () {
      for (final t in [-30.0, -5.0, 0.0, 12.5, 35.0]) {
        expect(dewPointC(airC: t, rhPct: 100), closeTo(t, 1e-9));
      }
    });

    test('ujemny punkt rosy: punkt szronu wyższy i to on jest progiem', () {
      final dew = dewPointC(airC: -10, rhPct: 80)!;
      final frost = frostPointC(airC: -10, rhPct: 80)!;
      expect(dew, closeTo(-12.795, 0.001));
      expect(frost, closeTo(-11.400, 0.001));
      expect(condensationPointC(airC: -10, rhPct: 80), frost);
      // Dodatni punkt rosy — szron nie gra roli.
      expect(condensationPointC(airC: 20, rhPct: 50),
          dewPointC(airC: 20, rhPct: 50));
    });

    test('dane spoza zakresu → null', () {
      expect(dewPointC(airC: 20, rhPct: 0), isNull);
      expect(dewPointC(airC: 20, rhPct: 100.1), isNull);
      expect(dewPointC(airC: 70, rhPct: 50), isNull);
      expect(dewPointC(airC: double.nan, rhPct: 50), isNull);
      expect(assessWeather(_in(rhPct: 0)), isNull);
    });
  });

  group('wiatr: jednostki i Beaufort', () {
    test('m/s ↔ km/h, mph', () {
      expect(msToKmh(1), 3.6);
      expect(kmhToMs(36), closeTo(10, 1e-12));
      expect(windToMs(18, WindUnit.kmh), closeTo(5, 1e-12));
      expect(windToMs(5, WindUnit.ms), 5);
      expect(windFromMs(5, WindUnit.kmh), closeTo(18, 1e-12));
      expect(kmhToMs(msToKmh(7.3)), closeTo(7.3, 1e-12));
      // 5 mph (AWS D1.1) = 2,235 m/s ≈ 8 km/h; domyślny próg 2,2 m/s jest
      // po stronie bezpiecznej.
      expect(mphToMs(5), closeTo(2.2352, 1e-4));
      expect(WeatherThresholds.kDefaultMaxWindGasMs,
          lessThanOrEqualTo(mphToMs(5)));
      expect(
          msToKmh(WeatherThresholds.kDefaultMaxWindGasMs), closeTo(7.92, 0.01));
    });

    test('skala Beauforta: ciągła, rosnąca, 0–7', () {
      expect(kBeaufortScale.map((b) => b.force), [0, 1, 2, 3, 4, 5, 6, 7]);
      for (var i = 1; i < kBeaufortScale.length; i++) {
        expect(kBeaufortScale[i].minMs,
            closeTo(kBeaufortScale[i - 1].maxMs + 0.1, 1e-9));
      }
      expect(beaufortFor(0).force, 0);
      expect(beaufortFor(2.2).force, 2);
      expect(beaufortFor(3.3).force, 2);
      expect(beaufortFor(3.4).force, 3);
      expect(beaufortFor(10.8).force, 6);
      expect(beaufortFor(40).force, 7);
      // Próg silnego wiatru = dolna granica 6° B.
      expect(WeatherThresholds.kDefaultMaxWindAnyMs, kBeaufortScale[6].minMs);
    });
  });

  group('werdykt', () {
    test('spokojny dzień, MMA → można spawać', () {
      final a = _a(_in());
      expect(a.verdict, WeatherVerdict.go);
      expect(a.stops, isEmpty);
      expect(a.conditions, isEmpty);
      expect(a.surfaceAssumed, isTrue);
      expect(a.surfaceC, 15);
      expect(a.marginK, closeTo(15 - 4.658, 0.001));
    });

    test('MMA vs MAG przy wietrze 5 m/s', () {
      final mma = _a(_in(windMs: 5));
      expect(mma.verdict, WeatherVerdict.go);
      expect(_sev(mma, WeatherCode.windGas), FindingSeverity.ok);

      final mag = _a(_in(windMs: 5, process: WeatherProcess.mag135));
      expect(mag.verdict, WeatherVerdict.noGo);
      expect(mag.stops.single.code, WeatherCode.windGas);

      for (final p in [
        WeatherProcess.tig141,
        WeatherProcess.mig131,
        WeatherProcess.fcawG136,
        WeatherProcess.gas311,
      ]) {
        expect(_a(_in(windMs: 5, process: p)).verdict, WeatherVerdict.noGo,
            reason: p.name);
      }
      for (final p in [WeatherProcess.fcawS114, WeatherProcess.saw121]) {
        expect(_a(_in(windMs: 5, process: p)).verdict, WeatherVerdict.go,
            reason: p.name);
      }
    });

    test('granica wiatru dla gazu: 2,2 m/s jeszcze OK, 2,3 m/s już nie', () {
      expect(_a(_in(windMs: 2.2, process: WeatherProcess.tig141)).verdict,
          WeatherVerdict.go);
      expect(_a(_in(windMs: 2.3, process: WeatherProcess.tig141)).verdict,
          WeatherVerdict.noGo);
      // 8 km/h wpisane w km/h = 2,22 m/s > 2,2 → już ponad próg.
      expect(
          _a(_in(windMs: kmhToMs(8), process: WeatherProcess.tig141)).verdict,
          WeatherVerdict.noGo);
    });

    test('osłona znosi zakaz wiatru — zostaje warunek do odhaczenia', () {
      for (final s in [WeatherShelter.windbreak, WeatherShelter.enclosure]) {
        final a =
            _a(_in(windMs: 6, process: WeatherProcess.mag135, shelter: s));
        expect(a.stops, isEmpty, reason: s.name);
        expect(a.verdict, WeatherVerdict.conditional, reason: s.name);
        expect(a.conditions.single.code, WeatherCode.windGas);
      }
    });

    test('silny wiatr: 10,8 m/s jeszcze nie, 10,9 m/s — bez namiotu stop', () {
      expect(_a(_in(windMs: 10.8)).verdict, WeatherVerdict.go);
      final a = _a(_in(windMs: 10.9));
      expect(a.verdict, WeatherVerdict.noGo);
      expect(a.stops.single.code, WeatherCode.windHigh);
      // Parawan nie wystarcza, namiot — warunkowo.
      expect(_a(_in(windMs: 12, shelter: WeatherShelter.windbreak)).verdict,
          WeatherVerdict.noGo);
      final tent = _a(_in(windMs: 12, shelter: WeatherShelter.enclosure));
      expect(tent.verdict, WeatherVerdict.conditional);
      expect(tent.conditions.single.code, WeatherCode.windHigh);
    });

    test('opad bez namiotu → nie spawać; parawan nie pomaga; namiot → warunki',
        () {
      for (final p in [
        Precipitation.drizzle,
        Precipitation.rain,
        Precipitation.snow
      ]) {
        final a = _a(_in(precipitation: p));
        expect(a.verdict, WeatherVerdict.noGo, reason: p.name);
        expect(a.stops.single.code, WeatherCode.precipitation);
        expect(
            _a(_in(precipitation: p, shelter: WeatherShelter.windbreak))
                .verdict,
            WeatherVerdict.noGo,
            reason: p.name);
        final tent =
            _a(_in(precipitation: p, shelter: WeatherShelter.enclosure));
        expect(tent.verdict, WeatherVerdict.conditional, reason: p.name);
        expect(tent.conditions.map((f) => f.code),
            contains(WeatherCode.precipitation));
      }
      final rain = _a(_in(precipitation: Precipitation.rain));
      expect(rain.recommendations.map((f) => f.code),
          contains(WeatherCode.recHotWeld));
    });

    test('mróz: -18 °C (0 °F) jeszcze nie blokuje, -18,1 °C bez namiotu tak',
        () {
      final at = _a(_in(ambientC: -18, rhPct: 60));
      expect(_sev(at, WeatherCode.ambient), FindingSeverity.ok);
      final below = _a(_in(ambientC: -18.1, rhPct: 60));
      expect(below.verdict, WeatherVerdict.noGo);
      expect(below.stops.map((f) => f.code), [WeatherCode.ambient]);
      final tent =
          _a(_in(ambientC: -25, rhPct: 60, shelter: WeatherShelter.enclosure));
      expect(tent.stops, isEmpty);
      expect(_sev(tent, WeatherCode.ambient), FindingSeverity.condition);
    });

    test('ujemna temperatura stali węglowej → podgrzać do 21 °C (70 °F)', () {
      final a = _a(_in(ambientC: -5, rhPct: 80));
      expect(a.verdict, WeatherVerdict.conditional);
      expect(a.requiredMaterialC, 21);
      expect(_sev(a, WeatherCode.materialTemp), FindingSeverity.condition);
      // Rosa -7,92 °C < 0 → progiem jest szron -7,02 °C.
      expect(a.frostPointC, closeTo(-7.024, 0.001));
      expect(a.condensationPointC, a.frostPointC);
      expect(a.marginK, closeTo(-5 + 7.024, 0.001));
      expect(a.targetSurfaceC, 21);
      expect(
          a.findings
              .firstWhere((f) => f.code == WeatherCode.materialTemp)
              .textPl,
          contains('≥ 21 °C'));
    });

    test('granica „zimnej” stali: 0 °C → min. 10 °C, -0,1 °C → 21 °C', () {
      expect(_a(_in(ambientC: 5, surfaceC: 0)).requiredMaterialC, 10);
      expect(_a(_in(ambientC: 5, surfaceC: -0.1)).requiredMaterialC, 21);
    });

    test('nierdzewna i aluminium przy mrozie: minimum 10 °C, nie 21 °C', () {
      for (final m in [WeatherMaterial.stainless, WeatherMaterial.aluminium]) {
        final a = _a(_in(ambientC: -5, rhPct: 80, material: m));
        expect(a.requiredMaterialC, 10, reason: m.name);
      }
      expect(
          _a(_in(material: WeatherMaterial.aluminium))
              .recommendations
              .map((f) => f.code),
          contains(WeatherCode.recAluminium));
    });

    test('granica minimum materiału: 10 °C OK, 9,9 °C — podgrzać', () {
      expect(_sev(_a(_in(ambientC: 10, rhPct: 40)), WeatherCode.materialTemp),
          FindingSeverity.ok);
      expect(_sev(_a(_in(ambientC: 9.9, rhPct: 40)), WeatherCode.materialTemp),
          FindingSeverity.condition);
    });

    test('podgrzewanie z WPS podnosi wymaganą temperaturę', () {
      final a = _a(_in(wpsPreheatC: 100));
      expect(a.requiredMaterialC, 100);
      expect(a.verdict, WeatherVerdict.conditional);
      expect(a.recommendations.map((f) => f.code),
          contains(WeatherCode.recHeatZone));
      // Złącze już gorące — OK.
      expect(
          _a(_in(surfaceC: 120, wpsPreheatC: 100)).verdict, WeatherVerdict.go);
    });

    test('punkt rosy: powierzchnia poniżej → warunek; zapas < 3 K → warunek',
        () {
      // 20 °C / 50 % → Td 9,26 °C.
      final wet = _a(_in(ambientC: 20, rhPct: 50, surfaceC: 8));
      expect(wet.marginK, closeTo(-1.261, 0.001));
      expect(_sev(wet, WeatherCode.condensation), FindingSeverity.condition);
      expect(
          wet.findings
              .firstWhere((f) => f.code == WeatherCode.condensation)
              .textPl,
          contains('rosa'));

      final close = _a(_in(ambientC: 20, rhPct: 50, surfaceC: 11));
      expect(_sev(close, WeatherCode.condensation), FindingSeverity.condition);
      expect(close.targetSurfaceC, closeTo(12.261, 0.001));

      // Zapas dokładnie 3 K — jeszcze OK (warunek „< 3 K”).
      final edge = _a(_in(
          ambientC: 20,
          rhPct: 50,
          surfaceC: dewPointC(airC: 20, rhPct: 50)! + 3));
      expect(_sev(edge, WeatherCode.condensation), FindingSeverity.ok);
    });

    test('brak temperatury powierzchni → założenie i zalecenie pomiaru', () {
      final assumed = _a(_in());
      expect(assumed.surfaceAssumed, isTrue);
      expect(assumed.recommendations.map((f) => f.code),
          contains(WeatherCode.recMeasureSurface));
      final measured = _a(_in(surfaceC: 14));
      expect(measured.surfaceAssumed, isFalse);
      expect(measured.recommendations.map((f) => f.code),
          isNot(contains(WeatherCode.recMeasureSurface)));
    });

    test('każdy punkt ma podstawę i oba języki', () {
      final a = _a(_in(
          ambientC: -25,
          rhPct: 90,
          windMs: 12,
          precipitation: Precipitation.snow,
          process: WeatherProcess.mma111,
          shelter: WeatherShelter.enclosure,
          wpsPreheatC: 50));
      for (final f in [...a.findings, ...a.recommendations]) {
        expect(f.basis, isNotEmpty, reason: f.code);
        expect(f.textPl, isNotEmpty, reason: f.code);
        expect(f.textEn, isNotEmpty, reason: f.code);
        expect(f.basisText(false), isNotEmpty, reason: f.code);
        expect(f.basisText(true), isNotEmpty, reason: f.code);
      }
      expect(a.recommendations.map((f) => f.code),
          contains(WeatherCode.recElectrodes));
    });

    test('własne progi (specyfikacja) zmieniają werdykt', () {
      final i = _in(windMs: 4, process: WeatherProcess.mag135);
      expect(_a(i).verdict, WeatherVerdict.noGo);
      final loose = WeatherThresholds.defaults.copyWith(maxWindGasMs: 5);
      expect(loose.isDefault, isFalse);
      expect(_a(i, loose).verdict, WeatherVerdict.go);
    });
  });

  group('JSON', () {
    final input = _in(
      ambientC: -3.5,
      rhPct: 88,
      surfaceC: -6,
      windMs: 3.2,
      precipitation: Precipitation.snow,
      process: WeatherProcess.fcawG136,
      shelter: WeatherShelter.enclosure,
      material: WeatherMaterial.stainless,
      wpsPreheatC: 15,
    );

    test('wejście i progi: zapis i odczyt bez strat', () {
      final back =
          WeatherInput.fromJson(jsonDecode(jsonEncode(input.toJson())));
      expect(back.toJson(), input.toJson());
      const t = WeatherThresholds(maxWindGasMs: 3, dewMarginK: 2);
      expect(decodeWeatherThresholds(encodeWeatherThresholds(t)).toJson(),
          t.toJson());
    });

    test('wpis historii: zapis i odczyt', () {
      final r = WeatherCheckRecord(
        id: '1',
        takenAt: DateTime(2026, 10, 17, 7, 5),
        place: 'Estakada E-3',
        input: input,
        thresholds: const WeatherThresholds(minMaterialC: 5),
        verdict: assessWeather(input)!.verdict,
        checked: {WeatherCode.materialTemp},
      );
      final list = decodeWeatherHistory(encodeWeatherHistory([r]));
      expect(list, hasLength(1));
      final b = list.single;
      expect(b.id, '1');
      expect(b.takenAt, DateTime(2026, 10, 17, 7, 5));
      expect(b.place, 'Estakada E-3');
      expect(b.verdict, r.verdict);
      expect(b.checked, {WeatherCode.materialTemp});
      expect(b.thresholds.minMaterialC, 5);
      expect(b.input.toJson(), input.toJson());
      expect(b.assessment!.verdict, r.verdict);
    });

    test('uszkodzony JSON historii → pusta lista, bez wyjątku', () {
      expect(decodeWeatherHistory(null), isEmpty);
      expect(decodeWeatherHistory(''), isEmpty);
      expect(decodeWeatherHistory('{nie json'), isEmpty);
      expect(decodeWeatherHistory('{"a":1}'), isEmpty);
      expect(decodeWeatherHistory('"tekst"'), isEmpty);
    });

    test('uszkodzone pojedyncze wpisy są pomijane, reszta zostaje', () {
      final good = WeatherCheckRecord(
        id: 'ok',
        takenAt: DateTime(2026, 10, 1),
        input: _in(),
        verdict: WeatherVerdict.go,
      ).toJson();
      final raw = jsonEncode([
        1,
        'x',
        {'id': 'bez-daty'},
        {
          'id': 'zla-data',
          'takenAt': 'wczoraj',
          'input': _in().toJson(),
        },
        {
          'id': 'bez-liczb',
          'takenAt': '2026-10-02T10:00:00.000',
          'input': {'ambientC': 'zimno'},
        },
        good,
      ]);
      final list = decodeWeatherHistory(raw);
      expect(list.map((r) => r.id), ['ok']);
    });

    test('brak werdyktu w zapisie → odtworzony z danych; sortowanie', () {
      final raw = jsonEncode([
        {
          'id': 'a',
          'takenAt': '2026-10-01T08:00:00.000',
          'input': _in(precipitation: Precipitation.rain).toJson(),
        },
        {
          'id': 'b',
          'takenAt': '2026-10-02T08:00:00.000',
          'input': _in().toJson(),
          'verdict': 'go',
          'checked': [1, 'material_temp'],
        },
      ]);
      final list = decodeWeatherHistory(raw);
      expect(list.map((r) => r.id), ['b', 'a']);
      expect(list.last.verdict, WeatherVerdict.noGo);
      expect(list.first.checked, {'material_temp'});
    });

    test('uszkodzone progi → domyślne (całe albo pojedyncze pole)', () {
      expect(decodeWeatherThresholds(null).isDefault, isTrue);
      expect(decodeWeatherThresholds('][').isDefault, isTrue);
      expect(decodeWeatherThresholds('[1,2]').isDefault, isTrue);
      final t = decodeWeatherThresholds(jsonEncode({
        'maxWindGasMs': -1,
        'dewMarginK': 'trzy',
        'minMaterialC': 5,
      }));
      expect(t.maxWindGasMs, WeatherThresholds.kDefaultMaxWindGasMs);
      expect(t.dewMarginK, WeatherThresholds.kDefaultDewMarginK);
      expect(t.minMaterialC, 5);
    });
  });

  test('liczby: przecinek w PL, bez „-0,0”', () {
    expect(weatherNum(-0.04), '0,0');
    expect(weatherNum(-3.25, decimals: 2), '-3,25');
    expect(weatherNum(2.5, english: true), '2.5');
  });
}
