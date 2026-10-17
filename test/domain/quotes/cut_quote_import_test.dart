// Import spoin z projektu CUT (lista cięć) do wyceny: reguły liczenia spoin
// z odcinków i kształtek (services/cut_quote_import.dart) przez to samo
// grupowanie co skan i dziennik (domain/quotes/quote_import.dart).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/quotes/quote_calculator.dart';
import 'package:cut_list_app/domain/quotes/quote_import.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/services/cut_quote_import.dart';

LibraryComponent _lib(String id, String type,
    {double d = 114.3, double t = 6.02, double? out}) {
  final axial = type == 'ELB90' || type == 'ELB45' || type == 'TEE';
  return LibraryComponent(
    id: id,
    materialGroup: 'CS',
    type: type,
    diameterMm: d,
    wallThicknessMm: t,
    axisMm: axial ? 152.4 : null,
    lengthMm: axial ? null : 100,
    measurementMode: axial ? null : 'FACE',
    diameterOutMm: out,
    createdAt: 0,
    updatedAt: 0,
  );
}

final Map<String, LibraryComponent> _library = {
  for (final c in [
    _lib('e90', 'ELB90'),
    _lib('e45', 'ELB45'),
    _lib('tee', 'TEE'),
    _lib('red', 'REDUCER', out: 60.3),
    _lib('fl', 'FLANGE'),
    _lib('vlv', 'VALVE'),
  ])
    c.id: c,
};

/// Rodzaj końca jak zapisuje go ekran budowania odcinka: brak = koniec
/// otwarty, wpis osiowy = `axial`, reszta = `nonAxial`. [kind] — wprost
/// (kształtka ze skanu bez wpisu, wpis usunięty z biblioteki).
String _kind(String? lib, String? kind) {
  if (kind != null) return kind;
  if (lib == null) return 'logical';
  return (_library[lib]?.isAxial ?? false) ? 'axial' : 'nonAxial';
}

Segment _seg(
  int seq, {
  String? start,
  String? end,
  String? startKind,
  String? endKind,
  double od = 114.3,
  double t = 6.02,
  double cut = 1000,
  String? label,
}) =>
    Segment(
      id: 's$seq',
      projectId: 'p',
      seqNo: seq,
      diameterMm: od,
      wallThicknessMm: t,
      startKind: _kind(start, startKind),
      startLibraryId: start,
      startValueMm: 0,
      endKind: _kind(end, endKind),
      endLibraryId: end,
      endValueMm: 0,
      isoRef: 'AXIS|AXIS',
      isoExpr: '$cut',
      isoMm: cut,
      cutMm: cut,
      createdAt: 0,
      updatedAt: 0,
      label: label,
    );

Project _project({
  String? name = 'Linia wody',
  double stock = 6000,
  double gap = 0,
  String material = 'CS',
  String? isoNo,
  String? isoRev,
  String? lineNo,
}) =>
    Project(
      id: 'p',
      name: name,
      materialGroup: material,
      diameterMm: 114.3,
      wallThicknessMm: 6.02,
      currentDiameterMm: 114.3,
      stockLengthMm: stock,
      sawKerfMm: 1,
      gapMm: gap,
      createdAt: 0,
      updatedAt: 0,
      isoNo: isoNo,
      isoRev: isoRev,
      lineNo: lineNo,
    );

CutProjectWelds _welds(
  List<Segment> segments, {
  CutImportOptions options = const CutImportOptions(),
  Project? project,
}) =>
    importWeldsFromCutProject(
      CutImportProject(
        project: project ?? _project(),
        segments: segments,
        library: _library,
      ),
      options: options,
    );

QuoteImportPlan _plan(
  List<Segment> segments, {
  CutImportOptions options = const CutImportOptions(),
  Project? project,
  WeldPosition defaultPosition = WeldPosition.pa,
}) =>
    planQuoteImport(
      _welds(segments, options: options, project: project).welds,
      defaultPosition: defaultPosition,
    );

List<ImportSkipReason> _reasons(QuoteImportPlan p) =>
    [for (final s in p.skipped) s.reason];

int _ids = 0;
String _newId() => 'c${++_ids}';

