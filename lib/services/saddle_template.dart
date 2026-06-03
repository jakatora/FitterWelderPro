import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

// Saddle cut (fish-mouth) template generator for branch-on-header pipe
// connections. Produces:
//   1. Numeric offset table (depth around branch circumference)
//   2. Scaled visual preview of the unrolled cut profile
//   3. 1:1 strip template that the fitter wraps onto the branch pipe to
//      mark the cutting line with a marker before saddle-cutting.
//
// Geometry (90° branch on cylindrical header, no offset):
//   φ = angle around branch circumference (0..2π)
//   R_h = header outside radius
//   R_b = branch outside radius (R_b ≤ R_h)
//
//   The branch axis is perpendicular to the header axis. A point on the
//   branch surface at angular position φ has horizontal offset from the
//   branch axis of R_b·sin(φ) in the plane normal to the header axis.
//   That point first intersects the header surface (x² + y² = R_h²) when
//   z = √(R_h² - R_b²·sin²(φ)).
//
//   Depth d(φ) from the deepest point of the cut to the bottom of the
//   profile is therefore:
//     d(φ) = R_h - √(R_h² - R_b²·sin²(φ))
//
//   When unrolled, the horizontal position around the branch is x(φ) = R_b·φ.
//   So the cut profile is (x, d) parametric in φ.
//
// For angles ≠ 90° we apply a tilt correction: the effective z grows by
//   z' = z / sin(angleRad)
// This handles 45°, 60° branches with the same formula.

class SaddleCutPoint {
  /// Position around branch circumference, in degrees (0..360).
  final double phiDeg;

  /// Horizontal distance from the start of the strip (mm). When the strip is
  /// wrapped around the branch, this equals the chord traced along its OD.
  final double xMm;

  /// Depth of the cut measured from the long side ("crown") of the branch
  /// down to the line where the saddle meets the header (mm).
  final double depthMm;

  const SaddleCutPoint(this.phiDeg, this.xMm, this.depthMm);
}

class SaddleTemplate {
  final double headerOdMm;
  final double branchOdMm;
  final double angleDeg;

  /// Number of points around the branch circumference (incl. both endpoints).
  /// 73 points = every 5° around 360°.
  final int pointsCount;

  late final List<SaddleCutPoint> points;

  /// Maximum depth of the cut — at φ = 90° / 270° (the branch sides that sit
  /// deepest into the header).
  late final double maxDepthMm;

  /// Total unrolled strip length = π × branch_OD.
  late final double stripLengthMm;

  SaddleTemplate({
    required this.headerOdMm,
    required this.branchOdMm,
    required this.angleDeg,
    this.pointsCount = 73,
  }) {
    final rh = headerOdMm / 2.0;
    final rb = branchOdMm / 2.0;
    final angleRad = angleDeg * math.pi / 180.0;
    final sinA = math.sin(angleRad);

    if (branchOdMm > headerOdMm) {
      throw ArgumentError(
          'Branch OD ($branchOdMm) must be ≤ header OD ($headerOdMm)');
    }
    if (angleDeg < 15 || angleDeg > 90) {
      throw ArgumentError(
          'Angle must be in [15°, 90°], got $angleDeg°');
    }

    final pts = <SaddleCutPoint>[];
    double maxD = 0;
    for (int i = 0; i < pointsCount; i++) {
      final phi = (i / (pointsCount - 1)) * 2 * math.pi;
      final phiDeg = phi * 180 / math.pi;
      final sinPhi = math.sin(phi);

      // depth at this angular position
      final under = rh * rh - rb * rb * sinPhi * sinPhi;
      // shouldn't go negative when rb ≤ rh; clamp for numerical safety
      final z = under > 0 ? math.sqrt(under) : 0.0;
      // tilt correction for off-90° angles
      double dRaw = (rh - z);
      if (angleDeg < 90) {
        // The cut becomes longer on the "obtuse" side and shorter on the
        // "acute" side. Simple linear model used by most field guides:
        // d(φ, α) = (rh - z)/sin(α) + rb·cos(α)·cos(φ)
        final tiltAdd = rb * math.cos(angleRad) * math.cos(phi);
        dRaw = (rh - z) / sinA + tiltAdd;
      }
      if (dRaw < 0) dRaw = 0;
      if (dRaw > maxD) maxD = dRaw;

      final x = rb * phi; // unrolled circumference (mm)
      pts.add(SaddleCutPoint(phiDeg, x, dRaw));
    }

    points = pts;
    maxDepthMm = maxD;
    stripLengthMm = 2 * math.pi * rb;
  }

