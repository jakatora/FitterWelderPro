// Metadane protokołu próby (firma, projekt, pakiet, P&ID/ISO, medium, preset,
// ST/S, temp. metalu, manometr, zawór bezpieczeństwa, nr/rewizja protokołu).
//
// Tabela hydrotest_records nie ma na nie kolumn (DDL zmienia inny zespół), więc
// do czasu migracji jadą jako JSON doklejony do istniejącej kolumny TEXT
// `notes`. Test pilnuje, że uwagi użytkownika wracają nietknięte, a stare
// rekordy (bez znacznika) czytają się jak dotąd.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/pressure_test/hydrotest_protocol_meta.dart';
import 'package:cut_list_app/domain/pressure_test/test_pressure.dart';

const _full = HydrotestProtocolMeta(
  company: 'Montaż Rur Sp. z o.o.',
  project: 'Rozbudowa WFI / Klient: Pharma SA',
  testPackage: 'TP-101-03',
  drawingRefs: 'P&ID 101-PI-003 rev B; ISO 101-WFI-0042',
  testMedium: 'Woda zdemineralizowana',
  presetId: 'b31_3_hydro',
  stressRatio: 1.2,
  metalTempC: 14.5,
  gaugeRange: '0–25 bar',
  gaugeCalibrationDue: '2027-03-31',
  reliefSetBar: 19.5,
  protocolNo: 'HT-2026-017',
  revision: 'B',
);

void main() {
  group('JSON w kolumnie notes', () {
    test('uwagi + metadane: zapis i odczyt bez strat', () {
      const notes = 'Odpowietrzenie na najwyższym punkcie, korki 2×.';
      final raw = embedHydrotestMeta(notes, _full);
      expect(raw, startsWith(notes));
      final back = splitHydrotestNotes(raw);
      expect(back.notes, notes);
      expect(back.meta, _full);
    });

    test('same metadane, bez uwag', () {
      final back = splitHydrotestNotes(embedHydrotestMeta('', _full));
      expect(back.notes, '');
      expect(back.meta, _full);
    });

    test('stary rekord bez znacznika czyta się jak dotąd', () {
      const legacy = 'Przeciek na kołnierzu.';
      final back = splitHydrotestNotes(legacy);
      expect(back.notes, legacy);
      expect(back.meta, isNull);
    });

    test('uszkodzony JSON nie gubi tekstu użytkownika', () {
      final raw = 'Uwaga\n\n$kHydrotestMetaMarker{nie-json';
      final back = splitHydrotestNotes(raw);
      expect(back.notes, raw);
      expect(back.meta, isNull);
    });

    test('ponowne osadzenie nie dubluje bloku metadanych', () {
      final once = embedHydrotestMeta('Uwaga', _full);
      final twice = embedHydrotestMeta(once, _full);
      expect(twice, once);
      expect(kHydrotestMetaMarker.allMatches(twice).length, 1);
    });

    test('puste metadane nie dopisują niczego do uwag', () {
      expect(embedHydrotestMeta('Uwaga', const HydrotestProtocolMeta()),
          'Uwaga');
      expect(const HydrotestProtocolMeta().isEmpty, isTrue);
      expect(_full.isEmpty, isFalse);
    });
  });

  group('model', () {
    test('preset z id', () {
      expect(_full.preset, PressureTestPreset.b313Hydro);
      expect(const HydrotestProtocolMeta(presetId: 'x').preset, isNull);
    });

    test('toRow / fromRow — kolumny docelowe po migracji', () {
      final row = _full.toRow();
      expect(row.keys.toSet(), HydrotestProtocolMeta.columns.keys.toSet());
      expect(row['relief_set_bar'], 19.5);
      expect(row['test_preset'], 'b31_3_hydro');
      expect(HydrotestProtocolMeta.fromRow(row), _full);
      // SQLite oddaje REAL z całą wartością jako int na niektórych platformach.
      expect(HydrotestProtocolMeta.fromRow({'metal_temp_c': 15}).metalTempC,
          15.0);
    });

    test('fromJson toleruje brakujące i obce pola', () {
      final m = HydrotestProtocolMeta.fromJson(
          {'company': 'X', 'stress_ratio': 1, 'nieznane': true});
      expect(m.company, 'X');
      expect(m.stressRatio, 1.0);
      expect(m.project, '');
      expect(m.reliefSetBar, isNull);
    });
  });
}