void main() {
  group('rura–kształtka', () {
    test('rura–kolano–rura = 2 doczołowe w wymiarze odcinków', () {
      final plan = _plan([
        _seg(1, end: 'e90'),
        _seg(2, start: 'e90'),
      ]);
      expect(plan.skipped, isEmpty);
      final g = plan.groups.single;
      expect(g.kind, JointKind.pipeButt);
      expect((g.odMm, g.wallMm), (114.3, 6.02));
      expect(g.count, 2);
      expect(g.kindAssumedCount, 0);
      expect(g.sizeLabel, 'DN100 Sch 40');
      expect(g.refs, ['S01 end', 'S02 start']);
    });

    test('trójnik z trzema odcinkami = 3 spoiny, bez wolnych końców', () {
      final plan = _plan([
        _seg(1, end: 'tee'),
        _seg(2, start: 'tee'),
        _seg(3, start: 'tee'), // odgałęzienie
      ]);
      expect(plan.skipped, isEmpty);
      expect(plan.groups.single.count, 3);
    });

    test('trójnik bez odcinka odgałęzienia: 2 spoiny + wolny koniec do '
        'sprawdzenia (nie do ceny)', () {
      final plan = _plan([
        _seg(1, end: 'tee'),
        _seg(2, start: 'tee'),
      ]);
      expect(plan.groups.single.count, 2);
      expect(_reasons(plan), [ImportSkipReason.openPort]);
      expect(plan.skipped.single.weld.ref, 'TEE Ø114.3');
      expect(plan.weldCount, 2);
    });

    test('redukcja = 2 spoiny o różnych średnicach i ściankach', () {
      final plan = _plan([
        _seg(1, end: 'red'),
        _seg(2, start: 'red', od: 60.3, t: 3.91),
      ]);
      expect(plan.skipped, isEmpty);
      expect([
        for (final g in plan.groups) (g.odMm, g.wallMm, g.count, g.sizeLabel)
      ], [
        (60.3, 3.91, 1, 'DN50 Sch 40'),
        (114.3, 6.02, 1, 'DN100 Sch 40'),
      ]);
      expect(plan.groups.every((g) => g.kind == JointKind.pipeButt), isTrue);
    });

    test('kolano 45° i kolano bez odcinka po drugiej stronie — spoina z rurą '
        'liczona, wolny koniec do sprawdzenia', () {
      final plan = _plan([_seg(1, start: 'e45', end: 'e90')]);
      expect(plan.groups.single.count, 2);
      expect(_reasons(plan),
          [ImportSkipReason.openPort, ImportSkipReason.openPort]);
      expect({for (final s in plan.skipped) s.weld.ref},
          {'ELB45 Ø114.3', 'ELB90 Ø114.3'});
    });

    test('dwie różne kształtki wprost do siebie (kolano 90° → kolano 45°, '
        'bez rury): model nie odróżnia jednej spoiny od dwóch z czymś spoza '
        'projektu — oba wolne końce do sprawdzenia (licznik może być '
        'zawyżony), do ceny nic', () {
      final plan = _plan([
        _seg(1, end: 'e90'),
        _seg(2, start: 'e45'),
      ]);
      expect(plan.groups.single.count, 2); // spoiny z rurą S01 i S02
      expect(_reasons(plan),
          [ImportSkipReason.openPort, ImportSkipReason.openPort]);
      expect([for (final s in plan.skipped) s.weld.ref],
          ['ELB90 Ø114.3', 'ELB45 Ø114.3']);
    });

    test('ta sama kształtka na końcach odcinków nie po kolei = dwie sztuki '
        '(reguła zestawienia materiałów) — wolne końce tylko do sprawdzenia',
        () {
      final plan = _plan([
        _seg(1, end: 'e90'),
        _seg(2),
        _seg(3, start: 'e90'),
      ]);
      expect(plan.groups.single.count, 2);
      expect(plan.skippedFor(ImportSkipReason.openPort), 2);
    });
  });

  group('typ wpisu zapisany inną wielkością liter / ze spacją', () {
    // Te same trasy na wpisach „ tee", „Elb90", „reducer ", „Flange",
    // „valve" — spoiny, wolne końce i opisy jak dla typów wielkimi literami.
    final mixed = {
      for (final c in [
        _lib('e90', 'Elb90'),
        _lib('e45', 'elb45'),
        _lib('tee', ' tee'),
        _lib('red', 'reducer ', out: 60.3),
        _lib('fl', 'Flange'),
        _lib('vlv', 'valve'),
      ])
        c.id: c,
    };

    List<(ImportSkipReason?, String, String, double?)> describe(
            Map<String, LibraryComponent> library, List<Segment> segs) =>
        [
          for (final w in importWeldsFromCutProject(
                  CutImportProject(
                      project: _project(), segments: segs, library: library),
                  options: const CutImportOptions(
                      flanges: CutEndJoint.fillet, valves: CutEndJoint.butt))
              .welds)
            (w.skip, w.ref, w.jointType, w.odMm),
        ];

    final routes = <String, List<Segment>>{
      'trójnik bez odgałęzienia': [_seg(1, end: 'tee'), _seg(2, start: 'tee')],
      'trójnik z odgałęzieniem': [
        _seg(1, end: 'tee'),
        _seg(2, start: 'tee'),
        _seg(3, start: 'tee'),
      ],
      'kolano bez drugiego odcinka': [_seg(1, end: 'e90')],
      'redukcja bez drugiego odcinka': [_seg(1, end: 'red')],
      'kolano 90° → kolano 45°': [_seg(1, end: 'e90'), _seg(2, start: 'e45')],
      'kołnierz i zawór': [_seg(1, start: 'fl', end: 'vlv')],
    };
    for (final r in routes.entries) {
      test(r.key, () {
        expect(describe(mixed, r.value), describe(_library, r.value));
      });
    }

    test('wolne końce widziane mimo małych liter (wcześniej gubione)', () {
      final welds = describe(mixed, [_seg(1, end: 'tee'), _seg(2, start: 'tee')]);
      expect(welds.where((w) => w.$1 == ImportSkipReason.openPort),
          [(ImportSkipReason.openPort, 'TEE Ø114.3', 'BW', 114.3)]);
      final red = describe(mixed, [_seg(1, end: 'red')]);
      expect(red.last, (ImportSkipReason.openPort, 'REDUCER Ø114.3→60.3', 'BW',
          null));
    });
  });

  group('kołnierze i zawory', () {
    test('kołnierz bez typu → do sprawdzenia, nie zgadywany', () {
      final res = _welds([_seg(1, start: 'fl')]);
      expect(res.flangeEnds, 1);
      expect(res.valveEnds, 0);
      final plan = planQuoteImport(res.welds, defaultPosition: WeldPosition.pa);
      expect(plan.groups, isEmpty);
      expect(_reasons(plan), [ImportSkipReason.flangeType]);
      expect(plan.skipped.single.weld.ref, 'S01 start');
    });

    test('kołnierz WN → 1 doczołowa', () {
      final plan = _plan([_seg(1, start: 'fl')],
          options: const CutImportOptions(flanges: CutEndJoint.butt));
      expect(plan.skipped, isEmpty);
      final g = plan.groups.single;
      expect(g.kind, JointKind.pipeButt);
      expect(g.count, 1);
    });

    test('kołnierz SO / SW → pachwinowa z a z reguły mufy', () {
      final plan = _plan([_seg(1, start: 'fl')],
          options: const CutImportOptions(flanges: CutEndJoint.fillet));
      final g = plan.groups.single;
      expect(g.kind, JointKind.pipeFillet);
      expect(g.throatMm, socketWeldThroatMm(6.02));
      expect(g.throatMm, 5.0);
      expect(g.kindAssumedCount, 0);
    });

    test('kołnierz luźny / gwintowany → 0 spoin', () {
      final plan = _plan([_seg(1, start: 'fl')],
          options: const CutImportOptions(flanges: CutEndJoint.none));
      expect(plan.isEmpty, isTrue);
    });

    test('para kołnierzy skręcona śrubami: dwie spoiny, każda z rurą', () {
      final plan = _plan([
        _seg(1, end: 'fl'),
        _seg(2, start: 'fl'),
      ], options: const CutImportOptions(flanges: CutEndJoint.butt));
      expect(plan.groups.single.count, 2);
      expect(plan.skipped, isEmpty);
    });

    test('zawór: bez wyboru do sprawdzenia; BW / SW / kołnierzowy', () {
      final segs = [_seg(1, end: 'vlv'), _seg(2, start: 'vlv')];
      final res = _welds(segs);
      expect(res.valveEnds, 2);
      final unknown =
          planQuoteImport(res.welds, defaultPosition: WeldPosition.pa);
      expect(unknown.groups, isEmpty);
      expect(_reasons(unknown),
          [ImportSkipReason.valveEnds, ImportSkipReason.valveEnds]);

      final butt = _plan(segs,
          options: const CutImportOptions(valves: CutEndJoint.butt));
      expect(butt.groups.single.kind, JointKind.pipeButt);
      expect(butt.groups.single.count, 2);
      expect(butt.skipped, isEmpty);

      final socket = _plan(segs,
          options: const CutImportOptions(valves: CutEndJoint.fillet));
      expect(socket.groups.single.kind, JointKind.pipeFillet);
      expect(socket.groups.single.count, 2);

      final flanged = _plan(segs,
          options: const CutImportOptions(valves: CutEndJoint.none));
      expect(flanged.isEmpty, isTrue);
    });
  });

  group('końce bez spoiny i niepewne', () {
    test('koniec otwarty po obu stronach — bez spoiny', () {
      expect(_plan([_seg(1)]).isEmpty, isTrue);
    });

    test('brak wymiaru odcinka → pominięta z powodem, nie zgadywana', () {
      final plan = _plan([
        _seg(1, end: 'e90', od: 0),
        _seg(2, start: 'e90'),
      ]);
      expect(plan.groups.single.count, 1);
      expect(_reasons(plan), [ImportSkipReason.noSize]);
      expect(plan.skipped.single.weld.ref, 'S01 end');
    });

    test('ścianka ≥ promień (literówka) → pominięta jako zły wymiar', () {
      final plan = _plan([_seg(1, end: 'e90', t: 60), _seg(2, start: 'e90')]);
      expect(plan.skippedFor(ImportSkipReason.badSize), 1);
    });

    test('kształtka ze skanu: z korpusem bez typu → do sprawdzenia; osiowa '
        '→ spoina jest, rodzaj przyjęty jako doczołowa', () {
      final plan = _plan([
        _seg(1, endKind: 'nonAxial'),
        _seg(2, startKind: 'axial'),
      ]);
      expect(_reasons(plan), [ImportSkipReason.fittingType]);
      final g = plan.groups.single;
      expect(g.kind, JointKind.pipeButt);
      expect(g.count, 1);
      expect(g.kindAssumedCount, 1);
    });

    test('wpis usunięty z biblioteki: osiowy → doczołowa, z korpusem → do '
        'sprawdzenia', () {
      final plan = _plan([
        _seg(1,
            start: 'gone-elbow',
            startKind: 'axial',
            end: 'gone-body',
            endKind: 'nonAxial'),
      ]);
      expect(plan.groups.single.count, 1);
      expect(plan.groups.single.kindAssumedCount, 0);
      expect(_reasons(plan), [ImportSkipReason.fittingType]);
    });

    test('rodzaj końca spoza słownika (stare dane) → do sprawdzenia', () {
      final plan = _plan([_seg(1, startKind: 'ELBOW')]);
      expect(_reasons(plan), [ImportSkipReason.fittingType]);
    });
  });

  group('podział odcinka i oznaczenia', () {
    test('odcinek dłuższy niż sztanga: spoina łącząca na każdy podział '
        '(ta sama reguła co lista cięć)', () {
      final plan = _plan([_seg(1, cut: 13000)],
          project: _project(stock: 6000, gap: 3));
      final g = plan.groups.single;
      expect(g.kind, JointKind.pipeButt);
      expect(g.count, 2); // 6000 + 6000 + 994 → 3 części
      expect(g.refs, ['S01 (1|2)', 'S01 (2|3)']);
      expect(_plan([_seg(1, cut: 6000)]).isEmpty, isTrue);
    });

    test('numer spoiny: znak odcinka (z oznaczeniem z rysunku) i strona', () {
      final plan = _plan(
        [
          _seg(1, end: 'e90', label: 'SP02-03'),
          _seg(2, start: 'e90'),
        ],
        options: const CutImportOptions(startTag: 'pocz.', endTag: 'kon.'),
      );
      expect(plan.groups.single.refs, ['S01 SP02-03 kon.', 'S02 pocz.']);
    });

    test('pozycja i warsztat / obiekt — brak w projekcie: pozycja z wyceny '
        'jako założenie', () {
      final plan = _plan([_seg(1, end: 'e90'), _seg(2, start: 'e90')],
          defaultPosition: WeldPosition.pf);
      final g = plan.groups.single;
      expect(g.position, WeldPosition.pf);
      expect(g.positionAssumedCount, g.count);
      expect(g.unknownLocationCount, g.count);
    });

    test('kolejność odcinków z bazy nie musi być posortowana', () {
      final plan = _plan([
        _seg(2, start: 'e90'),
        _seg(1, end: 'e90'),
      ]);
      expect(plan.groups.single.refs, ['S01 end', 'S02 start']);
      expect(plan.skipped, isEmpty);
    });
  });

  test('trasa: kołnierz–kolano–trójnik (z odgałęzieniem)–redukcja → pozycje '
      'wyceny, które wycena policzy', () {
    final segs = [
      _seg(1, start: 'fl', end: 'e90'),
      _seg(2, start: 'e90', end: 'tee'),
      _seg(3, start: 'tee', end: 'red'),
      _seg(4, start: 'red', od: 60.3, t: 3.91),
      _seg(5, start: 'tee', end: 'fl'),
    ];
    final unknown = _plan(segs);
    expect(unknown.weldCount, 7);
    expect(unknown.skippedCount, 2);
    expect(unknown.skippedFor(ImportSkipReason.flangeType), 2);

    final plan = _plan(segs,
        options: const CutImportOptions(flanges: CutEndJoint.fillet));
    expect([for (final g in plan.groups) (g.kind, g.odMm, g.count)], [
      (JointKind.pipeButt, 60.3, 1),
      (JointKind.pipeButt, 114.3, 6),
      (JointKind.pipeFillet, 114.3, 2),
    ]);
    final joints = quoteJointsFromImport(plan,
        selected: {for (final g in plan.groups) g.key},
        label: 'Linia wody',
        newId: _newId);
    expect(joints, hasLength(3));
    expect(joints.every((j) => j.isValid), isTrue);
    expect(joints.every((j) => j.label == 'Linia wody'), isTrue);
    // Wycena z importu liczy się jak z pozycji wpisanych ręcznie.
    final r = computeQuote(
        WeldQuote(id: 'q', joints: joints, createdAt: 0, updatedAt: 0));
    expect(r.invalidJointCount, 0);
    expect(r.weldCount, 9);
    expect(r.netGrosze, greaterThan(0));
  });

  test('pominięta przez źródło (ImportWeld.skip) nie wchodzi do grup, nawet '
      'z pełnym wymiarem', () {
    final plan = planQuoteImport(const [
      ImportWeld(
          ref: 'X',
          jointType: 'BW',
          odMm: 114.3,
          wallMm: 6.02,
          skip: ImportSkipReason.openPort),
      ImportWeld(ref: 'Y', jointType: 'BW', odMm: 114.3, wallMm: 6.02),
    ], defaultPosition: WeldPosition.pa);
    expect(plan.groups.single.refs, ['Y']);
    expect(plan.skipped.single.weld.ref, 'X');
    expect(plan.totalCount, 2);
  });

  group('etykieta i materiał projektu', () {
    test('nazwa, inaczej ISO z rewizją, inaczej linia', () {
      expect(cutImportLabel(_project(name: ' Linia wody '), english: false),
          'Linia wody');
      expect(
          cutImportLabel(_project(name: '', isoNo: 'ISO-7', isoRev: 'B'),
              english: false),
          'ISO-7 rew. B');
      expect(
          cutImportLabel(_project(name: null, isoNo: 'ISO-7', isoRev: 'B'),
              english: true),
          'ISO-7 rev. B');
      expect(cutImportLabel(_project(name: null, lineNo: 'L-100'),
          english: false), 'L-100');
      expect(cutImportLabel(_project(name: null), english: false), '');
    });

    test('SS = nierdzewna (etykieta schedule 10S / 40S)', () {
      expect(cutProjectIsStainless(_project(material: 'SS')), isTrue);
      expect(cutProjectIsStainless(_project(material: 'CS')), isFalse);
    });
  });
}
