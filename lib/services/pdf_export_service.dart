import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/project.dart';
import '../models/segment.dart';
import '../services/bar_nesting.dart';

// ─── Kolory PDF ────────────────────────────────────────────────────────────
final _kAccent   = PdfColor.fromHex('#F5A623');
final _kCard     = PdfColor.fromHex('#1A1D26');
final _kBorder   = PdfColor.fromHex('#2C3354');
final _kText     = PdfColor.fromHex('#E8ECF0');
final _kMuted    = PdfColor.fromHex('#9BA3C7');
final _kGreen    = PdfColor.fromHex('#2ECC71');

class PdfExportService {
  /// Generuje CUT LIST jako PDF i udostępnia przez share sheet.
  static Future<void> exportCutList({
    required Project project,
    required List<Segment> segments,
  }) async {
    final doc = pw.Document();

    // Grupuj wg średnicy + ścianki
    final groups = <String, List<double>>{};
    for (final s in segments) {
      final key = '${s.diameterMm}|${s.wallThicknessMm}';
      groups.putIfAbsent(key, () => []).add(s.cutMm);
    }

    // Oblicz podsumowanie
    int totalBars = 0;
    double totalNet = 0;
    double totalWaste = 0;
    final groupPlans = <String, List<BarPlan>>{};
    for (final e in groups.entries) {
      final cuts = List<double>.from(e.value)..sort((a, b) => b.compareTo(a));
      final plans = nestCutsToBars(
        cutsMm: cuts,
        stockLengthMm: project.stockLengthMm,
        sawKerfMm: project.sawKerfMm,
      );
      groupPlans[e.key] = plans;
      totalBars  += plans.length;
      totalNet   += cuts.fold(0.0, (s, v) => s + v);
      totalWaste += plans.fold(0.0, (s, b) => s + b.remainingMm);
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => _buildHeader(project, ctx.pageNumber, ctx.pagesCount),
      footer: (_) => pw.Text(
        'Fitter Welder Pro  ·  ${DateTime.now().toString().substring(0, 16)}',
        style: pw.TextStyle(fontSize: 8, color: _kMuted),
      ),
      build: (ctx) => [
        _buildSummaryBlock(project, totalBars, totalNet, totalWaste, segments.length),
        pw.SizedBox(height: 20),
        ...groupPlans.entries.map((e) {
          final parts = e.key.split('|');
          final d = double.parse(parts[0]);
          final w = double.parse(parts[1]);
          return _buildGroupBlock(
            diameterMm: d,
            wallMm: w,
            cuts: groups[e.key]!,
            plans: e.value,
            project: project,
          );
        }),
        pw.SizedBox(height: 20),
        _buildSegmentTable(segments),
      ],
    ));

    // Zapisz do pliku tymczasowego
    final bytes = await doc.save();
    final dir   = await getTemporaryDirectory();
    final name  = 'CutList_${_safeName(project.name ?? 'projekt')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file  = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);

