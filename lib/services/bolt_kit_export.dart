/// Zamówienie śrub do kołnierzy do udostępnienia: tekst (komunikator,
/// e-mail do magazynu) i PDF.
///
/// Ta sama mechanika co `flange_check_export.dart`: Roboto z `assets/fonts/`
/// (polskie znaki), atrament do druku zamiast ciemnej palety ekranu, plik
/// tymczasowy sprawdzony co do długości i arkusz udostępniania systemu.
/// Fonty przekazywane z zewnątrz, żeby test renderował prawdziwą stronę.
///
///   * PURE — tekst zamówienia, nazwa pliku, budowa dokumentu PDF.
///   * PLATFORM — [shareBoltKit]: zapis i arkusz udostępniania.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/bolting/bolt_kit.dart';

enum BoltKitShareFormat { text, pdf }

/// Funkcja udostępniania wstrzykiwana do ekranu (test podmienia ją, żeby
/// nie wołać platformy).
typedef BoltKitShareFn = Future<void> Function(
    BoltKitOrder order, BoltKitShareFormat format, bool en);

// ═══════════════════════════════════════════════════════════════════════════
// PURE HALF
// ═══════════════════════════════════════════════════════════════════════════

String _t(bool en, String pl, String e) => en ? e : pl;

String _title(bool en) =>
    _t(en, 'ZAMÓWIENIE ŚRUB DO KOŁNIERZY', 'FLANGE BOLTING ORDER');

/// Opis połączenia bez liczby: „DN150 (6") · Class 300 · RF — A193 B7 /
/// A194 2H, spiralna (ASME B16.20), 12 × 3/4" × 4-3/4"”. Ten sam w tekście
/// i w komórce tabeli PDF — oznaczenie szpilek nie może zniknąć z PDF.
String jointDescription(BoltKitJoint j, {required bool en}) {
  final s = j.stud;
  final studs = s == null
      ? ''
      : ', ${s.boltCount} × ${studDesignation(s.size, s.lengthQuarterIn)}';
  return '${jointTitle(j)} — ${j.material.pair}, '
      '${jointGasketLabel(j, en: en)}$studs';
}

/// Wiersz połączenia w tekście: „4 × ” + [jointDescription].
String jointLine(BoltKitJoint j, {required bool en}) =>
    '${j.count} × ${jointDescription(j, en: en)}';

/// Wiersze tabeli „Połączenia” w PDF: (liczba, opis).
List<(String, String)> boltKitPdfJointRows(BoltKitOrder o,
        {required bool en}) =>
    [
      for (final j in o.joints) ('${j.count} ×', jointDescription(j, en: en)),
    ];

/// Zamówienie jako zwykły tekst.
String buildBoltKitText(BoltKitOrder o, {required bool en}) {
  final buf = StringBuffer()..writeln(_title(en));
  buf
    ..writeln()
    ..writeln(
        _t(en, 'Połączenia (${o.totalJoints}):', 'Joints (${o.totalJoints}):'));
  for (final j in o.joints) {
    buf.writeln('• ${jointLine(j, en: en)}');
  }
  buf
    ..writeln()
    ..writeln(_t(en, 'Szpilki (stud bolts):', 'Stud bolts:'));
  for (final l in o.studs) {
    buf.writeln('• ${studLineLabel(l, en: en)} — '
        '${qtyLabel(l.qty, o.sparePercent, en: en)}');
  }
  buf
    ..writeln()
    ..writeln(_t(en, 'Nakrętki (2 na szpilkę):', 'Nuts (2 per stud):'));
  for (final l in o.nuts) {
    buf.writeln('• ${nutLineLabel(l, en: en)} — '
        '${qtyLabel(l.qty, o.sparePercent, en: en)}');
  }
  buf
    ..writeln()
    ..writeln(_t(en, 'Uszczelki:', 'Gaskets:'));
  for (final l in o.gaskets) {
    buf.writeln('• ${gasketLineLabel(l, en: en)} — '
        '${qtyLabel(l.qty, o.sparePercent, en: en)}');
  }
  buf.writeln();
  if (o.sparePercent > 0) {
    buf.writeln(_t(en, 'Zapas: ${o.sparePercent} % (zaokrąglony w górę).',
        'Spare: ${o.sparePercent} % (rounded up).'));
  }
  buf
    ..writeln(boltKitAssumptionsNote(en: en))
    ..write('Fitter Welder Pro');
  return buf.toString();
}

/// `Sruby_kolnierze_2026-10-17.pdf`.
String boltKitFileName(DateTime date, {required String extension}) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Sruby_kolnierze_${date.year}-${two(date.month)}-${two(date.day)}'
      '.$extension';
}

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');

