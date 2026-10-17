/// Protokół wejścia i spawania w przestrzeni zamkniętej jako PDF — dla
/// nadzoru i wydającego pozwolenie.
///
/// Te same zasady co eksport prac pożarowych: Roboto z `assets/fonts/`
/// (polskie znaki, indeksy O₂ / H₂S), czcionki podawane z zewnątrz, więc
/// test renderuje prawdziwe strony. Górna połowa czysta (budowa
/// dokumentu), dolna — platforma (plik tymczasowy + arkusz udostępniania).
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/confined_space/confined_space_checklist.dart';
import '../domain/confined_space/confined_space_gas.dart';
import '../domain/confined_space/confined_space_record.dart';
import '../domain/confined_space/confined_space_text.dart';

/// `Przestrzen_zamknieta_protokol_2026-10-17.pdf` (data pracy z protokołu).
String confinedSpaceFileName(ConfinedSpaceRecord r, {required bool english}) {
  final date = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(r.date) ? r.date : '';
  final base =
      english ? 'Confined_space_record' : 'Przestrzen_zamknieta_protokol';
  return date.isEmpty ? '$base.pdf' : '${base}_$date.pdf';
}

String confinedSpaceSubject({required bool english}) => english
    ? 'Confined space — entry and welding record'
    : 'Przestrzeń zamknięta — protokół wejścia i spawania';

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kWarnFill = PdfColor.fromHex('#FFF4DC');
final PdfColor _kFail = PdfColor.fromHex('#C0392B');

class ConfinedSpaceExport {
  const ConfinedSpaceExport._();

