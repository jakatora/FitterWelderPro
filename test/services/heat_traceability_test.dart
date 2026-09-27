// Numery wytopów (identyfikowalność) w projekcie CUT.
//
// Było: wpisy `component_heats` kluczowane `S003_END` (z seq_no) — po
// usunięciu ostatniego segmentu nowy dostawał ten sam numer i heat starej
// kształtki „przechodził” na nową; lista zakładała jedną ciągłą trasę (START
// tylko pierwszego segmentu), rury nie miały wiersza, kształtka ze skanu
// udawała „OPEN END”, a numerów nie było widać nigdzie poza licznikiem.
//
// Jest: miejsca liczone z topologii (ta sama reguła złącza co BOM), heat
// przypięty do id segmentu + strony, wpisy bez miejsca pokazane osobno.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/component_heat_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/models/component_heat.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/services/heat_traceability.dart';
import 'package:cut_list_app/services/material_list_builder.dart';

import '../support/test_database.dart';

Segment _seg(String id, int seq, String? start, String? end,
    {String startKind = 'axial', String endKind = 'axial', double dia = 114.3}) {
  return Segment(
    id: id,
    projectId: 'p',
    seqNo: seq,
    diameterMm: dia,
    wallThicknessMm: 3.05,
    startKind: start == null && startKind == 'axial' ? 'logical' : startKind,
    startLibraryId: start,
    startValueMm: 0,
    endKind: end == null && endKind == 'axial' ? 'logical' : endKind,
    endLibraryId: end,
    endValueMm: 0,
    isoRef: 'AXIS|AXIS',
    isoExpr: '1000',
    isoMm: 1000,
    cutMm: 800,
    createdAt: 0,
    updatedAt: 0,
  );
}

ComponentHeat _heat(String id, String? seg, TraceSide? side, String no) =>
    ComponentHeat(
      id: id,
      projectId: 'p',
      componentKey: 'x',
      heatNo: no,
      imagePath: null,
      note: null,
      createdAt: 0,
      segmentId: seg,
      side: side,
    );

List<String> _keys(List<TracePoint> pts) =>
    [for (final p in pts) '${p.segment.id}:${p.side.code}${p.joinedNext == null ? '' : '>${p.joinedNext!.id}'}'];

int _ports(FittingKey k) =>
    MaterialListBuilder.portsForType(k.libraryId);

