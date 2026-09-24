// Edycja ustawień projektu (nazwa, długość sztangi, kerf, gap) po utworzeniu.
//
// Do tej pory nic z tego nie dało się zmienić: ProjectDao.updateName istniało,
// ale nikt go nie wołał, a gap, kerf i sztanga były zamrożone na wartościach z
// formularza. Pomyłka w gapie (0 zamiast 3) oznaczała albo cały projekt od
// nowa, albo cięcie rur o szczelinę za długich.
//
// Zmiana gapu musi przeliczyć zapisane CUT WSZYSTKICH segmentów tą samą regułą
// co kreator — PrefabEngine.anchoredCutMm z liczbą spoin z
// PrefabEngine.weldCountForEnds — w jednej transakcji: albo projekt i
// wszystkie segmenty, albo nic.
//
// Liczby ręcznie, CUT = ISO − zdjęte_start − zdjęte_koniec − gap × spoiny.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';
import 'package:cut_list_app/services/prefab_engine.dart';

import '../support/test_database.dart';

Project _project(String id, {double gap = 0, String? name}) => Project(
      id: id,
      name: name ?? 'Projekt $id',
      materialGroup: 'SS',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      currentDiameterMm: 114.3,
      stockLengthMm: 6000,
      sawKerfMm: 1,
      gapMm: gap,
      createdAt: 1,
      updatedAt: 1,
    );

Map<String, Object?> _row(
  String projectId,
  int seq, {
  required String startKind,
  String? startLib,
  required double startValue,
  required String endKind,
  String? endLib,
  required double endValue,
  required String isoRef,
  required double iso,
  required double cut,
}) =>
    {
      'id': '$projectId-seg$seq',
      'project_id': projectId,
      'seq_no': seq,
      'diameter_mm': 114.3,
      'wall_thickness_mm': 3.05,
      'start_kind': startKind,
      'start_library_id': startLib,
      'start_value_mm': startValue,
      'end_kind': endKind,
      'end_library_id': endLib,
      'end_value_mm': endValue,
      'iso_ref': isoRef,
      'iso_expr': iso.toStringAsFixed(0),
      'iso_mm': iso,
      'cut_mm': cut,
      'created_at': 1,
      'updated_at': 1,
    };

