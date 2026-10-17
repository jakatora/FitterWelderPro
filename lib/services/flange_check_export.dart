/// Protokół odbioru połączenia kołnierzowego do udostępnienia: tekst
/// (komunikator, e-mail) i PDF (dla inspektora QC).
///
/// Ta sama mechanika co `hydrotest_export.dart` / `coupon_log_export.dart`:
/// Roboto z `assets/fonts/` (polskie znaki), atrament do druku zamiast
/// ciemnej palety ekranu, plik tymczasowy sprawdzony co do długości
/// i arkusz udostępniania systemu. Fonty przekazywane z zewnątrz, żeby test
/// renderował prawdziwą stronę.
///
///   * PURE — tekst protokołu, nazwa pliku, budowa dokumentu PDF.
///   * PLATFORM — [shareFlangeCheck]: zapis i arkusz udostępniania.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/flange/flange_check.dart';
import '../domain/flange/flange_labels.dart';

enum FlangeShareFormat { text, pdf }

/// Funkcja udostępniania wstrzykiwana do ekranu (test podmienia ją, żeby
/// nie wołać platformy).
typedef FlangeShareFn = Future<void> Function(
    FlangeCheck check, FlangeShareFormat format, bool en);

// ═══════════════════════════════════════════════════════════════════════════
// PURE HALF
// ═══════════════════════════════════════════════════════════════════════════

String _t(bool en, String pl, String e) => en ? e : pl;

/// Wiersze „etykieta: wartość” danych połączenia (puste pola pomijane
/// w tekście, w PDF jako „—”).
List<(String, String)> flangeJointRows(FlangeCheck c, {required bool en}) {
  final j = c.joint;
  final t = j.gasketThicknessMm;
  return [
    (_t(en, 'Oznaczenie', 'Tag'), j.tag),
    (_t(en, 'Średnica', 'Size'), j.dn == null ? '' : flangeSizeLabel(j.dn!)),
    (_t(en, 'Klasa / PN', 'Class / PN'), j.rating),
    (
      _t(en, 'Uszczelka', 'Gasket'),
      [
        j.gasketType.trim(),
        if (t != null && t > 0) formatLength(t, c.unit, en: en),
      ].where((s) => s.isNotEmpty).join(', ')
    ),
    (
      _t(en, 'Śruby', 'Bolting'),
      [
        if (j.boltCount != null) '${j.boltCount} ×',
        j.boltGrade.trim(),
      ].where((s) => s.isNotEmpty).join(' ')
    ),
    (_t(en, 'Miejsce / projekt', 'Location / project'), j.location),
    (_t(en, 'Monter', 'Fitter'), j.fitter),
    (_t(en, 'Data', 'Date'), j.date),
  ];
}

String _tolerancesNote(FlangeCheck c, {required bool en}) => c.tolerances.isPcc1
    ? _t(en, 'Tolerancje: $kPcc1Edition zał. E.',
        'Tolerances: $kPcc1Edition Appendix E.')
    : _t(en, 'Tolerancje: własne (specyfikacja zakładu), nie PCC-1.',
        'Tolerances: custom (plant specification), not PCC-1.');

String _unitNote(FlangeCheck c, {required bool en}) => c.unit == LengthUnit.mm
    ? _t(en, 'Pomiary w mm.', 'Measured in mm.')
    : _t(en, 'Pomiary w calach.', 'Measured in inches.');

/// Odczyty szczeliny: „0°: 3,1 · 90°: 3,4 · …” w jednostce protokołu.
String flangeGapReadings(FlangeCheck c, {required bool en}) {
  final gaps = c.measurements.gapsMm;
  return [
    for (final (i, g) in gaps.indexed)
      '${fmtNum(gapPointAngle(i, gaps.length), decimals: 0, en: en)}°: '
          '${g == null ? '—' : fieldText(g, c.unit, en: en)}'
  ].join(' · ');
}