  static Future<void> sharePdf(ConfinedSpaceRecord record,
      {required bool english}) async {
    final doc = await buildPdfDocument(
      record: record,
      english: english,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: DateTime.now(),
    );
    final bytes = await doc.save();
    final name = confinedSpaceFileName(record, english: english);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: confinedSpaceSubject(english: english),
    );
  }

  static Future<pw.Document> buildPdfDocument({
    required ConfinedSpaceRecord record,
    required bool english,
    required pw.Font font,
    pw.Font? boldFont,
    required DateTime generatedAt,
  }) async {
    final en = english;
    final r = record;
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
          base: font, bold: bold, italic: font, boldItalic: bold),
    );
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${generatedAt.year}-${two(generatedAt.month)}-'
        '${two(generatedAt.day)} ${two(generatedAt.hour)}:'
        '${two(generatedAt.minute)}';
    final a = r.assess();
    final statusColor = a.readiness == CsReadiness.stop ? _kFail : _kInk;

    pw.Widget cell(String t,
            {bool head = false, PdfColor? color, double size = 8}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.all(3.5),
          child: _pdfText(t,
              style: pw.TextStyle(
                  fontSize: size,
                  fontWeight: head ? pw.FontWeight.bold : null,
                  color: color ?? _kInk)),
        );

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: _pdfText(t,
              style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _kInk)),
        );

    pw.Widget table(List<CsLine> lines) => pw.Table(
          border: pw.TableBorder.all(color: _kRule, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(150),
            1: pw.FlexColumnWidth(),
          },
          children: [
            for (final l in lines)
              pw.TableRow(children: [
                pw.Container(
                  color: _kHeadFill,
                  child: cell(l.label, head: true, size: 8.5),
                ),
                cell(l.value, size: 8.5),
              ]),
          ],
        );

    pw.Widget readingCell(CsMeasurement m, CsGas g) {
      final q = m[g];
      if (q == null) return cell('—');
      final s = csReadingState(g, q, r.limits);
      return cell(
        '${formatCsQty(g, q, en: en)}\n${csStateLabel(s, g, en: en)}',
        head: s.stop,
        color: s.stop ? _kFail : _kInk,
      );
    }

    final checklist = <pw.Widget>[];
    for (final phase in ConfinedSpacePhase.values) {
      final checks = confinedSpaceChecksIn(phase);
      final done = checks.where(r.isSettled).length;
      checklist
          .add(heading('${phase.label(en: en)} ($done/${checks.length})'));
      checklist.add(pw.Table(
        border: pw.TableBorder.all(color: _kRule, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(36),
          1: pw.FlexColumnWidth(),
        },
        children: [
          for (final g in confinedSpaceGroupsIn(phase)) ...[
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _kHeadFill),
              children: [
                cell(''),
                cell(g.label(en: en), head: true, size: 8),
              ],
            ),
            for (final c in confinedSpaceChecksInGroup(g))
              pw.TableRow(children: [
                cell(_markPdf(r, c, en: en),
                    head: true, color: r.isSettled(c) ? _kInk : _kFail),
                cell('${c.label(en: en)}  [${c.source}]'),
              ]),
          ],
        ],
      ));
    }

    final warnings = confinedSpaceWarnings(r.processes);

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
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: _pdfText(
                  en
                      ? 'Confined space — entry and welding record'
                      : 'Przestrzeń zamknięta — protokół wejścia i spawania',
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: _kInk)),
            ),
            pw.SizedBox(width: 8),
            _pdfText(
                '${en ? 'Page' : 'Strona'} ${ctx.pageNumber} / '
                '${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: _kInkMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: _pdfText(
          'Fitter Welder Pro  ·  $stamp  ·  '
          '${en ? 'checklist aid, not a permit' : 'lista pomocnicza, nie pozwolenie'}',
          style: pw.TextStyle(fontSize: 7, color: _kInkMuted),
        ),
      ),
      build: (_) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: _kWarnFill,
            border: pw.Border.all(color: _kAccent, width: 0.8),
          ),
          child: _pdfText(confinedSpaceDisclaimer(en: en),
              style: pw.TextStyle(fontSize: 8.5, color: _kInk)),
        ),
        pw.SizedBox(height: 8),
        table(confinedSpaceLines(r, en: en)),
        pw.SizedBox(height: 6),
        _pdfText(
          '${en ? 'Status' : 'Stan'}: '
          '${confinedSpaceReadinessText(a, r.limits, en: en)}',
          style: pw.TextStyle(
              fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: statusColor),
        ),
        for (final v in a.stops.skip(1))
          _pdfText('STOP — ${csStopText(v, r.limits, en: en)}',
              style: pw.TextStyle(fontSize: 8.5, color: _kFail)),
        for (final v in a.ties)
          _pdfText(csTieText(v, en: en),
              style: pw.TextStyle(fontSize: 8.5, color: _kFail)),
        heading(en ? 'Gas limits' : 'Progi gazów'),
        table(confinedSpaceLimitLines(r, en: en)),
        heading(en ? 'Gas readings' : 'Pomiary atmosfery'),
        if (r.measurements.isEmpty)
          _pdfText(en ? '— no reading —' : '— brak pomiaru —',
              style: pw.TextStyle(fontSize: 8.5, color: _kFail))
        else
          pw.Table(
            border: pw.TableBorder.all(color: _kRule, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(40),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(),
              3: pw.FlexColumnWidth(),
              4: pw.FlexColumnWidth(),
              5: pw.FlexColumnWidth(),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _kHeadFill),
                children: [
                  cell(en ? 'Time' : 'Godz.', head: true),
                  cell(en ? 'Place / level' : 'Miejsce / poziom', head: true),
                  for (final g in CsGas.values)
                    cell(g.label(en: en), head: true),
                ],
              ),
              for (final m in r.measurementsChrono)
                pw.TableRow(children: [
                  cell(m.time.isEmpty ? '—' : m.time),
                  cell(m.place.trim().isEmpty ? '—' : m.place.trim()),
                  for (final g in CsGas.values) readingCell(m, g),
                ]),
            ],
          ),
        heading(en ? 'Warnings for the welder' : 'Ostrzeżenia dla spawacza'),
        for (final w in warnings)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: _pdfText('• ${w.label(en: en)}  [${w.source}]',
                style: pw.TextStyle(fontSize: 8, color: _kInk)),
          ),
        ...checklist,
        if (r.notes.trim().isNotEmpty) ...[
          heading(en ? 'Notes' : 'Uwagi'),
          _pdfText(r.notes.trim(),
              style: pw.TextStyle(fontSize: 8.5, color: _kInk)),
        ],
        heading(en ? 'Signatures' : 'Podpisy'),
        pw.Row(children: [
          for (final (role, name) in [
            (en ? 'Entrants' : 'Wchodzący', r.entrants),
            (en ? 'Attendant' : 'Asekurujący', r.attendant),
            (en ? 'Supervisor' : 'Nadzór', r.supervisor),
            (en ? 'Permit issuer' : 'Wydający', r.issuer),
          ])
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                padding: const pw.EdgeInsets.all(6),
                height: 62,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _kRule, width: 0.5)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _pdfText(role,
                        style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _kInk)),
                    if (name.trim().isNotEmpty)
                      _pdfText(name.trim(),
                          style: pw.TextStyle(fontSize: 7.5, color: _kInk)),
                  ],
                ),
              ),
            ),
        ]),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kRule, width: 0.5)),
          child: _pdfText(
            en
                ? 'All out at: ______   Headcount checked by: ______   '
                    'Permit closed, signature: ____________________'
                : 'Wszyscy wyszli, godz.: ______   Stan osób sprawdził: '
                    '______   Pozwolenie zamknięte, podpis: ________________',
            style: pw.TextStyle(fontSize: 8, color: _kInk),
          ),
        ),
      ],
    ));
    return doc;
  }
}

/// Roboto z `assets/fonts/` nie ma indeksu dolnego „₂” — w PDF „O₂”,
/// „H₂S”, „CO₂” piszemy zwykłą dwójką (na ekranie zostaje indeks).
String confinedSpacePdfSafe(String s) => s.replaceAll('₂', '2');

pw.Widget _pdfText(String s, {pw.TextStyle? style}) =>
    pw.Text(confinedSpacePdfSafe(s), style: style);

/// Oznaczenie w PDF — słowem, nie znakiem (Roboto nie ma ☑).
String _markPdf(ConfinedSpaceRecord r, ConfinedSpaceCheck c,
    {required bool en}) {
  if (r.isChecked(c)) return en ? 'YES' : 'TAK';
  if (r.isNa(c)) return en ? 'n/a' : 'n/d';
  return en ? 'NO' : 'NIE';
}
