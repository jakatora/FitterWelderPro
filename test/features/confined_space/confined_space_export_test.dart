// PDF protokołu przestrzeni zamkniętej renderuje się z Roboto (polskie
// znaki; indeks „₂” zamieniany na „2”, bo Roboto go nie ma) — wypełniony
// i pusty, PL i EN; nazwa pliku z datą.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/confined_space/confined_space_gas.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';
import 'package:cut_list_app/services/confined_space_export.dart';

pw.Font _font(String f) => pw.Font.ttf(
    ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));

Future<List<int>> _render(ConfinedSpaceRecord r, {required bool english}) async {
  final doc = await ConfinedSpaceExport.buildPdfDocument(
    record: r,
    english: english,
    font: _font('Roboto-Regular.ttf'),
    boldFont: _font('Roboto-Bold.ttf'),
    generatedAt: DateTime(2026, 10, 17, 9, 30),
  );
  return doc.save();
}

final _filled = ConfinedSpaceRecord(
  id: 'r',
  permitNo: 'PZ/7/2026',
  location: 'Zbiornik T-101 — właz M1 (żółta strefa)',
  description: 'Spawanie króćca DN80 od środka, formowanie argonem',
  processes: const {CsProcess.tig, CsProcess.purge, CsProcess.grinding},
  date: '2026-10-17',
  validFrom: '07:00',
  validTo: '15:00',
  entrants: 'Jan Kowalski',
  attendant: 'Adam Nowak',
  supervisor: 'Ewa Zając',
  issuer: 'Piotr Wiśniewski',
  rescue: 'Straż zakładowa, trójnóg T-2',
  limits: CsLimits.defaults
      .withLimit(CsBound.lelMax, const CsQty(5, CsUnit.pctLel)),
  measurements: [
    CsMeasurement(
      time: '06:50',
      at: DateTime(2026, 10, 17, 6, 50).millisecondsSinceEpoch,
      values: const {
        CsGas.o2: CsQty(20.9, CsUnit.pctVol),
        CsGas.lel: CsQty(0, CsUnit.pctLel),
        CsGas.co: CsQty(23, CsUnit.mgM3),
        CsGas.h2s: CsQty(0, CsUnit.ppm),
      },
      place: 'dno',
    ),
    CsMeasurement(
      time: '10:00',
      at: DateTime(2026, 10, 17, 10).millisecondsSinceEpoch,
      values: const {CsGas.o2: CsQty(18.5, CsUnit.pctVol)},
    ),
  ],
  checked: const {'perm-written', 'iso-blind', 'res-attendant'},
  na: const {'clean-sewer'},
  notes: 'Nawiew z wentylatora W-3; łączność radiowa z dyspozytornią.',
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  test('wypełniony protokół — PL i EN', () async {
    for (final en in [false, true]) {
      final bytes = await _render(_filled, english: en);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });

  test('pusty protokół (bez pomiaru i progów) też się renderuje', () async {
    final blank = ConfinedSpaceRecord.blank(
            id: 'b', now: DateTime(2026, 10, 17))
        .copyWith(limits: const CsLimits({}));
    final bytes = await _render(blank, english: false);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('nazwa pliku z datą pracy; indeks ₂ zamieniany w PDF', () {
    expect(confinedSpaceFileName(_filled, english: false),
        'Przestrzen_zamknieta_protokol_2026-10-17.pdf');
    expect(confinedSpaceFileName(_filled, english: true),
        'Confined_space_record_2026-10-17.pdf');
    expect(
        confinedSpaceFileName(_filled.copyWith(date: 'zła data'),
            english: false),
        'Przestrzen_zamknieta_protokol.pdf');
    expect(confinedSpacePdfSafe('O₂ i H₂S, CO₂'), 'O2 i H2S, CO2');
  });
}