/// Zamówienie A4. [pw.MultiPage] — długa lista połączeń przechodzi na
/// kolejne strony.
pw.Document buildBoltKitPdf(
  BoltKitOrder o, {
  required pw.Font font,
  pw.Font? boldFont,
  required bool en,
  required DateTime generatedAt,
}) {
  final bold = boldFont ?? font;
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
        base: font, bold: bold, italic: font, boldItalic: bold),
  );
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${generatedAt.year}-${two(generatedAt.month)}-'
      '${two(generatedAt.day)} ${two(generatedAt.hour)}:'
      '${two(generatedAt.minute)}';
  final small = pw.TextStyle(fontSize: 8, color: _kInkMuted);
  final body = pw.TextStyle(fontSize: 9.5, color: _kInk);
  final head =
      pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _kInk);
  final spare = o.sparePercent > 0;

  pw.Widget cell(String s, {pw.TextStyle? style, bool right = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(s,
            style: style ?? body,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
      );

  pw.Widget section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
        child: pw.Text(title.toUpperCase(),
            style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: _kInkMuted,
                letterSpacing: 0.8)),
      );

  pw.Widget qtyTable(String what, List<(String, int)> rows) => pw.Table(
        border: pw.TableBorder.all(color: _kRule, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(),
          1: const pw.FixedColumnWidth(54),
          if (spare) 2: const pw.FixedColumnWidth(70),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _kHeadFill),
            children: [
              cell(what, style: head),
              cell(_t(en, 'Ilość', 'Qty'), style: head, right: true),
              if (spare)
                cell(
                    _t(en, 'Z zapasem ${o.sparePercent} %',
                        'With ${o.sparePercent} % spare'),
                    style: head,
                    right: true),
            ],
          ),
          for (final (label, qty) in rows)
            pw.TableRow(children: [
              cell(label),
              cell('$qty', right: true),
              if (spare)
                cell('${o.spare(qty)}',
                    style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _kInk),
                    right: true),
            ]),
        ],
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    maxPages: 60,
    header: (ctx) => ctx.pageNumber == 1
        ? pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(
              border:
                  pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5)),
            ),
            child: pw.Text(_title(en),
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _kInk)),
          )
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(_title(en), style: small)),
    footer: (ctx) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(boltKitAssumptionsNote(en: en), style: small),
          pw.SizedBox(height: 2),
          pw.Text(
              'Fitter Welder Pro  ·  $stamp  ·  '
              '${_t(en, 'Strona', 'Page')} ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: small),
        ],
      ),
    ),
    build: (_) => [
      section(
          _t(en, 'Połączenia (${o.totalJoints})', 'Joints (${o.totalJoints})')),
      pw.Table(
        border: pw.TableBorder.all(color: _kRule, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(40),
          1: pw.FlexColumnWidth(),
        },
        children: [
          for (final (count, description) in boltKitPdfJointRows(o, en: en))
            pw.TableRow(children: [
              cell(count, style: head, right: true),
              cell(description),
            ]),
        ],
      ),
      section(_t(en, 'Szpilki (stud bolts)', 'Stud bolts')),
      qtyTable(
          _t(en, 'Średnica × długość, gatunek', 'Diameter × length, grade'),
          [for (final l in o.studs) (studLineLabel(l, en: en), l.qty)]),
      section(_t(en, 'Nakrętki (2 na szpilkę)', 'Nuts (2 per stud)')),
      qtyTable(_t(en, 'Średnica, typ, gatunek', 'Diameter, type, grade'),
          [for (final l in o.nuts) (nutLineLabel(l, en: en), l.qty)]),
      section(_t(en, 'Uszczelki', 'Gaskets')),
      qtyTable(_t(en, 'Typ, rozmiar', 'Type, size'),
          [for (final l in o.gaskets) (gasketLineLabel(l, en: en), l.qty)]),
      if (spare)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
              _t(en, 'Zapas ${o.sparePercent} % zaokrąglony w górę.',
                  '${o.sparePercent} % spare rounded up.'),
              style: small),
        ),
    ],
  ));
  return doc;
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM HALF
// ═══════════════════════════════════════════════════════════════════════════

/// Domyślne udostępnianie: tekst przez arkusz systemu albo PDF z pliku
/// tymczasowego.
Future<void> shareBoltKit(
    BoltKitOrder o, BoltKitShareFormat format, bool en) async {
  final subject =
      _t(en, 'Zamówienie śrub do kołnierzy', 'Flange bolting order');
  if (format == BoltKitShareFormat.text) {
    await Share.share(buildBoltKitText(o, en: en), subject: subject);
    return;
  }
  final now = DateTime.now();
  final doc = buildBoltKitPdf(
    o,
    font: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
    boldFont:
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
    en: en,
    generatedAt: now,
  );
  final bytes = await doc.save();
  final name = boltKitFileName(now, extension: 'pdf');
  if (kIsWeb) {
    await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
        subject: subject);
    return;
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  if (!await file.exists() || (await file.length()) < 100) {
    throw StateError(
        'PDF zapisany niepoprawnie — sprawdź miejsce na dysku (${dir.path}).');
  }
  await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: subject);
}
