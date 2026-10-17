/// Ocena serii pomiarów twardości do udostępnienia: tekst (komunikator,
/// e-mail) i PDF (dla QC / do teczki WPQR).
///
/// Ta sama mechanika co `coupon_log_export.dart` / `flange_check_export.dart`:
/// Roboto z `assets/fonts/` (polskie znaki), atrament do druku, plik
/// tymczasowy sprawdzony co do długości, arkusz udostępniania systemu.
/// Fonty przekazywane z zewnątrz, żeby test renderował prawdziwą stronę.
///
///   * PURE — etykiety (wspólne z ekranem), tekst, nazwa pliku, PDF.
///   * PLATFORM — [shareHardness]: zapis i arkusz udostępniania.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/welding/hardness.dart';

enum HardnessShareFormat { text, pdf }

/// Wszystko, co trafia do protokołu: materiał, limit (preset albo własny)
/// i seria pomiarów. Werdykt liczony z tych danych, nie z ekranu.
class HardnessReport {
  final HardnessMaterial material;

  /// `null` — własny limit.
  final HardnessLimitPreset? preset;
  final HardnessLimit limit;
  final List<HardnessReading> readings;

  const HardnessReport({
    required this.material,
    required this.preset,
    required this.limit,
    required this.readings,
  });

  HardnessSeriesResult get result => evaluateHardnessSeries(readings, limit,
      material: material, preset: preset);
}

/// Funkcja udostępniania wstrzykiwana do ekranu (test podmienia ją, żeby
/// nie wołać platformy).
typedef HardnessShareFn = Future<void> Function(
    HardnessReport report, HardnessShareFormat format, bool en);

// ═══════════════════════════════════════════════════════════════════════════
// PURE HALF — etykiety wspólne z ekranem
// ═══════════════════════════════════════════════════════════════════════════

String _t(bool en, String pl, String e) => en ? e : pl;

String hardnessMaterialLabel(HardnessMaterial m, {required bool en}) =>
    switch (m) {
      HardnessMaterial.carbonLowAlloy => _t(en,
          'Stal niestopowa / niskostopowa', 'Unalloyed / low-alloy steel'),
      HardnessMaterial.stainless => _t(en,
          'Stal nierdzewna / austenityczna', 'Stainless / austenitic steel'),
    };

String hardnessStatusLabel(ReadingStatus s, {required bool en}) =>
    switch (s) {
      ReadingStatus.ok => 'OK',
      ReadingStatus.exceeded => _t(en, 'Przekroczony', 'Exceeded'),
      ReadingStatus.outOfRange =>
        _t(en, 'Poza zakresem tablicy', 'Outside the table'),
      ReadingStatus.notConvertible =>
        _t(en, 'Bez przeliczenia', 'Not convertible'),
      ReadingStatus.invalid => _t(en, 'Błędna wartość', 'Invalid value'),
      ReadingStatus.blank => _t(en, 'Brak wartości', 'No value'),
      ReadingStatus.noLimit => _t(en, 'Brak limitu', 'No limit'),
      ReadingStatus.limitNotForMaterial =>
        _t(en, 'Limit nie dla tego materiału', 'Limit not for this material'),
    };

/// Dlaczego preset nie pasuje do materiału — `null`, gdy pasuje (albo
/// własny limit). Ten sam tekst na ekranie, w tekście i w PDF.
String? hardnessPresetMismatchReason(
    HardnessLimitPreset? preset, HardnessMaterial material,
    {required bool en}) {
  if (hardnessPresetFitsMaterial(preset, material)) return null;
  return switch (preset!.material) {
    HardnessMaterial.carbonLowAlloy => _t(
        en,
        'Preset dotyczy stali węglowych/niskostopowych — wybierz własny limit '
            'ze specyfikacji.',
        'The preset is for carbon/low-alloy steels — choose a custom limit '
            'from the specification.'),
    HardnessMaterial.stainless => _t(
        en,
        'Preset dotyczy stali nierdzewnej — zmień materiał na nierdzewną '
            'albo wybierz własny limit ze specyfikacji.',
        'The preset is for stainless steel — switch the material to '
            'stainless or choose a custom limit from the specification.'),
  };
}

