// Schemat v19: kolumny protokołu próby w hydrotest_records muszą być dokładnie
// tymi z HydrotestProtocolMeta.columns (nazwa i typ), a HydrotestDao musi je
// zapisywać i odczytywać.

import 'package:flutter_test/flutter_test.dart';
import '../support/test_database.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/hydrotest_dao.dart';
import 'package:cut_list_app/domain/pressure_test/hydrotest_protocol_meta.dart';

void main() {
  useTestDatabase();

  test('hydrotest_records ma kolumny protokołu z właściwymi typami', () async {
    final db = await AppDatabase.get();
    final info = await db.rawQuery('PRAGMA table_info(hydrotest_records);');
    final types = {
      for (final r in info) r['name'] as String: (r['type'] as String).toUpperCase(),
    };
    for (final c in HydrotestProtocolMeta.columns.entries) {
      expect(types[c.key], c.value, reason: 'hydrotest_records.${c.key}');
    }
    expect(AppDatabase.schemaVersion, greaterThanOrEqualTo(19));
  });

  test('HydrotestDao zapisuje i odczytuje metadane protokołu', () async {
    const meta = HydrotestProtocolMeta(
      company: 'Montaż Rur Sp. z o.o.',
      project: 'Pharma SA',
      testPackage: 'TP-101-03',
      drawingRefs: 'P&ID 101-PI-003; ISO 101-0042',
      testMedium: 'Woda',
      presetId: 'en13480_ped_hydro',
      stressRatio: 1.1,
      metalTempC: 14,
      gaugeRange: '0–25 bar',
      gaugeCalibrationDue: '2027-01-31',
      reliefSetBar: 17.5,
      protocolNo: 'HT-017',
      revision: 'A',
    );
    final id = 'meta_${DateTime.now().microsecondsSinceEpoch}';
    final dao = HydrotestDao();
    await dao.insert(HydrotestRecord(
      id: id,
      systemName: 'WFI-101',
      date: '2026-09-24',
      result: kHydrotestPass,
      createdAt: 1,
      notes: 'Korki 2×.',
      meta: meta,
    ));
    final back = (await dao.listAll()).firstWhere((r) => r.id == id);
    expect(back.meta, meta);
    // Uwagi zostają tekstem użytkownika — nic w nie nie jest doklejane.
    expect(back.notes, 'Korki 2×.');
    await dao.deleteById(id);
  });

  test('rekord bez metadanych zapisuje NULL w kolumnach protokołu', () async {
    final id = 'nometa_${DateTime.now().microsecondsSinceEpoch}';
    final dao = HydrotestDao();
    await dao.insert(HydrotestRecord(
      id: id,
      systemName: 'X',
      date: '2026-09-24',
      result: kHydrotestFail,
      createdAt: 2,
    ));
    final back = (await dao.listAll()).firstWhere((r) => r.id == id);
    expect(back.meta.isEmpty, isTrue);
    final raw = (await (await AppDatabase.get())
            .query('hydrotest_records', where: 'id = ?', whereArgs: [id]))
        .single;
    for (final c in HydrotestProtocolMeta.columns.keys) {
      expect(raw[c], isNull, reason: c);
    }
    await dao.deleteById(id);
  });
}
