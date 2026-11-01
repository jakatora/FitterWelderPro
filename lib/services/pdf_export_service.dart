import '../utils/decimal_input_text.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/project.dart';
import '../models/segment.dart';
import '../services/bar_nesting.dart';
import '../services/cut_list_csv.dart' show cutListFileStem;
import '../services/cut_list_summary.dart';
import '../services/heat_traceability.dart' show HeatReportRow;

// ─── Kolory PDF ────────────────────────────────────────────────────────────
// The cut list is PRINTED — usually on a worn mono laser in the workshop —
// and pinned next to the saw. The old screen palette (#E8ECF0 text, dark
// card fills, orange accents) came out as invisible light grey on white paper
// and burned toner on solid blocks. Everything here is dark ink on bare
// paper: text in black / dark grey, structure in thin lines, no fills.
final PdfColor _kInk = PdfColors.black;
final PdfColor _kInkMuted = PdfColor.fromHex('#404040');
final PdfColor _kRule = PdfColor.fromHex('#555555');

const double _kHairline = 0.6;
const double _kRuleStrong = 1.2;

class PdfExportService {
  /// Generuje CUT LIST jako PDF i udostępnia przez share sheet.
  ///
  /// [sharePositionOrigin] anchors the share popover on iPad.
  static Future<void> exportCutList({
    required Project project,
    required List<Segment> segments,
    bool english = false,
    Rect? sharePositionOrigin,
    List<HeatReportRow> heatRows = const [],
  }) async {
    final now = DateTime.now();
    final bytes = await buildCutListPdf(
      project: project,
      segments: segments,
      english: english,
      generatedAt: now,
      heatRows: heatRows,
    );
    final dir = await getTemporaryDirectory();
    final name = 'CutList_${cutListFileStem(project.name ?? '')}_'
        '${now.millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    // A truncated write (full disk) would otherwise be shared as a corrupt
    // attachment and only discovered at the saw.
    if (!await file.exists() || (await file.length()) < 100) {
      throw FileSystemException('PDF zapisany niepoprawnie', file.path);
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: 'CUT LIST — ${project.name ?? ''}',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Builds the cut-list PDF (A4) and returns its bytes. No file, no share
  /// sheet — so it can be checked in tests.
  ///
  /// Text is set in the bundled Roboto (full Latin-2): the `pdf` package's
  /// default Helvetica is Latin-1 only, so ą/ć/ę/ł/ń/ś/ź/ż in project names
  /// and headings came out as empty boxes.
  ///
  /// [heatRows] (heat numbers per place, `heatReportRows`) are printed as a
  /// traceability table after the segment list when there are any.
  static Future<Uint8List> buildCutListPdf({
    required Project project,
    required List<Segment> segments,
    bool english = false,
    DateTime? generatedAt,
    List<HeatReportRow> heatRows = const [],
    @visibleForTesting pw.ThemeData? theme,
  }) async {
    final doc = pw.Document(theme: theme ?? await loadTheme());
    final t = _Tr(english);
    final stamp = _stamp(generatedAt ?? DateTime.now());

    // Grupowanie wg średnicy + ścianki i sumy — wspólna, testowalna funkcja
    // (ta sama co ekran i CSV).
    final summary = summarizeCutList(
      segments: segments,
      stockLengthMm: project.stockLengthMm,
      sawKerfMm: project.sawKerfMm,
      joinGapMm: project.gapMm,
    );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) =>
          _buildHeader(project, ctx.pageNumber, ctx.pagesCount, t),
      footer: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Fitter Welder Pro  ·  $stamp',
          style: pw.TextStyle(fontSize: 8, color: _kInkMuted),
        ),
      ),
      build: (ctx) => [
        _buildSummaryBlock(project, summary, t),
        if (summary.splitCuts.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _buildWarnings(project, summary, t),
        ],
        pw.SizedBox(height: 16),
        ...summary.groups.map((g) => _buildGroupBlock(g, project, t)),
        pw.SizedBox(height: 8),
        _buildSegmentTable(segments, summary, t),
        if (heatRows.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _buildHeatTable(heatRows, t),
        ],
      ],
    ));

    return doc.save();
  }

  /// Regular + bold Roboto from assets. Public for the test that checks the
  /// bold face really is a separate font.
  @visibleForTesting
  static Future<pw.ThemeData> loadTheme() async {
    final regular =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    // Roboto-Bold.ttf ships in assets/fonts/; the fallback keeps export
    // working if the asset is ever missing from a build.
    pw.Font bold = regular;
    try {
      bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    } catch (_) {
      // Asset not bundled — keep regular.
    }
    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
    );
  }

  static String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  // ── Nagłówek strony ──────────────────────────────────────────────────────
  static pw.Widget _buildHeader(Project p, int page, int pages, _Tr t) {
    // Line / ISO + revision / client / class on every page (schema v22): a
    // sheet that has come loose from the stack still says which job it is.
    final identity = p.identity.summary(english: t.english);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _kInk, width: _kRuleStrong),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('CUT LIST',
                    style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: _kInk)),
                // Project name identifies the sheet once it is pinned on the
                // wall — dark ink, same size as the section titles.
                pw.Text(p.name ?? '',
                    style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: _kInk)),
                if (identity.isNotEmpty)
                  pw.Text(identity,
                      style: pw.TextStyle(fontSize: 9, color: _kInk)),
              ],
            ),
          ),
          pw.Text('$page / $pages',
              style: pw.TextStyle(fontSize: 9, color: _kInkMuted)),
        ],
      ),
    );
  }

  // ── Blok podsumowania ────────────────────────────────────────────────────
  static pw.Widget _buildSummaryBlock(
      Project p, CutListSummary summary, _Tr t) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _kInk, width: 0.8),
      ),
      child: pw.Row(
        children: [
          _summaryCell(t('Materiał', 'Material'), p.materialGroup),
          _summaryCell(t('Sztanga', 'Stock'),
              '${p.stockLengthMm.toStringAsFixed(0)} mm'),
          _summaryCell(
              t('Rzaz', 'Kerf'), '${p.sawKerfMm.toStringAsFixed(1)} mm'),
          _summaryCell(t('Segmenty', 'Segments'), '${summary.segmentCount}'),
          _summaryCell(t('Sztangi', 'Bars'), '${summary.totalBars}'),
          _summaryCell(t('Rura netto', 'Net pipe'),
              '${(summary.totalNetMm / 1000).toStringAsFixed(2)} m'),
          _summaryCell(
              t('Odpad', 'Waste'), '${summary.wastePct.toStringAsFixed(1)}%'),
        ],
      ),
    );
  }

  static pw.Widget _summaryCell(String label, String value) => pw.Expanded(
        child: pw.Column(children: [
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: _kInk)),
          pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _kInkMuted)),
        ]),
      );

  // ── Ostrzeżenia: cięcie dłuższe niż sztanga ──────────────────────────────
  static pw.Widget _buildWarnings(Project p, CutListSummary summary, _Tr t) {
    // Thick left rule + thin frame: stands out on a mono print without a
    // filled (toner) background.
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: _kInk, width: 3),
          top: pw.BorderSide(color: _kInk, width: 0.8),
          right: pw.BorderSide(color: _kInk, width: 0.8),
          bottom: pw.BorderSide(color: _kInk, width: 0.8),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final piece in summary.splitCuts)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(
                '${t('UWAGA', 'WARNING')}: ${oversizeCutWarning(
                  piece,
                  stockLengthMm: p.stockLengthMm,
                  english: t.english,
                )}',
                style: pw.TextStyle(fontSize: 10, color: _kInk),
              ),
            ),
        ],
      ),
    );
  }

  // ── Blok grupy rur ────────────────────────────────────────────────────────
  static pw.Widget _buildGroupBlock(CutListGroup g, Project project, _Tr t) {
    // Same rule as the nesting: non-positive / non-finite cuts are not pipe.
    final netMm = g.cutsMm
        .where((c) => c.isFinite && c > 0)
        .fold<double>(0, (s, v) => s + v);
    final wasteMm = g.plans.fold<double>(0, (s, b) => s + b.remainingMm);
    final pieceCount = g.cutsMm.length;
    final barCount = g.plans.length;
    final title = 'Ø${decimalInputText(g.diameterMm)} × '
        '${decimalInputText(g.wallMm)} mm  ·  '
        '${t.pieces(pieceCount)}  ·  ${t.bars(barCount)}';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(bottom: 3),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _kInk, width: _kRuleStrong),
            ),
          ),
          child: pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold, color: _kInk)),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _kRule, width: _kHairline),
            bottom: pw.BorderSide(color: _kRule, width: _kHairline),
          ),
          columnWidths: const {
            0: pw.FixedColumnWidth(44),
            1: pw.FlexColumnWidth(),
            2: pw.FixedColumnWidth(40),
            3: pw.FixedColumnWidth(84),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _kInk, width: 0.8),
                ),
              ),
              children: [
                _head(t('Sztanga', 'Bar')),
                _head(t('Odcinki (segment: mm)', 'Pieces (segment: mm)')),
                _head(t('Cięcia', 'Cuts')),
                _head(t('Zostaje', 'Remaining')),
              ],
            ),
            for (var i = 0; i < g.plans.length; i++)
              _barRow(i, g.plans[i], project),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          t(
            'Netto: ${(netMm / 1000).toStringAsFixed(3)} m  ·  '
                'Odpad: ${wasteMm.toStringAsFixed(0)} mm',
            'Net: ${(netMm / 1000).toStringAsFixed(3)} m  ·  '
                'Waste: ${wasteMm.toStringAsFixed(0)} mm',
          ),
          style: pw.TextStyle(fontSize: 9, color: _kInkMuted),
        ),
        pw.SizedBox(height: 14),
      ],
    );
  }

  static pw.TableRow _barRow(int index, BarPlan bar, Project project) {
    final wastePct = project.stockLengthMm > 0
        ? (bar.remainingMm / project.stockLengthMm * 100)
        : 0.0;
    return pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        _cell('${index + 1}', size: 11, bold: true),
        // Pieces are the numbers the saw operator reads: largest type on the
        // page, each prefixed with its segment tag (S03, S03 (1/2)) and an
        // empty box to tick with a pen once it is cut.
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: pw.Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (var i = 0; i < bar.pieces.length; i++)
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (i > 0) ...[
                      pw.Text('+',
                          style: pw.TextStyle(fontSize: 11, color: _kInk)),
                      pw.SizedBox(width: 6),
                    ],
                    _tickBox(),
                    pw.SizedBox(width: 4),
                    pw.Text(formatBarPiece(bar.pieces[i]),
                        style: pw.TextStyle(fontSize: 11, color: _kInk)),
                  ],
                ),
            ],
          ),
        ),
        _cell('${bar.cutsCount}'),
        _cell('${formatCutMm(bar.remainingMm)} mm '
            '(${wastePct.toStringAsFixed(0)}%)'),
      ],
    );
  }

  /// Empty square to tick a piece off with a pen at the saw.
  static pw.Widget _tickBox() => pw.Container(
        width: 9,
        height: 9,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _kInk, width: 0.8),
        ),
      );

  // ── Numery wytopów ───────────────────────────────────────────────────────
  static pw.Widget _buildHeatTable(List<HeatReportRow> rows, _Tr t) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(t('NUMERY WYTOPÓW (IDENTYFIKOWALNOŚĆ)', 'HEAT NUMBERS (TRACEABILITY)'),
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold, color: _kInk)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _kRule, width: _kHairline),
          columnWidths: const {
            0: pw.FixedColumnWidth(80),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _kInk, width: 0.8),
                ),
              ),
              children: [
                _head('Segment'),
                _head(t('Element', 'Item')),
                _head('Heat'),
              ],
            ),
            for (final r in rows)
              pw.TableRow(children: [
                _cell(r.segments, bold: true),
                _cell(r.place),
                _cell(r.heats, size: 10, bold: true),
              ]),
          ],
        ),
      ],
    );
  }

  // ── Tabela segmentów ─────────────────────────────────────────────────────
  static pw.Widget _buildSegmentTable(
      List<Segment> segments, CutListSummary summary, _Tr t) {
    if (segments.isEmpty) return pw.SizedBox();
    // Segment → bar numbers, looked up per diameter/wall group (bar numbers
    // restart in every group).
    final barsFor = <String, String>{};
    for (final g in summary.groups) {
      g.barsByLabel.forEach((label, bars) {
        barsFor['${cutGroupKey(g.diameterMm, g.wallMm)}|$label'] =
            bars.join(', ');
      });
    }
    // A piece mark (`S03 SP02-03`) needs room; plain `S03` keeps the old
    // narrow column so an unlabelled list prints exactly as before.
    final labelled = segments.any((s) => s.label != null);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(t('LISTA SEGMENTÓW', 'SEGMENT LIST'),
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold, color: _kInk)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _kRule, width: _kHairline),
          columnWidths: {
            0: pw.FixedColumnWidth(labelled ? 96 : 48),
            1: pw.FixedColumnWidth(58),
            2: pw.FlexColumnWidth(2),
            3: pw.FixedColumnWidth(54),
            4: pw.FixedColumnWidth(54),
            5: pw.FixedColumnWidth(48),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _kInk, width: 0.8),
                ),
              ),
              children: [
                _head('Segment'),
                _head('Ø×t'),
                _head('ISO'),
                _head('ISO mm'),
                _head('CUT mm'),
                _head(t('Sztanga', 'Bar')),
              ],
            ),
            ...segments.map((s) {
              final label = segmentLabel(s);
              return pw.TableRow(
                children: [
                  _cell(label, bold: true),
                  _cell('${decimalInputText(s.diameterMm)}×'
                      '${decimalInputText(s.wallThicknessMm)}'),
                  _cell(s.isoExpr),
                  _cell(formatCutMm(s.isoMm)),
                  _cell(formatCutMm(s.cutMm), size: 10, bold: true),
                  _cell(barsFor['${cutGroupKey(s.diameterMm, s.wallThicknessMm)}|$label'] ??
                      '—'),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _head(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: _kInk)),
      );

  static pw.Widget _cell(String text, {double size = 9, bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(text,
            style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: _kInk,
            )),
      );
}

/// PL/EN picker for the PDF (no BuildContext here) plus the PL plural forms
/// used in group titles.
class _Tr {
  final bool english;
  const _Tr(this.english);

  String call(String pl, String en) => english ? en : pl;

  String pieces(int n) => english
      ? (n == 1 ? '1 piece' : '$n pieces')
      : '$n ${_pl(n, 'odcinek', 'odcinki', 'odcinków')}';

  String bars(int n) => english
      ? (n == 1 ? '1 bar' : '$n bars')
      : '$n ${_pl(n, 'sztanga', 'sztangi', 'sztang')}';

  static String _pl(int n, String one, String few, String many) {
    if (n == 1) return one;
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
    return many;
  }
}
