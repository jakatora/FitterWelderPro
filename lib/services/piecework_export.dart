/// Akord — zestawienie tekstem i PDF (do sprawdzenia rozliczenia z firmą).
///
/// Wzór: raport postępu robót (Roboto z `assets/fonts/` dla polskich znaków,
/// czcionki podawane z zewnątrz, żeby test renderował prawdziwe strony).
/// Treść i kwoty liczy `lib/domain/piecework/` — tu tylko układ.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/piecework/piecework.dart';
import '../domain/quotes/quote_calculator.dart' show formatPln;
import '../domain/weld_journal/weld_dates.dart';

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kWarnFill = PdfColor.fromHex('#FFF4DC');

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef PieceworkShareText = Future<void> Function(String text, String subject);

/// Udostępnienie PDF — wstrzykiwane w testach.
typedef PieceworkSharePdf = Future<void> Function(
    PieceworkReport report, bool english);

class PieceworkExport {
  const PieceworkExport._();

  static Future<void> shareText(String text, String subject) =>
      Share.share(text, subject: subject);

  static String subject(PieceworkReport report, {required bool en}) =>
      '${report.title(en: en)} — ${report.periodText(en: en)}';

  /// PDF z czcionkami z zasobów aplikacji.
  static Future<Uint8List> buildPdfBytes(PieceworkReport report,
      {required bool en}) async {
    final doc = buildPdfDocument(
      report: report,
      en: en,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
    );
    return doc.save();
  }

