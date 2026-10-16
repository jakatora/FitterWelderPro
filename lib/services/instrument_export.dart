/// Rejestr przyrządów i kalibracji — CSV (Excel) i PDF (segregator
/// jakości / audyt ISO 3834). Te same zasady co rejestr pasywacji: `;`,
/// CRLF, BOM UTF-8, Roboto dla polskich znaków; czcionki podawane
/// z zewnątrz, więc test renderuje prawdziwe strony.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/instruments/instrument.dart';
import '../domain/qualification/qualification_dates.dart';
import 'qualification_reminders.dart';
import 'weld_journal_export.dart'
    show escapeCsvField, kUtf8Bom, kWeldJournalCsvEol, kWeldJournalCsvSeparator;

/// Przypomnienia o kalibracji — własny kanał i klucze, ta sama warstwa
/// co uprawnienia spawacza.
final QualificationReminders instrumentReminders = QualificationReminders(
  platform: LocalNotificationsReminderPlatform(
    channelId: 'instrument_calibration_reminders',
    channelName: 'Kalibracja przyrządów / Instrument calibration',
    channelDescription:
        'Przypomnienia o terminach kalibracji i walidacji przyrządów.',
    payloadPrefix: 'instrument',
  ),
  enabledKey: 'instrument_reminders_enabled_v1',
  idsKey: 'instrument_reminder_ids_v1',
);

/// Plan przypomnień dla rejestru — wołany po każdej zmianie.
Future<void> rescheduleInstrumentReminders(List<Instrument> all,
        {required bool english}) =>
    instrumentReminders.reschedule(
        planInstrumentReminders(all, now: DateTime.now(), english: english));

String _statusLabel(InstrumentStatus s, {required bool en}) => switch (s) {
      InstrumentStatus.ok => en ? 'OK' : 'OK',
      InstrumentStatus.dueSoon => en ? 'Due soon' : 'Wkrótce',
      InstrumentStatus.overdue => en ? 'OVERDUE' : 'PO TERMINIE',
      InstrumentStatus.unknown => en ? 'No date' : 'Brak daty',
    };

List<(String, String Function(Instrument, DateTime))> _columns() => [
      ('Rodzaj / Kind', (i, _) => '${i.kind.labelPl} / ${i.kind.labelEn}'),
      ('Nazwa / Name', (i, _) => i.name),
      ('Nr seryjny / Serial no.', (i, _) => i.serialNo),
      ('Miejsce / Location', (i, _) => i.location),
      ('Ostatnia kalibracja / Last calibration', (i, _) => i.lastCalibration),
      ('Interwał (mies.) / Interval (months)', (i, _) => '${i.intervalMonths}'),
      (
        'Termin / Due',
        (i, _) => i.dueDate == null ? '' : formatIsoDate(i.dueDate!)
      ),
      (
        'Status',
        (i, today) =>
            '${_statusLabel(i.statusOn(today), en: false)} / ${_statusLabel(i.statusOn(today), en: true)}'
      ),
      ('Świadectwo / Certificate', (i, _) => i.certificateNo),
      ('Kalibrował / Calibrated by', (i, _) => i.calibratedBy),
      ('Uwagi / Notes', (i, _) => i.notes),
    ];

String buildInstrumentCsv(List<Instrument> list, DateTime today) {
  final cols = _columns();
  final b = StringBuffer()..write(kUtf8Bom);
  b.write(cols.map((c) => escapeCsvField(c.$1)).join(kWeldJournalCsvSeparator));
  b.write(kWeldJournalCsvEol);
  for (final i in sortForRegister(list, today)) {
    b.write(cols
        .map((c) => escapeCsvField(c.$2(i, today)))
        .join(kWeldJournalCsvSeparator));
    b.write(kWeldJournalCsvEol);
  }
  return b.toString();
}

String instrumentFileName(String ext, DateTime now) =>
    'Rejestr_przyrzadow_${formatIsoDate(now)}.$ext';

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHead = PdfColor.fromHex('#EDEFF3');
final PdfColor _kBad = PdfColor.fromHex('#C62828');

class InstrumentExport {
  const InstrumentExport._();

  static Future<void> shareCsv(List<Instrument> list) async {
    final now = DateTime.now();
    final name = instrumentFileName('csv', now);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(utf8.encode(buildInstrumentCsv(list, now)),
        flush: true);
    await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv', name: name)],
        subject: 'Rejestr przyrządów / Instrument register');
  }

  static Future<void> sharePdf(List<Instrument> list) async {
    final now = DateTime.now();
    final doc = buildPdf(
      list: list,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: now,
    );
    final bytes = await doc.save();
    final name = instrumentFileName('pdf', now);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
        [XFile(f.path, mimeType: 'application/pdf', name: name)],
        subject: 'Rejestr przyrządów / Instrument register');
  }

  static pw.Document buildPdf({
    required List<Instrument> list,
    required pw.Font font,
    required pw.Font bold,
    required DateTime generatedAt,
  }) {
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(
            base: font, bold: bold, italic: font, boldItalic: bold));
    final cols = _columns();
    final today = dateOnly(generatedAt);
    final sorted = sortForRegister(list, today);
    final overdue = sorted
        .where((i) => i.statusOn(today) == InstrumentStatus.overdue)
        .length;
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
                'REJESTR PRZYRZĄDÓW I KALIBRACJI / INSTRUMENT & CALIBRATION REGISTER',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _kInk)),
            pw.Text(
                '${formatIsoDate(today)} · ${ctx.pageNumber}/${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: _kMuted)),
          ],
        ),
      ),
      footer: (_) => pw.Text(
          'Fitter Welder Pro · EN ISO 3834-2 §12 · ${sorted.length} poz. / items'
          '${overdue > 0 ? ' · po terminie / overdue: $overdue' : ''}',
          style: pw.TextStyle(fontSize: 7, color: _kMuted)),
      build: (_) => [
        if (sorted.isEmpty)
          pw.Text('Brak przyrządów. / No instruments.',
              style: pw.TextStyle(fontSize: 9, color: _kMuted))
        else
          pw.Table(
            border: pw.TableBorder.all(color: _kRule, width: 0.5),
            children: [
              pw.TableRow(
                repeat: true,
                decoration: pw.BoxDecoration(color: _kHead),
                children: [
                  for (final c in cols)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(c.$1,
                          style: pw.TextStyle(
                              fontSize: 6.5,
                              fontWeight: pw.FontWeight.bold,
                              color: _kInk)),
                    ),
                ],
              ),
              for (final i in sorted)
                pw.TableRow(children: [
                  for (final c in cols)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(c.$2(i, today),
                          style: pw.TextStyle(
                              fontSize: 7,
                              color:
                                  i.statusOn(today) == InstrumentStatus.overdue
                                      ? _kBad
                                      : _kInk)),
                    ),
                ]),
            ],
          ),
        pw.SizedBox(height: 10),
        pw.Text(
            'Interwały wg procedury firmy / producenta; klucze dynamometryczne '
            'wg ISO 6789 (12 mies. albo 5000 cykli). / Intervals per company '
            'procedure / manufacturer; torque wrenches per ISO 6789.',
            style: pw.TextStyle(fontSize: 7, color: _kMuted)),
      ],
    ));
    return doc;
  }
}