String hardnessVerdictTitle(SeriesVerdict v, {required bool en}) =>
    switch (v) {
      SeriesVerdict.pass => _t(en, 'ZGODNE — wszystkie pomiary w limicie',
          'PASS — all readings within the limit'),
      SeriesVerdict.fail =>
        _t(en, 'NIEZGODNE — limit przekroczony', 'FAIL — limit exceeded'),
      SeriesVerdict.incomplete => _t(
          en,
          'BRAK OCENY — nie wszystkie pomiary ocenione',
          'NOT RATED — not all readings could be rated'),
      SeriesVerdict.empty => _t(en, 'Brak pomiarów', 'No readings'),
      SeriesVerdict.invalidLimit =>
        _t(en, 'Nieprawidłowy limit', 'Invalid limit'),
    };

/// „max 250 HV”.
String hardnessLimitText(HardnessLimit l, {required bool en}) =>
    'max ${formatHardnessExact(l.value, en: en)} ${l.scale.label}';

/// Pomiar tak, jak wpisany: „22 HRC”.
String hardnessReadingValueText(HardnessReading r, {required bool en}) {
  final v = r.value;
  if (r.blank || v == null) return '—';
  return '${formatHardnessExact(v, en: en)} ${r.scale.label}';
}

/// Porównanie pomiaru z limitem, liczby zaokrąglone w stronę werdyktu:
///  • ta sama skala: „250 HV ≤ 250 HV”;
///  • przeliczone: „22 HRC ≈ 248,8 HV ≤ 250 HV”;
///  • porównanie w skali pomiaru: „200 HV ≤ 248,9 HV (≈ 22 HRC)”.
String hardnessCheckDetail(ReadingCheck c, HardnessLimit limit,
    {required bool en}) {
  final r = c.reading;
  final lim = '${formatHardnessExact(limit.value, en: en)} ${limit.scale.label}';
  switch (c.status) {
    case ReadingStatus.ok:
    case ReadingStatus.exceeded:
      final rel = c.isOk ? '≤' : '>';
      final v = r.value!;
      final measured = '${formatHardnessExact(v, en: en)} ${r.scale.label}';
      final x = c.inLimitScale;
      if (x != null && !c.converted) return '$measured $rel $lim';
      if (x != null) {
        return '$measured ≈ ${formatAgainstLimit(x, limit.value, en: en)} '
            '${limit.scale.label} $rel $lim';
      }
      final lm = c.limitInReadingScale!;
      return '$measured $rel ${formatLimitEquivalent(lm, v, en: en)} '
          '${r.scale.label} (≈ $lim)';
    case ReadingStatus.outOfRange:
      return _t(
          en,
          '${hardnessReadingValueText(r, en: en)} — poza zakresem tablicy '
              'ISO 18265; zmierz w skali limitu (${limit.scale.label})',
          '${hardnessReadingValueText(r, en: en)} — outside the ISO 18265 '
              'table; measure in the limit scale (${limit.scale.label})');
    case ReadingStatus.notConvertible:
      return _t(
          en,
          'Stal nierdzewna — nie przeliczaj; zmierz w ${limit.scale.label}',
          'Stainless steel — do not convert; measure in ${limit.scale.label}');
    case ReadingStatus.invalid:
      final v = r.value;
      if (v != null && v.isFinite && v > r.scale.maxPlausible) {
        final max = formatHardnessExact(r.scale.maxPlausible, en: en);
        return _t(
            en,
            '${hardnessReadingValueText(r, en: en)} — poza skalą '
                '${r.scale.label} (max $max); sprawdź wybraną skalę',
            '${hardnessReadingValueText(r, en: en)} — beyond the '
                '${r.scale.label} scale (max $max); check the selected scale');
      }
      return _t(en, 'Wpisz liczbę większą od 0, w zakresie skali',
          'Enter a number above 0, within the scale');
    case ReadingStatus.blank:
      return _t(en, 'Wpisz wartość albo usuń pomiar',
          'Enter a value or remove the reading');
    case ReadingStatus.noLimit:
      return _t(en, 'Ustaw poprawny limit', 'Set a valid limit');
    case ReadingStatus.limitNotForMaterial:
      return _t(
          en,
          '${hardnessReadingValueText(r, en: en)} — nie oceniono: preset nie '
              'dotyczy wybranego materiału',
          '${hardnessReadingValueText(r, en: en)} — not rated: the preset '
              'does not apply to the selected material');
  }
}

