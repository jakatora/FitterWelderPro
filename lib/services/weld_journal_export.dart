/// Data export for the weld journal — CSV (spreadsheet) and PDF (paper).
///
/// The weld journal is the only document a welder can put on the table at a
/// quality audit: weld number, welder stamp, heat numbers, WPS reference and
/// examination result. Until now `weld_journal_screen.dart` had no way of
/// getting a single row out of the phone — no PDF, no CSV, not even a
/// clipboard copy — even though `README.md` and the in-app help step
/// (`kHelpWeldJournal`, "Eksportuj dziennik do PDF lub CSV") both promise it.
/// A journal that cannot leave the device is worthless the moment the
/// inspector asks for it, so this file is the missing half of the feature.
///
/// The file is deliberately split in two halves:
///   * the top half is PURE Dart — the [WeldJournalRecord] model, CSV
///     serialisation and the small summary helpers. No I/O, no plugins, no
///     locale globals, so it is fully covered by
///     `test/services/weld_journal_export_test.dart`.
///   * the bottom half ([WeldJournalExport]) does the platform work: render
///     the PDF, write a temp file, hand it to the OS share sheet. That part
///     needs the same plugins `iso_pdf_export.dart` uses and is verified by
///     reading, not by unit tests.
///
/// Nothing here converts values. Lengths stay in millimetres exactly as the
/// welder typed them (the app's internal base unit) — an export that quietly
/// rewrites cell content cannot be reconciled against the app screen during
/// an audit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PURE HALF — model, CSV, summaries. Keep free of I/O so tests stay honest.
// ═══════════════════════════════════════════════════════════════════════════

/// One immutable journal row, decoupled from the screen's mutable `WeldEntry`.
///
/// The screen maps `WeldEntry` into this via `toExportRecord()`. The mapping
/// is an explicit constructor call (not a `Map<String, Object?>` round-trip)
/// so the compiler — not a runtime string lookup — catches a field that is
/// added to the journal and forgotten in the export.
///
/// The internal `id` (uuid) is intentionally NOT part of the export: it means
/// nothing to an inspector and only widens the sheet.
class WeldJournalRecord {
  final String weldNo;
  final String projectName;
  final String pipeName;
  final String material;

  /// Outside diameter in millimetres, as typed ("60.3" or "60,3").
  final String od;

  /// Wall thickness in millimetres, as typed.
  final String t;

  final String method;
  final String welder;

  /// ISO date `YYYY-MM-DD` as stored by the editor.
  final String date;

  final String notes;

  /// `OK` / `NOK` / `PENDING`.
  final String status;

  /// `ORBITAL` / `AUTO` / `MANUAL`.
  final String weldType;

  final String fitter;
  final String heatNo1;
  final String heatNo2;
  final String couponRef;
  final String exam;
  final String wpsRef;

  const WeldJournalRecord({
    required this.weldNo,
    this.projectName = '',
    this.pipeName = '',
    this.material = '',
    this.od = '',
    this.t = '',
    this.method = '',
    this.welder = '',
    this.date = '',
    this.notes = '',
    this.status = '',
    this.weldType = '',
    this.fitter = '',
    this.heatNo1 = '',
    this.heatNo2 = '',
    this.couponRef = '',
    this.exam = '',
    this.wpsRef = '',
  });
}

/// Field separator. Semicolon, not comma: Polish Windows Excel opens a
/// comma-separated file as one squashed column, and this file is printed and
/// mailed by Polish welders far more often than it is parsed by a script.
const String kWeldJournalCsvSeparator = ';';

/// RFC 4180 record terminator. Excel and LibreOffice both accept bare `\n`,
/// but Notepad on older Windows does not, and the journal gets opened there.
const String kWeldJournalCsvEol = '\r\n';

/// UTF-8 byte-order mark. Without it Excel decodes the file as the system
/// code page and every Polish diacritic in a welder stamp or a note turns
/// into mojibake ("Å»Ã³Å‚Ä‡") — which makes the document useless as evidence.
const String kUtf8Bom = '\u{FEFF}';

