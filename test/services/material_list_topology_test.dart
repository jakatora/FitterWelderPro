// Lista materiałowa: liczba FIZYCZNYCH kształtek w różnych topologiach.
//
// Model danych: segment = [koniec start] — rura — [koniec end]. Kształtka na
// końcu segmentu N i na początku segmentu N+1 to ta sama sztuka (złącze).
// Trójnik ma trzy wyloty: dwa zajmuje przelot (koniec N + początek N+1),
// trzeci — odgałęzienie, które monter zaczyna (lub kończy) na tym samym
// trójniku w innym miejscu listy. Kołnierz ma jeden wylot do spawania, więc
// kołnierz na końcu N i na początku N+1 to PARA kołnierzy (dwie sztuki).
//
// Projekty ze skanera nie mają wpisu biblioteki (library_id = null), mają
// tylko rodzaj końca (axial / nonAxial) i wymiar do osi — BOM liczy je z
// rodzaju, zamiast pokazywać 0 kształtek.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/models/material_item.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/services/material_list_builder.dart';

class _FakeSegmentDao extends SegmentDao {
  final List<Segment> rows;
  _FakeSegmentDao(this.rows);

  @override
  Future<List<Segment>> listForProject(String projectId) async =>
      rows.where((s) => s.projectId == projectId).toList();
}

class _FakeLibraryDao extends ComponentLibraryDao {
  final Map<String, LibraryComponent> byId;
  _FakeLibraryDao(this.byId);

  @override
  Future<LibraryComponent?> getById(String id) async => byId[id];
}

const _pid = 'PRJ-T';

/// Segment from the segment builder: a library id means a real component
/// (kind axial / nonAxial as the builder writes it), null means an open end.
Segment _seg(int seq, String? start, String? end, {double cut = 1000}) {
  String kindOf(String? id) {
    if (id == null) return 'logical';
    return id == 'FLANGE' ? 'nonAxial' : 'axial';
  }

  return Segment(
    id: 'S$seq',
    projectId: _pid,
    seqNo: seq,
    diameterMm: 114.3,
    wallThicknessMm: 3.6,
    startKind: kindOf(start),
    startLibraryId: start,
    startValueMm: 0,
    endKind: kindOf(end),
    endLibraryId: end,
    endValueMm: 0,
    isoRef: 'FACE|FACE',
    isoExpr: '$cut',
    isoMm: cut,
    cutMm: cut,
    createdAt: 0,
    updatedAt: 0,
  );
}

/// Segment as ScanReviewScreen saves it: no library ids, only the end kind
/// and the take-out in *_value_mm (0 for faces and open ends).
Segment _scan(int seq, String startKind, double startMm, String endKind,
    double endMm) {
  return Segment(
    id: 'K$seq',
    projectId: _pid,
    seqNo: seq,
    diameterMm: 114.3,
    wallThicknessMm: 6.02,
    startKind: startKind,
    startLibraryId: null,
    startValueMm: startMm,
    endKind: endKind,
    endLibraryId: null,
    endValueMm: endMm,
    isoRef: 'AXIS',
    isoExpr: '1000',
    isoMm: 1000,
    cutMm: 800,
    createdAt: 0,
    updatedAt: 0,
  );
}

LibraryComponent _lib(String type) => LibraryComponent(
      id: type,
      materialGroup: 'SS',
      type: type,
      diameterMm: 114.3,
      wallThicknessMm: 3.6,
      axisMm: type == 'FLANGE' ? null : 76.2,
      lengthMm: type == 'FLANGE' ? 60 : null,
      measurementMode: type == 'FLANGE' ? 'FACE' : null,
      diameterOutMm: null,
      createdAt: 0,
      updatedAt: 0,
    );

final _library = _FakeLibraryDao({
  for (final t in ['TEE', 'ELB90', 'FLANGE']) t: _lib(t),
});

Future<List<MaterialItem>> _build(List<Segment> segs) =>
    MaterialListBuilder(_FakeSegmentDao(segs), _library).buildForProject(_pid);

