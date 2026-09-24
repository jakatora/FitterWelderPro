// Component library lookup by Ø and wall (`ComponentLibraryDao.listFor`).
//
// Both columns are SQLite REAL and used to be matched with `=`: a takeout
// saved as 114.3 was invisible to a project whose Ø came in as
// 114.30000000000001, or was typed "114,30" on another screen. The builder
// then asked for the takeout again and a second entry went into the library.
// The lookup now matches within ±kLibraryMatchToleranceMm (0.05 mm).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/utils/decimal_parse.dart';

import '../support/test_database.dart';

LibraryComponent _comp(
  String id, {
  String group = 'SS',
  String type = 'ELB90',
  required double d,
  required double t,
  double? out,
}) =>
    LibraryComponent(
      id: id,
      materialGroup: group,
      type: type,
      diameterMm: d,
      wallThicknessMm: t,
      axisMm: type == 'REDUCER' ? null : 152.4,
      lengthMm: type == 'REDUCER' ? 102 : null,
      measurementMode: type == 'REDUCER' ? 'FACE' : null,
      diameterOutMm: out,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  useTestDatabase();
  final dao = ComponentLibraryDao();

  setUp(() async {
    final db = await AppDatabase.get();
    await db.delete('component_library');
  });

  Future<List<String>> ids(double d, double t, {String group = 'SS'}) async =>
      (await dao.listFor(
        materialGroup: group,
        currentDiameter: d,
        wallThickness: t,
      ))
          .map((c) => c.id)
          .toList();

  test('saved as 114.3 → found for "114,3" and for "114.30"', () async {
    await dao.insert(_comp('elb-114', d: 114.3, t: 3.05));

    // Exactly what a field hands over after the fitter typed it.
    expect(await ids(parseDecimal('114,3')!, parseDecimal('3,05')!),
        ['elb-114']);
    expect(await ids(parseDecimal('114.30')!, parseDecimal('3.050')!),
        ['elb-114']);
  });

  test('floating-point and rounding noise still matches', () async {
    await dao.insert(_comp('elb-114', d: 114.3, t: 3.05));

    expect(await ids(114.1 + 0.2, 3.05), ['elb-114'],
        reason: '114.1 + 0.2 = 114.29999999999998 in binary');
    expect(await ids(114.34, 3.05), ['elb-114']);
    expect(await ids(114.26, 3.01), ['elb-114']);
    // ASME 60.33 is the same 2" tube as the metric 60.3.
    await dao.insert(_comp('elb-60', d: 60.3, t: 2.77));
    expect(await ids(60.33, 2.77), ['elb-60']);
  });

  test('the ±0.05 mm edge is inclusive both ways', () async {
    await dao.insert(_comp('elb-114', d: 114.3, t: 3.05));
    expect(await ids(114.35, 3.05), ['elb-114']);
    expect(await ids(114.25, 3.05), ['elb-114']);
    expect(await ids(114.3, 3.1), ['elb-114']);
    expect(await ids(114.3, 3.0), ['elb-114']);
  });

  test('a genuinely different pipe is not matched', () async {
    await dao.insert(_comp('elb-114', d: 114.3, t: 3.05));
    await dao.insert(_comp('elb-76-1', d: 76.1, t: 2.0));

    expect(await ids(114.4, 3.05), isEmpty, reason: '0.1 mm off in Ø');
    expect(await ids(114.3, 3.2), isEmpty, reason: 'different wall');
    expect(await ids(1143, 3.05), isEmpty,
        reason: '"1143" typed without the comma is not 114.3');
    // EN 76.1 and sanitary 76.2 — the closest pair of real ODs.
    expect(await ids(76.2, 2.0), isEmpty);
    expect(await ids(76.1, 2.0), ['elb-76-1']);
  });

  test('material group is still matched exactly', () async {
    await dao.insert(_comp('elb-114', d: 114.3, t: 3.05));
    expect(await ids(114.3, 3.05, group: 'CS'), isEmpty);
  });

  test('reducers match on inlet OR outlet within the tolerance', () async {
    await dao.insert(
        _comp('red', type: 'REDUCER', d: 114.3, t: 3.05, out: 60.3));
    expect(await ids(parseDecimal('114,30')!, 3.05), ['red'],
        reason: 'inlet side');
    expect(await ids(parseDecimal('60,3')!, 3.05), ['red'],
        reason: 'outlet side');
    expect(await ids(60.32, 3.05), ['red']);
    expect(await ids(88.9, 3.05), isEmpty);
  });
}
