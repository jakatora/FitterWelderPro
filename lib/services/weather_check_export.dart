/// Pomiar „Warunki do spawania” jako tekst (komunikator, e-mail) i PDF
/// (dla nadzoru / QC).
///
/// Te same zasady co eksport planu PWHT i logu kuponów: Roboto
/// z `assets/fonts/` (polskie znaki), czcionki podawane z zewnątrz, więc test
/// renderuje prawdziwe strony. Górna połowa czysta, dolna — platforma.
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/welding/weather_conditions.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PURE HALF
// ═══════════════════════════════════════════════════════════════════════════

String _tr(bool en, String pl, String eng) => en ? eng : pl;
String _n(double v, bool en, [int d = 1]) =>
    weatherNum(v, decimals: d, english: en);

/// Wartość wpisana / próg — z precyzją pola (do 2 miejsc, bez zbędnych zer).
String _v(double v, bool en) => weatherNumAuto(v, english: en);
String _two(int v) => v.toString().padLeft(2, '0');

/// `2026-10-17 07:05`.
String weatherStamp(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

/// `Warunki_spawania_2026-10-17_0705.pdf`.
String weatherCheckFileName({required DateTime takenAt}) =>
    'Warunki_spawania_${takenAt.year}-${_two(takenAt.month)}-'
    '${_two(takenAt.day)}_${_two(takenAt.hour)}${_two(takenAt.minute)}.pdf';

String weatherCheckSubject({required bool english}) =>
    _tr(english, 'Warunki do spawania', 'Welding conditions');

String weatherDisclaimer({required bool english}) => _tr(
    english,
    'Ocena pomocnicza z danych wpisanych ręcznie — nie zastępuje WPS, '
        'specyfikacji projektu ani decyzji nadzoru / QC. Wymagania norm podano '
        'w skrócie, z oznaczeniem wydania i punktu; wiąże tekst normy '
        'wskazanej w kontrakcie.',
    'Advisory check from manually entered data — it does not replace the '
        'WPS, the project specification or the supervisor’s / QC decision. '
        'Code requirements are summarised with edition and clause; the code '
        'named in the contract governs.');

/// Zapas nad punktem rosy z tą samą precyzją co w tekście warunku (tyle
/// miejsc, żeby relacja do wymaganego zapasu była widoczna).
String weatherMarginText(WeatherAssessment a, {required bool english}) =>
    weatherPair(a.marginK, a.thresholds.dewMarginK, english: english).$1;

/// Wiatr: w jednostce wpisanej przez spawacza, druga w nawiasie, stopień
/// Beauforta. Prędkości zaokrąglone W GÓRĘ (m/s do 2 miejsc, km/h do 1) —
/// raport nigdy nie zaniża wiatru.
String weatherWindText(WeatherInput i, {required bool english}) {
  final ms = '${weatherNumAuto(ceilTo(i.windMs, 2), english: english)} m/s';
  final kmh =
      '${weatherNumAuto(ceilTo(msToKmh(i.windMs), 1), maxDecimals: 1, english: english)} km/h';
  final first = i.windUnit == WindUnit.ms ? '$ms ($kmh)' : '$kmh ($ms)';
  return '$first · ${beaufortText(i.windMs, english: english)}';
}

/// Wiersze „pomiar” (etykieta, wartość).
List<(String, String)> weatherInputRows(WeatherAssessment a,
    {required bool english}) {
  final i = a.input;
  final en = english;
  return [
    (
      _tr(en, 'Temperatura powietrza', 'Air temperature'),
      '${_v(i.ambientC, en)} °C'
    ),
    (
      _tr(en, 'Wilgotność względna', 'Relative humidity'),
      '${_v(i.rhPct, en)} %'
    ),
    (
      _tr(en, 'Temperatura powierzchni', 'Surface temperature'),
      a.surfaceAssumed
          ? '${_v(a.surfaceC, en)} °C — ${_tr(en, 'założenie: = powietrze (brak pomiaru)', 'assumed: = air (not measured)')}'
          : '${_v(a.surfaceC, en)} °C — ${_tr(en, 'pomiar kontaktowy', 'contact measurement')}'
    ),
    (
      _tr(en, 'Stan powierzchni złącza', 'Joint surface'),
      i.surfaceState.label(en)
    ),
    (_tr(en, 'Wiatr', 'Wind'), weatherWindText(i, english: en)),
    (_tr(en, 'Opad', 'Precipitation'), i.precipitation.label(en)),
    (_tr(en, 'Metoda', 'Process'), i.process.label(en)),
    (_tr(en, 'Osłona', 'Shelter'), i.shelter.label(en)),
    (_tr(en, 'Materiał', 'Material'), i.material.label(en)),
    (
      _tr(en, 'Podgrzewanie z WPS', 'Preheat from WPS'),
      i.wpsPreheatC == null ? '—' : '${_v(i.wpsPreheatC!, en)} °C'
    ),
  ];
}

/// Wiersze „wyniki”. Temperatury do osiągnięcia — w górę ([weatherNumMin]).
List<(String, String)> weatherResultRows(WeatherAssessment a,
    {required bool english}) {
  final en = english;
  return [
    (_tr(en, 'Punkt rosy', 'Dew point'), '${_n(a.dewPointC, en)} °C'),
    if (a.frostPointC != null)
      (_tr(en, 'Punkt szronu', 'Frost point'), '${_n(a.frostPointC!, en)} °C'),
    (
      _tr(en, 'Zapas powierzchni nad punktem rosy', 'Surface above dew point'),
      '${weatherMarginText(a, english: en)} K'
    ),
    (
      _tr(en, 'Min. temperatura materiału', 'Min. base metal temperature'),
      '${weatherNumMin(a.requiredMaterialC, english: en)} °C'
    ),
    (
      _tr(en, 'Złącze utrzymywać co najmniej', 'Keep the joint at least at'),
      '${weatherNumMin(a.targetSurfaceC, english: en)} °C'
    ),
  ];
}

/// Pełny tekst pomiaru do udostępnienia.
String weatherCheckText(WeatherCheckRecord r, {required bool english}) {
  final en = english;
  final a = r.assessment;
  final b = StringBuffer()
    ..writeln(_tr(en, 'WARUNKI DO SPAWANIA', 'WELDING CONDITIONS'))
    ..writeln(weatherStamp(r.takenAt));
  if (r.place.trim().isNotEmpty) {
    b.writeln('${_tr(en, 'Miejsce', 'Location')}: ${r.place.trim()}');
  }
  b.writeln(
      '${_tr(en, 'Werdykt', 'Verdict')}: ${weatherVerdictText(r.verdict, english: en).toUpperCase()}');
  final looser = weatherLooserWarning(r.thresholds, english: en);
  if (looser != null) b.writeln('!!! $looser');
  final mismatch = weatherRulesMismatchText(r, english: en);
  if (mismatch != null) b.writeln('! $mismatch');
  if (a == null) {
    b
      ..writeln()
      ..writeln(weatherDisclaimer(english: en));
    return b.toString().trimRight();
  }
  b
    ..writeln()
    ..writeln(_tr(en, 'Pomiar:', 'Measurement:'));
  for (final (k, v) in weatherInputRows(a, english: en)) {
    b.writeln('• $k: $v');
  }
  b
    ..writeln()
    ..writeln(_tr(en, 'Wyniki:', 'Results:'));
  for (final (k, v) in weatherResultRows(a, english: en)) {
    b.writeln('• $k: $v');
  }
  if (a.stops.isNotEmpty) {
    b
      ..writeln()
      ..writeln(_tr(en, 'Nie spawać, bo:', 'Do not weld because:'));
    for (final f in a.stops) {
      b
        ..writeln('✗ ${f.text(en)}')
        ..writeln('  ${_tr(en, 'Podstawa', 'Basis')}: ${f.basisText(en)}');
    }
  }
  if (a.conditions.isNotEmpty) {
    b
      ..writeln()
      ..writeln(_tr(en, 'Warunki do spełnienia:', 'Conditions to meet:'));
    for (final f in a.conditions) {
      final box = r.checked.contains(f.code) ? '[x]' : '[ ]';
      b
        ..writeln('$box ${f.text(en)}')
        ..writeln('    ${_tr(en, 'Podstawa', 'Basis')}: ${f.basisText(en)}');
    }
  }
  if (a.passed.isNotEmpty) {
    b
      ..writeln()
      ..writeln(_tr(en, 'Sprawdzone — OK:', 'Checked — OK:'));
    for (final f in a.passed) {
      b.writeln('• ${f.text(en)}');
    }
  }
  if (a.recommendations.isNotEmpty) {
    b
      ..writeln()
      ..writeln(_tr(en, 'Zalecenia:', 'Recommendations:'));
    for (final f in a.recommendations) {
      b.writeln('• ${f.text(en)}');
    }
  }
  if (!r.thresholds.isDefault) {
    b
      ..writeln()
      ..writeln(_tr(
          en,
          'Progi zmienione względem domyślnych (wg specyfikacji):',
          'Thresholds changed from the defaults (per specification):'));
    for (final (k, v) in weatherThresholdRows(r.thresholds, english: en)) {
      b.writeln('• $k: $v');
    }
  }
  b
    ..writeln()
    ..writeln(weatherDisclaimer(english: en));
  return b.toString().trimRight();
}

/// Progi jako wiersze (do raportu, gdy różnią się od domyślnych) — z tą
/// samą precyzją co w polach ustawień (do 4 miejsc, bez zbędnych zer).
List<(String, String)> weatherThresholdRows(WeatherThresholds t,
    {required bool english}) {
  final looser = looserThanDefaults(t);
  return [
    for (final f in ThresholdField.all)
      (
        thresholdLabel(f, english: english),
        '${weatherNumAuto(t.valueOf(f), maxDecimals: 4, english: english)} '
            '${thresholdUnit(f)}'
            '${looser.contains(f) ? _tr(english, ' (łagodniej niż norma)', ' (looser than the code)') : ''}'
      ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM HALF
// ═══════════════════════════════════════════════════════════════════════════

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kWarnFill = PdfColor.fromHex('#FFF4DC');
final PdfColor _kOkInk = PdfColor.fromHex('#1E7A3C');
final PdfColor _kWarnInk = PdfColor.fromHex('#8A5A00');
final PdfColor _kNokInk = PdfColor.fromHex('#B3261E');

class WeatherCheckExport {
  const WeatherCheckExport._();

  static Future<void> sharePdf(WeatherCheckRecord record,
      {required bool english, bool Function()? mayShare}) async {
    if (mayShare != null && !mayShare()) return;
    final doc = await buildPdfDocument(
      record: record,
      english: english,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: DateTime.now(),
    );
    if (mayShare != null && !mayShare()) return;
    final bytes = await doc.save();
    if (mayShare != null && !mayShare()) return;
    final name = weatherCheckFileName(takenAt: record.takenAt);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    if (!await file.exists() || (await file.length()) < 100) {
      throw StateError(
          'PDF zapisany niepoprawnie — sprawdź miejsce na dysku (${dir.path}).');
    }
    if (mayShare != null && !mayShare()) return;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: weatherCheckSubject(english: english),
    );
  }

  static Future<pw.Document> buildPdfDocument({
    required WeatherCheckRecord record,
    required bool english,
    required pw.Font font,
    pw.Font? boldFont,
    required DateTime generatedAt,
  }) async {
    final en = english;
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
          base: font, bold: bold, italic: font, boldItalic: bold),
    );
    final a = record.assessment;
    final verdictInk = switch (record.verdict) {
      WeatherVerdict.go => _kOkInk,
      WeatherVerdict.conditional => _kWarnInk,
      WeatherVerdict.noGo => _kNokInk,
    };

    pw.Widget table(List<(String, String)> rows) => pw.Table(
          border: pw.TableBorder.all(color: _kRule, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(170),
            1: pw.FlexColumnWidth(),
          },
          children: [
            for (final (k, v) in rows)
              pw.TableRow(children: [
                pw.Container(
                  color: _kHeadFill,
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(k,
                      style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _kInk)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(v,
                      style: pw.TextStyle(fontSize: 8.5, color: _kInk)),
                ),
              ]),
          ],
        );

    pw.Widget heading(String s) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Text(s,
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kInk)),
        );

    pw.Widget item(WeatherFinding f, String mark, PdfColor ink) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 22,
                child: pw.Text(mark,
                    style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: ink)),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(f.text(en),
                        style: pw.TextStyle(fontSize: 8.5, color: _kInk)),
                    if (f.basis.isNotEmpty)
                      pw.Text(
                          '${_tr(en, 'Podstawa', 'Basis')}: ${f.basisText(en)}',
                          style: pw.TextStyle(fontSize: 7, color: _kInkMuted)),
                  ],
                ),
              ),
            ],
          ),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 20,
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        margin: const pw.EdgeInsets.only(bottom: 10),
        decoration: pw.BoxDecoration(
            border:
                pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(weatherCheckSubject(english: en),
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _kInk)),
            pw.Text(
                '${_tr(en, 'Strona', 'Page')} ${ctx.pageNumber} / '
                '${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: _kInkMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Fitter Welder Pro  ·  ${weatherStamp(generatedAt)}',
          style: pw.TextStyle(fontSize: 7, color: _kInkMuted),
        ),
      ),
      build: (_) => [
        table([
          (
            _tr(en, 'Data i godzina pomiaru', 'Date and time'),
            weatherStamp(record.takenAt)
          ),
          (
            _tr(en, 'Miejsce / opis', 'Location / description'),
            record.place.trim().isEmpty ? '—' : record.place.trim()
          ),
        ]),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: verdictInk, width: 1.2),
          ),
          child: pw.Text(
            weatherVerdictText(record.verdict, english: en).toUpperCase(),
            style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: verdictInk),
          ),
        ),
        for (final note in [
          weatherLooserWarning(record.thresholds, english: en),
          weatherRulesMismatchText(record, english: en),
        ])
          if (note != null)
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 6),
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                color: _kWarnFill,
                border: pw.Border.all(color: _kNokInk, width: 1),
              ),
              child: pw.Text(note,
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: _kNokInk)),
            ),
        if (a != null) ...[
          heading(_tr(en, 'Pomiar', 'Measurement')),
          table(weatherInputRows(a, english: en)),
          heading(_tr(en, 'Wyniki', 'Results')),
          table(weatherResultRows(a, english: en)),
          if (a.stops.isNotEmpty) ...[
            heading(_tr(en, 'Nie spawać, bo', 'Do not weld because')),
            for (final f in a.stops) item(f, 'X', _kNokInk),
          ],
          if (a.conditions.isNotEmpty) ...[
            heading(_tr(en, 'Warunki do spełnienia', 'Conditions to meet')),
            for (final f in a.conditions)
              item(f, record.checked.contains(f.code) ? '[x]' : '[ ]',
                  _kWarnInk),
          ],
          if (a.passed.isNotEmpty) ...[
            heading(_tr(en, 'Sprawdzone — OK', 'Checked — OK')),
            for (final f in a.passed) item(f, 'OK', _kOkInk),
          ],
          if (a.recommendations.isNotEmpty) ...[
            heading(_tr(en, 'Zalecenia', 'Recommendations')),
            for (final f in a.recommendations) item(f, '•', _kInkMuted),
          ],
          if (!record.thresholds.isDefault) ...[
            heading(_tr(en, 'Progi wg specyfikacji (zmienione)',
                'Thresholds per specification (changed)')),
            table(weatherThresholdRows(record.thresholds, english: en)),
          ],
        ],
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: _kWarnFill,
            border: pw.Border.all(color: _kAccent, width: 0.8),
          ),
          child: pw.Text(weatherDisclaimer(english: en),
              style: pw.TextStyle(fontSize: 8, color: _kInk)),
        ),
        pw.SizedBox(height: 16),
        pw.Row(children: [
          for (final role in en
              ? const ['Measured by (welder)', 'Supervisor', 'QC / Inspector']
              : const ['Pomiar (spawacz)', 'Nadzór', 'Kontrola jakości / QC'])
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                padding: const pw.EdgeInsets.all(6),
                height: 46,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _kRule, width: 0.5)),
                child: pw.Text(role,
                    style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _kInk)),
              ),
            ),
        ]),
      ],
    ));
    return doc;
  }
}