/// Category → quantity for every non-pipe row.
Future<Map<String, int>> _counts(List<Segment> segs) async {
  final items = await _build(segs);
  return {
    for (final i in items)
      if (i.category != 'PIPE') i.category: i.quantity!,
  };
}

void main() {
  group('trójnik z odgałęzieniem liczony raz', () {
    test('FLANGE→TEE, TEE→ELB, TEE→FLANGE: 1 trójnik (było 2)', () async {
      // Przelot: S1 kończy się na trójniku, S2 zaczyna na nim; S3 to
      // odgałęzienie z trzeciego wylotu tego samego trójnika.
      expect(
        await _counts([
          _seg(1, 'FLANGE', 'TEE'),
          _seg(2, 'TEE', 'ELB90'),
          _seg(3, 'TEE', 'FLANGE'),
        ]),
        {'TEE': 1, 'ELB90': 1, 'FLANGE': 2},
      );
    });

    test('odgałęzienie wpisane przed przelotem: nadal 1 trójnik', () async {
      expect(
        await _counts([
          _seg(1, 'TEE', 'FLANGE'),
          _seg(2, 'FLANGE', 'TEE'),
          _seg(3, 'TEE', 'FLANGE'),
        ]),
        // S1.end i S2.start to dwa różne kołnierze (kołnierz ma jeden wylot).
        {'TEE': 1, 'FLANGE': 3},
      );
    });

    test('odgałęzienie rysowane w stronę trójnika (…→TEE): 1 trójnik',
        () async {
      expect(
        await _counts([
          _seg(1, 'FLANGE', 'TEE'),
          _seg(2, 'TEE', 'FLANGE'),
          _seg(3, 'FLANGE', 'TEE'),
        ]),
        {'TEE': 1, 'FLANGE': 3},
      );
    });

    test('dwa trójniki w przelocie i dwa odgałęzienia: 2 trójniki', () async {
      expect(
        await _counts([
          _seg(1, 'FLANGE', 'TEE'),
          _seg(2, 'TEE', 'TEE'),
          _seg(3, 'TEE', 'FLANGE'),
          _seg(4, 'TEE', 'FLANGE'),
          _seg(5, 'TEE', 'FLANGE'),
        ]),
        {'TEE': 2, 'FLANGE': 4},
      );
    });

    test('trzecie odgałęzienie przy dwóch trójnikach wymaga trzeciego',
        () async {
      expect(
        await _counts([
          _seg(1, 'FLANGE', 'TEE'),
          _seg(2, 'TEE', 'TEE'),
          _seg(3, 'TEE', 'FLANGE'),
          _seg(4, 'TEE', 'FLANGE'),
          _seg(5, 'TEE', 'FLANGE'),
          _seg(6, 'TEE', 'FLANGE'),
        ]),
        {'TEE': 3, 'FLANGE': 5},
      );
    });

    test('dwie nitki schodzą się w trójniku i idą dalej: 1 trójnik', () async {
      expect(
        await _counts([
          _seg(1, 'FLANGE', 'TEE'),
          _seg(2, 'FLANGE', 'TEE'),
          _seg(3, 'TEE', 'FLANGE'),
        ]),
        {'TEE': 1, 'FLANGE': 3},
      );
    });
  });

  group('kołnierze i kolana', () {
    test('kołnierz na końcu S1 i początku S2 to para: 2 kołnierze', () async {
      expect(
        await _counts([
          _seg(1, 'ELB90', 'FLANGE'),
          _seg(2, 'FLANGE', 'ELB90'),
        ]),
        {'ELB90': 2, 'FLANGE': 2},
      );
    });

    test('kolano nie „przyczepia się” do odległego kolana', () async {
      // Kolano ma dwa wyloty — łączy tylko sąsiednie segmenty.
      expect(
        await _counts([
          _seg(1, 'FLANGE', 'ELB90'),
          _seg(2, 'FLANGE', 'FLANGE'),
          _seg(3, 'ELB90', 'FLANGE'),
        ]),
        {'ELB90': 2, 'FLANGE': 4},
      );
    });
  });

  group('projekt ze skanera (bez wpisów biblioteki)', () {
    test('kształtki liczone z rodzaju końca zamiast 0', () async {
      // otwarty koniec → kolano (do osi 152.4) → zawór → otwarty koniec
      final items = await _build([
        _scan(1, 'logical', 0, 'axial', 152.4),
        _scan(2, 'axial', 152.4, 'nonAxial', 0),
        _scan(3, 'nonAxial', 0, 'logical', 0),
      ]);
      final fittings = items.where((i) => i.category != 'PIPE').toList();
      expect(fittings.map((i) => (i.category, i.quantity)), [
        ('FITTING_AXIAL', 1),
        ('FITTING_BODY', 1),
      ]);
      final axial = fittings.first;
      expect(axial.endKind, 'axial');
      expect(axial.diameterMm, 114.3);
      expect(axial.takeoutMm, 152.4);
      expect(axial.libraryEntryMissing, isFalse);
      expect(fittings.last.endKind, 'nonAxial');
      expect(fittings.last.takeoutMm, isNull);
    });

    test('trzy kolana na złączach trasy: 3 sztuki', () async {
      expect(
        await _counts([
          _scan(1, 'logical', 0, 'axial', 152.4),
          _scan(2, 'axial', 152.4, 'axial', 152.4),
          _scan(3, 'axial', 152.4, 'axial', 152.4),
          _scan(4, 'axial', 152.4, 'logical', 0),
        ]),
        {'FITTING_AXIAL': 3},
      );
    });

    test('różne wymiary do osi to osobne pozycje BOM', () async {
      final items = await _build([
        _scan(1, 'logical', 0, 'axial', 152.4),
        _scan(2, 'axial', 152.4, 'axial', 104.8),
        _scan(3, 'axial', 104.8, 'logical', 0),
      ]);
      final axial = items.where((i) => i.category == 'FITTING_AXIAL').toList();
      expect(axial.map((i) => (i.takeoutMm, i.quantity)), [
        (104.8, 1),
        (152.4, 1),
      ]);
    });

    test('same otwarte końce: tylko rura', () async {
      final items = await _build([
        _scan(1, 'logical', 0, 'logical', 0),
      ]);
      expect(items.map((i) => i.category), ['PIPE']);
    });
  });

  test('wpis usunięty z biblioteki nie znika z BOM', () async {
    // Segmenty wskazują na kolano, którego nie ma już w bibliotece —
    // wcześniej pozycja była po cichu pomijana (monter nie zamawiał kolan).
    final items = await _build([
      _seg(1, 'GONE', 'GONE'),
      _seg(2, 'GONE', null),
    ]);
    final missing = items.where((i) => i.category != 'PIPE').single;
    expect(missing.libraryEntryMissing, isTrue);
    expect(missing.quantity, 2);
    expect(missing.category, 'FITTING_AXIAL');
    expect(missing.endKind, 'axial');
  });

  group('countComponentInstances z liczbą wylotów', () {
    test('bez informacji o typach: dawne reguły (2 wyloty dla wszystkich)',
        () {
      expect(
        MaterialListBuilder.countComponentInstances([
          _seg(1, 'FLANGE', 'TEE'),
          _seg(2, 'TEE', 'ELB90'),
          _seg(3, 'TEE', 'FLANGE'),
        ]),
        {'FLANGE': 2, 'TEE': 2, 'ELB90': 1},
      );
    });

    test('z typami z biblioteki: trójnik 3 wyloty, kołnierz 1', () {
      expect(
        MaterialListBuilder.countComponentInstances(
          [
            _seg(1, 'FLANGE', 'TEE'),
            _seg(2, 'TEE', 'ELB90'),
            _seg(3, 'TEE', 'FLANGE'),
          ],
          portsOf: (id) => MaterialListBuilder.portsForType(id),
        ),
        {'FLANGE': 2, 'TEE': 1, 'ELB90': 1},
      );
    });

    test('portsForType', () {
      expect(MaterialListBuilder.portsForType('TEE'), 3);
      expect(MaterialListBuilder.portsForType('FLANGE'), 1);
      expect(MaterialListBuilder.portsForType('ELB90'), 2);
      expect(MaterialListBuilder.portsForType('REDUCER'), 2);
      expect(MaterialListBuilder.portsForType(null), 2);
    });
  });
}
