// Identyfikacja sztuk (schemat v22): projekt niesie nr linii, nr ISO,
// rewizję, klienta i klasę rurociągu; segment — oznaczenie sztuki (SP02-03)
// i spool. Wszystko opcjonalne: stary kod, który tych pól nie zna (zeszyt
// ISO, kreator, skaner), dalej zapisuje projekt bez nich.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/services/cut_list_summary.dart';
import 'package:cut_list_app/services/piece_marks.dart';

import '../support/test_database.dart';

Project _project(String id, {ProjectIdentity identity = ProjectIdentity.empty}) =>
    Project(
      id: id,
      name: 'Rack $id',
      materialGroup: 'CS',
      diameterMm: 114.3,
      wallThicknessMm: 6.02,
      currentDiameterMm: 114.3,
      stockLengthMm: 6000,
      sawKerfMm: 1,
      gapMm: 0,
      createdAt: 1,
      updatedAt: 1,
      lineNo: identity.lineNo,
      isoNo: identity.isoNo,
      isoRev: identity.isoRev,
      client: identity.client,
      spec: identity.spec,
    );

Map<String, Object?> _segRow(String id, String projectId, int seq,
        {Object? label = '', Object? spool = ''}) =>
    {
      'id': id,
      'project_id': projectId,
      'seq_no': seq,
      'diameter_mm': 114.3,
      'wall_thickness_mm': 6.02,
      'start_kind': 'logical',
      'start_library_id': null,
      'start_value_mm': 0.0,
      'end_kind': 'logical',
      'end_library_id': null,
      'end_value_mm': 0.0,
      'iso_ref': 'OPEN|OPEN',
      'iso_expr': '1000',
      'iso_mm': 1000.0,
      'cut_mm': 1000.0,
      'created_at': 1,
      'updated_at': 1,
      if (label != '') 'label': label,
      if (spool != '') 'spool_id': spool,
    };

Segment _seg(int seq, {String? label}) => Segment(
      id: 's$seq',
      projectId: 'p',
      seqNo: seq,
      diameterMm: 114.3,
      wallThicknessMm: 6.02,
      startKind: 'logical',
      startLibraryId: null,
      startValueMm: 0,
      endKind: 'logical',
      endLibraryId: null,
      endValueMm: 0,
      isoRef: 'OPEN|OPEN',
      isoExpr: '1000',
      isoMm: 1000,
      cutMm: 1000,
      createdAt: 1,
      updatedAt: 1,
      label: label,
    );

const _full = ProjectIdentity(
  lineNo: 'DN100-CWS-1234',
  isoNo: 'ISO-7',
  isoRev: 'B',
  client: 'Orlen',
  spec: 'A1B',
);