void main() {
  group('traceabilityPoints', () {
    test('ciągła trasa: kolano na złączu to jedno miejsce, każda rura ma swoje',
        () {
      final pts = traceabilityPoints([
        _seg('a', 1, null, 'ELB90'),
        _seg('b', 2, 'ELB90', 'ELB90'),
        _seg('c', 3, 'ELB90', null),
      ], portsOf: _ports);
      expect(_keys(pts), [
        'a:PIPE',
        'a:END>b',
        'b:PIPE',
        'b:END>c',
        'c:PIPE',
      ]);
      expect(pts[1].segmentsLabel, 'S01 → S02');
    });

    test('trasa nieciągła: START odgałęzienia ma własne miejsce', () {
      final pts = traceabilityPoints([
        _seg('a', 1, 'FLANGE', 'ELB90'),
        _seg('b', 2, 'TEE', 'FLANGE'),
      ], portsOf: _ports);
      expect(_keys(pts), [
        'a:START',
        'a:PIPE',
        'a:END',
        'b:START',
        'b:PIPE',
        'b:END',
      ]);
    });

    test('para kołnierzy na złączu to dwa miejsca', () {
      final pts = traceabilityPoints([
        _seg('a', 1, null, 'FLANGE'),
        _seg('b', 2, 'FLANGE', null),
      ], portsOf: _ports);
      expect(_keys(pts), ['a:PIPE', 'a:END', 'b:START', 'b:PIPE']);
    });

    test('redukcja ze skanu (Ø114,3 → Ø60,3) to jedno miejsce', () {
      final pts = traceabilityPoints([
        _seg('a', 1, null, null, endKind: 'nonAxial'),
        _seg('b', 2, null, null, startKind: 'nonAxial', dia: 60.3),
      ]);
      expect(_keys(pts), ['a:PIPE', 'a:END>b', 'b:PIPE']);
      expect(
        tracePlaceLabel(pts[1], english: false, typeOf: (_) => null),
        'Element (skan) Ø114.3 · koniec',
        reason: 'kształtka ze skanu nie jest „OPEN END”',
      );
    });
  });

  group('HeatIndex', () {
    test('heat przypięty do id: nowy segment z tym samym seq_no go nie dostaje',
        () {
      // S3 (id 'c') miał heat na końcu; usunięty, dodany nowy S3 (id 'c2').
      final pts = traceabilityPoints([
        _seg('a', 1, null, 'ELB90'),
        _seg('c2', 3, 'ELB90', 'ELB90'),
      ], portsOf: _ports);
      final index = HeatIndex([_heat('h', 'c', TraceSide.end, 'H-OLD')]);
      for (final p in pts) {
        expect(index.forPoint(p), isEmpty, reason: p.key);
      }
      expect(index.unplaced(pts).single.heatNo, 'H-OLD',
          reason: 'wpis zostaje widoczny jako „bez miejsca”');
    });

    test('heat zapisany na START następnego segmentu widać na złączu', () {
      final segs = [
        _seg('a', 1, null, 'ELB90'),
        _seg('b', 2, 'ELB90', null),
      ];
      final pts = traceabilityPoints(segs, portsOf: _ports);
      final index = HeatIndex([
        _heat('h1', 'a', TraceSide.end, 'H-1'),
        _heat('h2', 'b', TraceSide.start, 'H-2'),
        _heat('h3', 'b', TraceSide.pipe, 'P-9'),
        _heat('h4', null, null, 'H-LEGACY'),
      ]);
      final joint = pts.firstWhere((p) => p.side == TraceSide.end);
      expect(index.forPoint(joint).map((h) => h.heatNo), ['H-1', 'H-2']);
      expect(index.unplaced(pts).map((h) => h.heatNo), ['H-LEGACY']);

      final bySeg = segmentHeats(pts, index);
      expect(bySeg['a']!.end, ['H-1', 'H-2']);
      expect(bySeg['b']!.start, ['H-1', 'H-2'],
          reason: 'początek b to ta sama kształtka co koniec a');
      expect(bySeg['b']!.pipe, ['P-9']);

      final rows = heatReportRows(pts, index,
          english: false, typeOf: (id) => id);
      expect(rows.map((r) => r.line), [
        'S01 → S02 · ELB90 Ø114.3 · koniec: H-1, H-2',
        'S02 · Rura Ø114.3 × 3.05: P-9',
        '— · bez miejsca (segment usunięty): H-LEGACY',
      ]);
    });
  });

  group('ComponentHeatDao', () {
    useTestDatabase();
    final dao = ComponentHeatDao();

    setUp(() async {
      final db = await AppDatabase.get();
      await db.delete('component_heats');
    });

    test('dodaj → lista → popraw → usuń; pusty numer odrzucony', () async {
      final id = await dao.add(
        projectId: 'p',
        segmentId: 'seg-a',
        side: TraceSide.pipe,
        heatNo: '  A12345 ',
        note: ' atest 3.1 ',
      );
      var all = await dao.listForProject('p');
      expect(all.single.heatNo, 'A12345');
      expect(all.single.note, 'atest 3.1');
      expect(all.single.segmentId, 'seg-a');
      expect(all.single.side, TraceSide.pipe);

      await dao.update(id, heatNo: 'A12346', note: '');
      all = await dao.listForProject('p');
      expect(all.single.heatNo, 'A12346');
      expect(all.single.note, isNull);

      expect(
        () => dao.add(
            projectId: 'p', segmentId: 's', side: TraceSide.end, heatNo: '  '),
        throwsArgumentError,
      );

      await dao.deleteById(id);
      expect(await dao.listForProject('p'), isEmpty);
    });
  });
}
