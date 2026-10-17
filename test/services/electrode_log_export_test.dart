// Dziennik elektrod dla QC: tekst do komunikatora (PL / EN) i PDF z Roboto
// (polskie znaki, Ø, °C) — czysta połowa usługi, bez udostępniania.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/welding/electrode_exposure.dart';
import 'package:cut_list_app/services/electrode_log_export.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 17, h, m);

void main() {
  final batch = ElectrodeBatch.takenOut(
    id: 'b1',
    electrode: ElectrodeClass.e7018,
    at: at(7),
    diameterMm: 3.2,
    quantity: '40 szt.',
    location: 'hala B',
  ).returnToOven(at(9)).takeOutAgain(at(13)).redried(at(17, 30));
  final now = at(18);

  test('tekst PL: nagłówek, partia, stan i wpisy z godziną', () {
    final text = buildElectrodeLogText([batch],
        now: now, range: LogRange.today, en: false);
    expect(text, startsWith('DZIENNIK ELEKTROD ZASADOWYCH — 2026-10-17 18:00'));
    expect(text, contains('Zakres: dziś · partie: 1'));
    expect(text, contains('E7018 · Ø3,2 · 40 szt. — hala B'));
    expect(text, contains('limit 4 h 00 min · suszenia 1/1'));
    expect(text, contains('Na powietrzu — OK — zostało 3 h 30 min (do 21:30)'));
    expect(text, contains('2026-10-17 07:00  Wyjęte z piecyka'));
    expect(text,
        contains('2026-10-17 09:00  Do piecyka (na powietrzu 2 h 00 min)'));
    expect(
        text,
        contains(
            '2026-10-17 13:00  Wyjęte ponownie — limit od nowa (min. 4 h w piecyku)'));
    expect(text, contains('2026-10-17 17:30  Ponownie wysuszone (nr 1 z 1)'));
  });

  test('tekst EN i pusty dziennik', () {
    final text = buildElectrodeLogText([batch],
        now: now, range: LogRange.week, en: true);
    expect(text, startsWith('LOW-HYDROGEN ELECTRODE LOG'));
    expect(text, contains('Range: last 7 days · batches: 1'));
    expect(text, contains('Re-dried (no. 1 of 1)'));
    final empty =
        buildElectrodeLogText([], now: now, range: LogRange.all, en: false);
    expect(empty, contains('Brak partii.'));
  });

  test('PDF dziennika z Roboto', () async {
    pw.Font font(String f) => pw.Font.ttf(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));
    final scrapped = ElectrodeBatch.takenOut(
            id: 'b2', electrode: ElectrodeClass.enIso2560B, at: at(6))
        .close(at(12), BatchClosure.scrapped);
    final doc = ElectrodeLogExport.buildPdf(
      batches: [batch, scrapped],
      font: font('Roboto-Regular.ttf'),
      bold: font('Roboto-Bold.ttf'),
      generatedAt: now,
      range: LogRange.today,
    );
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
    expect(
        electrodeLogFileName('pdf', now), 'Dziennik_elektrod_2026-10-17.pdf');
  });
}
