/// Zlecenie badań NDT — tekst do wysłania i PDF dla laboratorium / inspektora.
///
/// Wzór: raport postępu robót (Roboto z `assets/fonts/` dla polskich znaków,
/// czcionki podawane z zewnątrz, żeby test renderował prawdziwe strony).
/// Treść liczy `lib/domain/ndt/` — tu tylko układ.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/ndt/ndt_plan.dart';
import '../domain/weld_journal/weld_dates.dart';
import '../domain/weld_journal/weld_ndt.dart';
import '../domain/weld_journal/weld_stats.dart' show weldLineKey;

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kPassFill = PdfColor.fromHex('#E3F6EC');
final PdfColor _kWarnFill = PdfColor.fromHex('#FFF4DC');

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef NdtShareText = Future<void> Function(String text, String subject);

/// Udostępnienie PDF — wstrzykiwane w testach.
typedef NdtSharePdf = Future<void> Function(
    NdtOrderReport report, bool english);

class NdtPlanExport {
  const NdtPlanExport._();

  static Future<void> shareText(String text, String subject) =>
      Share.share(text, subject: subject);

  static Future<Uint8List> buildPdfBytes(NdtOrderReport report,
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

  static Future<void> sharePdf(NdtOrderReport report, bool english) async {
    final bytes = await buildPdfBytes(report, en: english);
    final name = report.fileName(en: english);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: report.subject(en: english),
    );
  }

  /// Wiersz tabeli zlecenia: Lp., spoina, linia, ISO, spawacz, rodzaj,
  /// metoda, powód.
  static List<String> orderCells(int no, NdtOrderItem i, {required bool en}) {
    final e = i.weld;
    return [
      '$no',
      e.weldNo.trim().isEmpty ? '?' : e.weldNo.trim(),
      ndtLineName(weldLineKey(e).trim(), en: en),
      e.isoDrawing.trim(),
      e.stamps.isEmpty ? (en ? 'no welder' : 'bez spawacza') : e.stamps.join('/'),
      ndtJointOf(e) ?? '',
      i.method.code,
      ndtOrderReason(i, en: en),
    ];
  }