/// Maksimum serii w skali limitu, zaokrąglone w stronę werdyktu; „> limit”,
/// gdy przekroczony pomiar nie daje się wyrazić w skali limitu.
String? hardnessMaxText(HardnessSeriesResult r, {required bool en}) {
  final l = r.limit;
  if (r.maxAboveLimitUnknown) {
    return '> ${formatHardnessExact(l.value, en: en)} ${l.scale.label}';
  }
  final m = r.max;
  if (m == null) return null;
  return '${formatAgainstLimit(m, l.value, en: en)} ${l.scale.label}';
}

String? hardnessMeanText(HardnessSeriesResult r, {required bool en}) {
  final m = r.mean;
  if (m == null) return null;
  return '${formatAgainstLimit(m, r.limit.value, en: en)} ${r.limit.scale.label}';
}

String hardnessConversionNote({required bool en}) => _t(
    en,
    'Przeliczenia skal wg $kHardnessTableSourcePl — przybliżone, interpolacja '
        'liniowa, bez ekstrapolacji. Nie dotyczą stali nierdzewnych '
        'i austenitycznych. W razie sporu wiąże pomiar w skali wymaganej '
        'przez specyfikację.',
    'Scale conversions per $kHardnessTableSourceEn — approximate, linear '
        'interpolation, no extrapolation. Not valid for stainless and '
        'austenitic steels. In case of dispute the reading in the scale '
        'required by the specification governs.');

String _limitTitle(HardnessReport r, {required bool en}) {
  final p = r.preset;
  if (p == null) return _t(en, 'Własny limit', 'Custom limit');
  return en ? p.titleEn : p.titlePl;
}

String? _limitSource(HardnessReport r, {required bool en}) {
  final p = r.preset;
  if (p == null) return null;
  return en ? p.sourceEn : p.sourcePl;
}

String _location(HardnessReading r, int index, {required bool en}) {
  final l = r.location.trim();
  return l.isEmpty ? _t(en, 'Pomiar ${index + 1}', 'Reading ${index + 1}') : l;
}

/// Ocena jako zwykły tekst (WhatsApp, SMS, e-mail).
String buildHardnessText(HardnessReport report, {required bool en}) {
  final res = report.result;
  final buf = StringBuffer()
    ..writeln(_t(en, 'POMIAR TWARDOŚCI — OCENA', 'HARDNESS TEST — ASSESSMENT'))
    ..writeln('${_t(en, 'Werdykt', 'Verdict')}: '
        '${hardnessVerdictTitle(res.verdict, en: en)}');
  final mismatch =
      hardnessPresetMismatchReason(report.preset, report.material, en: en);
  if (mismatch != null) {
    buf.writeln('${_t(en, 'Powód', 'Reason')}: $mismatch');
  }
  buf
    ..writeln()
    ..writeln('${_t(en, 'Limit', 'Limit')}: '
        '${hardnessLimitText(report.limit, en: en)} — '
        '${_limitTitle(report, en: en)}');
  final src = _limitSource(report, en: en);
  if (src != null) buf.writeln('${_t(en, 'Źródło', 'Source')}: $src');
  buf
    ..writeln('${_t(en, 'Materiał', 'Material')}: '
        '${hardnessMaterialLabel(report.material, en: en)}')
    ..writeln()
    ..writeln(_t(en, 'Pomiary', 'Readings'));
  for (final (i, c) in res.checks.indexed) {
    buf.writeln('${i + 1}. ${_location(c.reading, i, en: en)}: '
        '${hardnessCheckDetail(c, report.limit, en: en)} — '
        '${hardnessStatusLabel(c.status, en: en)}');
  }
  final max = hardnessMaxText(res, en: en);
  final mean = hardnessMeanText(res, en: en);
  if (max != null) {
    buf
      ..writeln()
      ..writeln('Max: $max'
          '${mean == null ? '' : ' · ${_t(en, 'średnia', 'mean')}: $mean'}'
          ' (${res.statsCount} ${_t(en, 'z', 'of')} ${res.checks.length})');
  }
  if (res.convertedCount > 0) {
    buf.writeln(_t(en, 'Przeliczono skalę: ${res.convertedCount}',
        'Scale converted: ${res.convertedCount}'));
  }
  buf
    ..writeln()
    ..writeln(hardnessConversionNote(en: en))
    ..write('Fitter Welder Pro');
  return buf.toString();
}