class _CsvColumn {
  /// Bilingual header. PL first (the shop floor), EN after the slash, so the
  /// same file works when the spool travels to a foreign site inspector.
  final String header;
  final String Function(WeldJournalRecord r) read;
  const _CsvColumn(this.header, this.read);
}

/// Column definition. Order follows the `WeldEntry` field order 1:1 —
/// identification first, then the ASME BPE traceability block — so a diff
/// between the model and this list is obvious at a glance.
final List<_CsvColumn> _csvColumns = <_CsvColumn>[
  _CsvColumn('Nr spoiny / Weld no.', (r) => r.weldNo),
  _CsvColumn('Projekt / Project', (r) => r.projectName),
  _CsvColumn('Rura / Pipe', (r) => r.pipeName),
  _CsvColumn('Materiał / Material', (r) => r.material),
  _CsvColumn('OD (mm)', (r) => r.od),
  _CsvColumn('t (mm)', (r) => r.t),
  _CsvColumn('Metoda / Method', (r) => r.method),
  _CsvColumn('Spawacz / Welder', (r) => r.welder),
  _CsvColumn('Data / Date', (r) => r.date),
  _CsvColumn('Uwagi / Notes', (r) => r.notes),
  _CsvColumn('Status', (r) => r.status),
  _CsvColumn('Typ spoiny / Weld type', (r) => r.weldType),
  _CsvColumn('Monter / Fitter', (r) => r.fitter),
  _CsvColumn('Nr wytopu 1 / Heat no. 1', (r) => r.heatNo1),
  _CsvColumn('Nr wytopu 2 / Heat no. 2', (r) => r.heatNo2),
  _CsvColumn('Kupon próbny / Test coupon', (r) => r.couponRef),
  _CsvColumn('Wynik badania / Examination', (r) => r.exam),
  _CsvColumn('Nr WPS / WPS no.', (r) => r.wpsRef),
];

/// Header labels in export order. Exposed so a test can pin the order down —
/// silently reordering columns would break every spreadsheet the QA
/// department already built on top of an earlier export.
List<String> get weldJournalCsvHeaders =>
    _csvColumns.map((c) => c.header).toList(growable: false);

/// Escapes one field per RFC 4180 §2.6–2.7.
///
/// A field is quoted only when it has to be (separator, double quote, CR or
/// LF inside), and an embedded double quote is doubled. Welders paste real
/// text into "Uwagi" — `grań OK; lico do szlifowania` or `spoina "na zimno"`
/// — and an unescaped semicolon there would shift every later column of that
/// row by one, silently attributing the wrong WPS to the wrong weld.
String escapeCsvField(String raw) {
  final needsQuotes = raw.contains(kWeldJournalCsvSeparator) ||
      raw.contains('"') ||
      raw.contains('\n') ||
      raw.contains('\r');
  if (!needsQuotes) return raw;
  return '"${raw.replaceAll('"', '""')}"';
}

/// Builds the whole CSV document: BOM, header row, then one row per record
/// in the order given (the caller decides the order — the screen passes the
/// list exactly as it is displayed, filter included).
///
/// An empty [records] list still yields BOM + header, so the file opens as a
/// valid — merely empty — table instead of a zero-byte attachment that looks
/// like a failed export.
String buildWeldJournalCsv(List<WeldJournalRecord> records) {
  final buf = StringBuffer()..write(kUtf8Bom);
  buf.write(_csvColumns.map((c) => escapeCsvField(c.header)).join(kWeldJournalCsvSeparator));
  buf.write(kWeldJournalCsvEol);
  for (final r in records) {
    buf.write(_csvColumns.map((c) => escapeCsvField(c.read(r))).join(kWeldJournalCsvSeparator));
    buf.write(kWeldJournalCsvEol);
  }
  return buf.toString();
}

