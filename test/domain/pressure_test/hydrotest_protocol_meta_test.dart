// Metadane protokołu próby (firma, projekt, pakiet, P&ID/ISO, medium, preset,
// ST/S, temp. metalu, manometr, zawór bezpieczeństwa, nr/rewizja protokołu) —
// kolumny hydrotest_records w schemacie v19. Zgodność z bazą sprawdza
// test/database/hydrotest_protocol_columns_test.dart.

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
  test('preset z id', () {
    expect(_full.preset, PressureTestPreset.b313Hydro);
    expect(const HydrotestProtocolMeta(presetId: 'x').preset, isNull);
  });

  test('toRow / fromRow — dokładnie kolumny v19, bez strat', () {
    final row = _full.toRow();
    expect(row.keys.toSet(), HydrotestProtocolMeta.columns.keys.toSet());
    expect(row['relief_set_bar'], 19.5);
    expect(row['test_preset'], 'b31_3_hydro');
    expect(row['protocol_rev'], 'B');
    expect(HydrotestProtocolMeta.fromRow(row), _full);
    // Pusty tekst → NULL, jak w próbach sprzed v19.
    final empty = const HydrotestProtocolMeta().toRow();
    expect(empty.values.every((v) => v == null), isTrue);
  });

  test('wiersz sprzed v19 (NULL / brak kolumn) daje puste metadane', () {
    final fromNulls = HydrotestProtocolMeta.fromRow(
        {for (final c in HydrotestProtocolMeta.columns.keys) c: null});
    expect(fromNulls.isEmpty, isTrue);
    expect(HydrotestProtocolMeta.fromRow(const {}).isEmpty, isTrue);
    expect(_full.isEmpty, isFalse);
  });

  test('SQLite oddaje REAL z całą wartością jako int — czytamy przez num', () {
    final m = HydrotestProtocolMeta.fromRow(
        {'metal_temp_c': 15, 'stress_ratio': 1, 'relief_set_bar': 20});
    expect(m.metalTempC, 15.0);
    expect(m.stressRatio, 1.0);
    expect(m.reliefSetBar, 20.0);
  });

  test('obce typy w kolumnach tekstowych nie wywracają odczytu', () {
    final m = HydrotestProtocolMeta.fromRow({'company': 42, 'project': 'P'});
    expect(m.company, '');
    expect(m.project, 'P');
  });
}