/// Protokół jako zwykły tekst (WhatsApp, SMS, e-mail).
String buildFlangeCheckText(FlangeCheck c, {required bool en}) {
  final e = c.evaluate();
  final buf = StringBuffer()
    ..writeln(_t(en, 'PROTOKÓŁ ODBIORU POŁĄCZENIA KOŁNIERZOWEGO',
        'FLANGE JOINT ASSEMBLY CHECK'))
    ..writeln('${_t(en, 'Werdykt', 'Verdict')}: '
        '${protocolVerdictLabel(e.verdict, en: en)}');
  if (e.verdict == ProtocolVerdict.incomplete) {
    buf.writeln('(${missingSummary(e, en: en)})');
  }
  final looser = looserWarning(e.looserThanPcc1, en: en);
  if (looser != null) buf.writeln(looser);
  buf.writeln();
  for (final (k, v) in flangeJointRows(c, en: en)) {
    if (v.trim().isNotEmpty) buf.writeln('$k: $v');
  }
  buf
    ..writeln()
    ..writeln(_t(en, 'Osiowanie', 'Alignment'));
  for (final r in e.criteria) {
    buf.writeln('• ${criterionTitle(r.criterion, en: en)}: '
        '${criterionValueLine(c, r, en: en)} — '
        '${checkVerdictLabel(r.verdict, en: en)}');
  }
  buf
    ..writeln('  ${_t(en, 'Szczelina', 'Gap')} '
        '(${c.measurements.gapPointCount} ${_t(en, 'pkt', 'pts')}): '
        '${flangeGapReadings(c, en: en)}')
    ..writeln()
    ..writeln(_t(en, 'Montaż', 'Assembly'));
  for (final i in FlangeChecklistItem.values) {
    buf.writeln('${c.checked.contains(i) ? '[x]' : '[ ]'} '
        '${checklistTitle(i, en: en)}');
  }
  for (final p in e.problems) {
    buf.writeln('! ${problemLabel(p, en: en)}');
  }
  if (c.notes.trim().isNotEmpty) {
    buf
      ..writeln()
      ..writeln('${_t(en, 'Uwagi', 'Notes')}: ${c.notes.trim()}');
  }
  buf
    ..writeln()
    ..writeln('${_tolerancesNote(c, en: en)} ${_unitNote(c, en: en)}')
    ..write('Fitter Welder Pro');
  return buf.toString();
}

/// `Kolnierz_L-101-F1_2026-10-17.pdf` — bez znaków, które psują nazwy plików.
String flangeCheckFileName(FlangeCheck c, {required String extension}) {
  final cleaned = c.joint.tag
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[_.]+|[_.]+$'), '');
  final safe = cleaned.isEmpty ? 'protokol' : cleaned;
  final date = c.joint.date.isEmpty ? '' : '_${c.joint.date}';
  return 'Kolnierz_$safe$date.$extension';
}

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kOkInk = PdfColor.fromHex('#1E7A3C');
final PdfColor _kNokInk = PdfColor.fromHex('#B3261E');
final PdfColor _kWarnInk = PdfColor.fromHex('#8A5A00');

PdfColor _verdictInk(ProtocolVerdict v) => switch (v) {
      ProtocolVerdict.accepted => _kOkInk,
      ProtocolVerdict.rejected => _kNokInk,
      ProtocolVerdict.incomplete => _kWarnInk,
    };

PdfColor _checkInk(CheckVerdict v) => switch (v) {
      CheckVerdict.ok => _kOkInk,
      CheckVerdict.fail => _kNokInk,
      CheckVerdict.missing => _kInkMuted,
    };

/// Najdłuższy tekst pola danych połączenia w PDF (wiersz tabeli nie dzieli
/// się między strony — przesadnie długi wpis zablokowałby cały dokument).
const int kPdfFieldMaxChars = 300;

/// Najdłuższe uwagi w PDF; dłuższe są przycinane z dopiskiem (pełna treść
/// zostaje w aplikacji i w udostępnianym tekście).
const int kPdfNotesMaxChars = 20000;

String _clip(String s, int max, {required bool en}) => s.length <= max
    ? s
    : '${s.substring(0, max)}… ${_t(en, '(skrócono — pełna treść w aplikacji)', '(shortened — full text in the app)')}';

/// Słowo dłuższe niż linia strony (np. wklejony numer bez spacji) łamane
/// co [width] znaków — inaczej nie zmieści się w szerokości kolumny.
String _breakLongWords(String s, {int width = 60}) => s.replaceAllMapped(
    RegExp('\\S{${width + 1},}'),
    (m) => [
          for (var i = 0; i < m[0]!.length; i += width)
            m[0]!.substring(i, (i + width).clamp(0, m[0]!.length))
        ].join(' '));

