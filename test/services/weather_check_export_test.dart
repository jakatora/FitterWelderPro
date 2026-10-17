// PDF i tekst pomiaru „Warunki do spawania”: Roboto (polskie znaki), PL i EN,
// wszystkie sekcje (zakazy, warunki z odhaczeniem, OK, zalecenia, progi
// zmienione), nazwa pliku z datą.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/welding/weather_conditions.dart';
import 'package:cut_list_app/services/weather_check_export.dart';

pw.Font _font(String f) => pw.Font.ttf(
    ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));

WeatherCheckRecord _record({
  WeatherInput? input,
  WeatherThresholds thresholds = WeatherThresholds.defaults,
  Set<String> checked = const {},
}) {
  final i = input ??
      const WeatherInput(
        ambientC: -8,
        rhPct: 92,
        windMs: 6,
        windUnit: WindUnit.kmh,
        precipitation: Precipitation.snow,
        process: WeatherProcess.mag135,
        shelter: WeatherShelter.enclosure,
        material: WeatherMaterial.carbonSteel,
        wpsPreheatC: 50,
      );
  return WeatherCheckRecord(
    id: 'r1',
    takenAt: DateTime(2026, 10, 17, 6, 40),
    place: 'Zbiornik T-101, pas 3 — spoina pionowa',
    input: i,
    thresholds: thresholds,
    verdict: assessWeather(i, thresholds)!.verdict,
    checked: checked,
  );
}

void main() {
  test('PDF: PL i EN, z warunkami, zaleceniami i zmienionymi progami',
      () async {
    final r = _record(
        thresholds: const WeatherThresholds(maxWindGasMs: 3),
        checked: {WeatherCode.precipitation});
    for (final en in [false, true]) {
      final doc = await WeatherCheckExport.buildPdfDocument(
        record: r,
        english: en,
        font: _font('Roboto-Regular.ttf'),
        boldFont: _font('Roboto-Bold.ttf'),
        generatedAt: DateTime(2026, 10, 17, 6, 45),
      );
      final bytes = await doc.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    }
  });

  test('PDF: werdykt „nie spawać” (opad bez osłony) też się renderuje',
      () async {
    final r = _record(
        input: const WeatherInput(
            ambientC: 4,
            rhPct: 97,
            windMs: 2,
            precipitation: Precipitation.rain,
            process: WeatherProcess.tig141));
    expect(r.verdict, WeatherVerdict.noGo);
    final doc = await WeatherCheckExport.buildPdfDocument(
      record: r,
      english: false,
      font: _font('Roboto-Regular.ttf'),
      generatedAt: DateTime(2026, 10, 17),
    );
    expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
  });

  test('tekst: wiatr w jednostce wpisanej, odhaczenia, progi, zastrzeżenie',
      () {
    final r = _record(
        thresholds: const WeatherThresholds(maxWindGasMs: 3),
        checked: {WeatherCode.precipitation});
    final pl = weatherCheckText(r, english: false);
    expect(pl, startsWith('WARUNKI DO SPAWANIA\n2026-10-17 06:40'));
    expect(pl, contains('Miejsce: Zbiornik T-101, pas 3 — spoina pionowa'));
    expect(pl, contains('Werdykt: MOŻNA SPAWAĆ PO SPEŁNIENIU WARUNKÓW'));
    // Wpisane w km/h: 6 m/s = 21,6 km/h pierwsze.
    expect(pl, contains('Wiatr: 21,6 km/h (6 m/s) · 4° Beaufort'));
    expect(pl, contains('[x] Opad (śnieg)'));
    expect(pl, contains('[ ] '));
    expect(pl, contains('Progi zmienione względem domyślnych'));
    expect(pl, contains('wiatr — procesy gazowe: 3 m/s (łagodniej niż norma)'));
    // Próg łagodniejszy od normy → twarde ostrzeżenie zaraz pod werdyktem.
    expect(pl, contains('!!! UWAGA: progi łagodniejsze niż wartości z norm'));
    expect(pl, contains('Stan powierzchni złącza: nie sprawdzono'));
    expect(pl, contains(weatherDisclaimer(english: false)));

    final en = weatherCheckText(r, english: true);
    expect(en, contains('Verdict: WELD ONLY ONCE THE CONDITIONS ARE MET'));
    expect(en, contains('Location: Zbiornik T-101'));
    expect(en, contains('!!! WARNING: thresholds looser than the code'));
    expect(en, contains(weatherDisclaimer(english: true)));
  });

  test('raport: precyzja jak w polach (WPS 65,4 °C, próg 2,26 m/s) (W3)', () {
    final r = _record(
      input: const WeatherInput(
          ambientC: -17.85,
          rhPct: 62.5,
          windMs: 1,
          surfaceState: SurfaceState.dry,
          wpsPreheatC: 65.4),
      thresholds: const WeatherThresholds(maxWindGasMs: 2.26),
    );
    final pl = weatherCheckText(r, english: false);
    expect(pl, contains('Temperatura powietrza: -17,85 °C'));
    expect(pl, contains('Wilgotność względna: 62,5 %'));
    expect(pl, contains('Podgrzewanie z WPS: 65,4 °C'));
    expect(pl, contains('Min. temperatura materiału: 65,4 °C'));
    expect(pl, contains('≥ 65,4 °C przed spawaniem'));
    expect(pl, contains('wiatr — procesy gazowe: 2,26 m/s'));
  });

  test('wpis zapisany inną wersją reguł → ostrzeżenie w tekście i PDF (W7)',
      () async {
    const input = WeatherInput(
        ambientC: 15, rhPct: 50, windMs: 1, surfaceState: SurfaceState.dry);
    final old = WeatherCheckRecord(
      id: 'old',
      takenAt: DateTime(2026, 10, 1, 8),
      input: input,
      verdict: WeatherVerdict.go,
      rulesVersion: 1,
    );
    final pl = weatherCheckText(old, english: false);
    expect(pl, contains('! Szczegóły odtworzone inną wersją reguł'));
    expect(pl, contains('wiąże zapisany werdykt: Można spawać'));
    final doc = await WeatherCheckExport.buildPdfDocument(
      record: old,
      english: false,
      font: _font('Roboto-Regular.ttf'),
      generatedAt: DateTime(2026, 10, 17),
    );
    expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
  });

  test('nazwa pliku z datą i godziną', () {
    expect(weatherCheckFileName(takenAt: DateTime(2026, 1, 5, 7, 3)),
        'Warunki_spawania_2026-01-05_0703.pdf');
  });
}
