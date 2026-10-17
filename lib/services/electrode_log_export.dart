/// Dziennik partii elektrod zasadowych dla QC — tekst (komunikator, mail)
/// i PDF (segregator jakości). Te same zasady co log kuponów: Roboto dla
/// polskich znaków, czcionki podawane z zewnątrz, więc test renderuje
/// prawdziwe strony. Górna połowa czysta, dolna — platforma.
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/welding/electrode_exposure.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PURE HALF
// ═══════════════════════════════════════════════════════════════════════════

String electrodeStateLabel(ExposureState s, {required bool en}) => switch (s) {
      ExposureState.inOven => en ? 'In holding oven' : 'W piecyku',
      ExposureState.ok => en ? 'Exposed — OK' : 'Na powietrzu — OK',
      ExposureState.endingSoon =>
        en ? 'Exposed — ending soon' : 'Na powietrzu — kończy się',
      ExposureState.exceeded => en
          ? 'LIMIT EXCEEDED — re-dry or scrap'
          : 'PRZEKROCZONY — do suszenia albo złom',
      ExposureState.consumed => en ? 'Used up' : 'Zużyte',
      ExposureState.scrapped => en ? 'Scrapped' : 'Złom',
    };

/// Treść wpisu dziennika, np. „Do piecyka (na powietrzu 1 h 45 min)”.
String electrodeEventLabel(BatchEvent e, ElectrodeBatch b, {required bool en}) {
  final exp = formatSpan(e.exposure);
  return switch (e.kind) {
    BatchEventKind.takenOut => b.source == ElectrodeSource.hermeticPack
        ? (en
            ? 'Hermetic / vacuum pack opened'
            : 'Otwarte opakowanie próżniowe')
        : (en ? 'Taken out of the oven' : 'Wyjęte z piecyka'),
    BatchEventKind.returnedToOven => en
        ? 'Back to holding oven (exposed $exp)'
        : 'Do piecyka (na powietrzu $exp)',
    BatchEventKind.takenOutAgain => e.reset
        ? (en
            ? 'Taken out again — limit reset (min. ${kOvenResetHold.inHours} h in oven)'
            : 'Wyjęte ponownie — limit od nowa (min. ${kOvenResetHold.inHours} h w piecyku)')
        : (en
            ? 'Taken out again — clock continues from $exp'
            : 'Wyjęte ponownie — licznik dalej od $exp'),
    BatchEventKind.redried => en
        ? 'Re-dried (no. ${e.value ?? '?'} of ${b.maxRedries}), exposed before: $exp'
        : 'Ponownie wysuszone (nr ${e.value ?? '?'} z ${b.maxRedries}), wcześniej na powietrzu $exp',
    BatchEventKind.consumed =>
      en ? 'Used up (exposed $exp)' : 'Zużyte (na powietrzu $exp)',
    BatchEventKind.scrapped =>
      en ? 'Scrapped (exposed $exp)' : 'Złom (na powietrzu $exp)',
    BatchEventKind.limitChanged => en
        ? 'Limit changed to ${formatSpan(Duration(minutes: e.value ?? 0))}'
            '${e.exceeded ? ' (batch was over its limit)' : ''}'
        : 'Zmieniono limit na ${formatSpan(Duration(minutes: e.value ?? 0))}'
            '${e.exceeded ? ' (partia była przekroczona)' : ''}',
  };
}

String _rangeLabel(LogRange r, {required bool en}) => switch (r) {
      LogRange.today => en ? 'today' : 'dziś',
      LogRange.week => en ? 'last 7 days' : 'ostatnie 7 dni',
      LogRange.all => en ? 'all' : 'wszystko',
    };