final RegExp _isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Date span covered by [records], for the PDF header ("this document covers
/// welds from … to …" is the first thing an inspector looks for).
///
/// Only well-formed `YYYY-MM-DD` values count — the date field is free text
/// and a half-typed "2026-0" must not become the reported range start.
/// ISO dates sort lexicographically, so no DateTime parsing is needed.
/// Returns `''` when no entry carries a usable date, and a single date when
/// every weld was made the same day.
String weldJournalDateRange(List<WeldJournalRecord> records) {
  final dates = records
      .map((r) => r.date.trim())
      .where(_isoDatePattern.hasMatch)
      .toList()
    ..sort();
  if (dates.isEmpty) return '';
  if (dates.first == dates.last) return dates.first;
  return '${dates.first} - ${dates.last}';
}

/// Distinct welder stamps in the export, in first-seen order.
///
/// A shift journal usually carries one stamp, but a foreman exporting a whole
/// project gets several — the PDF header must name all of them rather than
/// implying a single welder made every joint.
String weldJournalWelders(List<WeldJournalRecord> records) {
  final seen = <String>{};
  final out = <String>[];
  for (final r in records) {
    final w = r.welder.trim();
    if (w.isEmpty || !seen.add(w)) continue;
    out.add(w);
  }
  return out.join(', ');
}

/// Status tally for the PDF summary block. Single pass; `other` catches rows
/// with a status the app no longer writes (legacy DB values) so the numbers
/// always add up to `total` and nothing disappears from the report.
({int total, int ok, int nok, int pending, int other}) weldJournalTally(
    List<WeldJournalRecord> records) {
  var ok = 0, nok = 0, pending = 0, other = 0;
  for (final r in records) {
    switch (r.status) {
      case 'OK':
        ok++;
        break;
      case 'NOK':
        nok++;
        break;
      case 'PENDING':
        pending++;
        break;
      default:
        other++;
    }
  }
  return (
    total: records.length,
    ok: ok,
    nok: nok,
    pending: pending,
    other: other,
  );
}

/// Human-readable, collision-safe file name, e.g.
/// `Dziennik_spoin_NOK_2026-08-29.csv`.
///
/// Named by date (not by epoch millis like the cut-list export) because the
/// recipient sees this string in the mail attachment list — `Dziennik_spoin_
/// 1756412345678.csv` tells an inspector nothing. Re-exporting the same day
/// overwrites the temp file, which is what we want.
String weldJournalFileName({
  required String extension,
  required DateTime generatedAt,
  String? filterLabel,
}) {
  final y = generatedAt.year.toString().padLeft(4, '0');
  final m = generatedAt.month.toString().padLeft(2, '0');
  final d = generatedAt.day.toString().padLeft(2, '0');
  final raw = (filterLabel ?? '').trim();
  final filter = (raw.isEmpty || raw == 'ALL')
      ? ''
      : '_${raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';
  return 'Dziennik_spoin${filter}_$y-$m-$d.$extension';
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM HALF — PDF rendering + share sheet.
// ═══════════════════════════════════════════════════════════════════════════

// Print-safe ink. Lesson already paid for in pdf_export_service.dart: the
// screen palette (#E8ECF0 text on a dark card) is invisible on white paper,
// and the journal is a document that gets PRINTED and signed. Everything
// here is dark enough to survive a worn mono laser in a workshop.
final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kOkInk = PdfColor.fromHex('#1E7A3C');
final PdfColor _kNokInk = PdfColor.fromHex('#B3261E');
final PdfColor _kPendingInk = PdfColor.fromHex('#8A4A00');

class WeldJournalExport {
  const WeldJournalExport._();

  /// Writes the CSV to a temp file and opens the OS share sheet.
  ///
  /// Bytes are written explicitly through [utf8] rather than
  /// `writeAsString` so the encoding of the file is decided here, next to the
  /// BOM that promises it, and cannot be changed by a platform default.
  static Future<void> shareCsv({
    required List<WeldJournalRecord> records,
    String? filterLabel,
    DateTime? generatedAt,
  }) async {
    final now = generatedAt ?? DateTime.now();
    final csv = buildWeldJournalCsv(records);
    final name = weldJournalFileName(
      extension: 'csv',
      generatedAt: now,
      filterLabel: filterLabel,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(utf8.encode(csv), flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: name)],
      subject: _subject(records, filterLabel),
    );
  }

  /// Renders the journal as a landscape A4 table and opens the share sheet.
  ///
  /// [welderFallback] is the identity stamp of the phone owner; it is only
  /// used when no entry carries a welder, so an otherwise unstamped export
  /// still says who produced it.
  static Future<void> sharePdf({
    required List<WeldJournalRecord> records,
    String? filterLabel,
    String welderFallback = '',
    DateTime? generatedAt,
  }) async {
    final now = generatedAt ?? DateTime.now();

    // Bundled Roboto covers Latin-2, so Polish text (ą/ć/ę/ł/ń/ó/ś/ź/ż) in
    // notes, welder names and project names renders. The `pdf` package's
    // built-in Helvetica is Latin-1 only and drops those glyphs — same fix
    // iso_pdf_export.dart already carries.
    final fontBytes = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final baseFont = pw.Font.ttf(fontBytes);
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: baseFont,
        italic: baseFont,
        boldItalic: baseFont,
      ),
    );

    final welders = weldJournalWelders(records);
    final range = weldJournalDateRange(records);
    final tally = weldJournalTally(records);
    final stamp = '${_isoDate(now)} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    doc.addPage(pw.MultiPage(
      // Landscape: 18 traceability fields do not fit across a portrait page
      // at a font size a welder can read in a workshop.
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (ctx) => _pageHeader(
        welders: welders.isEmpty ? welderFallback : welders,
        range: range,
        filterLabel: filterLabel,
        stamp: stamp,
        page: ctx.pageNumber,
        pages: ctx.pagesCount,
      ),
      footer: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Fitter Welder Pro  ·  $stamp',
          style: pw.TextStyle(fontSize: 7, color: _kInkMuted),
        ),
      ),
      build: (_) => [
        _summaryBlock(tally),
        pw.SizedBox(height: 10),
        _table(records),
      ],
    ));

    final bytes = await doc.save();
    final name = weldJournalFileName(
      extension: 'pdf',
      generatedAt: now,
      filterLabel: filterLabel,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    // Same guard as iso_pdf_export: a truncated write (full disk) would
    // otherwise be shared as a corrupt attachment and only discovered by the
    // inspector who cannot open it.
    if (!await file.exists() || (await file.length()) < 100) {
      throw StateError(
        'PDF zapisany niepoprawnie — sprawdź miejsce na dysku (${dir.path}).',
      );
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: _subject(records, filterLabel),
    );
  }

  static String _subject(List<WeldJournalRecord> records, String? filterLabel) {
    final range = weldJournalDateRange(records);
    final filter = (filterLabel == null || filterLabel.isEmpty || filterLabel == 'ALL')
        ? ''
        : ' [$filterLabel]';
    final span = range.isEmpty ? '' : ' — $range';
    return 'Dziennik spoin / Weld journal$filter$span';
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── Running page header ───────────────────────────────────────────────────
  static pw.Widget _pageHeader({
    required String welders,
    required String range,
    required String? filterLabel,
    required String stamp,
    required int page,
    required int pages,
  }) {
    final showFilter =
        filterLabel != null && filterLabel.isNotEmpty && filterLabel != 'ALL';
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(
              'DZIENNIK SPOIN / WELD JOURNAL',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: _kInk,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Spawacz / Welder: ${welders.isEmpty ? '—' : welders}',
              style: pw.TextStyle(fontSize: 9, color: _kInk),
            ),
            pw.Text(
              'Zakres dat / Date range: ${range.isEmpty ? '—' : range}',
              style: pw.TextStyle(fontSize: 9, color: _kInk),
            ),
            if (showFilter)
              // The screen exports what it shows. If the welder had a filter
              // on, the paper must say so — otherwise a "NOK only" printout
              // reads as a complete journal with a catastrophic reject rate.
              pw.Text(
                'Filtr / Filter: $filterLabel',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _kPendingInk,
                ),
              ),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('$page / $pages',
                style: pw.TextStyle(fontSize: 9, color: _kInkMuted)),
            pw.SizedBox(height: 2),
            pw.Text('Wygenerowano / Generated: $stamp',
                style: pw.TextStyle(fontSize: 8, color: _kInkMuted)),
          ]),
        ],
      ),
    );
  }

  // ── Tally block ───────────────────────────────────────────────────────────
  static pw.Widget _summaryBlock(
      ({int total, int ok, int nok, int pending, int other}) t) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _kHeadFill,
        border: pw.Border.all(color: _kRule, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(children: [
        _summaryCell('Spoiny / Welds', '${t.total}', _kInk),
        _summaryCell('OK', '${t.ok}', _kOkInk),
        _summaryCell('NOK', '${t.nok}', _kNokInk),
        _summaryCell('Oczekuje / Pending', '${t.pending}', _kPendingInk),
        if (t.other > 0) _summaryCell('Inne / Other', '${t.other}', _kInkMuted),
      ]),
    );
  }

  static pw.Widget _summaryCell(String label, String value, PdfColor color) =>
      pw.Expanded(
        child: pw.Column(children: [
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: color)),
          pw.Text(label, style: pw.TextStyle(fontSize: 7, color: _kInkMuted)),
        ]),
      );

  // ── Weld table ────────────────────────────────────────────────────────────
  static pw.Widget _table(List<WeldJournalRecord> records) {
    if (records.isEmpty) {
      return pw.Text(
        'Brak spoin w tym zakresie. / No welds in this selection.',
        style: pw.TextStyle(fontSize: 9, color: _kInkMuted),
      );
    }
    const headers = <String>[
      'Nr / No.',
      'Data / Date',
      'Projekt / Rura',
      'Mat.',
      'OD x t',
      'Metoda',
      'Spawacz',
      'Monter',
      'WPS',
      'Wytop / Heat',
      'Kupon',
      'Badanie / Exam',
      'Uwagi / Notes',
      'Status',
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: _kRule, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(52),
        1: pw.FixedColumnWidth(48),
        2: pw.FlexColumnWidth(2.0),
        3: pw.FixedColumnWidth(34),
        4: pw.FixedColumnWidth(46),
        5: pw.FixedColumnWidth(42),
        6: pw.FixedColumnWidth(44),
        7: pw.FixedColumnWidth(44),
        8: pw.FlexColumnWidth(1.3),
        9: pw.FlexColumnWidth(1.4),
        10: pw.FlexColumnWidth(1.1),
        11: pw.FlexColumnWidth(1.4),
        12: pw.FlexColumnWidth(1.7),
        13: pw.FixedColumnWidth(40),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _kHeadFill),
          repeat: true, // header repeats on every page of a long journal
          children: headers
              .map((h) => pw.Padding(
                    padding:
                        const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                    child: pw.Text(h,
                        style: pw.TextStyle(
                            fontSize: 6.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _kInk)),
                  ))
              .toList(),
        ),
        ...records.map((r) => pw.TableRow(children: [
              _cell(r.weldNo, bold: true),
              _cell(r.date),
              _cell(_join(r.projectName, r.pipeName, ' / ')),
              _cell(r.material),
              _cell(_join(r.od, r.t, ' x ')),
              _cell(_join(r.method, r.weldType, ' · ')),
              _cell(r.welder),
              _cell(r.fitter),
              _cell(r.wpsRef),
              _cell(_join(r.heatNo1, r.heatNo2, ' / ')),
              _cell(r.couponRef),
              _cell(r.exam),
              _cell(r.notes),
              _cell(r.status, color: _statusInk(r.status), bold: true),
            ])),
      ],
    );
  }

  /// Joins two optional fields, dropping the glue when either side is empty
  /// so the cell never reads " / " or "60.3 x ".
  static String _join(String a, String b, String glue) {
    final l = a.trim();
    final r = b.trim();
    if (l.isEmpty) return r;
    if (r.isEmpty) return l;
    return '$l$glue$r';
  }

  static PdfColor _statusInk(String status) => switch (status) {
        'OK' => _kOkInk,
        'NOK' => _kNokInk,
        'PENDING' => _kPendingInk,
        _ => _kInk,
      };

  static pw.Widget _cell(String text, {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 7,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? _kInk,
          ),
        ),
      );
}