  static pw.Document buildPdfDocument({
    required NdtOrderReport report,
    required bool en,
    required pw.Font font,
    pw.Font? boldFont,
  }) {
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
          base: font, bold: bold, italic: font, boldItalic: bold),
    );
    final plan = report.plan;
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

    pw.Widget cell(String t, {bool head = false, bool right = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(t,
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
              style: pw.TextStyle(
                  fontSize: head ? 7 : 7.5,
                  fontWeight: head ? pw.FontWeight.bold : null,
                  color: _kInk)),
        );

    pw.Widget table(List<String> headers, List<List<String>> rows,
            {Set<int> rightAligned = const {},
            List<PdfColor?> fills = const []}) =>
        pw.Table(
          border: pw.TableBorder.all(color: _kRule, width: 0.5),
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: _kHeadFill),
              children: [
                for (var i = 0; i < headers.length; i++)
                  cell(headers[i], head: true, right: rightAligned.contains(i)),
              ],
            ),
            for (var r = 0; r < rows.length; r++)
              pw.TableRow(
                decoration: r < fills.length && fills[r] != null
                    ? pw.BoxDecoration(color: fills[r])
                    : null,
                children: [
                  for (var i = 0; i < rows[r].length; i++)
                    cell(rows[r][i], right: rightAligned.contains(i)),
                ],
              ),
          ],
        );

    final toOrder = plan.toOrder;
    final ordered = plan.ordered;
    final orderRows = <List<String>>[];
    for (final m in NdtMethod.values) {
      for (final i in toOrder[m] ?? const <NdtOrderItem>[]) {
        orderRows.add(orderCells(orderRows.length + 1, i, en: en));
      }
    }
    final orderedRows = <List<String>>[];
    for (final m in NdtMethod.values) {
      for (final i in ordered[m] ?? const <NdtOrderItem>[]) {
        orderedRows.add(orderCells(orderedRows.length + 1, i, en: en));
      }
    }
    final orderHeaders = [
      en ? 'No.' : 'Lp.',
      en ? 'Weld' : 'Spoina',
      en ? 'Line' : 'Linia',
      'ISO',
      en ? 'Welder' : 'Spawacz',
      en ? 'Type' : 'Rodzaj',
      en ? 'Method' : 'Metoda',
      en ? 'Reason' : 'Powód',
    ];

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 60,
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
                  text(report.title(en: en).toUpperCase(),
                      size: 12, strong: true),
                  text(
                      '${en ? 'Project' : 'Projekt'}: '
                      '${ndtProjectName(report.project, en: en)}',
                      size: 8.5,
                      color: _kInkMuted),
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
        heading(en ? 'Requirements' : 'Wymagania'),
        if (plan.rules.isEmpty)
          text(en ? 'No rules set.' : 'Brak reguł.', size: 8.5),
        for (final r in plan.rules) text('• ${ndtRuleText(r, en: en)}', size: 8.5),
        if (!plan.rulesIntact)
          text(
              en
                  ? 'The saved rules were damaged — the plan is not final.'
                  : 'Zapisane reguły były uszkodzone — plan nie jest ostateczny.',
              size: 8.5,
              strong: true),
        heading(en ? 'To order' : 'Do zlecenia'),
        if (orderRows.isEmpty)
          text(en ? 'Nothing new to order.' : 'Nic nowego do zlecenia.',
              size: 8.5)
        else
          table(orderHeaders, orderRows, rightAligned: const {0}),
        if (orderedRows.isNotEmpty) ...[
          heading(en
              ? 'Ordered earlier, no result yet'
              : 'Zlecone wcześniej, bez wyniku'),
          table(orderHeaders, orderedRows, rightAligned: const {0}),
        ],
        if (plan.progressiveGroups.isNotEmpty) ...[
          heading(en
              ? 'Additional examinations (B31.3 §341.3.4)'
              : 'Badania dodatkowe (B31.3 §341.3.4)'),
          text(
              en
                  ? 'Picked by the inspector: same welder, same method.'
                  : 'Wybiera inspektor: ten sam spawacz, ta sama metoda.',
              size: 8,
              color: _kInkMuted),
          pw.SizedBox(height: 4),
          table(
            [en ? 'Group' : 'Grupa', en ? 'Due' : 'Do wykonania'],
            [
              for (final g in plan.progressiveGroups)
                [ndtGroupTitle(g, en: en), '${g.progressive}']
            ],
            rightAligned: const {1},
          ),
        ],
        if (plan.lines.isNotEmpty) ...[
          heading(en
              ? 'Pressure test readiness — ${plan.readyLines} of '
                  '${plan.lines.length} lines'
              : 'Gotowość do próby ciśnieniowej — ${plan.readyLines} z '
                  '${plan.lines.length} linii'),
          table(
            [
              en ? 'Line' : 'Linia',
              en ? 'Verdict' : 'Werdykt',
              en ? 'Numbers' : 'Liczby',
              en ? 'Blocking' : 'Blokuje',
            ],
            [
              for (final l in plan.lines)
                [
                  ndtLineName(l.line, en: en),
                  ndtVerdictText(l, en: en),
                  ndtLineNumbers(l, en: en),
                  [
                    for (final k in l.blockers.keys)
                      ndtBlockerText(k, l, en: en)
                  ].join('; '),
                ]
            ],
            fills: [
              for (final l in plan.lines) l.ready ? _kPassFill : _kWarnFill
            ],
          ),
        ],
        heading(en ? 'Groups' : 'Grupy'),
        if (plan.groups.isEmpty)
          text(en ? 'No groups.' : 'Brak grup.', size: 8.5)
        else
          table(
            [
              en ? 'Group' : 'Grupa',
              en ? 'Numbers' : 'Liczby',
              'Status',
            ],
            [
              for (final g in plan.groups)
                [
                  ndtGroupTitle(g, en: en),
                  ndtGroupNumbers(g, en: en),
                  ndtGroupStatusText(g, en: en),
                ]
            ],
          ),
        heading(en ? 'Definitions' : 'Definicje'),
        for (final d in ndtDefinitions(en: en))
          text('• $d', size: 7.5, color: _kInkMuted),
        pw.SizedBox(height: 18),
        pw.Row(children: [
          for (final role in en
              ? const ['Ordered by (QC)', 'Accepted by (NDT)']
              : const ['Zlecił (kontrola jakości)', 'Przyjął (laboratorium NDT)'])
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                padding: const pw.EdgeInsets.all(6),
                height: 46,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _kRule, width: 0.5)),
                child: text(role, size: 7.5, strong: true),
              ),
            ),
        ]),
      ],
    ));
    return doc;
  }
}
