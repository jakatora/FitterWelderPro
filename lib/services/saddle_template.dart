import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'saddle_geometry.dart';
import 'saddle_print_layout.dart';
export 'saddle_geometry.dart' show SaddleCutPoint;

/// A newer input snapshot or a closed screen invalidated this export.
class SaddleExportCancelled implements Exception {
  const SaddleExportCancelled();
}

/// Numeric preview and printable template share the exact cylinder geometry.
class SaddleTemplate extends SaddleGeometry {
  final int pointsCount;
  late final List<SaddleCutPoint> points;

  SaddleTemplate(
      {required super.headerOdMm,
      required super.branchOdMm,
      required super.angleDeg,
      this.pointsCount = 73}) {
    points = sample(pointsCount);
  }

  /// Separate rendering from the share sheet so previews/tests use the same PDF.
  Future<Uint8List> buildPdf(
      {String? projectName, bool isEnglish = false}) async {
    final layout = SaddlePrintLayout(this);
    final name = (projectName ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.length > 160) {
      throw ArgumentError('Project name is limited to 160 characters');
    }
    final font =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    final doc =
        pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));
    final renderer = _SaddlePdf(this, layout, isEnglish, name);
    doc.addPage(renderer.summary());
    doc.addPage(renderer.preview());
    for (final tile in layout.tiles) {
      doc.addPage(renderer.tilePage(tile));
    }
    return doc.save();
  }

  Future<File> exportPdf(
      {String? projectName,
      bool isEnglish = false,
      bool Function()? canShare}) async {
    final bytes =
        await buildPdf(projectName: projectName, isEnglish: isEnglish);
    if (canShare != null && !canShare()) throw const SaddleExportCancelled();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final file = File(
        '${dir.path}/saddle_${branchOdMm.toInt()}x${headerOdMm.toInt()}_$stamp.pdf');
    await file.writeAsBytes(bytes);
    // Recheck after the last file-system await, immediately before sharing.
    if (canShare != null && !canShare()) throw const SaddleExportCancelled();
    await Share.shareXFiles([XFile(file.path)],
        subject: isEnglish ? 'Saddle template' : 'Szablon wycięcia siodłowego');
    return file;
  }
}

class _SaddlePdf {
  final SaddleTemplate geometry;
  final SaddlePrintLayout layout;
  final bool isEnglish;
  final String projectName;
  _SaddlePdf(this.geometry, this.layout, this.isEnglish, this.projectName);

  static const mm = PdfPageFormat.mm;
  final ink = PdfColor.fromHex('#17252A');
  final accent = PdfColor.fromHex('#146C60');
  final grid = PdfColor.fromHex('#C7CDD0');
  String tr(String pl, String en) => isEnglish ? en : pl;
  String number(double value) => value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
  String get dimensions =>
      '${tr('OD główna', 'Header OD')} ${number(geometry.headerOdMm)} mm'
      ' | ${tr('OD boczna', 'Branch OD')} ${number(geometry.branchOdMm)} mm'
      ' | ${tr('Kąt osi', 'Axis angle')} ${number(geometry.angleDeg)}°';
  String get limits => tr(
      'Centralne połączenie powierzchni zewnętrznych. Bez grubości ścianki, ukosowania, szczeliny i naddatków. '
          'Sprawdź dopasowanie na materiale oraz wymagania dokumentacji złącza przed cięciem.',
      'Centred outside-surface intersection. Wall thickness, bevel, gap and allowances are excluded. '
          'Check fit on the material and joint documentation before cutting.');

  pw.Text text(String value, {double size = 9, PdfColor? color}) =>
      pw.Text(value, style: pw.TextStyle(fontSize: size, color: color ?? ink));

