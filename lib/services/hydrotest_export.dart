/// Paper for a hydrostatic pressure test — the one-page protocol.
///
/// A pressure test is an acceptance step: ASME B31.3 § 345.2.7 asks the owner
/// to retain records of the piping tested, the test fluid, the test pressure
/// and the date. Until the register in `hydrotest_dao.dart` existed there was
/// nothing to print; now that a test is stored, it has to be able to leave the
/// phone as a document somebody can sign.
///
/// Built on the same mechanics as `weld_journal_export.dart`, deliberately:
/// the bundled Roboto face from `assets/fonts/`, print-safe ink instead of the
/// dark screen palette, a temp file written with an explicit length check and
/// handed to the OS share sheet. Two files that produce audit paper should
/// fail — and be fixed — the same way.
///
/// Split in two halves, again matching the weld journal:
///   * PURE half — file name, labels, formatting, the two audit notes. No I/O,
///     no plugins, no locale globals; covered by
///     `test/services/hydrotest_export_test.dart`.
///   * PLATFORM half ([HydrotestExport]) — render, write, share. Verified by
///     reading, not by unit tests.
///
/// Nothing here converts units. Pressures are printed in bar (with MPa and psi
/// shown alongside, because a foreign inspector reads one of those), lengths
/// come out of the record in millimetres and are shown in metres only where
/// the crew measured in metres — every conversion is labelled on the page.
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../database/hydrotest_dao.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PURE HALF — naming, formatting, audit notes. Keep free of I/O.
// ═══════════════════════════════════════════════════════════════════════════

/// bar → MPa. 1 MPa = 10 bar exactly.
const double kBarPerMpa = 10.0;

/// bar → psi. Same constant the calculator screen uses, kept identical so the
/// paper never disagrees with what was on the display.
const double kPsiPerBar = 14.5038;

/// Formats one measured value for the protocol, or an em dash when it was
/// never recorded.
///
/// An empty cell is the honest rendering of "not measured". Printing `0.00`
/// there would read as a measurement of zero — which, for a pressure or a
/// hold time, is the difference between an incomplete record and a failed
/// test.
String formatHydrotestValue(double? v, {int decimals = 2, String unit = ''}) {
  if (v == null) return '—';
  final n = v.toStringAsFixed(decimals);
  return unit.isEmpty ? n : '$n $unit';
}

/// Pressure with its two conversions, e.g. `15.00 bar  (1.500 MPa · 218 psi)`.
///
/// All three go on the page because the crew works in bar, the drawing is
/// usually in MPa and the client's inspector may only have a psi gauge — and
/// an inspector who has to convert by hand is an inspector who finds a
/// discrepancy that is not there.
String formatHydrotestPressure(double? bar) {
  if (bar == null) return '—';
  return '${bar.toStringAsFixed(2)} bar  '
      '(${(bar / kBarPerMpa).toStringAsFixed(3)} MPa · '
      '${(bar * kPsiPerBar).toStringAsFixed(0)} psi)';
}

/// Hold time as `12 min` (or `12.5 min`), or an em dash when not recorded.
///
/// Trailing `.0` is dropped: nobody writes "10.0 minutes" on a protocol, and
/// the fractional form only appears when somebody actually held for half a
/// minute more.
String formatHydrotestHold(double? minutes) {
  if (minutes == null) return '—';
  final whole = minutes.roundToDouble() == minutes;
  return whole
      ? '${minutes.toStringAsFixed(0)} min'
      : '${minutes.toStringAsFixed(1)} min';
}

/// The line length back in metres, the unit the crew measured in. Stored in
/// millimetres like every other length in the app (see `hydrotest_dao.dart`).
String formatHydrotestLength(double? lengthMm) {
  if (lengthMm == null) return '—';
  return '${(lengthMm / 1000.0).toStringAsFixed(1)} m';
}

/// Bilingual warning when the hold was shorter than the code minimum, or
/// `null` when it was long enough (or was not recorded — [hydrotestMissingNote]
/// covers that case).
///
/// This is printed on the paper, not just shown in the app: a protocol with a
/// 4-minute hold that says nothing about § 345.4.2 invites the reader to
/// assume the app checked. It did — and it disagreed.
String? hydrotestHoldNote(HydrotestRecord r) {
  final h = r.holdMinutes;
  if (h == null || h >= kHydrotestMinHoldMinutes) return null;
  return 'UWAGA: czas wytrzymania ${formatHydrotestHold(h)} jest krótszy niż '
      'minimum 10 min (ASME B31.3 § 345.4.2). / WARNING: hold time is shorter '
      'than the 10 min minimum (ASME B31.3 § 345.4.2).';
}

