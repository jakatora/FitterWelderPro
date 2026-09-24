// Renderowanie protokołu PDF bez platformy: czcionka z assets/fonts podana
// wprost, bez udostępniania. Pilnuje, że nowe sekcje (projekt, manometr,
// zawór, temp. metalu, wzór, ST/S) mieszczą się w układzie i nic nie rzuca —
// także dla starego rekordu bez metadanych.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/database/hydrotest_dao.dart';
import 'package:cut_list_app/domain/pressure_test/hydrotest_protocol_meta.dart';
import 'package:cut_list_app/services/hydrotest_export.dart';

pw.Font _font() {
  final bytes = File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync();
  return pw.Font.ttf(ByteData.sublistView(bytes));
}

HydrotestRecord _record({required String notes, double? start = 18.0}) =>
    HydrotestRecord(
      id: 'pdf-1',
      systemName: 'WFI-101 — pętla dystrybucji',
      date: '2026-09-24',
      gauge: 'M-12 / św. 123/2026',
      pressureStartBar: start,
      pressureEndBar: 17.9,
      temperatureC: 12,
      holdMinutes: 4,
      result: kHydrotestPass,
      witness: 'J. Kowalski',
      odMm: 60.3,
      wallMm: 3.91,
      lineLengthMm: 120000,
      designBar: 10,
      factor: 1.8,
      testPressureBar: 18,
      volumeL: 259.4,
      notes: notes,
      createdAt: 1790000000000,
    );

void main() {
  test('pełny protokół z metadanymi renderuje się do PDF', () async {
    const meta = HydrotestProtocolMeta(
      company: 'Montaż Rur Sp. z o.o.',
      project: 'Rozbudowa instalacji WFI / Klient: Pharma SA',
      testPackage: 'TP-101-03',
      drawingRefs: 'P&ID 101-PI-003 rev B; ISO 101-WFI-0042, 0043, 0044',
      testMedium: 'Woda zdemineralizowana',
      presetId: 'b31_3_hydro',
      stressRatio: 1.2,
      metalTempC: 14.5,
      gaugeRange: '0–25 bar',
      gaugeCalibrationDue: '2026-09-01',
      reliefSetBar: 19.5,
      protocolNo: 'HT-2026-017',
      revision: 'B',
    );
    final r = _record(
        notes: embedHydrotestMeta(
            'Odpowietrzenie na najwyższym punkcie, korki 2×. ' * 8, meta));
    // Trzy notatki audytowe naraz: krótki czas, spadek przy PASS,
    // przeterminowana kalibracja.
    expect(hydrotestHoldNote(r), isNotNull);
    expect(hydrotestDropNote(r), isNotNull);
    expect(hydrotestCalibrationNote(r), isNotNull);

    final bytes = await HydrotestExport.buildPdf(
      record: r,
      font: _font(),
      generatedAt: DateTime(2026, 9, 24, 14, 30),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(5000));
  });

  test('stary rekord bez metadanych i bez pomiarów też się renderuje',
      () async {
    final bytes = await HydrotestExport.buildPdf(
      record: _record(notes: 'Przeciek na kołnierzu.', start: null),
      font: _font(),
      generatedAt: DateTime(2026, 9, 24),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