/// Linia stanu partii z pozostałym czasem.
String electrodeStatusLine(ElectrodeBatch b, DateTime now, {required bool en}) {
  final s = b.stateAt(now);
  final label = electrodeStateLabel(s, en: en);
  final left = b.remainingAt(now);
  // Bez `!`: partia z niespójnego zapisu nie może wywalić dziennika.
  final end = b.deadline;
  final until = end == null
      ? ''
      : en
          ? ' (until ${formatHm(end)})'
          : ' (do ${formatHm(end)})';
  return switch (s) {
    ExposureState.ok || ExposureState.endingSoon => en
        ? '$label — ${formatSpan(left)} left$until'
        : '$label — zostało ${formatSpan(left)}$until',
    ExposureState.exceeded => en
        ? '$label — over by ${formatSpan(left)}'
        : '$label — o ${formatSpan(left)}',
    ExposureState.inOven => en
        ? '$label — exposed so far ${formatSpan(b.exposureAt(now))}'
        : '$label — dotąd na powietrzu ${formatSpan(b.exposureAt(now))}',
    _ => label,
  };
}

/// Tekst dziennika do udostępnienia.
String buildElectrodeLogText(
  List<ElectrodeBatch> batches, {
  required DateTime now,
  required LogRange range,
  required bool en,
}) {
  final b = StringBuffer()
    ..writeln(en
        ? 'LOW-HYDROGEN ELECTRODE LOG — ${formatYmd(now)} ${formatHm(now)}'
        : 'DZIENNIK ELEKTROD ZASADOWYCH — ${formatYmd(now)} ${formatHm(now)}')
    ..writeln(en
        ? 'Range: ${_rangeLabel(range, en: true)} · batches: ${batches.length}'
        : 'Zakres: ${_rangeLabel(range, en: false)} · partie: ${batches.length}');
  if (batches.isEmpty) {
    b
      ..writeln()
      ..writeln(en ? 'No batches.' : 'Brak partii.');
  }
  for (final batch in batches) {
    b
      ..writeln()
      ..writeln([
        batch.label(en: en),
        if (batch.location.isNotEmpty) batch.location,
      ].join(' — '))
      ..writeln(en
          ? '  ${batch.electrode.desc(en: true)} · limit ${formatSpan(batch.limit)}'
              ' · re-dries ${batch.redryCount}/${batch.maxRedries}'
          : '  ${batch.electrode.desc(en: false)} · limit ${formatSpan(batch.limit)}'
              ' · suszenia ${batch.redryCount}/${batch.maxRedries}')
      ..writeln('  ${electrodeStatusLine(batch, now, en: en)}');
    for (final e in batch.events) {
      b.writeln('  ${formatYmd(e.at)} ${formatHm(e.at)}  '
          '${electrodeEventLabel(e, batch, en: en)}');
    }
  }
  b
    ..writeln()
    ..write(en
        ? 'Limits: AWS D1.1 Table 7.1 / manufacturer data; WPS may be stricter. '
            'Fitter Welder Pro'
        : 'Limity: AWS D1.1 Tabela 7.1 / karta producenta; WPS może być '
            'ostrzejsza. Fitter Welder Pro');
  return b.toString();
}

/// `Dziennik_elektrod_2026-10-17.pdf`.
String electrodeLogFileName(String extension, DateTime now) =>
    'Dziennik_elektrod_${formatYmd(now)}.$extension';

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM HALF
// ═══════════════════════════════════════════════════════════════════════════

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHead = PdfColor.fromHex('#EDEFF3');
final PdfColor _kBad = PdfColor.fromHex('#B3261E');

class ElectrodeLogExport {
  const ElectrodeLogExport._();

  static Future<void> shareText(String text, {required bool en}) => Share.share(
      text,
      subject:
          en ? 'Low-hydrogen electrode log' : 'Dziennik elektrod zasadowych');

