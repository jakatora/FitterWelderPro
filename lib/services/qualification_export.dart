/// Eksport rejestru uprawnień spawacza i logu ciągłości (welder continuity
/// log) — CSV i PDF dla QC i klienta.
///
/// Rejestr: norma, numer, stempel, egzaminator, egzamin, ważność, zakres
/// i status na dzień eksportu (data ważności + termin 6-miesięczny).
/// Log ciągłości: każde potwierdzenie ISO 9606-1 §9.2 / wpis ciągłości WPQ
/// z historii (data, kto, uwagi) i ostatnia spoina procesem z dziennika.
/// Górna połowa czysta, dolna — platforma (jak w weld_journal_export.dart).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/qualification/certificate_status.dart';
import '../domain/qualification/qualification_dates.dart';
import '../domain/qualification/weld_process.dart';
import 'weld_journal_export.dart'
    show escapeCsvField, kUtf8Bom, kWeldJournalCsvEol, kWeldJournalCsvSeparator;

String _d(DateTime? d) => d == null ? '' : formatIsoDate(d);

String _num(double? v) =>
    v == null ? '' : v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

String _range(double? min, double? max) {
  if (min == null && max == null) return '';
  if (min != null && max != null) return '${_num(min)}–${_num(max)}';
  return min != null ? '≥ ${_num(min)}' : '≤ ${_num(max)}';
}

/// Status na dzień eksportu, dwujęzycznie.
String qualificationStateLabel(QualificationState s) => switch (s) {
      QualificationState.valid => 'ważny / valid',
      QualificationState.confirmationDue =>
        'wymaga potwierdzenia / confirmation due',
      QualificationState.expiringSoon => 'wygasa wkrótce / expiring soon',
      QualificationState.lapsed => 'przeterminowany / lapsed',
      QualificationState.expired => 'wygasł / expired',
    };

final List<(String, String Function(CertificateEvaluation))> _columns = [
  ('Norma / Standard', (e) => e.certificate.standardName(english: false)),
  ('Nr / No.', (e) => e.certificate.certNo ?? ''),
  ('Stempel / Stamp', (e) => e.certificate.welderStamp ?? ''),
  ('Egzaminator / Examiner', (e) => e.certificate.examiner ?? ''),
  ('Egzamin / Test', (e) => _d(e.certificate.testDate)),
  ('Ważny do / Valid until', (e) => _d(e.certificate.expiryDate)),
  ('Proces / Process', (e) => e.certificate.processes),
  ('Grupa / Group', (e) => e.certificate.materialGroup),
  (
    't (mm)',
    (e) => _range(e.certificate.thicknessMinMm, e.certificate.thicknessMaxMm)
  ),
  (
    'D (mm)',
    (e) => _range(e.certificate.diameterMinMm, e.certificate.diameterMaxMm)
  ),
  ('Pozycje / Positions', (e) => e.certificate.positions),
  ('BW/FW', (e) => encodeJointKinds(e.certificate.jointKinds)),
  (
    'Ostatnie potwierdzenie / Last confirmation',
    (e) => _d(e.certificate.lastConfirmedDate)
  ),
  ('Termin 6 mies. / 6-month deadline', (e) => _d(e.continuityDeadline)),
  (
    'Ostatnia spoina procesem / Last weld with process',
    (e) => _d(e.lastJournalWeld)
  ),
  ('Status', (e) => qualificationStateLabel(e.state)),
];

List<String> get qualificationCsvHeaders =>
    _columns.map((c) => c.$1).toList(growable: false);

String buildQualificationCsv(List<CertificateEvaluation> evaluations) {
  final buf = StringBuffer()..write(kUtf8Bom);
  buf.write(
      _columns.map((c) => escapeCsvField(c.$1)).join(kWeldJournalCsvSeparator));
  buf.write(kWeldJournalCsvEol);
  for (final e in evaluations) {
    buf.write(_columns
        .map((c) => escapeCsvField(c.$2(e)))
        .join(kWeldJournalCsvSeparator));
    buf.write(kWeldJournalCsvEol);
  }
  return buf.toString();
}