/// Bilingual warning when a test was signed off as passed even though the
/// gauge lost pressure, or `null` otherwise.
///
/// A PASS with a measured drop is the single most common way a pressure test
/// record falls apart under review. It can be legitimate — a 10 K temperature
/// swing moves the needle on its own — but then the reason belongs in the
/// notes, and the note below is what makes somebody write it down.
String? hydrotestDropNote(HydrotestRecord r) {
  if (!r.passed || !r.hasPressureDrop) return null;
  final drop = r.pressureDropBar!;
  return 'UWAGA: zanotowano spadek ciśnienia ${drop.toStringAsFixed(2)} bar '
      'przy wyniku PASS — uzasadnij w uwagach (np. zmiana temperatury). / '
      'WARNING: a pressure drop of ${drop.toStringAsFixed(2)} bar was recorded '
      'on a PASS result — justify it in the notes (e.g. temperature change).';
}

/// Bilingual note listing the witnessed fields nobody filled in, or `null`
/// when the record is complete.
///
/// The record is deliberately permissive — a crew without a thermometer can
/// still file a test — but the resulting document must say what is missing
/// instead of leaving the reader to notice the blanks.
String? hydrotestMissingNote(HydrotestRecord r) {
  final missing = <String>[];
  if (r.gauge.trim().isEmpty) missing.add('manometr / gauge');
  if (r.pressureStartBar == null) {
    missing.add('ciśnienie początkowe / start pressure');
  }
  if (r.pressureEndBar == null) {
    missing.add('ciśnienie końcowe / end pressure');
  }
  if (r.temperatureC == null) missing.add('temperatura / temperature');
  if (r.holdMinutes == null) missing.add('czas wytrzymania / hold time');
  if (r.witness.trim().isEmpty) missing.add('świadek / witness');
  if (missing.isEmpty) return null;
  return 'Protokół niekompletny — brak: ${missing.join(', ')}. / '
      'Incomplete protocol — missing: ${missing.join(', ')}.';
}