void main() {
  group('ProjectIdentity', () {
    test('clean: przycięte, puste → null', () {
      final i = ProjectIdentity.clean(
          lineNo: '  L-1 ', isoNo: '', isoRev: '   ', client: null, spec: 'A1');
      expect(i.lineNo, 'L-1');
      expect(i.isoNo, isNull);
      expect(i.isoRev, isNull);
      expect(i.client, isNull);
      expect(i.spec, 'A1');
      expect(ProjectIdentity.clean().isEmpty, isTrue);
    });

    test('podsumowanie PL / EN i skrót pod nazwą', () {
      expect(_full.summary(english: false),
          'Linia: DN100-CWS-1234 · ISO: ISO-7 rew. B · Klient: Orlen · Klasa: A1B');
      expect(_full.summary(english: true),
          'Line: DN100-CWS-1234 · ISO: ISO-7 rev. B · Client: Orlen · Class: A1B');
      expect(_full.shortSummary(english: false), 'DN100-CWS-1234 · ISO-7 rew. B');
      expect(const ProjectIdentity(isoRev: 'C').summary(english: false),
          'Rew.: C');
      expect(ProjectIdentity.empty.summary(english: false), '');
    });

    test('wyszukiwarka: nazwa, linia, ISO, klient; każde słowo musi pasować',
        () {
      final p = _project('1', identity: _full);
      expect(projectMatchesQuery(p, ''), isTrue);
      expect(projectMatchesQuery(p, 'rack'), isTrue);
      expect(projectMatchesQuery(p, 'cws-1234'), isTrue);
      expect(projectMatchesQuery(p, 'iso-7'), isTrue);
      expect(projectMatchesQuery(p, 'orlen 1234'), isTrue);
      expect(projectMatchesQuery(p, 'orlen 9999'), isFalse);
      expect(projectMatchesQuery(_project('2'), 'cws'), isFalse);
    });
  });

  group('oznaczenie sztuki', () {
    test('kolejny numer: ostatnia grupa cyfr, zera zachowane', () {
      expect(nextPieceLabel('SP02-03'), 'SP02-04');
      expect(nextPieceLabel('SP02-09'), 'SP02-10');
      expect(nextPieceLabel('S9'), 'S10');
      expect(nextPieceLabel('12'), '13');
      expect(nextPieceLabel('L-100/7A'), 'L-100/8A');
      expect(nextPieceLabel('SP-1/2'), 'SP-1/3');
      expect(nextPieceLabel('SPOOL'), isNull);
      expect(nextPieceLabel(null), isNull);
    });

    test('podpowiedź: po ostatnim oznaczonym segmencie, bez zajętych', () {
      expect(suggestNextSegmentLabel(const []), isNull);
      expect(suggestNextSegmentLabel([_seg(1), _seg(2)]), isNull);
      expect(
          suggestNextSegmentLabel(
              [_seg(1, label: 'SP02-01'), _seg(2, label: 'SP02-02'), _seg(3)]),
          'SP02-03');
      // Out of order in the list — seq_no decides which one is last.
      expect(
          suggestNextSegmentLabel(
              [_seg(2, label: 'SP02-03'), _seg(1, label: 'SP02-01')]),
          'SP02-04');
      // SP02-04 is already used further up the project.
      expect(
          suggestNextSegmentLabel([
            _seg(1, label: 'SP02-04'),
            _seg(2, label: 'SP02-03'),
          ]),
          'SP02-05');
    });

    test('etykieta na liście cięć: S03 obok oznaczenia, bez niego samo S03',
        () {
      expect(segmentLabel(_seg(3)), 'S03');
      expect(segmentLabel(_seg(3, label: 'SP02-03')), 'S03 SP02-03');
      expect(segmentLabel(_seg(3, label: '   ')), 'S03',
          reason: 'blank mark is no mark');
    });
  });

  group('DAO', () {
    useTestDatabase();

    test('projekt z identyfikacją: zapis i odczyt', () async {
      final dao = ProjectDao();
      await dao.insert(_project('id-full', identity: _full));
      final p = (await dao.getById('id-full'))!;
      expect(p.identity, _full);
      expect(p.lineNo, 'DN100-CWS-1234');
      expect(p.isoRev, 'B');
    });

    test('projekt bez identyfikacji (stary kod) zapisuje się jak dotąd',
        () async {
      final dao = ProjectDao();
      await dao.insert(_project('id-none'));
      final p = (await dao.getById('id-none'))!;
      expect(p.identity.isEmpty, isTrue);
    });

    test('updateSettings: identyfikacja zapisuje się, null jej nie rusza',
        () async {
      final dao = ProjectDao();
      await dao.insert(_project('id-set', identity: _full));

      await dao.updateSettings('id-set',
          name: 'Rack',
          stockLengthMm: 6000,
          sawKerfMm: 1,
          gapMm: 0);
      expect((await dao.getById('id-set'))!.identity, _full,
          reason: 'a caller that does not edit the identity cannot wipe it');

      await dao.updateSettings('id-set',
          name: 'Rack',
          stockLengthMm: 6000,
          sawKerfMm: 1,
          gapMm: 0,
          identity: const ProjectIdentity(lineNo: 'L-2', isoRev: 'C'));
      final p = (await dao.getById('id-set'))!;
      expect(p.lineNo, 'L-2');
      expect(p.isoRev, 'C');
      expect(p.isoNo, isNull, reason: 'cleared in the dialog → cleared');
      expect(p.client, isNull);
    });

    test('updateIdentity', () async {
      final dao = ProjectDao();
      await dao.insert(_project('id-upd'));
      expect(await dao.updateIdentity('id-upd', _full), 1);
      expect((await dao.getById('id-upd'))!.identity, _full);
      expect(await dao.updateIdentity('no-such', _full), 0);
    });

    test('segment: oznaczenie i spool, puste zapisane jako NULL', () async {
      await ProjectDao().insert(_project('id-seg'));
      final segs = SegmentDao();
      await segs.insert(
          _segRow('a', 'id-seg', 1, label: ' SP02-03 ', spool: 'SP02'));
      await segs.insert(_segRow('b', 'id-seg', 2, label: '  ', spool: ''));
      await segs.insert(_segRow('c', 'id-seg', 3)); // old code: no keys
      var list = await segs.listForProject('id-seg');
      expect(list.map((s) => s.label), ['SP02-03', null, null]);
      expect(list.map((s) => s.spoolId), ['SP02', null, null]);

      // A correction rewrites the mark; one without the key leaves it.
      await segs.update(_segRow('a', 'id-seg', 1, label: 'SP02-04'));
      await segs.update(_segRow('c', 'id-seg', 3));
      list = await segs.listForProject('id-seg');
      expect(list.first.label, 'SP02-04');
      expect(list.first.spoolId, 'SP02', reason: 'spool not in the update');
    });

    test('kasowanie z Cofnij przywraca też identyfikację i oznaczenia',
        () async {
      final dao = ProjectDao();
      await dao.insert(_project('id-undo', identity: _full));
      await SegmentDao()
          .insert(_segRow('u1', 'id-undo', 1, label: 'SP01-01', spool: 'SP01'));
      final deleted = await dao.deleteProjectCascade('id-undo');
      expect(await dao.getById('id-undo'), isNull);
      await dao.restore(deleted);
      expect((await dao.getById('id-undo'))!.identity, _full);
      final seg = (await SegmentDao().listForProject('id-undo')).single;
      expect(seg.label, 'SP01-01');
      expect(seg.spoolId, 'SP01');
    });
  });
}
