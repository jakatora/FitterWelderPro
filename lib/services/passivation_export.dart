/// Eksport rejestru trawienia / pasywacji — CSV i PDF (data book).
///
/// Te same zasady co log kuponów: `;`, CRLF, BOM UTF-8, Roboto dla polskich
/// znaków; czcionki podawane z zewnątrz, więc test renderuje prawdziwe
/// strony. Górna połowa czysta, dolna — platforma.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/passivation/passivation_record.dart';
import 'weld_journal_export.dart'
    show escapeCsvField, kUtf8Bom, kWeldJournalCsvEol, kWeldJournalCsvSeparator;

final List<(String, String Function(PassivationRecord))> _columns = [
  ('Data / Date', (r) => r.date),
  ('Zabieg / Treatment',
      (r) => '${PassivationTreatment.label(r.treatment, en: false)} / '
          '${PassivationTreatment.label(r.treatment, en: true)}'),
  ('Linia / Line', (r) => r.line),
  ('Pakiet testowy / Test package', (r) => r.testPackage),
  ('Obszar / Area', (r) => r.area),
  ('Środek / Agent', (r) => r.agent),
  ('Partia / Batch', (r) => r.agentBatch),
  ('Czas (min) / Time (min)', (r) => formatPassivationNumber(r.dwellMin)),
  ('Temp. (°C)', (r) => formatPassivationNumber(r.tempC)),
  ('Płukanie µS/cm / Rinse µS/cm', (r) => formatPassivationNumber(r.rinseUsCm)),
  ('Test', (r) => r.testMethod),
  ('Wynik / Result', (r) => r.testResult),
  ('Wykonał / By', (r) => r.byStamp),
  ('Uwagi / Notes', (r) => r.notes),
];

List<String> get passivationCsvHeaders =>
    _columns.map((c) => c.$1).toList(growable: false);

String buildPassivationCsv(List<PassivationRecord> records) {
  final buf = StringBuffer()..write(kUtf8Bom);
  buf.write(_columns
      .map((c) => escapeCsvField(c.$1))
      .join(kWeldJournalCsvSeparator));
  buf.write(kWeldJournalCsvEol);
  for (final r in records) {
    buf.write(_columns
        .map((c) => escapeCsvField(c.$2(r)))
        .join(kWeldJournalCsvSeparator));
    buf.write(kWeldJournalCsvEol);
  }
  return buf.toString();
}

String passivationFileName(
    {required String extension, required DateTime generatedAt}) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Rejestr_pasywacji_${generatedAt.year}-${two(generatedAt.month)}-'
      '${two(generatedAt.day)}.$extension';
}

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');

class PassivationExport {
  const PassivationExport._();

  static Future<void> shareCsv(List<PassivationRecord> records) async {
    final now = DateTime.now();
    final name = passivationFileName(extension: 'csv', generatedAt: now);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(utf8.encode(buildPassivationCsv(records)),
        flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: name)],
      subject: 'Rejestr trawienia i pasywacji / Pickling & passivation log',
    );
  }

  static Future<void> sharePdf(List<PassivationRecord> records) async {
    final now = DateTime.now();
    final doc = await buildPdfDocument(
      records: records,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: now,
    );
    final bytes = await doc.save();
    final name = passivationFileName(extension: 'pdf', generatedAt: now);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: 'Rejestr trawienia i pasywacji / Pickling & passivation log',
    );
  }

  static Future<pw.Document> buildPdfDocument({
    required List<PassivationRecord> records,
    required pw.Font font,
    pw.Font? boldFont,
    required DateTime generatedAt,
  }) async {
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
          base: font, bold: bold, italic: font, boldItalic: bold),
    );
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${generatedAt.year}-${two(generatedAt.month)}-'
        '${two(generatedAt.day)} ${two(generatedAt.hour)}:'
        '${two(generatedAt.minute)}';
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      maxPages: 500,
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
            border:
                pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
                'REJESTR TRAWIENIA I PASYWACJI / PICKLING & PASSIVATION LOG',
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold, color: _kInk)),
            pw.Text('Strona / Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: _kInkMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Fitter Welder Pro  ·  $stamp  ·  ASTM A380 / A967, ASME BPE',
          style: pw.TextStyle(fontSize: 7, color: _kInkMuted),
        ),
      ),
      build: (_) => [
        if (records.isEmpty)
          pw.Text('Brak wpisów. / No records.',
              style: pw.TextStyle(fontSize: 9, color: _kInkMuted))
        else
          pw.Table(
            border: pw.TableBorder.all(color: _kRule, width: 0.5),
            children: [
              pw.TableRow(
                repeat: true,
                decoration: pw.BoxDecoration(color: _kHeadFill),
                children: [
                  for (final h in passivationCsvHeaders)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(h,
                          style: pw.TextStyle(
                              fontSize: 6,
                              fontWeight: pw.FontWeight.bold,
                              color: _kInk)),
                    ),
                ],
              ),
              for (final r in records)
                pw.TableRow(children: [
                  for (final c in _columns)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(c.$2(r),
                          style: pw.TextStyle(fontSize: 6.5, color: _kInk)),
                    ),
                ]),
            ],
          ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Parametry wiążące: karta produktu i specyfikacja projektu. / '
          'Binding parameters: product data sheet and project specification.',
          style: pw.TextStyle(fontSize: 7, color: _kInkMuted),
        ),
        pw.SizedBox(height: 16),
        pw.Row(children: [
          for (final role in [
            'Wykonał / Performed by',
            'Kontrola jakości / QC',
            'Inspektor / Inspector',
          ])
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                padding: const pw.EdgeInsets.all(6),
                height: 50,
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
