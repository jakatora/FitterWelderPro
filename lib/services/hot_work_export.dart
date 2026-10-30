/// Protokół przygotowania stanowiska do prac pożarowo niebezpiecznych jako
/// PDF — dla nadzoru i wystawiającego zezwolenie.
///
/// Te same zasady co eksport pasywacji / planu PWHT: Roboto z
/// `assets/fonts/` (polskie znaki), czcionki podawane z zewnątrz, więc test
/// renderuje prawdziwe strony. Górna połowa czysta (budowa dokumentu),
/// dolna — platforma (plik tymczasowy + arkusz udostępniania).
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/hot_work/hot_work_checklist.dart';
import '../domain/hot_work/hot_work_permit.dart';
import '../domain/hot_work/hot_work_sources.dart';
import '../domain/hot_work/hot_work_text.dart';

/// `Zezwolenie_prace_pozarowe_2026-10-17.pdf` (data pracy z protokołu).
String hotWorkFileName(HotWorkPermit p, {required bool english}) {
  final date = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(p.date) ? p.date : '';
  final base = english ? 'Hot_work_record' : 'Prace_pozarowe_protokol';
  return date.isEmpty ? '$base.pdf' : '${base}_$date.pdf';
}

String hotWorkSubject({required bool english}) => english
    ? 'Hot work — area preparation record'
    : 'Prace pożarowo niebezpieczne — protokół';

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kWarnFill = PdfColor.fromHex('#FFF4DC');
final PdfColor _kFail = PdfColor.fromHex('#C0392B');

class HotWorkExport {
  const HotWorkExport._();