  /// Generates a PDF document and shares it via the platform share sheet.
  Future<File> exportPdf({String? projectName}) async {
    final doc = pw.Document();
    doc.addPage(_buildSummaryPage(projectName));
    doc.addPage(_buildScaledPreviewPage());
    final stripPages = _buildStripPages();
    for (final page in stripPages) {
      doc.addPage(page);
    }

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final f = File('${dir.path}/saddle_${branchOdMm.toInt()}x${headerOdMm.toInt()}_$stamp.pdf');
    await f.writeAsBytes(await doc.save());

    await Share.shareXFiles(
      [XFile(f.path)],
      subject: 'Saddle template ${branchOdMm.toStringAsFixed(0)}×${headerOdMm.toStringAsFixed(0)} mm @ ${angleDeg.toStringAsFixed(0)}°',
    );
    return f;
  }

  // ── PDF pages ───────────────────────────────────────────────────────────

  pw.Page _buildSummaryPage(String? projectName) {
    final kAccent = PdfColor.fromHex('#26A69A');
    final kCard = PdfColor.fromHex('#F5F7FA');
    final kMuted = PdfColor.fromHex('#6B7280');
    final kText = PdfColor.fromHex('#1A1D26');

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('FITTER WELDER PRO  ·  Saddle template',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: kAccent)),
            pw.SizedBox(height: 6),
            if (projectName != null && projectName.isNotEmpty)
              pw.Text(projectName, style: pw.TextStyle(fontSize: 12, color: kMuted)),
            pw.Text(DateTime.now().toString().substring(0, 16),
                style: pw.TextStyle(fontSize: 10, color: kMuted)),
            pw.SizedBox(height: 22),

