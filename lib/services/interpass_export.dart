/// Protokół temperatury podgrzania i międzyściegowej jednej spoiny jako PDF
/// — dowód dla QC.
///
/// Te same zasady co eksport prac pożarowych: Roboto z `assets/fonts/`
/// (polskie znaki), czcionki podawane z zewnątrz, więc test renderuje
/// prawdziwe strony. Górna połowa czysta (budowa dokumentu), dolna —
/// platforma (plik tymczasowy + arkusz udostępniania).
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/welding/interpass_log.dart';
import '../domain/welding/interpass_text.dart';

/// `Temperatura_miedzysciegowa_S-12_2026-10-17.pdf` (nr spoiny, data
/// pierwszego pomiaru albo utworzenia).
String interpassFileName(InterpassWeld w, {required bool english}) {
  final base = english ? 'Interpass_record' : 'Temperatura_miedzysciegowa';
  final no = w.weldNo
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final chrono = w.readingsChrono;
  final ms = chrono.isNotEmpty ? chrono.first.at : w.createdAt;
  final date =
      ms > 0 ? interpassDate(DateTime.fromMillisecondsSinceEpoch(ms)) : '';
  final stem = [base, if (no.isNotEmpty) no, if (date.isNotEmpty) date];
  return '${stem.join('_')}.pdf';
}

String interpassSubject({required bool english}) => english
    ? 'Preheat and interpass temperature record'
    : 'Protokół temperatury podgrzania i międzyściegowej';

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kWarnFill = PdfColor.fromHex('#FFF4DC');
final PdfColor _kFail = PdfColor.fromHex('#C0392B');
final PdfColor _kPass = PdfColor.fromHex('#1E8E5A');

class InterpassExport {
  const InterpassExport._();

  static Future<void> sharePdf(InterpassWeld weld,
      {required bool english, required InterpassUnit unit}) async {
    final doc = await buildPdfDocument(
      weld: weld,
      english: english,
      unit: unit,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: DateTime.now(),
    );
    final bytes = await doc.save();
    final name = interpassFileName(weld, english: english);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: interpassSubject(english: english),
    );
  }

  static Future<pw.Document> buildPdfDocument({
    required InterpassWeld weld,
    required bool english,
    required InterpassUnit unit,
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
    final stamp = '${interpassDate(generatedAt)} ${interpassTime(generatedAt)}';
    final a = weld.assess();
    final rows = interpassReadingRows(weld, unit, en: en);
    final minNote = interpassMinUnsetNote(a, unit, en: en);
    final status = a.status;
    final statusColor = status == InterpassWeldStatus.outOfLimits
        ? _kFail
        : status == InterpassWeldStatus.ok
            ? _kPass
            : _kInk;

    pw.Widget cell(String t,
            {bool head = false, PdfColor? color, double size = 8}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.all(3.5),
          child: pw.Text(t,
              style: pw.TextStyle(
                  fontSize: size,
                  fontWeight: head ? pw.FontWeight.bold : null,
                  color: color ?? _kInk)),
        );

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Text(t,
              style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _kInk)),
        );

    PdfColor checkColor(InterpassReading r) {
      final c = a.checkOf(r);
      if (!a.isDecisive(r)) return _kInkMuted;
      return switch (c) {
        InterpassCheck.low || InterpassCheck.high => _kFail,
        InterpassCheck.ok => _kPass,
        _ => _kInk,
      };
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 40,
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
              child: pw.Text(interpassSubject(english: en),
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: _kInk)),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
                '${en ? 'Page' : 'Strona'} ${ctx.pageNumber} / '
                '${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: _kInkMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Fitter Welder Pro  ·  $stamp  ·  '
          '${en ? 'record aid — limits per WPS' : 'rejestr pomocniczy — limity wg WPS'}',
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
          child: pw.Text(interpassDisclaimer(en: en),
              style: pw.TextStyle(fontSize: 8.5, color: _kInk)),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _kRule, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(150),
            1: pw.FlexColumnWidth(),
          },
          children: [
            for (final l in interpassWeldLines(weld, unit, en: en))
              pw.TableRow(children: [
                pw.Container(
                  color: _kHeadFill,
                  child: cell(l.label, head: true, size: 8.5),
                ),
                cell(l.value, size: 8.5),
              ]),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          '${en ? 'Verdict' : 'Werdykt'}: ${interpassStatusText(a, en: en)}',
          style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: statusColor),
        ),
        heading(
            en ? 'Readings (in time order)' : 'Pomiary (w kolejności czasu)'),
        if (a.chrono.isEmpty)
          pw.Text(en ? '— no readings —' : '— brak pomiarów —',
              style: pw.TextStyle(fontSize: 8.5, color: _kFail))
        else
          pw.Table(
            border: pw.TableBorder.all(color: _kRule, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(38),
              1: pw.FixedColumnWidth(78),
              2: pw.FixedColumnWidth(66),
              3: pw.FixedColumnWidth(52),
              4: pw.FixedColumnWidth(78),
              5: pw.FlexColumnWidth(),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _kHeadFill),
                children: [
                  cell(en ? 'Pass' : 'Ścieg', head: true),
                  cell(en ? 'Date, time' : 'Data, godzina', head: true),
                  cell(en ? 'Temperature' : 'Temperatura', head: true),
                  cell(en ? 'Method' : 'Metoda', head: true),
                  cell(en ? 'Assessment' : 'Ocena', head: true),
                  cell(en ? 'Notes' : 'Uwagi', head: true),
                ],
              ),
              // Te same wiersze co w protokole tekstowym (test PDF je czyta).
              for (final (i, row) in rows.indexed)
                pw.TableRow(children: [
                  for (final (j, text) in row.indexed)
                    j == 4
                        ? cell(text,
                            head: a.isDecisive(a.chrono[i]),
                            color: checkColor(a.chrono[i]))
                        : cell(text),
                ]),
            ],
          ),
        if (minNote != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(minNote,
                style: pw.TextStyle(fontSize: 8, color: _kInk)),
          ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(interpassUnitNote(unit, en: en),
              style: pw.TextStyle(fontSize: 7.5, color: _kInkMuted)),
        ),
        heading(en ? 'Rules' : 'Zasady'),
        for (final t in [
          interpassPassRule(en: en),
          interpassBoundaryNote(en: en),
          interpassMethodNote(weld.method, en: en),
          ...interpassPlaceNotes(en: en),
        ])
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text('• $t',
                style: pw.TextStyle(fontSize: 7.5, color: _kInk)),
          ),
        heading(en ? 'Signatures' : 'Podpisy'),
        pw.Row(children: [
          for (final role in [
            en ? 'Welder' : 'Spawacz',
            en ? 'Inspector (QC)' : 'Kontrola (QC)',
          ])
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                padding: const pw.EdgeInsets.all(6),
                height: 56,
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