    // Udostępnij
    await Share.shareXFiles([XFile(file.path)], subject: 'CUT LIST — ${project.name ?? ''}');
  }

  // ── Nagłówek strony ──────────────────────────────────────────────────────
  static pw.Widget _buildHeader(Project p, int page, int pages) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('CUT LIST', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _kAccent)),
            pw.Text(p.name ?? '', style: pw.TextStyle(fontSize: 11, color: _kMuted)),
          ]),
          pw.Text('$page / $pages', style: pw.TextStyle(fontSize: 10, color: _kMuted)),
        ],
      ),
    );
  }

  // ── Blok podsumowania ────────────────────────────────────────────────────
  static pw.Widget _buildSummaryBlock(
      Project p, int totalBars, double totalNetMm, double totalWasteMm, int segCount) {
    final wastePct = totalBars > 0 ? (totalWasteMm / (totalBars * p.stockLengthMm) * 100) : 0.0;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#1A1D26'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _kBorder),
      ),
      child: pw.Row(
        children: [
          _summaryCell('Materiał',    p.materialGroup),
          _summaryCell('Sztanga',     '${p.stockLengthMm.toStringAsFixed(0)} mm'),
          _summaryCell('Kerf',        '${p.sawKerfMm.toStringAsFixed(1)} mm'),
          _summaryCell('Segmenty',    '$segCount'),
          _summaryCell('Sztangi',     '$totalBars'),
          _summaryCell('Rura netto',  '${(totalNetMm/1000).toStringAsFixed(2)} m'),
          _summaryCell('Odpad',       '${wastePct.toStringAsFixed(1)}%'),
        ],
      ),
    );
  }

  static pw.Widget _summaryCell(String label, String value) => pw.Expanded(
    child: pw.Column(children: [
      pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _kAccent)),
      pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _kMuted)),
    ]),
  );

  // ── Blok grupy rur ────────────────────────────────────────────────────────
  static pw.Widget _buildGroupBlock({
    required double diameterMm,
    required double wallMm,
    required List<double> cuts,
    required List<BarPlan> plans,
    required Project project,
  }) {
    final sortedCuts = List<double>.from(cuts)..sort((a, b) => b.compareTo(a));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: _kCard,
          child: pw.Text(
            'Ø${diameterMm.toStringAsFixed(1)} × ${wallMm.toStringAsFixed(1)} mm  ·  ${cuts.length} odcinków  ·  ${plans.length} sztangi',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _kAccent),
          ),
        ),
        // Odcinki
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _kBorder)),
          child: pw.Wrap(
            spacing: 6,
            runSpacing: 4,
            children: sortedCuts.map((c) => pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#22263A'),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text('${c.toStringAsFixed(0)} mm', style: pw.TextStyle(fontSize: 9, color: _kText)),
            )).toList(),
          ),
        ),
        pw.SizedBox(height: 6),
        // Sztangi
        ...plans.asMap().entries.map((entry) {
          final i   = entry.key;
          final bar = entry.value;
          final wastePct = project.stockLengthMm > 0 ? (bar.remainingMm / project.stockLengthMm * 100) : 0.0;
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 4),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kBorder),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              children: [
                pw.SizedBox(width: 60,
                  child: pw.Text('Sztanga ${i+1}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _kAccent))),
                pw.Expanded(
                  child: pw.Text(bar.piecesMm.map((x) => x.toStringAsFixed(0)).join(' + '),
                      style: pw.TextStyle(fontSize: 10, color: _kText))),
                pw.Text('Cięcia: ${bar.cutsCount}', style: pw.TextStyle(fontSize: 8, color: _kMuted)),
                pw.SizedBox(width: 10),
                pw.Text('Zostaje: ${bar.remainingMm.toStringAsFixed(0)} mm (${wastePct.toStringAsFixed(0)}%)',
                    style: pw.TextStyle(fontSize: 8, color: wastePct < 10 ? _kGreen : _kMuted)),
              ],
            ),
          );
        }),
        pw.SizedBox(height: 14),
      ],
    );
  }

  // ── Tabela segmentów ─────────────────────────────────────────────────────
  static pw.Widget _buildSegmentTable(List<Segment> segments) {
    if (segments.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('LISTA SEGMENTÓW', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _kAccent)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _kBorder, width: 0.5),
          columnWidths: {
            0: const pw.FixedColumnWidth(35),
            1: const pw.FixedColumnWidth(60),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FixedColumnWidth(60),
            4: const pw.FixedColumnWidth(60),
          },
          children: [
            // Header
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _kCard),
              children: ['Nr', 'Ø×t', 'ISO', 'ISO mm', 'CUT mm'].map((h) =>
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: pw.Text(h, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _kAccent)),
                )).toList(),
            ),
            // Data
            ...segments.map((s) => pw.TableRow(
              children: [
                _cell('${s.seqNo}'),
                _cell('${s.diameterMm.toStringAsFixed(0)}×${s.wallThicknessMm.toStringAsFixed(1)}'),
                _cell(s.isoExpr),
                _cell(s.isoMm.toStringAsFixed(1)),
                _cell(s.cutMm.toStringAsFixed(1), bold: true),
              ],
            )),
          ],
        ),
      ],
    );
  }

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: bold ? _kAccent : _kText)),
  );

  static String _safeName(String s) => s.replaceAll(RegExp(r'[^\w\d_]'), '_');
}
