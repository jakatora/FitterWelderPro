/// Raport postępu robót — tekst do wysłania i PDF dla szefa.
///
/// Wzór: eksport rejestru pasywacji (Roboto z `assets/fonts/` dla polskich
/// znaków, czcionki podawane z zewnątrz, żeby test renderował prawdziwe
/// strony). Treść liczy `lib/domain/progress/` — tu tylko układ.
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/progress/progress_report.dart';
import '../domain/weld_journal/weld_dates.dart';

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');

class ProgressExport {
  const ProgressExport._();

  static Future<void> shareText(ProgressReport report, {required bool en}) =>
      Share.share(
        buildProgressReportText(report, en: en),
        subject: '${report.title(en: en)} — ${report.periodText(en: en)}',
      );

  static Future<void> sharePdf(ProgressReport report,
      {required bool en, bool Function()? mayShare}) async {
    if (mayShare != null && !mayShare()) return;
    final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    if (mayShare != null && !mayShare()) return;
    final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    if (mayShare != null && !mayShare()) return;
    final doc = buildPdfDocument(
      report: report,
      en: en,
      font: pw.Font.ttf(regular),
      boldFont: pw.Font.ttf(bold),
    );
    final bytes = await doc.save();
    if (mayShare != null && !mayShare()) return;
    final name = report.fileName(en: en);
    final dir = await getTemporaryDirectory();
    if (mayShare != null && !mayShare()) return;
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    if (mayShare != null && !mayShare()) return;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: '${report.title(en: en)} — ${report.periodText(en: en)}',
    );
  }

  static pw.Document buildPdfDocument({
    required ProgressReport report,
    required bool en,
    required pw.Font font,
    pw.Font? boldFont,
  }) {
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
          base: font, bold: bold, italic: font, boldItalic: bold),
    );
    final s = report.summary;
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
            {Set<int> rightAligned = const {}}) =>
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
            for (final r in rows)
              pw.TableRow(children: [
                for (var i = 0; i < r.length; i++)
                  cell(r[i], right: rightAligned.contains(i)),
              ]),
          ],
        );

    final facts = <(String, String)>[
      (en ? 'Done' : 'Wykonano', s.isEmpty ? '—' : doneLine(s, en: en)),
      ('Status', s.isEmpty ? '—' : statusLine(s, en: en)),
      if (report.pace != null) ...[
        (en ? 'Pace' : 'Tempo', paceLine(report.pace!, en: en)),
        (
          en ? 'Pace window' : 'Okno tempa',
          paceWindowLine(report.pace!, en: en)
        ),
      ],
      if (!s.isEmpty) ...[
        (
          en ? 'Repairs' : 'Naprawy',
          repairsText(s.crew, en: en),
        ),
        (
          en ? 'Repair rate (RT/UT)' : 'Odsetek napraw (RT/UT)',
          repairRateText(s.crew, en: en),
        ),
        if (s.crew.toExamine > 0)
          (
            en
                ? 'To examine (B31.3 §341.3.4)'
                : 'Do dobadania (B31.3 §341.3.4)',
            '${s.crew.toExamine}'
          ),
      ],
    ];

    final days =
        s.days.length > 31 ? s.days.sublist(s.days.length - 31) : s.days;
    final notes = dataNotes(s, en: en);
    final f = report.forecast;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 50,
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
                  text(report.filter.describeScope(en: en),
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
        if (s.isEmpty)
          text(en
              ? 'No welds in the journal for this period.'
              : 'Brak spoin w dzienniku w tym okresie.'),
        table(
          [en ? 'Item' : 'Pozycja', en ? 'Value' : 'Wartość'],
          [
            for (final x in facts) [x.$1, x.$2]
          ],
        ),
        if (!report.isDaily && days.isNotEmpty) ...[
          heading(en ? 'Day by day' : 'Dzień po dniu'),
          table(
            [en ? 'Day' : 'Dzień', en ? 'Welds' : 'Spoiny', 'DI'],
            [
              for (final d in days)
                [
                  dayLabel(d.day, en: en),
                  '${d.welds}',
                  progressNum(d.di, en: en),
                ]
            ],
            rightAligned: const {1, 2},
          ),
        ],
        if (s.welders.isNotEmpty) ...[
          heading(en ? 'Welders' : 'Spawacze'),
          table(
            [
              en ? 'Stamp' : 'Stempel',
              en ? 'Welds (shared)' : 'Spoiny (wspólne)',
              en ? 'DI (share)' : 'DI (udział)',
              en ? 'Repairs R1 / R2+' : 'Naprawy R1 / R2+',
              en ? 'RT/UT rejected / examined' : 'RT/UT odrz. / zbad.',
              en ? 'Repair rate' : 'Odsetek napraw',
            ],
            [
              for (final w in s.welders)
                [
                  w.isUnstamped ? (en ? 'no stamp' : 'bez stempla') : w.stamp,
                  '${w.welds}${w.sharedWelds == 0 ? '' : ' (${w.sharedWelds})'}',
                  progressDi(w.diShare, en: en, approx: w.diApprox)
                      .replaceAll(' DI', ''),
                  '${w.quality.r1} / ${w.quality.r2plus}',
                  '${w.quality.volumetricRejected} / '
                      '${w.quality.volumetricExamined}',
                  w.quality.repairRatePct == null
                      ? '—'
                      : progressPct(w.quality.repairRatePct!, en: en),
                ],
              [
                en ? 'Crew (each weld once)' : 'Brygada (każda spoina raz)',
                '${s.welds}',
                progressDi(s.di, en: en, approx: s.diApprox)
                    .replaceAll(' DI', ''),
                '${s.crew.r1} / ${s.crew.r2plus}',
                '${s.crew.volumetricRejected} / ${s.crew.volumetricExamined}',
                s.crew.repairRatePct == null
                    ? '—'
                    : progressPct(s.crew.repairRatePct!, en: en),
              ],
            ],
            rightAligned: const {1, 2, 3, 4, 5},
          ),
        ],
        if (f != null) ...[
          heading(en ? 'Forecast' : 'Prognoza'),
          for (final line in forecastLines(f, en: en)) text(line, size: 8.5),
        ],
        if (notes.isNotEmpty) ...[
          heading(en ? 'Notes' : 'Uwagi'),
          for (final n in notes) text('• $n', size: 8, color: _kInkMuted),
        ],
        heading(en ? 'Definitions' : 'Definicje'),
        for (final d in definitionLines(en: en))
          text('• $d', size: 7.5, color: _kInkMuted),
        pw.SizedBox(height: 18),
        pw.Row(children: [
          for (final role in en
              ? const ['Prepared by (foreman)', 'Site manager']
              : const ['Sporządził (brygadzista)', 'Kierownik robót'])
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