/// `Twardosc_2026-10-17.pdf`.
String hardnessFileName(DateTime at, {required String extension}) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Twardosc_${at.year.toString().padLeft(4, '0')}-${two(at.month)}-'
      '${two(at.day)}.$extension';
}

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kOkInk = PdfColor.fromHex('#1E7A3C');
final PdfColor _kNokInk = PdfColor.fromHex('#B3261E');
final PdfColor _kWarnInk = PdfColor.fromHex('#8A5A00');

PdfColor _verdictInk(SeriesVerdict v) => switch (v) {
      SeriesVerdict.pass => _kOkInk,
      SeriesVerdict.fail => _kNokInk,
      SeriesVerdict.invalidLimit => _kNokInk,
      SeriesVerdict.incomplete => _kWarnInk,
      SeriesVerdict.empty => _kInkMuted,
    };

PdfColor _statusInk(ReadingStatus s) => switch (s) {
      ReadingStatus.ok => _kOkInk,
      ReadingStatus.exceeded => _kNokInk,
      _ => _kWarnInk,
    };

/// Najdłuższy opis miejsca pomiaru w PDF (wiersz tabeli nie dzieli się
/// między strony).
const int kHardnessPdfLocationMaxChars = 120;

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

/// Słowo dłuższe niż kolumna (np. wklejony numer bez spacji) łamane co
/// [width] znaków.
String _breakLongWords(String s, {int width = 30}) => s.replaceAllMapped(
    RegExp('\\S{${width + 1},}'),
    (m) => [
          for (var i = 0; i < m[0]!.length; i += width)
            m[0]!.substring(i, (i + width).clamp(0, m[0]!.length))
        ].join(' '));

