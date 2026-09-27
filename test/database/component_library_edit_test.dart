// Biblioteka komponentów: poprawianie i usuwanie wpisów.
//
// Było: DAO miało tylko insert — błędny take-off (762 zamiast 76,2) albo
// redukcja z długością 0 zostawały na zawsze, a UNIQUE blokował dodanie
// poprawionej kopii obok („możliwy duplikat”). Usunąć też się nie dało.
//
// Jest: update w miejscu (UNIQUE nie przeszkadza, bo to ten sam wiersz),
// usuwanie tylko wpisu, którego nie używa żaden zapisany segment, i
// wyszukanie „takiego samego” wpisu, żeby dialog dodawania zaproponował
// poprawienie istniejącego zamiast błędu.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/models/library_component.dart';

import '../support/test_database.dart';

LibraryComponent _reducer(String id, {double length = 0, double d = 114.3, double out = 60.3}) =>
    LibraryComponent(
      id: id,
      materialGroup: 'SS',
      type: 'REDUCER',
      diameterMm: d,
      wallThicknessMm: 3.05,
      axisMm: null,
      lengthMm: length,
      measurementMode: 'FACE',
      diameterOutMm: out,
      createdAt: 1,
      updatedAt: 1,
    );

LibraryComponent _elbow(String id, double axis) => LibraryComponent(
      id: id,
      materialGroup: 'SS',
      type: 'ELB90',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      axisMm: axis,
      lengthMm: null,
      measurementMode: null,
      diameterOutMm: null,
      createdAt: 1,
      updatedAt: 1,
    );

Future<void> _segmentUsing(String id, String projectId, int seq,
    {String? start, String? end}) async {
  final db = await AppDatabase.get();
  await db.insert('segments', {
    'id': id,
    'project_id': projectId,
    'seq_no': seq,
    'diameter_mm': 114.3,
    'wall_thickness_mm': 3.05,
    'start_kind': start == null ? 'logical' : 'nonAxial',
    'start_library_id': start,
    'start_value_mm': 0.0,
    'end_kind': end == null ? 'logical' : 'nonAxial',
    'end_library_id': end,
    'end_value_mm': 0.0,
    'iso_ref': 'OPEN|FACE_FAR',
    'iso_expr': '1000',
    'iso_mm': 1000.0,
    'cut_mm': 1000.0,
    'created_at': 1,
    'updated_at': 1,
  });
}

void main() {
  useTestDatabase();
  final dao = ComponentLibraryDao();

  setUp(() async {
    final db = await AppDatabase.get();
    await db.delete('component_library');
    await db.delete('segments');
    await db.delete('projects');
  });

  test('redukcję z L = 0 da się poprawić w miejscu (UNIQUE nie blokuje)',
      () async {
    await dao.insert(_reducer('red', length: 0));

    // Druga redukcja o tych samych średnicach — stary błąd „duplikat”.
    await expectLater(dao.insert(_reducer('red-2', length: 102)),
        throwsA(anything));

    final changed = await dao.update(_reducer('red', length: 102));
    expect(changed, 1);
    final back = await dao.getById('red');
    expect(back!.lengthMm, 102);
    expect(back.createdAt, 1, reason: 'data założenia wpisu zostaje');
  });

  test('findSameKind znajduje ten sam wpis — redukcję także odwróconą',
      () async {
    await dao.insert(_reducer('red', length: 0));
    final same = await dao.findSameKind(_reducer('new', length: 102));
    expect(same?.id, 'red');
    final flipped =
        await dao.findSameKind(_reducer('new', d: 60.3, out: 114.3));
    expect(flipped?.id, 'red',
        reason: '60,3 → 114,3 to ta sama kształtka co 114,3 → 60,3');
    expect(await dao.findSameKind(_reducer('new', out: 88.9)), isNull);
    expect(await dao.findSameKind(_reducer('red')), isNull,
        reason: 'wpis nie jest duplikatem samego siebie');
  });

  test('usunięcie wpisu używanego w segmencie jest zablokowane', () async {
    await dao.insert(_elbow('elb', 762));
    final db = await AppDatabase.get();
    await db.insert('projects', {
      'id': 'p1',
      'name': 'Rack 7',
      'material_group': 'SS',
      'diameter_mm': 114.3,
      'wall_thickness_mm': 3.05,
      'current_diameter_mm': 114.3,
      'created_at': 1,
      'updated_at': 1,
    });
    await _segmentUsing('s3', 'p1', 3, end: 'elb');

    final blocked = await dao.deleteIfUnused('elb');
    expect(blocked, hasLength(1));
    expect(blocked.single.projectName, 'Rack 7');
    expect(blocked.single.seqNo, 3);
    expect(await dao.getById('elb'), isNotNull, reason: 'nic nie zniknęło');

    // Poprawka wartości jest dozwolona — i widać, których segmentów dotyczy.
    await dao.update(_elbow('elb', 76.2));
    expect((await dao.getById('elb'))!.axisMm, 76.2);
    expect((await dao.usages('elb')).map((u) => u.seqNo), [3]);
  });

  test('nieużywany wpis znika', () async {
    await dao.insert(_elbow('elb', 76.2));
    expect(await dao.deleteIfUnused('elb'), isEmpty);
    expect(await dao.getById('elb'), isNull);
  });
}