  pw.Page summary() => pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12 * mm),
        build: (_) => pw
            .Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          text('FITTER WELDER PRO', size: 12, color: accent),
          text(tr('Szablon wycięcia siodłowego', 'Saddle cutting template'),
              size: 19),
          if (projectName.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            text(projectName)
          ],
          text(DateTime.now().toString().substring(0, 16), size: 8),
          pw.SizedBox(height: 12),
          text(dimensions, size: 10),
          text(
              '${tr('Maks. głębokość', 'Maximum cutback')}: ${geometry.maxDepthMm.toStringAsFixed(2)} mm'
              ' | ${tr('Obwód', 'Circumference')}: ${geometry.stripLengthMm.toStringAsFixed(2)} mm'),
          pw.SizedBox(height: 10),
          text(tr(
              'Głębokość od płaszczyzny najdłuższych końców w stronę korpusu rury.',
              'Cutback from the longest-tip plane towards the pipe body.')),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: grid, width: .4),
            children: [
              pw.TableRow(
                  decoration:
                      pw.BoxDecoration(color: PdfColor.fromHex('#E9F2F0')),
                  children: [
                    cell(tr('Pozycja', 'Position')),
                    cell(tr('Łuk od 0° (mm)', 'Arc from 0° (mm)')),
                    cell(tr('Głębokość (mm)', 'Cutback (mm)')),
                  ]),
              for (var i = 0; i <= 24; i++)
                pw.TableRow(children: [
                  cell('${i * 15}°'),
                  cell(geometry.pointAt(i * 15.0).xMm.toStringAsFixed(2)),
                  cell(geometry.pointAt(i * 15.0).depthMm.toStringAsFixed(2)),
                ]),
            ],
          ),
          pw.SizedBox(height: 10),
          text(tr('Składanie i kontrola', 'Assembly and checking'),
              size: 12, color: accent),
          pw.SizedBox(height: 4),
          text(tr(
              '1. Drukuj strony 3+ w rozmiarze rzeczywistym (100%), bez dopasowania do strony.',
              '1. Print pages 3+ at actual size (100%), with fit-to-page disabled.')),
          text(tr(
              '2. Sprawdź linijką obie podziałki 100 mm: poziomą i pionową, na każdej kartce.',
              '2. Measure both 100 mm calibration bars: horizontal and vertical, on every sheet.')),
          text(tr(
              '3. Połącz pola według R (rząd) i C (kolumna). Nakładaj pola po 5 mm; wyrównaj siatkę i zakresy X/Y, nie brzegi papieru.',
              '3. Assemble by R (row) and C (column). Overlap plots by 5 mm; match the grid and X/Y ranges, not paper edges.')),
          text(tr(
              '4. 0° leży w płaszczyźnie osi, po stronie największego wycięcia. Bazę Y=0 ustaw prostopadle do osi odgałęzienia; +Y kieruj w stronę korpusu.',
              '4. 0° lies in the axes plane on the maximum-cutback side. Align base Y=0 perpendicular to the branch axis; +Y points towards the body.')),
          text(tr(
              '5. X odmierzaj po obwodzie, nie po cięciwie. Krawędź 360° zamyka się na 0°. Sprawdź orientację przed trasowaniem.',
              '5. X is circumference arc length, not a chord. The 360° edge closes at 0°. Check orientation before marking.')),
          pw.SizedBox(height: 8),
          text(limits, size: 8),
          pw.Spacer(),
          text(
              tr('Tabela co 15°. Kontur druku jest zagęszczany niezależnie od tabeli. Strona 2 nie ma skali 1:1.',
                  'Table every 15°. The print contour is independently refined. Page 2 is not 1:1.'),
              size: 8),
        ]),
      );

  pw.Widget cell(String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.4, horizontal: 5),
        child: pw.Text(value, style: pw.TextStyle(fontSize: 8.5, color: ink)),
      );

  pw.Page preview() => pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(10 * mm),
        build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              text(
                  tr('PODGLĄD - NIE DO TRASOWANIA 1:1',
                      'PREVIEW - NOT A 1:1 CUTTING PATTERN'),
                  size: 14,
                  color: accent),
              text(dimensions),
              text(tr(
                  'Odległość X po obwodzie; głębokość Y w stronę korpusu. Kontur właściwy: strony 3+.',
                  'X follows the circumference; Y cutback points towards the body. Actual-size contour: pages 3+.')),
              pw.SizedBox(height: 8 * mm),
              pw.SizedBox(
                  width: 260 * mm,
                  height: 140 * mm,
                  child: pw.CustomPaint(
                    size: const PdfPoint(260 * mm, 140 * mm),
                    painter: (canvas, size) {
                      final scale = math.min(
                          (size.x - 20) / geometry.stripLengthMm,
                          (size.y - 20) / math.max(geometry.maxDepthMm, 1));
                      canvas.saveContext();
                      canvas.drawRect(0, 0, size.x, size.y);
                      canvas.clipPath();
                      canvas.setColor(grid);
                      canvas.setLineWidth(.5);
                      canvas.drawLine(
                          10, 10, 10 + geometry.stripLengthMm * scale, 10);
                      canvas.strokePath();
                      canvas.setColor(accent);
                      canvas.setLineWidth(1);
                      final profile =
                          geometry.profileBetween(0, geometry.stripLengthMm);
                      drawLine(
                          canvas,
                          profile,
                          (p) => PdfPoint(
                              10 + p.xMm * scale, 10 + p.depthMm * scale));
                      canvas.restoreContext();
                    },
                  )),
              text(tr(
                  'Widok zachowuje proporcje. Druk 1:1: ${layout.columns} kolumn x ${layout.rows} rzędów, zakładka 5 mm.',
                  'Proportional preview. Actual-size print: ${layout.columns} columns x ${layout.rows} rows, 5 mm overlap.')),
            ]),
      );

  pw.Page tilePage(SaddlePrintTile tile) => pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(10 * mm),
        build: (_) => pw.Stack(children: [
          pw.Positioned(
              left: 0,
              top: 0,
              right: 0,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  text(
                      'FITTER WELDER PRO | R${tile.row + 1} C${tile.column + 1} | 1:1 / 100%',
                      size: 12,
                      color: accent),
                  text(dimensions, size: 9),
                  text(
                      'X: ${tile.startX.toStringAsFixed(2)}-${tile.endX.toStringAsFixed(2)} mm'
                      ' | Y: ${tile.startY.toStringAsFixed(2)}-${tile.endY.toStringAsFixed(2)} mm'
                      ' | ${tr('zakładka', 'overlap')}: 5 mm'),
                  text(
                      tr('+Y: w stronę korpusu rury. 0°: strona największego wycięcia.',
                          '+Y: towards the pipe body. 0°: maximum-cutback side.'),
                      size: 8),
                ],
              )),
          pw.Positioned(
              left: 0,
              top: 24 * mm,
              child: pw.SizedBox(
                  width: 260 * mm,
                  height: 140 * mm,
                  child: pw.CustomPaint(
                      size: const PdfPoint(260 * mm, 140 * mm),
                      painter: (canvas, size) => drawTile(canvas, tile)))),
          pw.Positioned(
              left: 265 * mm,
              top: 30 * mm,
              child: pw.SizedBox(
                  width: 10 * mm,
                  height: 105 * mm,
                  child: pw.Stack(children: [
                    pw.Positioned(
                        left: 0,
                        top: 0,
                        child: pw.CustomPaint(
                            size: const PdfPoint(8 * mm, 100 * mm),
                            painter: (canvas, size) =>
                                ruler(canvas, vertical: true))),
                    pw.Positioned(
                        left: 0, top: 101 * mm, child: text('100 mm', size: 7)),
                  ]))),
          pw.Positioned(
              left: 0,
              top: 170 * mm,
              child: pw.SizedBox(
                  width: 100 * mm,
                  height: 12 * mm,
                  child: pw.Column(children: [
                    pw.CustomPaint(
                        size: const PdfPoint(100 * mm, 5 * mm),
                        painter: (canvas, size) =>
                            ruler(canvas, vertical: false)),
                    text('100 mm', size: 8),
                  ]))),
          pw.Positioned(
              left: 106 * mm,
              top: 170 * mm,
              right: 0,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  text(
                      tr('Sprawdź obie podziałki linijką. Nie skaluj wydruku.',
                          'Measure both bars with a ruler. Do not scale this print.'),
                      size: 8),
                  text(
                      tr('Rzędy od Y=0 w górę. Kolumny od X=0 w prawo.',
                          'Rows go up from Y=0. Columns go right from X=0.'),
                      size: 8),
                  text(
                      tr('Linie przerywane wyznaczają zakładkę 5 mm.',
                          'Dashed lines mark the 5 mm overlap.'),
                      size: 8),
                ],
              )),
        ]),
      );

  void ruler(PdfGraphics canvas, {required bool vertical}) {
    canvas.setColor(ink);
    canvas.setLineWidth(.6);
    if (vertical) {
      canvas.drawLine(3 * mm, 0, 3 * mm, 100 * mm);
    } else {
      canvas.drawLine(0, 3 * mm, 100 * mm, 3 * mm);
    }
    canvas.strokePath();
    for (var i = 0; i <= 100; i += 10) {
      final tick = i % 50 == 0 ? 2.0 : 1.0;
      if (vertical) {
        canvas.drawLine((3 - tick) * mm, i * mm, (3 + tick) * mm, i * mm);
      } else {
        canvas.drawLine(i * mm, (3 - tick) * mm, i * mm, (3 + tick) * mm);
      }
      canvas.strokePath();
    }
  }

  void drawTile(PdfGraphics canvas, SaddlePrintTile tile) {
    final width = (tile.endX - tile.startX) * mm;
    final height = (tile.endY - tile.startY) * mm;
    canvas.saveContext();
    canvas.drawRect(0, 0, width, height);
    canvas.clipPath();
    canvas.setColor(grid);
    canvas.setLineWidth(.3);
    for (var x = (tile.startX / 50).ceil() * 50.0; x <= tile.endX; x += 50) {
      canvas.drawLine(
          (x - tile.startX) * mm, 0, (x - tile.startX) * mm, height);
    }
    for (var y = (tile.startY / 50).ceil() * 50.0; y <= tile.endY; y += 50) {
      canvas.drawLine(0, (y - tile.startY) * mm, width, (y - tile.startY) * mm);
    }
    canvas.strokePath();
    canvas.setColor(ink);
    canvas.setLineWidth(.5);
    canvas.setLineDashPattern([3, 2]);
    if (tile.column > 0) canvas.drawLine(5 * mm, 0, 5 * mm, height);
    if (tile.column < layout.columns - 1) {
      canvas.drawLine(width - 5 * mm, 0, width - 5 * mm, height);
    }
    if (tile.row > 0) canvas.drawLine(0, 5 * mm, width, 5 * mm);
    if (tile.row < layout.rows - 1) {
      canvas.drawLine(0, height - 5 * mm, width, height - 5 * mm);
    }
    canvas.strokePath();
    canvas.setLineDashPattern();
    canvas.setColor(accent);
    canvas.setLineWidth(.7);
    drawLine(
        canvas,
        geometry.profileBetween(tile.startX, tile.endX),
        (p) => PdfPoint(
            (p.xMm - tile.startX) * mm, (p.depthMm - tile.startY) * mm));
    canvas.restoreContext();
    canvas.setColor(ink);
    canvas.setLineWidth(.5);
    canvas.drawRect(0, 0, width, height);
    canvas.strokePath();
  }

  void drawLine(PdfGraphics canvas, List<SaddleCutPoint> points,
      PdfPoint Function(SaddleCutPoint) transform) {
    for (var i = 0; i < points.length; i++) {
      final p = transform(points[i]);
      if (i == 0) {
        canvas.moveTo(p.x, p.y);
      } else {
        canvas.lineTo(p.x, p.y);
      }
    }
    canvas.strokePath();
  }
}