/// Protokół A4. [pw.MultiPage] — długa seria przechodzi na kolejne strony.
pw.Document buildHardnessPdf(
  HardnessReport report, {
  required pw.Font font,
  pw.Font? boldFont,
  required bool en,
  required DateTime generatedAt,
}) {
  final bold = boldFont ?? font;
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
        base: font, bold: bold, italic: font, boldItalic: bold),
  );
  final res = report.result;
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${generatedAt.year}-${two(generatedAt.month)}-'
      '${two(generatedAt.day)} ${two(generatedAt.hour)}:'
      '${two(generatedAt.minute)}';
  final small = pw.TextStyle(fontSize: 8, color: _kInkMuted);
  final body = pw.TextStyle(fontSize: 9.5, color: _kInk);
  final head =
      pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _kInk);
  final src = _limitSource(report, en: en);
  final note = report.preset == null
      ? ''
      : (en ? report.preset!.noteEn : report.preset!.notePl);
  final max = hardnessMaxText(res, en: en);
  final mean = hardnessMeanText(res, en: en);
  final mismatch =
      hardnessPresetMismatchReason(report.preset, report.material, en: en);

  pw.Widget cell(String s, {pw.TextStyle? style}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(s, style: style ?? body),
      );

  pw.Widget section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
        child: pw.Text(title.toUpperCase(),
            style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: _kInkMuted,
                letterSpacing: 0.8)),
      );

  pw.Widget signature(String label) => pw.Expanded(
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
            pw.Container(height: 0.6, color: _kInk),
            pw.SizedBox(height: 2),
            pw.Text(label, style: small),
          ]));

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    maxPages: 40,
    header: (ctx) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5)),
      ),
      child: pw.Text(
          _t(en, 'POMIAR TWARDOŚCI — OCENA', 'HARDNESS TEST — ASSESSMENT'),
          style: pw.TextStyle(
              fontSize: 14, fontWeight: pw.FontWeight.bold, color: _kInk)),
    ),
    footer: (ctx) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(hardnessConversionNote(en: en), style: small),
          pw.SizedBox(height: 2),
          pw.Text(
              'Fitter Welder Pro  ·  $stamp  ·  '
              '${_t(en, 'Strona', 'Page')} ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: small),
        ],
      ),
    ),
    build: (_) => [
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _verdictInk(res.verdict), width: 1.2),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
                '${_t(en, 'Werdykt', 'Verdict')}: '
                '${hardnessVerdictTitle(res.verdict, en: en)}',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _verdictInk(res.verdict))),
            if (mismatch != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text('${_t(en, 'Powód', 'Reason')}: $mismatch',
                    style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _kWarnInk)),
              ),
            if (max != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text(
                    'Max: $max'
                    '${mean == null ? '' : '  ·  ${_t(en, 'średnia', 'mean')}: $mean'}'
                    '  (${res.statsCount} ${_t(en, 'z', 'of')} ${res.checks.length})',
                    style: body),
              ),
          ],
        ),
      ),
      section(_t(en, 'Limit i materiał', 'Limit and material')),
      pw.Table(
        border: pw.TableBorder.all(color: _kRule, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(110),
          1: pw.FlexColumnWidth(),
        },
        children: [
          pw.TableRow(children: [
            cell(_t(en, 'Limit', 'Limit'), style: head),
            cell('${hardnessLimitText(report.limit, en: en)} — '
                '${_limitTitle(report, en: en)}'),
          ]),
          if (src != null)
            pw.TableRow(children: [
              cell(_t(en, 'Źródło', 'Source'), style: head),
              cell(src),
            ]),
          if (note.isNotEmpty)
            pw.TableRow(children: [
              cell(_t(en, 'Uwagi do limitu', 'Limit notes'), style: head),
              cell(note),
            ]),
          pw.TableRow(children: [
            cell(_t(en, 'Materiał', 'Material'), style: head),
            cell(hardnessMaterialLabel(report.material, en: en)),
          ]),
        ],
      ),
      section(_t(en, 'Pomiary', 'Readings')),
      pw.Table(
        border: pw.TableBorder.all(color: _kRule, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(22),
          1: pw.FlexColumnWidth(1.2),
          2: pw.FlexColumnWidth(2.2),
          3: pw.FixedColumnWidth(78),
        },
        children: [
          pw.TableRow(
            repeat: true,
            decoration: pw.BoxDecoration(color: _kHeadFill),
            children: [
              cell(_t(en, 'Nr', 'No.'), style: head),
              cell(_t(en, 'Miejsce', 'Location'), style: head),
              cell(_t(en, 'Pomiar wobec limitu', 'Reading vs limit'),
                  style: head),
              cell(_t(en, 'Wynik', 'Result'), style: head),
            ],
          ),
          for (final (i, c) in res.checks.indexed)
            pw.TableRow(children: [
              cell('${i + 1}'),
              cell(_breakLongWords(_clip(_location(c.reading, i, en: en),
                  kHardnessPdfLocationMaxChars))),
              cell(hardnessCheckDetail(c, report.limit, en: en)),
              cell(hardnessStatusLabel(c.status, en: en),
                  style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _statusInk(c.status))),
            ]),
        ],
      ),
      pw.SizedBox(height: 28),
      pw.Row(children: [
        signature(_t(en, 'Wykonał pomiar', 'Tested by')),
        pw.SizedBox(width: 32),
        signature(_t(en, 'Kontrola QC', 'QC inspector')),
      ]),
    ],
  ));
  return doc;
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM HALF
// ═══════════════════════════════════════════════════════════════════════════

/// Domyślne udostępnianie: tekst przez arkusz systemu albo PDF z pliku
/// tymczasowego.
Future<void> shareHardness(
    HardnessReport report, HardnessShareFormat format, bool en) async {
  final subject = _t(en, 'Pomiar twardości — ocena', 'Hardness test');
  if (format == HardnessShareFormat.text) {
    await Share.share(buildHardnessText(report, en: en), subject: subject);
    return;
  }
  final now = DateTime.now();
  final doc = buildHardnessPdf(
    report,
    font: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
    boldFont:
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
    en: en,
    generatedAt: now,
  );
  final bytes = await doc.save();
  final name = hardnessFileName(now, extension: 'pdf');
  if (kIsWeb) {
    await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
        subject: subject);
    return;
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  if (!await file.exists() || (await file.length()) < 100) {
    throw StateError(
        'PDF zapisany niepoprawnie — sprawdź miejsce na dysku (${dir.path}).');
  }
  await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: subject);
}