  static Future<void> sharePdf(PieceworkReport report, bool english) async {
    final bytes = await buildPdfBytes(report, en: english);
    final name = report.fileName(en: english);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: subject(report, en: english),
    );
  }

  /// Wiersze tabeli „Pozycja / Wartość" na początku PDF.
  static List<(String, String)> factRows(PieceworkReport report,
      {required bool en}) {
    final r = report.result;
    return [
      (en ? 'Welder' : 'Spawacz', report.welderText(en: en)),
      (en ? 'Rate' : 'Stawka', pieceworkRateText(r.rates, en: en)),
      (en ? 'Welds' : 'Spoiny', '${r.welds} · ${pieceworkDiText(r, en: en)}'),
      (en ? 'Days with entries' : 'Dni z wpisami', '${r.daysWorked}'),
      if (r.perDayGrosze != null)
        (en ? 'Average per day' : 'Średnio na dzień', formatPln(r.perDayGrosze!)),
      if (report.perHourGrosze != null)
        (
          en ? 'Per hour' : 'Na godzinę',
          '${formatPln(report.perHourGrosze!)} · ${hoursText(report, en: en)}'
        ),
    ];
  }

  static String _material(PieceworkMaterial m, {required bool en}) =>
      switch (m) {
        PieceworkMaterial.carbon => en ? 'CS' : 'węgl.',
        PieceworkMaterial.stainless => en ? 'SS' : 'nierdz.',
        PieceworkMaterial.other => en ? 'other' : 'inne',
        PieceworkMaterial.unknown => '?',
      };

  /// Komórki wiersza tabeli „spoina po spoinie": spoina, data, linia, DI
  /// (z „≈" i „÷n" dla spoiny wspólnej), materiał, pozycja, wartość,
  /// potrącenie / naprawy, do zapłaty.
  static List<String> weldCells(PieceworkLine l, {required bool en}) => [
        l.weld.weldNo,
        l.weld.date,
        l.weld.pipeName,
        l.weldDi == null
            ? '—'
            : '${diNumberText(l.weldDi!, en: en, approx: l.diApprox)}'
                '${l.splitBetween > 1 ? ' ÷${l.splitBetween}' : ''}',
        _material(l.material, en: en),
        payPositionLabel(l.position),
        formatPln(l.valueGrosze, withUnit: false),
        [
          if (l.deductionGrosze != 0)
            formatPln(-l.deductionGrosze, withUnit: false),
          if (l.repairPayGrosze != 0)
            '+${formatPln(l.repairPayGrosze, withUnit: false)}',
        ].join(' '),
        formatPln(l.netGrosze, withUnit: false),
      ];

  static pw.Document buildPdfDocument({
    required PieceworkReport report,
    required bool en,
    required pw.Font font,
    pw.Font? boldFont,
  }) {
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
          base: font, bold: bold, italic: font, boldItalic: bold),
    );
    final r = report.result;
    final g = report.generatedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${isoDate(g)} ${two(g.hour)}:${two(g.minute)}';

    pw.Widget text(String t,
            {double size = 9, bool strong = false, PdfColor? color}) =>
        pw.Text(t,
            style: pw.TextStyle(
                fontSize: size,
                fontWeight: strong ? pw.FontWeight.bold : null,
                color: color ?? _kInk));

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child: text(t.toUpperCase(), size: 9, strong: true),
        );

    pw.Widget cell(String t,
            {bool head = false, bool right = false, bool strong = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(t,
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
              style: pw.TextStyle(
                  fontSize: head ? 7 : 7.5,
                  fontWeight: head || strong ? pw.FontWeight.bold : null,
                  color: _kInk)),
        );

    pw.Widget table(List<String> headers, List<List<String>> rows,
            {Set<int> rightAligned = const {},
            Map<int, pw.TableColumnWidth>? widths,
            bool lastStrong = false}) =>
        pw.Table(
          border: pw.TableBorder.all(color: _kRule, width: 0.5),
          columnWidths: widths,
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: _kHeadFill),
              children: [
                for (var i = 0; i < headers.length; i++)
                  cell(headers[i], head: true, right: rightAligned.contains(i)),
              ],
            ),
            for (var k = 0; k < rows.length; k++)
              pw.TableRow(children: [
                for (var i = 0; i < rows[k].length; i++)
                  cell(rows[k][i],
                      right: rightAligned.contains(i),
                      strong: lastStrong && k == rows.length - 1),
              ]),
          ],
        );

    final facts = factRows(report, en: en);
    final cmp = hourlyCompareText(report, en: en);
    final notes = pieceworkNotes(r, en: en);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 80,
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
            border:
                pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  text(
                      '${report.title(en: en).toUpperCase()} — '
                      '${report.periodText(en: en)}',
                      size: 12,
                      strong: true),
                  text(report.welderText(en: en),
                      size: 8.5, color: _kInkMuted),
                ],
              ),
            ),
            text(
                '${en ? 'Page' : 'Strona'} ${ctx.pageNumber} / ${ctx.pagesCount}',
                size: 8,
                color: _kInkMuted),
          ],
        ),
      ),
      footer: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: text(
            'Fitter Welder Pro  ·  $stamp  ·  '
            '${en ? 'from the weld journal' : 'z dziennika spoin'}',
            size: 7,
            color: _kInkMuted),
      ),
      build: (_) => [
        table(
          [en ? 'Item' : 'Pozycja', en ? 'Value' : 'Wartość'],
          [
            for (final x in facts) [x.$1, x.$2]
          ],
        ),
        heading(en ? 'Amount' : 'Kwota'),
        table(
          [en ? 'Component' : 'Składnik', en ? 'Amount' : 'Kwota'],
          [
            for (final row in pieceworkRows(r, en: en))
              [row.label, formatPln(row.grosze)],
            [en ? 'TOTAL (before tax)' : 'RAZEM (przed podatkiem)',
              formatPln(r.totalGrosze)],
          ],
          rightAligned: const {1},
          widths: const {
            0: pw.FlexColumnWidth(4),
            1: pw.FlexColumnWidth(1.4),
          },
          lastStrong: true,
        ),
        if (cmp != null) ...[
          pw.SizedBox(height: 6),
          text(cmp, size: 8.5),
        ],
        if (r.skippedNoOd.isNotEmpty) ...[
          heading(en
              ? 'Skipped — no size (OD), NOT in the amount'
              : 'Pominięte — brak wymiaru (OD), kwota ich NIE zawiera'),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            color: _kWarnFill,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                text(
                    en
                        ? 'Fill in the OD in the weld journal and print again.'
                        : 'Uzupełnij OD w dzienniku spoin i wydrukuj ponownie.',
                    size: 8,
                    strong: true),
                for (final e in r.skippedNoOd)
                  text('• ${skippedWeldLine(e)}', size: 8),
              ],
            ),
          ),
        ],
        if (r.lines.isNotEmpty) ...[
          heading(en ? 'Weld by weld' : 'Spoina po spoinie'),
          table(
            [
              en ? 'Weld' : 'Spoina',
              en ? 'Date' : 'Data',
              en ? 'Line' : 'Linia',
              'DI',
              en ? 'Mat.' : 'Mat.',
              en ? 'Pos.' : 'Poz.',
              en ? 'Value' : 'Wartość',
              en ? '− / + repair' : '− / + napr.',
              en ? 'To pay' : 'Do zapłaty',
            ],
            [
              for (final l in r.lines) weldCells(l, en: en),

            ],
            rightAligned: const {3, 6, 7, 8},
          ),
        ],
        if (r.days.isNotEmpty && r.minDayApplies) ...[
          heading(en ? 'Day by day' : 'Dzień po dniu'),
          table(
            [
              en ? 'Day' : 'Dzień',
              en ? 'Welds' : 'Spoiny',
              en ? 'Welds amount' : 'Za spoiny',
              en ? 'Top-up' : 'Dopłata',
            ],
            [
              for (final d in r.days)
                [
                  isoDate(d.day),
                  '${d.welds}',
                  formatPln(d.netGrosze),
                  d.skippedWelds > 0
                      ? (en ? 'skipped welds — fill in OD' : 'pominięte — uzupełnij OD')
                      : (d.topUpGrosze == 0 ? '—' : formatPln(d.topUpGrosze)),
                ],
            ],
            rightAligned: const {1, 2, 3},
          ),
        ],
        if (notes.isNotEmpty) ...[
          heading(en ? 'Notes' : 'Uwagi'),
          for (final n in notes) text('• $n', size: 8, color: _kInkMuted),
        ],
        heading(en ? 'How it is counted' : 'Jak liczone'),
        for (final d in pieceworkDefinitions(en: en))
          text('• $d', size: 7.5, color: _kInkMuted),
      ],
    ));
    return doc;
  }
}