            // Specs block
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: kCard,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                children: [
                  _specBox('Header OD', '${headerOdMm.toStringAsFixed(1)} mm', kAccent),
                  _specBox('Branch OD', '${branchOdMm.toStringAsFixed(1)} mm', kAccent),
                  _specBox('Angle', '${angleDeg.toStringAsFixed(0)}°', kAccent),
                  _specBox('Max depth', '${maxDepthMm.toStringAsFixed(1)} mm', kAccent),
                ],
              ),
            ),

            pw.SizedBox(height: 18),
            pw.Text('Offsets table  ·  (depth from crown, per 15° around branch)',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: kText)),
            pw.SizedBox(height: 6),
            _offsetsTable(),

            pw.SizedBox(height: 18),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#FFF8E6'),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('How to use:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('1. Mark a longitudinal reference line along the branch pipe (top of the saddle).', style: pw.TextStyle(fontSize: 9)),
                  pw.Text('2. Cut the strip pages out and tape them together end-to-end.', style: pw.TextStyle(fontSize: 9)),
                  pw.Text('3. Wrap the strip around the branch, aligning the 0° edge with your reference line.', style: pw.TextStyle(fontSize: 9)),
                  pw.Text('4. Trace the cut curve onto the pipe with a marker, then saw / grind / plasma-cut.', style: pw.TextStyle(fontSize: 9)),
                  pw.Text('5. Final fit-up gap before weld: ≤3 mm; root opening 2-4 mm typical.', style: pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),

            pw.Spacer(),
            pw.Divider(color: kMuted),
            pw.Text('Generated by Fitter Welder Pro · Print at 100% scale. Verify dimensions with a ruler on page 3+.',
                style: pw.TextStyle(fontSize: 8, color: kMuted)),
          ],
        );
      },
    );
  }

  pw.Widget _specBox(String label, String value, PdfColor accent) {
    return pw.Expanded(
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label.toUpperCase(),
                style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#6B7280'), letterSpacing: 1)),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: accent)),
          ],
        ),
      ),
    );
  }

  pw.Widget _offsetsTable() {
    final headerBg = PdfColor.fromHex('#E5E7EB');
    final rowAlt = PdfColor.fromHex('#F9FAFB');
    final kText = PdfColor.fromHex('#1A1D26');
    final kAccent = PdfColor.fromHex('#26A69A');

    final picks = <SaddleCutPoint>[];
    for (int i = 0; i < points.length; i++) {
      // Every 15° → 25 rows (0-360 inclusive)
      if ((i * 5) % 15 == 0) picks.add(points[i]);
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColor.fromHex('#D1D5DB'), width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            _cell('Position', isHeader: true),
            _cell('Wrap distance', isHeader: true),
            _cell('Depth from crown', isHeader: true),
          ],
        ),
        ...picks.asMap().entries.map((e) {
          final p = e.value;
          final alt = e.key % 2 == 1;
          return pw.TableRow(
            decoration: alt ? pw.BoxDecoration(color: rowAlt) : null,
            children: [
              _cell('${p.phiDeg.toStringAsFixed(0)}°'),
              _cell('${p.xMm.toStringAsFixed(1)} mm'),
              _cell('${p.depthMm.toStringAsFixed(2)} mm',
                  color: p.depthMm > maxDepthMm * 0.9 ? kAccent : kText, bold: p.depthMm > maxDepthMm * 0.9),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _cell(String text, {bool isHeader = false, PdfColor? color, bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: (isHeader || bold) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColor.fromHex('#1A1D26'),
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Page _buildScaledPreviewPage() {
    final kAccent = PdfColor.fromHex('#26A69A');
    final kText = PdfColor.fromHex('#1A1D26');

    return pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Scaled preview · NOT 1:1', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: kAccent)),
            pw.Text(
                'Pages 3+ contain the actual 1:1 cutting strip. This page is for visual reference only.',
                style: pw.TextStyle(fontSize: 9, color: PdfColor.fromHex('#6B7280'))),
            pw.SizedBox(height: 12),
            pw.Expanded(
              child: pw.CustomPaint(
                size: const PdfPoint(0, 0), // takes parent box size
                painter: (canvas, size) => _drawCutProfile(canvas, size, kAccent, kText),
              ),
            ),
          ],
        );
      },
    );
  }

  void _drawCutProfile(PdfGraphics canvas, PdfPoint size, PdfColor accent, PdfColor text) {
    // Drawing area: leave 30 px padding for labels
    final pad = 40.0;
    final dw = size.x - pad * 2;
    final dh = size.y - pad * 2;
    if (dw <= 0 || dh <= 0) return;

    // Scale to fit strip + max depth
    final sx = dw / stripLengthMm;
    final maxDepthDraw = maxDepthMm.clamp(1, double.infinity);
    final sy = (dh * 0.7) / maxDepthDraw;
    final scale = math.min(sx, sy);

    // Center origin vertically
    final originX = pad;
    final originY = size.y - pad - (size.y - 2 * pad) * 0.15;

    // Axes
    canvas.setColor(PdfColor.fromHex('#9CA3AF'));
    canvas.setLineWidth(0.5);
    canvas.drawLine(originX, originY, originX + dw, originY);
    canvas.strokePath();

    // 0/90/180/270/360 vertical guides
    for (final phi in [0, 90, 180, 270, 360]) {
      final x = originX + (phi / 360.0) * stripLengthMm * scale;
      canvas.setColor(PdfColor.fromHex('#D1D5DB'));
      canvas.drawLine(x, originY - dh * 0.7, x, originY + 10);
      canvas.strokePath();
    }

    // Cut profile curve
    canvas.setColor(accent);
    canvas.setLineWidth(1.5);
    bool first = true;
    for (final p in points) {
      final x = originX + p.xMm * scale;
      final y = originY - p.depthMm * scale;
      if (first) {
        canvas.moveTo(x, y);
        first = false;
      } else {
        canvas.lineTo(x, y);
      }
    }
    canvas.strokePath();

    // Fill area under curve with light accent
    canvas.setColor(PdfColor.fromHex('#B2DFDB'));
    canvas.moveTo(originX, originY);
    for (final p in points) {
      final x = originX + p.xMm * scale;
      final y = originY - p.depthMm * scale;
      canvas.lineTo(x, y);
    }
    canvas.lineTo(originX + stripLengthMm * scale, originY);
    canvas.lineTo(originX, originY);
    canvas.fillPath();

    // Re-draw the curve on top of the fill (so it shows crisply).
    canvas.setColor(accent);
    canvas.setLineWidth(1.5);
    first = true;
    for (final p in points) {
      final x = originX + p.xMm * scale;
      final y = originY - p.depthMm * scale;
      if (first) {
        canvas.moveTo(x, y);
        first = false;
      } else {
        canvas.lineTo(x, y);
      }
    }
    canvas.strokePath();
  }

  /// 1:1 cutting strip. May span multiple landscape A4 pages if the branch
  /// circumference exceeds the printable width of one page.
  List<pw.Page> _buildStripPages() {
    // A4 landscape printable width = 297mm − 20mm side margins = 277mm.
    const printableWmm = 277.0;
    final pages = <pw.Page>[];

    var startX = 0.0;
    int pageIdx = 1;
    while (startX < stripLengthMm) {
      final endX = math.min(startX + printableWmm, stripLengthMm);
      final isLast = endX >= stripLengthMm - 1e-3;
      pages.add(_buildOneStripPage(startX, endX, pageIdx, isLast));
      startX = endX;
      pageIdx++;
    }
    return pages;
  }

  pw.Page _buildOneStripPage(double startX, double endX, int pageIdx, bool isLast) {
    final kAccent = PdfColor.fromHex('#26A69A');
    final kMuted = PdfColor.fromHex('#6B7280');

    return pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(10, 14, 10, 14),
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Cutting strip · Page $pageIdx  ·  ${startX.toStringAsFixed(1)} mm  →  ${endX.toStringAsFixed(1)} mm  (1:1)',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: kAccent),
                ),
                pw.Text(
                  'Verify: ruler from 0 to 10 mm at bottom → must measure 10 mm',
                  style: pw.TextStyle(fontSize: 8, color: kMuted),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Expanded(
              child: pw.CustomPaint(
                size: const PdfPoint(0, 0),
                painter: (canvas, size) => _drawStrip11(canvas, size, startX, endX, kAccent, isLast),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              isLast
                  ? 'End of template. Align this edge with the next wrap layer if branch is split (multi-strip).'
                  : 'Continued on next page — tape the right edge of this strip to the LEFT edge of page ${pageIdx + 1}.',
              style: pw.TextStyle(fontSize: 8, color: kMuted),
            ),
          ],
        );
      },
    );
  }

  /// Draws the strip 1:1 — every PDF point (1/72 inch) maps to mm at the
  /// printable scale set by the [PdfPoint] units. Since [PdfPageFormat] uses
  /// points (not mm), we explicitly convert: 1 mm = 2.83465 PDF points.
  ///
  /// Text labels (mm marks, degree markers) are intentionally rendered via
  /// pw.Positioned in the parent page Stack — not via canvas.drawString —
  /// because PdfGraphics expects a [PdfFont] handle that requires a document
  /// context we don't have inside this painter callback.
  void _drawStrip11(PdfGraphics canvas, PdfPoint size, double startX, double endX, PdfColor accent, bool isLast) {
    const ptsPerMm = 2.83465;
    final widthMm = endX - startX;
    final widthPts = widthMm * ptsPerMm;

    final baselineY = 30.0; // small margin from bottom

    // Filter points inside [startX, endX]
    final inRange = points
        .where((p) => p.xMm >= startX - 1e-6 && p.xMm <= endX + 1e-6)
        .toList();

    if (inRange.isEmpty) return;

    // Baseline ruler (every 10 mm, longer tick every 50 mm, longest every 100 mm)
    canvas.setColor(PdfColor.fromHex('#9CA3AF'));
    canvas.setLineWidth(0.4);
    for (var x = startX.ceilToDouble(); x <= endX; x += 10.0) {
      final px = (x - startX) * ptsPerMm;
      final isMajor = (x % 100).abs() < 1e-6;
      final isMid = (x % 50).abs() < 1e-6;
      final tickH = isMajor ? 8.0 : (isMid ? 5.0 : 3.0);
      canvas.drawLine(px, baselineY - tickH, px, baselineY);
      canvas.strokePath();
    }

    // Horizontal baseline (long axis = unrolled branch circumference)
    canvas.setColor(PdfColor.fromHex('#374151'));
    canvas.setLineWidth(0.6);
    canvas.drawLine(0, baselineY, widthPts, baselineY);
    canvas.strokePath();

    // 10 mm verification scale at top-left (so user can confirm 1:1 print).
    // No text label here either — the label is rendered as a pw.Text in the
    // page Stack just above this point.
    canvas.setColor(PdfColor.fromHex('#1F2937'));
    canvas.setLineWidth(0.6);
    canvas.drawLine(4, baselineY - 22, 4 + 10 * ptsPerMm, baselineY - 22);
    canvas.strokePath();
    // Small tick marks at the 0 and 10 mm ends of the verification scale.
    canvas.drawLine(4, baselineY - 24, 4, baselineY - 20);
    canvas.drawLine(4 + 10 * ptsPerMm, baselineY - 24, 4 + 10 * ptsPerMm, baselineY - 20);
    canvas.strokePath();

    // Cut profile (depth pointing UPWARDS from baseline, mimics branch lying flat)
    canvas.setColor(accent);
    canvas.setLineWidth(1.2);
    bool first = true;
    for (final p in inRange) {
      final px = (p.xMm - startX) * ptsPerMm;
      final py = baselineY + p.depthMm * ptsPerMm;
      if (first) {
        canvas.moveTo(px, py);
        first = false;
      } else {
        canvas.lineTo(px, py);
      }
    }
    canvas.strokePath();
  }
}
