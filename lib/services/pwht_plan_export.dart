/// Plan PWHT jako PDF — dla firmy wyżarzającej / brygadzisty.
///
/// Te same zasady co eksport pasywacji: Roboto z `assets/fonts/` (polskie
/// znaki), czcionki podawane z zewnątrz, więc test renderuje prawdziwe
/// strony. Górna połowa czysta (budowa dokumentu), dolna — platforma
/// (plik tymczasowy + arkusz udostępniania).
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/pwht/pwht_plan.dart';
import '../domain/pwht/pwht_plan_text.dart';

String pwhtPlanFileName({required DateTime generatedAt}) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Plan_PWHT_${generatedAt.year}-${two(generatedAt.month)}-'
      '${two(generatedAt.day)}.pdf';
}

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kWarnFill = PdfColor.fromHex('#FFF4DC');

class PwhtPlanExport {
  const PwhtPlanExport._();

  static Future<void> sharePdf(PwhtPlan plan, {required bool english}) async {
    final now = DateTime.now();
    final doc = await buildPdfDocument(
      plan: plan,
      english: english,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: now,
    );
    final bytes = await doc.save();
    final name = pwhtPlanFileName(generatedAt: now);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: english ? 'PWHT plan' : 'Plan PWHT',
    );
  }

  static Future<pw.Document> buildPdfDocument({
    required PwhtPlan plan,
    required bool english,
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
    final lines = pwhtPlanLines(plan, english: english);
    final cycle = plan.cycle;
    final range = plan.entry.holdRange;

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
            pw.Text(english ? 'PWHT plan' : 'Plan PWHT',
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _kInk)),
            pw.Text(
                '${english ? 'Page' : 'Strona'} ${ctx.pageNumber} / '
                '${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: _kInkMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Fitter Welder Pro  ·  $stamp  ·  ${plan.entry.source}',
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
          child: pw.Text(pwhtDisclaimer(english: english),
              style: pw.TextStyle(fontSize: 9, color: _kInk)),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
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
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(l.label,
                      style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _kInk)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(l.value,
                      style: pw.TextStyle(fontSize: 8.5, color: _kInk)),
                ),
              ]),
          ],
        ),
        if (cycle != null && range != null) ...[
          pw.SizedBox(height: 14),
          pw.Text(
              english
                  ? 'Cycle chart (controlled part, from ${cycle.controlTempC} °C)'
                  : 'Wykres cyklu (część kontrolowana, od ${cycle.controlTempC} °C)',
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kInk)),
          pw.SizedBox(height: 6),
          pw.SizedBox(
            height: 190,
            child: _chart(cycle, range, english),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            english
                ? 'Heating up to ${cycle.controlTempC} °C and cooling below it '
                    'are not included in the cycle time.'
                : 'Nagrzewanie do ${cycle.controlTempC} °C i chłodzenie poniżej '
                    'niej nie są wliczone w czas cyklu.',
            style: pw.TextStyle(fontSize: 7.5, color: _kInkMuted),
          ),
        ],
        pw.SizedBox(height: 18),
        pw.Row(children: [
          for (final role in english
              ? const ['Prepared by', 'Heat treater', 'QC / Inspector']
              : const [
                  'Przygotował',
                  'Firma wyżarzająca',
                  'Kontrola jakości / Inspektor'
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

  static pw.Widget _chart(PwhtCycle cycle, PwhtTempRange range, bool english) {
    final total = cycle.totalHours;
    final step = _timeStep(total);
    final xTicks = <double>[];
    for (var h = 0.0; h < total + step - 1e-9; h += step) {
      xTicks.add(double.parse(h.toStringAsFixed(2)));
    }
    final yTop =
        (((range.maxC > cycle.holdTempC ? range.maxC : cycle.holdTempC) + 50) /
                    100)
                .ceil() *
            100;
    final yTicks = [for (var c = 0; c <= yTop; c += 100) c];
    final xEnd = xTicks.last;
    String fmtH(num v) =>
        v == v.roundToDouble() ? '${v.toInt()} h' : '${v.toStringAsFixed(1)} h';

    pw.PointChartValue p(double x, double y) => pw.PointChartValue(x, y);
    return pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis<double>(xTicks,
            format: fmtH,
            divisions: true,
            divisionsColor: _kRule,
            textStyle: pw.TextStyle(fontSize: 7, color: _kInkMuted)),
        yAxis: pw.FixedAxis<int>(yTicks,
            format: (v) => '${v.toInt()} °C',
            divisions: true,
            divisionsColor: _kRule,
            textStyle: pw.TextStyle(fontSize: 7, color: _kInkMuted)),
      ),
      datasets: [
        pw.LineDataSet(
          drawPoints: false,
          lineWidth: 0.6,
          color: _kAccent,
          data: [p(0, range.minC.toDouble()), p(xEnd, range.minC.toDouble())],
        ),
        pw.LineDataSet(
          drawPoints: false,
          lineWidth: 0.6,
          color: _kAccent,
          data: [p(0, range.maxC.toDouble()), p(xEnd, range.maxC.toDouble())],
        ),
        pw.LineDataSet(
          drawPoints: true,
          pointSize: 2,
          lineWidth: 1.8,
          color: _kInk,
          data: [for (final q in cycle.points) p(q.hours, q.tempC)],
        ),
      ],
    );
  }

  static double _timeStep(double total) {
    const steps = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0];
    for (final s in steps) {
      if (total / s <= 8) return s;
    }
    return 100;
  }
}