/// Protokół A4 do podpisu. [pw.MultiPage]: długie uwagi przechodzą na
/// kolejne strony zamiast wywracać dokument („won't fit”).
pw.Document buildFlangeCheckPdf(
  FlangeCheck c, {
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
  final e = c.evaluate();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${generatedAt.year}-${two(generatedAt.month)}-'
      '${two(generatedAt.day)} ${two(generatedAt.hour)}:'
      '${two(generatedAt.minute)}';
  final small = pw.TextStyle(fontSize: 8, color: _kInkMuted);
  final body = pw.TextStyle(fontSize: 9.5, color: _kInk);
  final head =
      pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _kInk);
  final looser = looserWarning(e.looserThanPcc1, en: en);
  final notes = _clip(c.notes.trim(), kPdfNotesMaxChars, en: en);

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
    maxPages: 60,
    header: (ctx) => ctx.pageNumber == 1
        ? pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(
              border:
                  pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5)),
            ),
            child: pw.Text(
                _t(en, 'PROTOKÓŁ ODBIORU POŁĄCZENIA KOŁNIERZOWEGO',
                    'FLANGE JOINT ASSEMBLY CHECK'),
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _kInk)),
          )
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
                '${_t(en, 'Protokół odbioru kołnierza', 'Flange joint check')} '
                '${_clip(c.joint.tag.trim(), 60, en: en)}',
                style: small)),
    footer: (ctx) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
              '${_tolerancesNote(c, en: en)} ${_unitNote(c, en: en)} '
              '${_t(en, 'Granice w mm i calach jak w normie (nie są dokładnym przeliczeniem); ocena w jednostce pomiaru.', 'Limits in mm and inches as in the standard (not exact conversions); judged in the unit measured.')}',
              style: small),
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
          border: pw.Border.all(color: _verdictInk(e.verdict), width: 1.2),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
                '${_t(en, 'Werdykt', 'Verdict')}: '
                '${protocolVerdictLabel(e.verdict, en: en)}',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _verdictInk(e.verdict))),
            if (e.verdict == ProtocolVerdict.incomplete)
              pw.Text(missingSummary(e, en: en), style: small),
            if (looser != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text(looser,
                    style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _kNokInk)),
              ),
          ],
        ),
      ),
      section(_t(en, 'Dane połączenia', 'Joint data')),
      pw.Table(
        border: pw.TableBorder.all(color: _kRule, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(120),
          1: pw.FlexColumnWidth(),
        },
        children: [
          for (final (k, v) in flangeJointRows(c, en: en))
            pw.TableRow(children: [
              cell(k, style: head),
              cell(v.trim().isEmpty
                  ? '—'
                  : _breakLongWords(
                      _clip(v.trim(), kPdfFieldMaxChars, en: en))),
            ]),
        ],
      ),
      section(_t(en, 'Osiowanie', 'Alignment')),
      pw.Table(
        border: pw.TableBorder.all(color: _kRule, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.4),
          1: pw.FlexColumnWidth(1.6),
          2: pw.FixedColumnWidth(80),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _kHeadFill),
            children: [
              cell(_t(en, 'Kryterium', 'Criterion'), style: head),
              cell(_t(en, 'Pomiar ≤ granica', 'Measured ≤ limit'), style: head),
              cell(_t(en, 'Wynik', 'Result'), style: head),
            ],
          ),
          for (final r in e.criteria)
            pw.TableRow(children: [
              cell(criterionTitle(r.criterion, en: en)),
              cell(criterionValueLine(c, r, en: en)),
              cell(checkVerdictLabel(r.verdict, en: en),
                  style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _checkInk(r.verdict))),
            ]),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(
          '${_t(en, 'Szczelina', 'Gap')} '
          '(${c.measurements.gapPointCount} ${_t(en, 'pkt', 'pts')}, '
          '${c.unit == LengthUnit.mm ? 'mm' : 'in'}): '
          '${flangeGapReadings(c, en: en)}',
          style: small),
      section(_t(en, 'Montaż', 'Assembly')),
      pw.Table(
        border: pw.TableBorder.all(color: _kRule, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(36),
          1: pw.FlexColumnWidth(),
        },
        children: [
          for (final i in FlangeChecklistItem.values)
            pw.TableRow(children: [
              cell(c.checked.contains(i) ? _t(en, 'TAK', 'YES') : '—',
                  style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: c.checked.contains(i) ? _kOkInk : _kNokInk)),
              cell(checklistTitle(i, en: en)),
            ]),
        ],
      ),
      for (final p in e.problems)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text('! ${problemLabel(p, en: en)}',
              style: pw.TextStyle(fontSize: 9, color: _kNokInk)),
        ),
      if (notes.isNotEmpty) ...[
        section(_t(en, 'Uwagi', 'Notes')),
        // Akapit po akapicie; TextOverflow.span — tylko wtedy pw.Text dzieli
        // się między strony MultiPage (inaczej „won't fit”).
        for (final para in notes.split('\n')) ...[
          pw.Text(_breakLongWords(para),
              style: body, overflow: pw.TextOverflow.span),
          pw.SizedBox(height: 3),
        ],
      ],
      pw.SizedBox(height: 28),
      pw.Row(children: [
        signature(_t(en, 'Monter', 'Fitter')),
        pw.SizedBox(width: 32),
        signature(_t(en, 'Inspektor QC', 'QC inspector')),
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
Future<void> shareFlangeCheck(
    FlangeCheck c, FlangeShareFormat format, bool en) async {
  final subject = _t(en, 'Protokół odbioru kołnierza ${c.joint.tag}'.trim(),
      'Flange joint check ${c.joint.tag}'.trim());
  if (format == FlangeShareFormat.text) {
    await Share.share(buildFlangeCheckText(c, en: en), subject: subject);
    return;
  }
  final doc = buildFlangeCheckPdf(
    c,
    font: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
    boldFont:
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
    en: en,
    generatedAt: DateTime.now(),
  );
  final bytes = await doc.save();
  final name = flangeCheckFileName(c, extension: 'pdf');
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
