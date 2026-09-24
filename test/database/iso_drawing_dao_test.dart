import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';

import '../support/test_database.dart';

IsoDrawingRecord _record(
  String id, {
  String name = '',
  String json = '{"format":1,"items":[]}',
  int createdAt = 1000,
  int updatedAt = 1000,
}) =>
    IsoDrawingRecord(
      id: id,
      name: name,
      json: json,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

void main() {
  useTestDatabase();

  final dao = IsoDrawingDao();

  setUp(() async {
    final db = await AppDatabase.get();
    await db.delete(IsoDrawingDao.table);
  });

  test('the table comes with the schema, so the backup carries sketches', () async {
    final db = await AppDatabase.get();
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [IsoDrawingDao.table],
    );
    expect(tables, hasLength(1));
  });

  test('no sketch yet → latest is null', () async {
    expect(await dao.latest(), isNull);
    expect(await dao.listAll(), isEmpty);
  });

  test('upsert inserts, then updates in place keeping created_at', () async {
    await dao.upsert(_record('s1', name: 'Linia 1', createdAt: 1000, updatedAt: 1000));
    await dao.upsert(_record('s1',
        name: 'Linia 1 — rev B',
        json: '{"format":1,"items":[{"kind":"note"}]}',
        createdAt: 9999,
        updatedAt: 2000));

    final back = (await dao.getById('s1'))!;
    expect(back.name, 'Linia 1 — rev B');
    expect(back.json, '{"format":1,"items":[{"kind":"note"}]}');
    expect(back.createdAt, 1000, reason: 'first save time is kept');
    expect(back.updatedAt, 2000);
    expect(await dao.listAll(), hasLength(1));
  });

  test('latest and the list follow the most recent save', () async {
    await dao.upsert(_record('old', name: 'Stary', updatedAt: 1000));
    await dao.upsert(_record('new', name: 'Nowy', updatedAt: 3000));
    await dao.upsert(_record('mid', name: 'Środkowy', updatedAt: 2000));
    expect((await dao.latest())!.id, 'new');

    await dao.upsert(_record('old', name: 'Stary', updatedAt: 4000));
    expect((await dao.latest())!.id, 'old');
    expect((await dao.listAll()).map((e) => e.id), ['old', 'new', 'mid']);
  });

  test('deleteById removes only that sketch', () async {
    await dao.upsert(_record('a'));
    await dao.upsert(_record('b'));
    await dao.deleteById('a');
    expect(await dao.getById('a'), isNull);
    expect(await dao.getById('b'), isNotNull);
  });
}
