import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

// PDF export for the ISO notebook. Captures the canvas as a raster image
// (so the painter doesn't have to be ported to the pdf widget library) and
// stacks it with a cut list table + BOM table on A4. This is the document
// monter prints / shares with brygadzista to take to the shop.

class IsoPdfExport {
  /// Renders [boundaryKey]'s canvas to a PDF and shares it via the OS share
  /// sheet. [cutListLines] is each pre-formatted line from the iso notebook's
  /// `_copySummary` (we just receive the already-built strings; no need to
  /// re-implement formatting here). [projectName] is the line number / title.
  static Future<void> export({
    required RenderRepaintBoundary boundary,
    required String projectName,
    required List<String> cutListLines,
    required Map<String, int> bom,
  }) async {
    // 1. Rasterise the canvas at 2× pixel ratio (sharper print).
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Canvas capture failed — no PNG bytes returned');
    }
    final pngBytes = byteData.buffer.asUint8List();
    final pdfImage = pw.MemoryImage(pngBytes);

    // 2. Build the PDF.
    // Bundled Roboto with full Latin-2 coverage so Polish chars (ą/ć/ę/ł/ń/ó
    // /ś/ź/ż) and engineering glyphs render correctly. The default Helvetica
    // shipped with the `pdf` package is Latin-1 only — that's why prior
    // exports rendered Polish text as blank boxes / missing glyphs.
    final fontBytes = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final baseFont = pw.Font.ttf(fontBytes);
    final theme = pw.ThemeData.withFont(
      base: baseFont,
      bold: baseFont,
      italic: baseFont,
      boldItalic: baseFont,
    );
    final doc = pw.Document(theme: theme);
    final now = DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => _header(projectName, stamp, ctx.pageNumber, ctx.pagesCount),
        footer: (_) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Fitter Welder Pro · isometric notebook',
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColor.fromHex('#9BA3C7'),
            ),
          ),
        ),
        build: (ctx) => [
          // Canvas image — capped to roughly half page so cut list fits.
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColor.fromHex('#2C3354'), width: 0.6),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(height: 14),
          if (cutListLines.isNotEmpty) ...[
            _sectionHeader('CUT LIST'),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F4F6FA'),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final l in cutListLines)
                    pw.Text(
                      l,
                      style: pw.TextStyle(
                        font: pw.Font.courier(),
                        fontSize: 9,
                        color: PdfColor.fromHex('#1A1D26'),
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
          ],
          if (bom.isNotEmpty) ...[
            _sectionHeader('BOM — zestawienie materiałowe'),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              cellAlignments: {1: pw.Alignment.centerRight},
              headers: const ['Komponent', 'Szt.'],
              data: bom.entries.map((e) => [e.key, '${e.value}']).toList(),
              border: pw.TableBorder.all(color: PdfColor.fromHex('#2C3354'), width: 0.4),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: PdfColor.fromHex('#F5A623'),
              ),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#1A1D26')),
              cellHeight: 16,
              columnWidths: const {
                0: pw.FlexColumnWidth(4),
                1: pw.FixedColumnWidth(40),
              },
            ),
          ],
        ],
      ),
    );

    // 3. Save + share. Two diagnostics added 2026-06-03 after "Eksport do
    // PDF nie działa" report:
    //   a) explicit MIME type on the XFile so Android's share sheet routes
    //      to apps that declare application/pdf in their intent filter
    //      (without this, some launchers offer only "text" targets);
    //   b) verified file existence before share so we surface the real
    //      failure if writeAsBytes silently no-ops (rare but seen on
    //      devices with low storage or scoped-storage quirks).
    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final safeName = _safeFileName(projectName.isEmpty ? 'iso' : projectName);
    final name = 'ISO_${safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    if (!await file.exists() || (await file.length()) < 100) {
      throw StateError(
        'PDF zapisany niepoprawnie — sprawdz miejsce na dysku '
        '(${dir.path}).',
      );
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: 'ISO — ${projectName.isEmpty ? "(bez nazwy)" : projectName}',
      text:
          'ISO ${projectName.isEmpty ? "(bez nazwy)" : projectName} — wygenerowany w Fitter Welder Pro',
    );
  }

  static pw.Widget _header(String projectName, String stamp, int page, int pages) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColor.fromHex('#F5A623'), width: 1.2),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'ISOMETRIC',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#F5A623'),
                  letterSpacing: 2,
                ),
              ),
              if (projectName.isNotEmpty)
                pw.Text(
                  projectName,
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: PdfColor.fromHex('#1A1D26'),
                  ),
                ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Wygenerowano $stamp',
                style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#9BA3C7')),
              ),
              pw.Text(
                'str. $page / $pages',
                style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#9BA3C7')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F5A623'),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          // Dark navy (not white) so B/W laser prints stay legible — orange
          // fill renders as ~30% gray on mono printers, and white-on-gray
          // becomes invisible on the sheet pinned in the workshop.
          color: PdfColor.fromHex('#1A1D26'),
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  static String _safeFileName(String s) {
    return s
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .substring(0, s.length.clamp(0, 40));
  }

  /// Helper to capture from a `GlobalKey` of a `RepaintBoundary` at call time.
  static Future<Uint8List> captureBoundary(GlobalKey key,
      {double pixelRatio = 2.0}) async {
    final ctx = key.currentContext;
    if (ctx == null) throw StateError('Repaint boundary not mounted');
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Repaint boundary not found at key');
    }
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) throw StateError('PNG conversion failed');
    return bd.buffer.asUint8List();
  }
}