  static Future<void> sharePdf(
    List<ElectrodeBatch> batches, {
    required DateTime now,
    required LogRange range,
  }) async {
    final doc = buildPdf(
      batches: batches,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: now,
      range: range,
    );
    final bytes = await doc.save();
    final name = electrodeLogFileName('pdf', now);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    if (!await file.exists() || (await file.length()) < 100) {
      throw StateError(
          'PDF zapisany niepoprawnie — sprawdź miejsce na dysku (${dir.path}).');
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: 'Dziennik elektrod zasadowych / Low-hydrogen electrode log',
    );
  }

  /// PDF dwujęzyczny (PL / EN) — jedna kartka trafia do każdego QC.
  static pw.Document buildPdf({
    required List<ElectrodeBatch> batches,
    required pw.Font font,
    required pw.Font bold,
    required DateTime generatedAt,
    required LogRange range,
  }) {
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(
            base: font, bold: bold, italic: font, boldItalic: bold));
    final now = generatedAt;
    final exceeded =
        batches.where((b) => b.stateAt(now) == ExposureState.exceeded).length;
    pw.Widget cell(String t, {bool head = false, PdfColor? color}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(t,
              style: pw.TextStyle(
                  fontSize: head ? 7 : 7.5,
                  fontWeight: head ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: color ?? _kInk)),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 300,
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
            border:
                pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                  'DZIENNIK ELEKTROD ZASADOWYCH / LOW-HYDROGEN ELECTRODE LOG',
                  style: pw.TextStyle(
                      fontSize: 11.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _kInk)),
            ),
            pw.Text(
                '${formatYmd(now)} ${formatHm(now)} · ${ctx.pageNumber}/${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: _kMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Text(
          'Fitter Welder Pro · AWS D1.1:2020 7.3.2, Tab. 7.1 / karta producenta '
          '/ manufacturer data · WPS może być ostrzejsza / WPS may be stricter',
          style: pw.TextStyle(fontSize: 6.5, color: _kMuted)),
      build: (_) => [
        pw.Text(
            'Zakres / Range: ${_rangeLabel(range, en: false)} / '
            '${_rangeLabel(range, en: true)} · partie / batches: '
            '${batches.length} · przekroczone / exceeded: $exceeded',
            style: pw.TextStyle(fontSize: 9, color: _kInk)),
        pw.SizedBox(height: 8),
        if (batches.isEmpty)
          pw.Text('Brak partii. / No batches.',
              style: pw.TextStyle(fontSize: 9, color: _kMuted)),
        for (final b in batches) ...[
          pw.Text(
              [b.label(en: false), if (b.location.isNotEmpty) b.location]
                  .join(' — '),
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kInk)),
          pw.Text(
              '${b.electrode.descPl} · limit ${formatSpan(b.limit)} · '
              'suszenia / re-dries ${b.redryCount}/${b.maxRedries}',
              style: pw.TextStyle(fontSize: 8, color: _kMuted)),
          pw.Text(
              '${electrodeStatusLine(b, now, en: false)} / '
              '${electrodeStatusLine(b, now, en: true)}',
              style: pw.TextStyle(
                  fontSize: 8,
                  color: b.stateAt(now) == ExposureState.exceeded
                      ? _kBad
                      : _kInk)),
          pw.SizedBox(height: 3),
          pw.Table(
            border: pw.TableBorder.all(color: _kRule, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(78),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                repeat: true,
                decoration: pw.BoxDecoration(color: _kHead),
                children: [
                  cell('Data / Date', head: true),
                  cell('Wpis', head: true),
                  cell('Entry', head: true),
                ],
              ),
              for (final e in b.events)
                pw.TableRow(children: [
                  cell('${formatYmd(e.at)} ${formatHm(e.at)}'),
                  cell(electrodeEventLabel(e, b, en: false)),
                  cell(electrodeEventLabel(e, b, en: true)),
                ]),
            ],
          ),
          pw.SizedBox(height: 10),
        ],
        pw.Text('Źródła / Sources: ${kElectrodeSources.join(' · ')}',
            style: pw.TextStyle(fontSize: 6.5, color: _kMuted)),
      ],
    ));
    return doc;
  }
}