/// Wiersze logu ciągłości jednego certyfikatu (od najstarszego):
/// egzamin, potwierdzenia, ostatnia spoina z dziennika.
List<(String date, String event, String detail)> continuityLogRows(
    CertificateEvaluation e) {
  final c = e.certificate;
  final rows = <(String, String, String)>[
    if (c.testDate != null)
      (_d(c.testDate), 'Egzamin / Test', c.examiner ?? ''),
    for (final k in c.confirmations)
      (
        _d(k.date),
        'Potwierdzenie / Confirmation',
        [k.confirmedBy, k.notes].where((s) => s.trim().isNotEmpty).join(' · '),
      ),
    if (c.confirmations.isEmpty && c.lastConfirmedDate != null)
      (_d(c.lastConfirmedDate), 'Potwierdzenie / Confirmation', ''),
    if (e.lastJournalWeld != null)
      (
        _d(e.lastJournalWeld),
        'Ostatnia spoina (dziennik) / Last weld',
        c.processes
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return rows;
}

String qualificationFileName(
        {required String extension, required DateTime generatedAt}) =>
    'Rejestr_uprawnien_${formatIsoDate(generatedAt)}.$extension';

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kNokInk = PdfColor.fromHex('#B3261E');

class QualificationExport {
  const QualificationExport._();

  static Future<void> shareCsv(List<CertificateEvaluation> evaluations,
      {bool Function()? mayShare}) async {
    if (mayShare != null && !mayShare()) return;
    final now = DateTime.now();
    final name = qualificationFileName(extension: 'csv', generatedAt: now);
    if (mayShare != null && !mayShare()) return;
    final root = await getTemporaryDirectory();
    final dir = await root.createTemp('qualification-export-');
    if (mayShare != null && !mayShare()) {
      await dir.delete(recursive: true);
      return;
    }
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(utf8.encode(buildQualificationCsv(evaluations)),
        flush: true);
    if (mayShare != null && !mayShare()) {
      await dir.delete(recursive: true);
      return;
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: name)],
      subject: 'Rejestr uprawnień spawacza / Welder qualification register',
    );
  }

  static Future<void> sharePdf(List<CertificateEvaluation> evaluations,
      {bool Function()? mayShare}) async {
    if (mayShare != null && !mayShare()) return;
    final now = DateTime.now();
    final doc = await buildPdfDocument(
      evaluations: evaluations,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: now,
    );
    final bytes = await doc.save();
    final name = qualificationFileName(extension: 'pdf', generatedAt: now);
    if (mayShare != null && !mayShare()) return;
    final root = await getTemporaryDirectory();
    final dir = await root.createTemp('qualification-export-');
    if (mayShare != null && !mayShare()) {
      await dir.delete(recursive: true);
      return;
    }
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    if (mayShare != null && !mayShare()) {
      await dir.delete(recursive: true);
      return;
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: 'Rejestr uprawnień spawacza / Welder qualification register',
    );
  }

  static pw.Widget _cell(String t, {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 6.5,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color ?? _kInk)),
      );

  static Future<pw.Document> buildPdfDocument({
    required List<CertificateEvaluation> evaluations,
    required pw.Font font,
    pw.Font? boldFont,
    required DateTime generatedAt,
  }) async {
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
          base: font, bold: bold, italic: font, boldItalic: bold),
    );
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      maxPages: 200,
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
            border:
                pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
                'REJESTR UPRAWNIEŃ SPAWACZA / WELDER QUALIFICATION REGISTER',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _kInk)),
            pw.Text(
                'Stan na / As of ${formatIsoDate(generatedAt)} · '
                'Strona / Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: _kInkMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Text(
        'Fitter Welder Pro · EN ISO 9606-1 §9.2 / §9.3 · ASME IX QW-322 · '
        'Dokument pomocniczy — wiążący jest certyfikat i podpisy na nim. / '
        'Aid only — the certificate and its signatures are binding.',
        style: pw.TextStyle(fontSize: 6.5, color: _kInkMuted),
      ),
      build: (_) => [
        if (evaluations.isEmpty)
          pw.Text('Brak certyfikatów. / No certificates.',
              style: pw.TextStyle(fontSize: 9, color: _kInkMuted))
        else ...[
          pw.Table(
            border: pw.TableBorder.all(color: _kRule, width: 0.5),
            children: [
              pw.TableRow(
                repeat: true,
                decoration: pw.BoxDecoration(color: _kHeadFill),
                children: [
                  for (final h in qualificationCsvHeaders) _cell(h, bold: true),
                ],
              ),
              for (final e in evaluations)
                pw.TableRow(children: [
                  for (final c in _columns)
                    _cell(c.$2(e),
                        bold: c.$1 == 'Status',
                        color: c.$1 == 'Status' && e.state.severity == 2
                            ? _kNokInk
                            : null),
                ]),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text('Log ciągłości / Continuity log',
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kInk)),
          pw.SizedBox(height: 4),
          for (final e in evaluations) ...[
            pw.Text(
              '${e.certificate.shortTitle(english: false)}'
              '${e.certificate.welderStamp == null ? '' : ' · ${e.certificate.welderStamp}'}'
              '${e.lateConfirmation == null ? '' : ' · potwierdzenie ${formatIsoDate(e.lateConfirmation!)} po terminie / after the deadline'}',
              style: pw.TextStyle(
                  fontSize: 8, fontWeight: pw.FontWeight.bold, color: _kInk),
            ),
            pw.Table(
              border: pw.TableBorder.all(color: _kRule, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(60),
                1: pw.FixedColumnWidth(170),
                2: pw.FlexColumnWidth(),
              },
              children: [
                for (final r in continuityLogRows(e))
                  pw.TableRow(
                      children: [_cell(r.$1), _cell(r.$2), _cell(r.$3)]),
              ],
            ),
            pw.SizedBox(height: 6),
          ],
        ],
      ],
    ));
    return doc;
  }
}