void main() {
  useTestDatabase();

  final projects = ProjectDao();
  final segments = SegmentDao();

  Future<Map<int, double>> cuts(String projectId) async {
    final list = await segments.listForProject(projectId);
    return {for (final s in list) s.seqNo: s.cutMm};
  }

  test('gap 0 → 3 przelicza CUT każdego segmentu według liczby jego spoin',
      () async {
    const id = 'settings-a';
    await projects.insert(_project(id));
    // A: kolano (152) → wolny koniec, ISO 1000: 1000 − 152 = 848 przy gap 0.
    await segments.insert(_row(id, 1,
        startKind: 'axial', startLib: 'lib-elb', startValue: 152,
        endKind: 'logical', endValue: 0,
        isoRef: 'AXIS|OPEN', iso: 1000, cut: 848));
    // B: kolano → kolano, ISO 2000: 2000 − 152 − 152 = 1696.
    await segments.insert(_row(id, 2,
        startKind: 'axial', startLib: 'lib-elb', startValue: 152,
        endKind: 'axial', endLib: 'lib-elb', endValue: 152,
        isoRef: 'AXIS|AXIS', iso: 2000, cut: 1696));
    // C: wolny koniec → wolny koniec, ISO 500: 500.
    await segments.insert(_row(id, 3,
        startKind: 'logical', startValue: 0,
        endKind: 'logical', endValue: 0,
        isoRef: 'OPEN|OPEN', iso: 500, cut: 500));
    // E: kolano → kołnierz do czoła uszczelnienia (L 76), ISO 1500:
    //    1500 − 152 − 76 = 1272.
    await segments.insert(_row(id, 4,
        startKind: 'axial', startLib: 'lib-elb', startValue: 152,
        endKind: 'nonAxial', endLib: 'lib-fl', endValue: 76,
        isoRef: 'AXIS|FACE_FAR', iso: 1500, cut: 1272));

    final result = await projects.updateSettings(
      id,
      name: 'Linia 7 po poprawce',
      stockLengthMm: 12000,
      sawKerfMm: 2,
      gapMm: 3,
    );

    expect(await cuts(id), {
      1: 845, //  1000 − 152 − 0 − 3 × 1
      2: 1690, // 2000 − 152 − 152 − 3 × 2
      3: 500, //  500 − 0 − 0 − 3 × 0
      4: 1266, // 1500 − 152 − 76 − 3 × 2
    });
    expect(result.recomputed, 4);
    expect(result.changedBeyondGap, isEmpty,
        reason: 'every row moved by exactly gap × its welds');

    final p = (await projects.getById(id))!;
    expect(p.gapMm, 3);
    expect(p.name, 'Linia 7 po poprawce');
    expect(p.stockLengthMm, 12000);
    expect(p.sawKerfMm, 2);
  });

  test('przeliczenie = ta sama funkcja co kreator (builderCutMm)', () async {
    // Segment A z testu wyżej, policzony tak, jak liczy go kreator na ekranie.
    final viaBuilder = builderCutMm(
      isoMm: 1000,
      startRef: IsoRefPoint.axis,
      startOffsetMm: 152,
      endRef: IsoRefPoint.open,
      endOffsetMm: 0,
      gapMm: 3,
      welds: builderWeldCount('ELB90', kOpenEndTag),
    );
    final viaStoredRow = PrefabEngine.storedSegmentCutMm(
      isoMm: 1000,
      isoRef: 'AXIS|OPEN',
      startKind: 'axial',
      startValueMm: 152,
      endKind: 'logical',
      endValueMm: 0,
      gapMm: 3,
    );
    expect(viaStoredRow, viaBuilder);
    expect(viaStoredRow, 845);
  });

  test('zmiana samej nazwy nie rusza żadnego CUT', () async {
    const id = 'settings-name';
    await projects.insert(_project(id, gap: 2));
    await segments.insert(_row(id, 1,
        startKind: 'axial', startLib: 'lib-elb', startValue: 152,
        endKind: 'axial', endLib: 'lib-elb', endValue: 152,
        isoRef: 'AXIS|AXIS', iso: 2000, cut: 1692));

    final result = await projects.updateSettings(
      id,
      name: 'Tylko nazwa',
      stockLengthMm: 6000,
      sawKerfMm: 1,
      gapMm: 2,
    );

    expect(result.recomputed, 0);
    expect(await cuts(id), {1: 1692});
    expect((await projects.getById(id))!.name, 'Tylko nazwa');
  });

  test('gap, przy którym któryś CUT wychodzi ≤ 0, nie zmienia NICZEGO',
      () async {
    const id = 'settings-rollback';
    await projects.insert(_project(id, name: 'Przed'));
    // D: kolano 152 → wolny koniec, ISO 154: przy gap 0 CUT 2,
    //    przy gap 3: 154 − 152 − 3 = −1 → nie do cięcia.
    await segments.insert(_row(id, 1,
        startKind: 'logical', startValue: 0,
        endKind: 'logical', endValue: 0,
        isoRef: 'OPEN|OPEN', iso: 700, cut: 700));
    await segments.insert(_row(id, 2,
        startKind: 'axial', startLib: 'lib-elb', startValue: 152,
        endKind: 'logical', endValue: 0,
        isoRef: 'AXIS|OPEN', iso: 154, cut: 2));

    await expectLater(
      projects.updateSettings(
        id,
        name: 'Po',
        stockLengthMm: 6000,
        sawKerfMm: 1,
        gapMm: 3,
      ),
      throwsA(isA<GapMakesCutImpossible>()
          .having((e) => e.seqNo, 'seqNo', 2)),
    );

    final p = (await projects.getById(id))!;
    expect(p.gapMm, 0, reason: 'one transaction: nothing may be half-applied');
    expect(p.name, 'Przed');
    expect(await cuts(id), {1: 700, 2: 2});
  });

  test('wiersz, który nie zgadzał się ze swoim gapem, jest zgłaszany',
      () async {
    // Zapisany starą regułą spoin (kolano → wolny koniec liczone jako 2
    // spoiny) przy gap 2: 1000 − 152 − 2 × 2 = 844. Poprawnie przy gap 3:
    // 1000 − 152 − 3 × 1 = 845 — przesunięcie o +1, a nie o (2 − 3) × 1 = −1,
    // więc monter dostaje numer segmentu do sprawdzenia.
    const id = 'settings-legacy';
    await projects.insert(_project(id, gap: 2));
    await segments.insert(_row(id, 5,
        startKind: 'axial', startLib: 'lib-elb', startValue: 152,
        endKind: 'logical', endValue: 0,
        isoRef: 'AXIS|OPEN', iso: 1000, cut: 844));

    final result = await projects.updateSettings(
      id,
      name: 'Projekt $id',
      stockLengthMm: 6000,
      sawKerfMm: 1,
      gapMm: 3,
    );

    expect(await cuts(id), {5: 845});
    expect(result.changedBeyondGap, [5]);
  });
}