/// Human-readable, collision-safe file name, e.g.
/// `Protokol_proby_WFI_101_2026-08-30.pdf`.
///
/// Named after the system and the date (not an epoch stamp) because this
/// string is what the recipient sees in the mail attachment list, and a
/// protocol is filed per system. Non-alphanumerics in the tag are folded to
/// `_` so no platform's file system rejects it, and the tag is capped at 32
/// characters — welders paste whole line descriptions into that field.
String hydrotestProtocolFileName({
  required String extension,
  required DateTime generatedAt,
  String? systemName,
}) {
  final y = generatedAt.year.toString().padLeft(4, '0');
  final m = generatedAt.month.toString().padLeft(2, '0');
  final d = generatedAt.day.toString().padLeft(2, '0');
  var tag = (systemName ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  // Strip the separators a fold can leave dangling at either end.
  tag = tag.replaceAll(RegExp(r'^_+|_+$'), '');
  if (tag.length > 32) tag = tag.substring(0, 32);
  final part = tag.isEmpty ? '' : '_$tag';
  return 'Protokol_proby${part}_$y-$m-$d.$extension';
}

/// Mail subject for the share sheet.
String hydrotestProtocolSubject(HydrotestRecord r) {
  final system = r.systemName.trim();
  final where = system.isEmpty ? '' : ' — $system';
  final when = r.date.trim().isEmpty ? '' : ' — ${r.date.trim()}';
  return 'Protokół próby ciśnieniowej / Hydrostatic test protocol'
      '$where$when — ${r.result}';
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM HALF — PDF rendering + share sheet.
// ═══════════════════════════════════════════════════════════════════════════

// Print-safe ink, same palette as weld_journal_export.dart. The screen colours
// (#E8ECF0 on a dark card) vanish on white paper, and this document exists to
// be printed and signed.
final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kPassInk = PdfColor.fromHex('#1E7A3C');
final PdfColor _kFailInk = PdfColor.fromHex('#B3261E');
final PdfColor _kWarnInk = PdfColor.fromHex('#8A4A00');

class HydrotestExport {
  const HydrotestExport._();

  /// Renders one test as an A4 protocol and opens the share sheet.
  ///
  /// Portrait, unlike the weld journal's landscape table: this is a form with
  /// a dozen labelled values and three signature lines, not a wide grid.
  static Future<void> sharePdf({
    required HydrotestRecord record,
    DateTime? generatedAt,
  }) async {
    final now = generatedAt ?? DateTime.now();

    // Bundled Roboto covers Latin-2, so Polish text (ą/ć/ę/ł/ń/ó/ś/ź/ż) in a
    // system tag, a witness name or the notes renders. The `pdf` package's
    // built-in Helvetica is Latin-1 only and silently drops those glyphs —
    // the same fix iso_pdf_export.dart and weld_journal_export.dart carry.
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

    final stamp = '${_isoDate(now)} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => _pageHeader(
        record: record,
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
        _resultBanner(record),
        pw.SizedBox(height: 12),
        _section('IDENTYFIKACJA / IDENTIFICATION', [
          _row('System / linia — System / line', record.systemName),
          _row('Data próby — Test date', record.date),
          _row('Manometr (nr / kalibracja) — Gauge (no. / calibration)',
              record.gauge),
          _row('Świadek / inspektor — Witness / inspector', record.witness),
        ]),
        pw.SizedBox(height: 10),
        _section('PRZEBIEG PRÓBY / TEST RECORD', [
          _row('Ciśnienie początkowe — Start pressure',
              formatHydrotestPressure(record.pressureStartBar)),
          _row('Ciśnienie końcowe — End pressure',
              formatHydrotestPressure(record.pressureEndBar)),
          _row('Spadek ciśnienia — Pressure drop',
              formatHydrotestValue(record.pressureDropBar, unit: 'bar')),
          _row('Temperatura — Temperature',
              formatHydrotestValue(record.temperatureC, decimals: 1, unit: '°C')),
          _row('Czas wytrzymania — Hold time',
              formatHydrotestHold(record.holdMinutes)),
          _row('Minimum wg ASME B31.3 § 345.4.2 — Code minimum', '10 min'),
        ]),
        pw.SizedBox(height: 10),
        // The calculator snapshot, kept verbatim from the moment of saving —
        // see HydrotestRecord's doc for why it is copied and not recomputed.
        _section('OBLICZENIA / CALCULATION', [
          _row('Średnica zewnętrzna — Outside diameter',
              formatHydrotestValue(record.odMm, unit: 'mm')),
          _row('Ścianka — Wall thickness',
              formatHydrotestValue(record.wallMm, unit: 'mm')),
          _row('Długość linii — Line length',
              formatHydrotestLength(record.lineLengthMm)),
          _row('Objętość wody — Water volume',
              formatHydrotestValue(record.volumeL, decimals: 1, unit: 'L')),
          _row('Ciśnienie projektowe — Design pressure',
              formatHydrotestPressure(record.designBar)),
          _row('Współczynnik próby — Test factor',
              record.factor == null
                  ? '—'
                  : '${record.factor!.toStringAsFixed(2)} ×'),
          _row('Ciśnienie próbne (obliczone) — Test pressure (calculated)',
              formatHydrotestPressure(record.testPressureBar)),
        ]),
        if (record.notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _section('UWAGI / NOTES', [_freeText(record.notes.trim())]),
        ],
        ..._notes(record),
        pw.SizedBox(height: 18),
        _signatures(),
        pw.SizedBox(height: 12),
        // Same disclaimer the screen shows above the inputs: the app does the
        // arithmetic, a person owns the procedure and the acceptance.
        pw.Text(
          'Procedurę próby i jej odbiór prowadzi inżynier QC. Aplikacja wykonuje '
          'wyłącznie obliczenia i zapis. / The QC engineer owns the test '
          'procedure and its acceptance. This app only calculates and records.',
          style: pw.TextStyle(fontSize: 7.5, color: _kInkMuted),
        ),
      ],
    ));

    final bytes = await doc.save();
    final name = hydrotestProtocolFileName(
      extension: 'pdf',
      generatedAt: now,
      systemName: record.systemName,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    // Same guard as weld_journal_export / iso_pdf_export: a truncated write
    // (full disk) would otherwise be shared as a corrupt attachment and only
    // discovered by the inspector who cannot open it.
    if (!await file.exists() || (await file.length()) < 100) {
      throw StateError(
        'PDF zapisany niepoprawnie — sprawdź miejsce na dysku (${dir.path}).',
      );
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: hydrotestProtocolSubject(record),
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── Running page header ───────────────────────────────────────────────────
  static pw.Widget _pageHeader({
    required HydrotestRecord record,
    required String stamp,
    required int page,
    required int pages,
  }) {
    final system = record.systemName.trim();
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(
              'PROTOKÓŁ PRÓBY CIŚNIENIOWEJ / HYDROSTATIC TEST PROTOCOL',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: _kInk,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'System / line: ${system.isEmpty ? '—' : system}',
              style: pw.TextStyle(fontSize: 9, color: _kInk),
            ),
            pw.Text(
              'Data / Date: ${record.date.trim().isEmpty ? '—' : record.date.trim()}',
              style: pw.TextStyle(fontSize: 9, color: _kInk),
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

  // ── PASS / FAIL banner ────────────────────────────────────────────────────
  //
  // Loudest element on the page on purpose: this is the one line a foreman
  // looks for, and a protocol whose verdict has to be hunted for gets read
  // wrong.
  static pw.Widget _resultBanner(HydrotestRecord r) {
    final ink = r.passed ? _kPassInk : _kFailInk;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: ink, width: 1.5),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text('WYNIK PRÓBY / TEST RESULT',
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kInk)),
          pw.Text(
            r.passed ? 'PASS — POZYTYWNY' : 'FAIL — NEGATYWNY',
            style: pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold, color: ink),
          ),
        ],
      ),
    );
  }

  // ── Labelled section ──────────────────────────────────────────────────────
  static pw.Widget _section(String title, List<pw.Widget> rows) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: _kHeadFill,
            child: pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _kInk,
                    letterSpacing: 0.6)),
          ),
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kRule, width: 0.5),
            ),
            // stretch, not the default centre: every row must span the full
            // width so the label column starts at the same x on every line and
            // the hairline separators reach both edges.
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ]);
  }

  /// One label/value line. The label column is fixed so every value in the
  /// document starts at the same x — a form that jitters is a form that gets
  /// misread on a photocopy.
  static pw.Widget _row(String label, String value) {
    final shown = value.trim().isEmpty ? '—' : value.trim();
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kRule, width: 0.25)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 210,
            child: pw.Text(label,
                style: pw.TextStyle(fontSize: 8, color: _kInkMuted)),
          ),
          pw.Expanded(
            child: pw.Text(shown,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: _kInk)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _freeText(String text) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 9, color: _kInk, lineSpacing: 1.5)),
      );

  /// The audit notes, printed only when they apply.
  static List<pw.Widget> _notes(HydrotestRecord r) {
    final notes = <String>[
      for (final n in [
        hydrotestHoldNote(r),
        hydrotestDropNote(r),
        hydrotestMissingNote(r),
      ])
        if (n != null) n,
    ];
    if (notes.isEmpty) return const [];
    return [
      pw.SizedBox(height: 10),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _kWarnInk, width: 0.8),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final n in notes)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(n,
                    style: pw.TextStyle(
                        fontSize: 8, color: _kWarnInk, lineSpacing: 1.3)),
              ),
          ],
        ),
      ),
    ];
  }

  // ── Signature block ───────────────────────────────────────────────────────
  //
  // Three ruled lines, no pre-printed names: the protocol is signed on paper
  // by whoever was actually standing at the manifold.
  static pw.Widget _signatures() {
    pw.Widget line(String label) => pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.SizedBox(height: 26),
              pw.Container(
                decoration: pw.BoxDecoration(
                  border:
                      pw.Border(top: pw.BorderSide(color: _kInk, width: 0.6)),
                ),
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text(label,
                    style: pw.TextStyle(fontSize: 7.5, color: _kInkMuted)),
              ),
            ],
          ),
        );
    return pw.Row(children: [
      line('Wykonawca / Contractor'),
      pw.SizedBox(width: 16),
      line('Świadek / Witness'),
      pw.SizedBox(width: 16),
      line('QC / Inspector'),
    ]);
  }
}
