import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/wps_dao.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';

import '../support/test_database.dart';

/// WPS jako dokument nadzorowany (v25): zmiana treści = nowa wersja z datą
/// obowiązywania; zapis bez zmiany treści nie mnoży wersji.
void main() {
  useTestDatabase();

  var now = 1790000000000;
  var seq = 0;
  WpsDao dao() => WpsDao(clock: () => now, newId: () => 'v-${seq++}');

  setUp(() async {
    final db = await AppDatabase.get();
    await db.delete('wps_library');
    await db.delete('wps_versions');
  });

  const base = WpsRecord(
    id: 'wps-1',
    wpsNo: 'WPS-141-01',
    revision: 'B',
    positions: 'PA, PC, PF, PE',
    createdAt: 1,
    updatedAt: 1,
  );

  test('pierwszy zapis = wersja 1 od zawsze; zmiana treści = wersja 2 od teraz',
      () async {
    expect(await dao().upsert(base), 1);
    var v = await dao().versionsOf('wps-1');
    expect(v.single.validFrom, 0);

    // Zapis bez zmiany treści (inny updated_at, ten sam zakres).
    now += 1000;
    expect(await dao().upsert(WpsRecord.fromRow({...base.toRow(), 'updated_at': 9})),
        1);
    expect(await dao().versionsOf('wps-1'), hasLength(1));

    now += 1000;
    final narrowed =
        WpsRecord.fromRow({...base.toRow(), 'positions': 'PA, PC, PF'});
    expect(await dao().upsert(narrowed, by: 'JK-12'), 2);
    v = await dao().versionsOf('wps-1');
    expect(v.map((x) => x.versionNo), [1, 2]);
    expect(v.last.validFrom, now);
    expect(v.last.byStamp, 'JK-12');
    expect(v.first.snapshot.positions, 'PA, PC, PF, PE');
    expect((await dao().getById('wps-1'))!.positions, 'PA, PC, PF');
    expect((await dao().versionsByWps())['wps-1'], hasLength(2));
  });

  test('wiersz bez historii (kopia sprzed v25): stara treść staje się wersją 1',
      () async {
    final db = await AppDatabase.get();
    await db.insert('wps_library', base.toRow());
    final changed =
        WpsRecord.fromRow({...base.toRow(), 'positions': 'wszystkie'});
    expect(await dao().upsert(changed), 2);
    final v = await dao().versionsOf('wps-1');
    expect(v.first.snapshot.positions, 'PA, PC, PF, PE');
    expect(v.first.validFrom, 0);
    expect(v.last.snapshot.positions, 'wszystkie');
  });

  test('duplikat numeru i rewizji; usunięcie kasuje wersje', () async {
    await dao().upsert(base);
    expect(await dao().duplicatesOf('wps-141-01', 'b'), hasLength(1));
    expect(await dao().duplicatesOf('wps-141-01', 'b', exceptId: 'wps-1'),
        isEmpty);
    await dao().delete('wps-1');
    expect(await dao().versionsOf('wps-1'), isEmpty);
  });
}
