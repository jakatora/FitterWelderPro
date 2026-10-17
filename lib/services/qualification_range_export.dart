/// PDF „Zakres uprawnień z próbki” (EN ISO 9606-1:2017) — oznaczenie
/// próbki, linie zakresu z punktami normy, uwagi i zastrzeżenie. Te same
/// linie co na ekranie i w tekście do udostępnienia
/// (`iso9606Lines` w lib/domain/qualification/iso9606_range.dart).
/// Wzór: qualification_export.dart.
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/qualification/iso9606_range.dart';
import '../domain/qualification/qualification_dates.dart';

String qualificationRangeFileName(DateTime generatedAt) =>
    'Zakres_uprawnien_${formatIsoDate(generatedAt)}.pdf';

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kWarnInk = PdfColor.fromHex('#8A5A00');

/// Indeksy dolne z ekranu (s₁, s₂) — pewniej zwykłymi cyframi w PDF.
String _pdfText(String s) => s.replaceAll('₁', '1').replaceAll('₂', '2');

class QualificationRangeExport {
  const QualificationRangeExport._();

  static Future<void> sharePdf(Iso9606Range range, {required bool en}) async {
    final now = DateTime.now();
    final doc = buildPdfDocument(
      range: range,
      en: en,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: now,
    );
    final bytes = await doc.save();
    final name = qualificationRangeFileName(now);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: iso9606Title(en: en),
    );
  }

  static pw.Widget _cell(String t, {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(_pdfText(t),
            style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color ?? _kInk)),
      );

  static pw.Document buildPdfDocument({
    required Iso9606Range range,
    required bool en,
    required pw.Font font,
    pw.Font? boldFont,
    required DateTime generatedAt,
  }) {
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
          base: font, bold: bold, italic: font, boldItalic: bold),
    );
    final lines = iso9606Lines(range, en: en);
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
            pw.Text(
                '${iso9606Title(en: en).toUpperCase()} · EN ISO 9606-1:2017',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold, color: _kInk)),
            pw.Text(
                '${formatIsoDate(generatedAt)} · '
                '${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: _kInkMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Text(
        'Fitter Welder Pro · ${iso9606Disclaimer(en: en)}',
        style: pw.TextStyle(fontSize: 7, color: _kInkMuted),
      ),
      build: (_) => [
        pw.Text(en ? 'Test piece' : 'Próbka',
            style: pw.TextStyle(fontSize: 9, color: _kInkMuted)),
        pw.Text(_pdfText(iso9606Designation(range.sample, en: en)),
            style: pw.TextStyle(
                fontSize: 12, fontWeight: pw.FontWeight.bold, color: _kInk)),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: _kRule, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(5),
            2: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: _kHeadFill),
              children: [
                _cell(en ? 'Variable' : 'Zmienna', bold: true),
                _cell(en ? 'Range of qualification' : 'Zakres uprawnienia',
                    bold: true),
                _cell(en ? 'Clause' : 'Punkt normy', bold: true),
              ],
            ),
            for (final l in lines)
              pw.TableRow(children: [
                _cell(l.label),
                _cell(l.value, bold: true),
                _cell(l.clause, color: _kInkMuted),
              ]),
          ],
        ),
        if (range.notes.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(en ? 'Notes' : 'Uwagi',
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kInk)),
          pw.SizedBox(height: 4),
          for (final n in range.notes)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Text(
                '• ${n.check ? (en ? '[check] ' : '[sprawdź] ') : ''}'
                '${_pdfText(n.text(en: en))}',
                style: pw.TextStyle(
                    fontSize: 8.5, color: n.check ? _kWarnInk : _kInk),
              ),
            ),
        ],
      ],
    ));
    return doc;
  }
}