  static Future<void> sharePdf(HotWorkPermit permit,
      {required bool english, bool Function()? canShare}) async {
    final now = DateTime.now();
    final doc = await buildPdfDocument(
      permit: permit,
      english: english,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: now,
    );
    final bytes = await doc.save();
    final name = hotWorkFileName(permit, english: english);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    if (canShare != null && !canShare()) return;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: hotWorkSubject(english: english),
    );
  }

  static Future<pw.Document> buildPdfDocument({
    required HotWorkPermit permit,
    required bool english,
    required pw.Font font,
    pw.Font? boldFont,
    required DateTime generatedAt,
  }) async {
    final en = english;
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
          base: font, bold: bold, italic: font, boldItalic: bold),
    );
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${generatedAt.year}-${two(generatedAt.month)}-'
        '${two(generatedAt.day)} ${two(generatedAt.hour)}:'
        '${two(generatedAt.minute)}';
    // Stan w chwili wydruku: wiek pomiaru i data protokołu.
    final a = permit.assess(now: generatedAt);
    final statusColor =
        a.readiness == HotWorkReadiness.overLimit ? _kFail : _kInk;

    pw.Widget cell(String t,
            {bool head = false, PdfColor? color, double size = 8}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.all(3.5),
          child: pw.Text(t,
              style: pw.TextStyle(
                  fontSize: size,
                  fontWeight: head ? pw.FontWeight.bold : null,
                  color: color ?? _kInk)),
        );

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Text(t,
              style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _kInk)),
        );

    final checklist = <pw.Widget>[];
    for (final phase in HotWorkPhase.values) {
      final checks = hotWorkChecksIn(phase);
      final done = checks.where(permit.isSettled).length;
      checklist.add(heading('${phase.label(en: en)} ($done/${checks.length})'));
      checklist.add(pw.Table(
        border: pw.TableBorder.all(color: _kRule, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(36),
          1: pw.FlexColumnWidth(),
        },
        children: [
          for (final g in hotWorkGroupsIn(phase)) ...[
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _kHeadFill),
              children: [
                cell(''),
                cell(g.label(en: en), head: true, size: 8),
              ],
            ),
            for (final c in hotWorkChecksInGroup(g))
              pw.TableRow(children: [
                cell(_markPdf(permit, c, en: en),
                    head: true, color: permit.isSettled(c) ? _kInk : _kFail),
                cell(c.source == null
                    ? c.label(en: en)
                    : '${c.label(en: en)}  [${c.source}]'),
              ]),
          ],
        ],
      ));
    }

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
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text(
                  en
                      ? 'Hot work — area preparation record'
                      : 'Prace pożarowo niebezpieczne — protokół '
                          'przygotowania stanowiska',
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: _kInk)),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
                '${en ? 'Page' : 'Strona'} ${ctx.pageNumber} / '
                '${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: _kInkMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Fitter Welder Pro  ·  $stamp  ·  '
          '${en ? 'checklist aid, not a permit' : 'lista pomocnicza, nie zezwolenie'}',
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
          child: pw.Text(hotWorkDisclaimer(en: en),
              style: pw.TextStyle(fontSize: 8.5, color: _kInk)),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _kRule, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(160),
            1: pw.FlexColumnWidth(),
          },
          children: [
            for (final l in hotWorkPermitLines(permit, en: en))
              pw.TableRow(children: [
                pw.Container(
                  color: _kHeadFill,
                  child: cell(l.label, head: true, size: 8.5),
                ),
                cell(l.value, size: 8.5),
              ]),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          '${en ? 'Status' : 'Stan'}: ${hotWorkReadinessText(a, en: en)}',
          style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: statusColor),
        ),
        heading(en ? 'Gas test' : 'Pomiar atmosfery'),
        if (permit.measurements.isEmpty)
          pw.Text(en ? '— no reading —' : '— brak pomiaru —',
              style: pw.TextStyle(fontSize: 8.5, color: _kFail))
        else
          pw.Table(
            border: pw.TableBorder.all(color: _kRule, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(60),
              1: pw.FixedColumnWidth(80),
              2: pw.FlexColumnWidth(),
              3: pw.FixedColumnWidth(90),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _kHeadFill),
                children: [
                  cell(en ? 'Time' : 'Godzina', head: true),
                  cell(en ? 'Result' : 'Wynik', head: true),
                  cell(en ? 'Place / notes' : 'Miejsce / uwagi', head: true),
                  cell(en ? 'Assessment' : 'Ocena', head: true),
                ],
              ),
              for (final m in permit.measurementsChrono)
                pw.TableRow(children: [
                  cell(hotWorkMeasurementTime(m, permit.date)),
                  cell(hotWorkDgw(m.dgwPct, en: en)),
                  cell(m.note.trim().isEmpty ? '—' : m.note.trim()),
                  _verdictCell(m, permit.dgwLimitPct, en: en, cell: cell),
                ]),
            ],
          ),
        ...checklist,
        if (permit.notes.trim().isNotEmpty) ...[
          heading(en ? 'Notes' : 'Uwagi'),
          pw.Text(permit.notes.trim(),
              style: pw.TextStyle(fontSize: 8.5, color: _kInk)),
        ],
        heading(en ? 'Signatures' : 'Podpisy'),
        pw.Row(children: [
          for (final (role, name) in [
            (en ? 'Performed by' : 'Wykonawca', permit.contractor),
            (
              en
                  ? 'Responsible for securing'
                  : 'Odpowiedzialny za zabezpieczenie',
              permit.securedBy
            ),
            (en ? 'Fire watch' : 'Dozorujący', permit.fireWatch),
            (en ? 'Permit issuer' : 'Wystawiający', permit.issuer),
          ])
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                padding: const pw.EdgeInsets.all(6),
                height: 62,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _kRule, width: 0.5)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(role,
                        style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _kInk)),
                    if (name.trim().isNotEmpty)
                      pw.Text(name.trim(),
                          style: pw.TextStyle(fontSize: 7.5, color: _kInk)),
                  ],
                ),
              ),
            ),
        ]),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kRule, width: 0.5)),
          child: pw.Text(
            en
                ? 'Work finished at: ______   Area inspected / fire watch '
                    'ended at: ______   Signature: ____________________'
                : 'Zakończenie pracy, godz.: ______   Kontrola / koniec dozoru, '
                    'godz.: ______   Podpis: ____________________',
            style: pw.TextStyle(fontSize: 8, color: _kInk),
          ),
        ),
      ],
    ));
    return doc;
  }

  static pw.Widget _verdictCell(HotWorkMeasurement m, double? limit,
      {required bool en,
      required pw.Widget Function(String,
              {bool head, PdfColor? color, double size})
          cell}) {
    if (limit == null) {
      // Bez limitu z zezwolenia — ponad 10 % DGW z przepisu i tak POWYŻEJ.
      if (!hotWorkMeasurementOk(m.dgwPct, kHotWorkDefaultDgwLimitPct)) {
        return cell(
            en ? 'ABOVE THE REGULATION LIMIT' : 'POWYŻEJ LIMITU Z PRZEPISU',
            head: true,
            color: _kFail);
      }
      return cell(en ? 'no limit entered' : 'brak limitu');
    }
    final ok = hotWorkMeasurementOk(m.dgwPct, limit);
    return cell(
      ok ? 'OK' : (en ? 'ABOVE LIMIT' : 'POWYŻEJ LIMITU'),
      head: true,
      color: ok ? _kInk : _kFail,
    );
  }
}

/// Oznaczenie w PDF — słowem, nie znakiem (Roboto nie ma ☑).
String _markPdf(HotWorkPermit p, HotWorkCheck c, {required bool en}) {
  if (p.isChecked(c)) return en ? 'YES' : 'TAK';
  if (p.isNa(c)) return en ? 'n/a' : 'n/d';
  return en ? 'NO' : 'NIE';
}
