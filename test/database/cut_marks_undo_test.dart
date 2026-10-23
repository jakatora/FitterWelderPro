// Odhaczanie uciętych kawałków (v23 cut_marks) i Cofnij usunięcia segmentu.
//
// Było: usunięcie segmentu „nie do cofnięcia”, a listy cięć nie dało się
// odhaczać przy pile (nic nie pamiętało, co już ucięte).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/cut_mark_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/models/project.dart';

import '../support/test_database.dart';

Map<String, Object?> _row(String id, int seq, {double cut = 1000}) => {
      'id': id,
      'project_id': 'p-undo',
      'seq_no': seq,
      'diameter_mm': 114.3,
      'wall_thickness_mm': 3.05,
      'start_kind': 'logical',
      'start_library_id': null,
      'start_value_mm': 0.0,
      'end_kind': 'logical',
      'end_library_id': null,
      'end_value_mm': 0.0,
      'iso_ref': 'OPEN|OPEN',
      'iso_expr': '$cut',
      'iso_mm': cut,
      'cut_mm': cut,
      'created_at': 1,
      'updated_at': 1,
    };

void main() {
  useTestDatabase();
  final segments = SegmentDao();
  final marks = CutMarkDao();

  setUp(() async {
    final db = await AppDatabase.get();
    for (final t in ['segments', 'cut_marks', 'projects', 'component_heats']) {
      await db.delete(t);
    }
  });

  test('odhaczenie zapisuje się i znika po zmianie CUT segmentu', () async {
    await insertTestProject('p-undo');
    await marks.mark(projectId: 'p-undo', segmentId: 's1', part: 1, cutMm: 1000);
    final m = await marks.forProject('p-undo');
    expect(CutMarkDao.stillValid(m[CutMarkDao.keyOf('s1', 1)], 1000), isTrue);
    expect(CutMarkDao.stillValid(m[CutMarkDao.keyOf('s1', 1)], 1003), isFalse,
        reason: 'segment poprawiony — kawałek przy pile ma starą długość');
    expect(CutMarkDao.stillValid(m[CutMarkDao.keyOf('s1', 2)], 1000), isFalse);

    await marks.unmark(segmentId: 's1', part: 1);
    expect(await marks.forProject('p-undo'), isEmpty);
  });

  test('Cofnij usunięcia: ten sam id i numer; zajęty numer → na koniec',
      () async {
    await insertTestProject('p-undo');
    await segments.insert(_row('s1', 1));
    await segments.insert(_row('s2', 2));

    final snap = await segments.deleteWithSnapshot('s2');
    expect(snap, isNotNull);
    expect(await segments.listForProject('p-undo'), hasLength(1));

    expect(await segments.restore(snap!), 2);
    final back = await segments.listForProject('p-undo');
    expect(back.map((s) => (s.id, s.seqNo)), [('s1', 1), ('s2', 2)]);

    // Usunięty ostatni, w międzyczasie dodany nowy z tym samym numerem.
    final again = await segments.deleteWithSnapshot('s2');
    await segments.insert(_row('s3', 2));
    expect(await segments.restore(again!), 3);
    expect(
        (await segments.listForProject('p-undo')).map((s) => (s.id, s.seqNo)),
        [('s1', 1), ('s3', 2), ('s2', 3)]);
  });

  test('usunięcie projektu zabiera odhaczenia, Cofnij je przywraca', () async {
    final dao = ProjectDao();
    await dao.insert(Project(
      id: 'p-undo',
      name: 'X',
      materialGroup: 'SS',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      currentDiameterMm: 114.3,
      stockLengthMm: 6000,
      sawKerfMm: 1,
      gapMm: 0,
      createdAt: 1,
      updatedAt: 1,
    ));
    await marks.mark(projectId: 'p-undo', segmentId: 's1', part: 1, cutMm: 1000);
    final deleted = await dao.deleteProjectCascade('p-undo');
    expect(await marks.forProject('p-undo'), isEmpty);
    await dao.restore(deleted);
    expect(await marks.forProject('p-undo'), hasLength(1));
  });
}
