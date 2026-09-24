/// Export of the daily test-coupon log — CSV (spreadsheet) and PDF (paper).
///
/// Same mechanics as `weld_journal_export.dart` (semicolon, CRLF, UTF-8 BOM,
/// Roboto for Polish diacritics, fonts passed in so a test renders real
/// pages). Top half pure, bottom half platform.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/heat_tint.dart';
import '../domain/weld_journal/coupon_entry.dart';
import 'weld_journal_export.dart'
    show escapeCsvField, kUtf8Bom, kWeldJournalCsvEol, kWeldJournalCsvSeparator;

// ═══════════════════════════════════════════════════════════════════════════
// PURE HALF
// ═══════════════════════════════════════════════════════════════════════════

/// `2 — Słomkowy / Light straw`; empty when no level was recorded.
String couponHeatTintLabel(int? level) {
  if (level == null) return '';
  final l = kHeatTintLevels.where((x) => x.level == level).firstOrNull;
  if (l == null) return '$level';
  return '$level — ${l.namePl} / ${l.nameEn}';
}

/// O₂ for a Polish spreadsheet: decimal COMMA — Polish Excel reads "18.5"
/// as the date 18 May.
String _o2Csv(double? v) => formatO2Ppm(v).replaceAll('.', ',');

final List<(String, String Function(CouponEntry))> _columns = [
  ('Data / Date', (c) => c.date),
  ('Spawacz / Welder', (c) => c.welder),
  ('Maszyna / Machine', (c) => c.machine),
  ('Wymiar / Size', (c) => c.size),
  ('Program', (c) => c.programNo),
  ('Parametry / Parameters', (c) => c.programParams),
  ('O₂ (ppm)', (c) => _o2Csv(c.o2Ppm)),
  ('Przebarwienie AWS D18.2 / Heat tint', (c) => couponHeatTintLabel(c.heatTint)),
  ('Wynik / Result', (c) => c.result),
  ('Uwagi / Notes', (c) => c.notes),
];

List<String> get couponLogCsvHeaders =>
    _columns.map((c) => c.$1).toList(growable: false);

String buildCouponLogCsv(List<CouponEntry> coupons) {
  final buf = StringBuffer()..write(kUtf8Bom);
  buf.write(_columns
      .map((c) => escapeCsvField(c.$1))
      .join(kWeldJournalCsvSeparator));
  buf.write(kWeldJournalCsvEol);
  for (final coupon in coupons) {
    buf.write(_columns
        .map((c) => escapeCsvField(c.$2(coupon)))
        .join(kWeldJournalCsvSeparator));
    buf.write(kWeldJournalCsvEol);
  }
  return buf.toString();
}

/// `Log_kuponow_2026-09-24.csv`.
String couponLogFileName({
  required String extension,
  required DateTime generatedAt,
}) {
  final y = generatedAt.year.toString().padLeft(4, '0');
  final m = generatedAt.month.toString().padLeft(2, '0');
  final d = generatedAt.day.toString().padLeft(2, '0');
  return 'Log_kuponow_$y-$m-$d.$extension';
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM HALF
// ═══════════════════════════════════════════════════════════════════════════

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kOkInk = PdfColor.fromHex('#1E7A3C');
final PdfColor _kNokInk = PdfColor.fromHex('#B3261E');

class CouponLogExport {
  const CouponLogExport._();

  static Future<void> shareCsv(List<CouponEntry> coupons,
      {DateTime? generatedAt}) async {
    final now = generatedAt ?? DateTime.now();
    final name = couponLogFileName(extension: 'csv', generatedAt: now);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(utf8.encode(buildCouponLogCsv(coupons)),
        flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: name)],
      subject: 'Log kuponów próbnych / Test coupon log',
    );
  }

  static Future<void> sharePdf(List<CouponEntry> coupons,
      {DateTime? generatedAt}) async {
    final now = generatedAt ?? DateTime.now();
    final doc = await buildPdfDocument(
      coupons: coupons,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: now,
    );
    final bytes = await doc.save();
    final name = couponLogFileName(extension: 'pdf', generatedAt: now);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    if (!await file.exists() || (await file.length()) < 100) {
      throw StateError(
        'PDF zapisany niepoprawnie — sprawdź miejsce na dysku (${dir.path}).',
      );
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: 'Log kuponów próbnych / Test coupon log',
    );
  }

  static Future<pw.Document> buildPdfDocument({
    required List<CouponEntry> coupons,
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
    final ok = coupons.where((c) => c.result == 'OK').length;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      maxPages: 500,
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
          border:
              pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('LOG KUPONÓW PRÓBNYCH / TEST COUPON LOG',
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _kInk)),
            pw.Text('Strona / Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: _kInkMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Fitter Welder Pro  ·  $stamp  ·  AWS D18.1/D18.2, ASME BPE MJ-7.3',
          style: pw.TextStyle(fontSize: 7, color: _kInkMuted),
        ),
      ),
      build: (_) => [
        pw.Text(
          'Kupony / Coupons: ${coupons.length}   OK: $ok   '
          'NOK: ${coupons.length - ok}',
          style: pw.TextStyle(fontSize: 9, color: _kInk),
        ),
        pw.SizedBox(height: 6),
        if (coupons.isEmpty)
          pw.Text('Brak kuponów. / No coupons.',
              style: pw.TextStyle(fontSize: 9, color: _kInkMuted))
        else
          pw.Table(
            border: pw.TableBorder.all(color: _kRule, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(52),
              1: pw.FixedColumnWidth(52),
              2: pw.FlexColumnWidth(1.1),
              3: pw.FlexColumnWidth(0.8),
              4: pw.FixedColumnWidth(40),
              5: pw.FlexColumnWidth(1.4),
              6: pw.FixedColumnWidth(40),
              7: pw.FlexColumnWidth(1.1),
              8: pw.FixedColumnWidth(34),
              9: pw.FlexColumnWidth(1.6),
            },
            children: [
              pw.TableRow(
                repeat: true,
                decoration: pw.BoxDecoration(color: _kHeadFill),
                children: [
                  for (final h in couponLogCsvHeaders)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      // Roboto has no subscript two: "O₂" would print as
                      // "O" plus a missing glyph.
                      child: pw.Text(h.replaceAll('₂', '2'),
                          style: pw.TextStyle(
                              fontSize: 6.5,
                              fontWeight: pw.FontWeight.bold,
                              color: _kInk)),
                    ),
                ],
              ),
              for (final c in coupons)
                pw.TableRow(children: [
                  for (final col in _columns)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(
                        col.$1 == 'O₂ (ppm)'
                            ? formatO2Ppm(c.o2Ppm)
                            : col.$2(c),
                        style: pw.TextStyle(
                          fontSize: 7,
                          color: col.$1 == 'Wynik / Result'
                              ? (c.result == 'OK' ? _kOkInk : _kNokInk)
                              : _kInk,
                          fontWeight: col.$1 == 'Wynik / Result'
                              ? pw.FontWeight.bold
                              : pw.FontWeight.normal,
                        ),
                      ),
                    ),
                ]),
            ],
          ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Przebarwienie: numer próbki AWS D18.2 (1 = srebrny … 10 = czarny). '
          'Kryterium przyjęcia wynika ze specyfikacji projektu / WPS. / '
          'Heat tint: AWS D18.2 sample number; acceptance per project '
          'specification / WPS.',
          style: pw.TextStyle(fontSize: 7, color: _kInkMuted),
        ),
      ],
    ));
    return doc;
  }
}
