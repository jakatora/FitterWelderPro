import 'package:flutter_test/flutter_test.dart';
import 'support/test_database.dart';

import 'package:cut_list_app/database/hydrotest_dao.dart';

void main() {
  useTestDatabase();

  /// Unique ids so each test is isolated from rows left by the others in the
  /// suite-local test database.
  String freshId() => 'hydro_${DateTime.now().microsecondsSinceEpoch}';

  test('ensureTable is idempotent — the lazy DDL runs on every call', () async {
    // The table is NOT created by db.dart (see the DAO's library doc), so this
    // has to be safe to run again on every single query for the lifetime of
    // the app. A second CREATE that threw would take the register down on the
    // second save, not the first — the worst kind of bug to find in the field.
    final dao = HydrotestDao();
    await dao.ensureTable();
    await dao.ensureTable();
    await dao.ensureTable();
  });

  test('insert / listAll / deleteById round-trip', () async {
    final dao = HydrotestDao();
    final id = freshId();

    final record = HydrotestRecord(
      id: id,
      systemName: 'WFI-101',
      date: '2026-08-30',
      gauge: 'M-12 / kal. 2026-03',
      pressureStartBar: 15.0,
      pressureEndBar: 14.8,
      temperatureC: 12.5,
      holdMinutes: 30,
      result: kHydrotestPass,
      witness: 'J. Kowalski',
      odMm: 60.3,
      wallMm: 3.91,
      // Metres on screen, MILLIMETRES in the database.
      lineLengthMm: 120000,
      designBar: 10.0,
      factor: 1.5,
      testPressureBar: 15.0,
      volumeL: 259.4,
      notes: 'Odpowietrzenie na najwyższym punkcie, korki 2×.',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await dao.insert(record);

    final back = (await dao.listAll()).firstWhere((r) => r.id == id);
    expect(back.systemName, 'WFI-101');
    expect(back.date, '2026-08-30');
    expect(back.gauge, 'M-12 / kal. 2026-03');
    expect(back.pressureStartBar, 15.0);
    expect(back.pressureEndBar, 14.8);
    expect(back.temperatureC, 12.5);
    expect(back.holdMinutes, 30);
    expect(back.result, kHydrotestPass);
    expect(back.witness, 'J. Kowalski');
    expect(back.odMm, 60.3);
    expect(back.wallMm, 3.91);
    expect(back.lineLengthMm, 120000);
    expect(back.designBar, 10.0);
    expect(back.factor, 1.5);
    expect(back.testPressureBar, 15.0);
    expect(back.volumeL, 259.4);
    // Polish diacritics survive the round-trip — the notes end up on a printed
    // protocol and mojibake there is not evidence of anything.
    expect(back.notes, contains('najwyższym'));

    await dao.deleteById(id);
    expect((await dao.listAll()).where((r) => r.id == id), isEmpty);
  });

  test('a half-filled test is still filable — nulls stay null', () async {
    // Deliberate: a crew without a thermometer must be able to file a record,
    // and the protocol names what is missing rather than printing a zero that
    // reads as a measurement.
    final dao = HydrotestDao();
    final id = freshId();
    await dao.insert(HydrotestRecord(
      id: id,
      systemName: 'Linia sprężonego powietrza',
      date: '2026-08-30',
      result: kHydrotestFail,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    final back = (await dao.listAll()).firstWhere((r) => r.id == id);
    expect(back.pressureStartBar, isNull);
    expect(back.pressureEndBar, isNull);
    expect(back.temperatureC, isNull);
    expect(back.holdMinutes, isNull);
    expect(back.testPressureBar, isNull);
    expect(back.pressureDropBar, isNull);
    // An unrecorded hold must never read as compliant.
    expect(back.meetsMinimumHold, isFalse);
    expect(back.passed, isFalse);
    expect(back.gauge, '');
    expect(back.witness, '');

    await dao.deleteById(id);
  });

  test('listAll returns newest first', () async {
    final dao = HydrotestDao();
    final older = freshId();
    final newer = '${older}_b';
    final now = DateTime.now().millisecondsSinceEpoch;

    await dao.insert(HydrotestRecord(
      id: older,
      systemName: 'OLD',
      date: '2026-08-01',
      result: kHydrotestPass,
      createdAt: now - 60000,
    ));
    await dao.insert(HydrotestRecord(
      id: newer,
      systemName: 'NEW',
      date: '2026-08-30',
      result: kHydrotestPass,
      createdAt: now,
    ));

    final rows = await dao.listAll();
    final iNewer = rows.indexWhere((r) => r.id == newer);
    final iOlder = rows.indexWhere((r) => r.id == older);
    expect(iNewer, greaterThanOrEqualTo(0));
    expect(iOlder, greaterThan(iNewer));

    await dao.deleteById(older);
    await dao.deleteById(newer);
  });

  test('count tracks inserts and deletes', () async {
    final dao = HydrotestDao();
    final before = await dao.count();
    final id = freshId();
    await dao.insert(HydrotestRecord(
      id: id,
      systemName: 'COUNT',
      date: '2026-08-30',
      result: kHydrotestPass,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    expect(await dao.count(), before + 1);
    await dao.deleteById(id);
    expect(await dao.count(), before);
  });

  test('update overwrites the filed test in place', () async {
    final dao = HydrotestDao();
    final id = freshId();
    final base = HydrotestRecord(
      id: id,
      systemName: 'WFI-102',
      date: '2026-08-30',
      result: kHydrotestPass,
      holdMinutes: 10,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await dao.insert(base);

    await dao.update(HydrotestRecord(
      id: id,
      systemName: 'WFI-102',
      date: '2026-08-30',
      result: kHydrotestFail,
      holdMinutes: 4,
      notes: 'Przeciek na kołnierzu.',
      createdAt: base.createdAt,
    ));

    final rows = (await dao.listAll()).where((r) => r.id == id).toList();
    // Updated, not duplicated.
    expect(rows.length, 1);
    expect(rows.single.result, kHydrotestFail);
    expect(rows.single.holdMinutes, 4);

    await dao.deleteById(id);
  });

  test('fromRow tolerates SQLite handing back an int for a REAL column', () {
    // sqflite returns whatever the platform stored: a REAL column holding a
    // whole number can come back as `int`. A hard `as double` cast would pass
    // on 10.5 and throw on 10 — a crash that only shows up on somebody's
    // round-numbered test.
    final r = HydrotestRecord.fromRow(<String, Object?>{
      'id': 'x',
      'system_name': 'WFI-101',
      'test_date': '2026-08-30',
      'gauge': 'M-12',
      'pressure_start_bar': 15, // int, not double
      'pressure_end_bar': 15,
      'temperature_c': 12,
      'hold_minutes': 10,
      'result': kHydrotestPass,
      'witness': '',
      'od_mm': 60,
      'wall_mm': 4,
      'line_length_mm': 120000,
      'design_bar': 10,
      'factor': 2,
      'test_pressure_bar': 20,
      'volume_l': 259,
      'notes': '',
      'created_at': 1756512000000,
    });
    expect(r.pressureStartBar, 15.0);
    expect(r.holdMinutes, 10.0);
    expect(r.meetsMinimumHold, isTrue);
    expect(r.hasPressureDrop, isFalse);
    expect(r.lineLengthM, 120.0);
  });

  test('a row written before a column existed reads as an unfilled field', () {
    // Defensive on purpose: the table is created lazily (see the DAO doc) and
    // will one day be migrated into db.dart. A missing key must degrade to
    // "not recorded", never crash the register open.
    final r = HydrotestRecord.fromRow(<String, Object?>{'id': 'legacy'});
    expect(r.systemName, '');
    expect(r.date, '');
    expect(r.pressureStartBar, isNull);
    // No verdict stored means the test cannot be claimed to have passed.
    expect(r.result, kHydrotestFail);
    expect(r.passed, isFalse);
    expect(r.createdAt, 0);
  });
}
