// IsoNotebookController — rysowanie Zeszytu ISO poleceniem (asystent głosowy,
// zadanie 3.1). Prawdziwy ekran, prawdziwy SQLite; asercje przez kodek z bazy
// jak w iso_notebook_autosave_test: to, co poszło do `iso_drawings`, jest
// tym, co monter zobaczy po ponownym otwarciu.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/domain/iso_notebook/spatial_route.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/prefab/end_connection.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';

const _openButton = 'Otwórz zeszyt';

/// Row height of the notebook grid (step 32), the same expression as `_snap`.
final double _dy = 32 * math.sqrt(3) / 2.0;

Widget _launcher() => AppLanguageScope(
      controller: AppLanguageController(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const IsoNotebookScreen()),
                ),
                child: const Text(_openButton),
              ),
            ),
          ),
        ),
      ),
    );

Finder get _canvas => find.byWidgetPredicate((w) =>
    w is Semantics &&
    (w.properties.label?.startsWith('Płótno szkicu izometrycznego') ?? false));

Future<void> _boot(WidgetTester tester,
    {Size size = const Size(1200, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_launcher());
  await tester.pumpAndSettle();
}

Future<IsoNotebookController> _open(WidgetTester tester) async {
  await tester.tap(find.text(_openButton));
  await tester.pumpAndSettle();
  final c = IsoNotebookController.active;
  expect(c, isNotNull, reason: 'the mounted notebook registers itself');
  await c!.ready;
  return c;
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.text(_openButton), findsOneWidget);
}

/// Lets the 500 ms autosave land, then reads the newest stored sketch.
Future<Map<String, Object?>?> _stored(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  final rec = await IsoDrawingDao().latest();
  if (rec == null) return null;
  return (jsonDecode(rec.json) as Map).cast<String, Object?>();
}

List<Map<String, Object?>> _items(Map<String, Object?>? sketch) => [
      for (final i in (sketch?['items'] as List?) ?? const [])
        (i as Map).cast<String, Object?>(),
    ];

List<Map<String, Object?>> _pipes(Map<String, Object?>? sketch) =>
    _items(sketch)
        .where((i) => i['kind'] == 'seg' && i['tool'] == 'pipe')
        .toList();

List<Map<String, Object?>> _comps(Map<String, Object?>? sketch, String tool) =>
    _items(sketch)
        .where((i) => i['kind'] == 'comp' && i['tool'] == tool)
        .toList();

Offset _pt(Object? raw) {
  final l = raw as List;
  return Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
}

Offset _a(Map<String, Object?> seg) => _pt(seg['a']);
Offset _b(Map<String, Object?> seg) => _pt(seg['b']);

/// Grid heading of a vector: 0 right, 1 up-right, 2 up-left, 3 left,
/// 4 down-left, 5 down-right (the notebook's `_isoHeadings`).
int _heading(Offset v) {
  const hs = [
    Offset(1, 0),
    Offset(0.5, -0.8660254037844387),
    Offset(-0.5, -0.8660254037844387),
    Offset(-1, 0),
    Offset(-0.5, 0.8660254037844387),
    Offset(0.5, 0.8660254037844387),
  ];
  final u = v / v.distance;
  var best = 0;
  var bestDot = -2.0;
  for (var i = 0; i < 6; i++) {
    final d = hs[i].dx * u.dx + hs[i].dy * u.dy;
    if (d > bestDot) {
      bestDot = d;
      best = i;
    }
  }
  expect(bestDot, closeTo(1, 1e-9), reason: 'pipe $v is not on an iso axis');
  return best;
}

bool _near(Offset p, Offset q) => (p - q).distance < 0.01;

Map<String, Object?> _seg(Offset a, Offset b) => <String, Object?>{
      'kind': 'seg',
      'tool': 'pipe',
      'a': <double>[a.dx, a.dy],
      'b': <double>[b.dx, b.dy],
      'slope': '',
      'insulated': false,
      'calc': null,
    };

Map<String, Object?> _elbow(Offset pos, int dir, int dir2) => <String, Object?>{
      'kind': 'comp',
      'tool': 'elbow90',
      'pos': <double>[pos.dx, pos.dy],
      'dir': dir,
      'dir2': dir2,
      'label': '',
      'dn': null,
      'elbowSubtype': null,
      'cteMm': null,
      'physicalLengthMm': null,
      'dnOut': null,
      'endA': null,
      'endB': null,
    };

Map<String, Object?> _northArrow(Offset pos, int dir) => <String, Object?>{
      'kind': 'comp',
      'tool': 'northArrow',
      'pos': <double>[pos.dx, pos.dy],
      'dir': dir,
      'dir2': null,
      'label': '',
      'dn': null,
      'elbowSubtype': null,
      'cteMm': null,
      'physicalLengthMm': null,
      'dnOut': null,
      'endA': null,
      'endB': null,
    };

Map<String, Object?> _sketch(String name, List<Map<String, Object?>> items) =>
    <String, Object?>{'format': 1, 'name': name, 'items': items};

Future<IsoDrawingRecord> _seed(String id, Map<String, Object?> sketch) async {
  final rec = IsoDrawingRecord(
    id: id,
    name: sketch['name'] as String,
    json: jsonEncode(sketch),
    createdAt: 1000,
    updatedAt: 1000,
  );
  await IsoDrawingDao().upsert(rec);
  return rec;
}

/// One pipe going right on grid row [row]: (x0, row) → (x0 + 128, row).
Map<String, Object?> _onePipe({int row = 4, double x0 = 64}) => _sketch(
      'Linia testowa',
      [_seg(Offset(x0, row * _dy), Offset(x0 + 128, row * _dy))],
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await AppDatabase.configureForTesting(inMemoryDatabasePath);
  });
  tearDownAll(AppDatabase.clearTestingConfiguration);

  testWidgets('manual sheet name and gap use chronological undo without deleting pipes', (tester) async {
    await _boot(tester);
    final c=await _open(tester);
    await c.draw(const [IsoPipe(lengthMm:1000)],stepDelay:Duration.zero);
    final before=await _stored(tester);
    final revision=c.revision;
    await tester.tap(find.byTooltip('Dotknij, aby zmienić nazwę projektu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of:find.byType(AlertDialog),matching:find.byType(TextField)),'Native CW');
    await tester.tap(find.widgetWithText(ElevatedButton,'OK'));
    await tester.pumpAndSettle();
    expect(c.revision,greaterThan(revision));
    expect(c.sketchName,'Native CW');
    await tester.tap(find.byTooltip('Szkice'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Szczelina spoiny:'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sketch-gap-field')),'3');
    await tester.tap(find.byKey(const ValueKey('sketch-gap-save')));
    await tester.pumpAndSettle();
    expect((await _stored(tester))!['gapMm'],3);
    c.undo();await tester.pumpAndSettle();
    final undoGap=await _stored(tester);
    expect(undoGap!['gapMm'],before!['gapMm']);expect(undoGap['name'],'Native CW');
    expect(_items(undoGap),_items(before));
    c.undo();await tester.pumpAndSettle();
    final undoName=await _stored(tester);
    expect(undoName!['name'],before['name']);expect(_items(undoName),_items(before));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'iso_notebook_hint_hidden': true});
    final db = await AppDatabase.get();
    await db.delete(IsoDrawingDao.table);
  });

  testWidgets(
      'two genuine 45 degree bends survive save, reopen, continuation and atomic undo',
      (tester) async {
    await _boot(tester);
    var c = await _open(tester);
    final report = await c.draw(const [
      IsoPipe(dir: IsoDir.right, lengthMm: 1000),
      IsoTurn(degrees: 45, toDir: IsoDir.up, dn: 100),
      IsoPipe(lengthMm: 1500),
      IsoTurn(degrees: 45, toDir: IsoDir.up, dn: 100),
      IsoPipe(lengthMm: 1000),
    ], stepDelay: Duration.zero);
    expect(report.ok, isTrue, reason: report.toString());
    expect(report.segments, 3);
    expect(report.elbows, 2);
    final sketch = await _stored(tester);
    expect(sketch!['format'], 5);
    final pipes = _pipes(sketch);
    final bends = _comps(sketch, 'elbow45');
    expect(bends, hasLength(2));
    expect(_comps(sketch, 'elbow90'), isEmpty);
    final rays = pipes
        .map((p) => IsoSpatialVector.fromJson(p['spatialDirection'])!)
        .toList();
    expect(rays[0].angleTo(rays[1]), closeTo(45, 1e-7));
    expect(rays[1].angleTo(rays[2]), closeTo(45, 1e-7));
    expect(rays[2].angleTo(IsoSpatialVector.gridHeading(1)), closeTo(0, 1e-7));
    expect(
        pipes.map((p) => (p['calc'] as Map)['iso']), ['1000', '1500', '1000']);
    expect(
        bends.every((b) =>
            b['dn'] == 100 &&
            b['elbowSubtype'] == 'lr45' &&
            (b['cteMm'] as num) > 0),
        isTrue);
    expect(c.debugPipeAxisTags[1], '3D');
    expect(find.text('Suma CUT: 3244.0 mm'), findsOneWidget,
        reason:
            '3500 mm centreline minus four actual 64 mm take-outs, once each');
    await _leave(tester);
    c = await _open(tester);
    final continuation =
        await c.draw(const [IsoPipe(lengthMm: 500)], stepDelay: Duration.zero);
    expect(continuation.ok, isTrue);
    final appended = _pipes(await _stored(tester));
    expect(_b(appended[2]), _a(appended[3]));
    expect(appended[3]['spatialDirection'], rays[2].toJson());
    c.undo();
    await tester.pumpAndSettle();
    expect(await _stored(tester), sketch);
    await _leave(tester);
  });

  testWidgets(
      'diagonal cursor is kept exact across separate commands and failed bends do not mutate it',
      (tester) async {
    await _boot(tester);
    var c = await _open(tester);
    final report = await c.draw(const [
      IsoPipe(lengthMm: 1000),
      IsoTurn(degrees: 45, toDir: IsoDir.back),
      IsoPipe(lengthMm: 1000)
    ], stepDelay: Duration.zero);
    expect(report.ok, isTrue);
    final before = await _stored(tester);
    final pipes = _pipes(before);
    final diagonal = pipes.last['spatialDirection'];
    await _leave(tester);
    c = await _open(tester);
    final invalid = await c.draw(
        const [IsoTurn(degrees: 90, toDir: IsoDir.back), IsoPipe()],
        stepDelay: Duration.zero);
    expect(invalid.problem, IsoDrawProblem.invalidSpatialTurn);
    expect(await _stored(tester), before);
    final continued =
        await c.draw(const [IsoPipe(lengthMm: 500)], stepDelay: Duration.zero);
    expect(continued.ok, isTrue);
    final after = _pipes(await _stored(tester));
    expect(_a(after.last), _b(pipes.last));
    expect(after.last['spatialDirection'], diagonal);
    expect(_comps(await _stored(tester), 'elbow90'), isEmpty);
    c.undo();
    await tester.pumpAndSettle();
    expect(await _stored(tester), before);
    await _leave(tester);
  });

  testWidgets('45 degree route is atomic for a missing plane and trailing bend',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    for (final steps in <List<IsoStep>>[
      const [IsoPipe(), IsoTurn(degrees: 45), IsoPipe()],
      const [IsoPipe(), IsoTurn(degrees: 45, toDir: IsoDir.up)],
      const [IsoPipe(), IsoTurn(degrees: 45, toDir: IsoDir.left), IsoPipe()],
    ]) {
      final report = await c.draw(steps, stepDelay: Duration.zero);
      expect(report.ok, isFalse);
      expect(c.hasContent, isFalse);
    }
    await _leave(tester);
  });

  for (final tool in [
    'ballValve',
    'gateValve',
    'checkValve',
    'globeValve',
    'butterflyValve',
    'flange',
    'blindFlange',
    'cap',
    'reducer',
    'weld',
    'fieldWeld',
    'support'
  ]) {
    testWidgets('spatial $tool aligns with pipe and survives reopen and Undo',
        (tester) async {
      await _boot(tester);
      var c = await _open(tester);
      await c.draw(const [
        IsoPipe(lengthMm: 1000),
        IsoTurn(degrees: 45, toDir: IsoDir.up, dn: 100),
        IsoPipe(lengthMm: 1000)
      ], stepDelay: Duration.zero);
      final before = await _stored(tester);
      final ray = _pipes(before).last['spatialDirection'];
      final report = await c.draw(
          [IsoFitting(tool, dn: 100, dnOut: tool == 'reducer' ? 80 : null)],
          stepDelay: Duration.zero);
      expect(report.ok, isTrue, reason: report.toString());
      expect(report.fittings, 1);
      final after = await _stored(tester);
      final fitting = _comps(after, tool).last;
      expect(fitting['spatialDirection'], ray);
      expect(after!['format'], 5);
      if (!['weld', 'fieldWeld', 'support'].contains(tool)) {
        expect(fitting['dn'], 100);
      }
      expect(tester.takeException(), isNull);
      // A real reopen proves codec and painter both understand the orientation.
      await _leave(tester);
      c = await _open(tester);
      expect(await _stored(tester), after);
      final continuation = await c
          .draw(const [IsoPipe(lengthMm: 1000)], stepDelay: Duration.zero);
      expect(continuation.ok, isTrue);
      expect(_pipes(await _stored(tester)).length, _pipes(after).length + 1);
      c.undo();
      await tester.pumpAndSettle();
      expect(await _stored(tester), after);
      await _leave(tester);
    });
  }
  testWidgets('spatial fittings and auto welds are one reversible command',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    final report = await c.draw(const [
      IsoPipe(lengthMm: 1000),
      IsoTurn(degrees: 45, toDir: IsoDir.up, dn: 100),
      IsoPipe(lengthMm: 1000),
      IsoFitting('ballValve', dn: 100),
      IsoPipe(lengthMm: 1000)
    ], stepDelay: Duration.zero);
    expect(report.ok, isTrue);
    expect(report.elbows, 1);
    expect(report.fittings, 1);
    final stored = await _stored(tester);
    final welds = _comps(stored, 'weld');
    expect(welds, hasLength(4));
    expect(welds.every((w) => w['spatialDirection'] != null), isTrue);
    expect(welds.map((w) => w['label']).toSet(), hasLength(4));
    c.undo();
    await tester.pumpAndSettle();
    expect(c.hasContent, isFalse);
    await _leave(tester);
  });

  testWidgets(
      'a manual pipe joining a spatial ray uses its physical 45 degree angle',
      (tester) async {
    final ray = IsoSpatialVector.gridHeading(0)
        .turnTowards(IsoSpatialVector.gridHeading(2), 45);
    final a = Offset(64, 6 * _dy), b = Offset(96, 4 * _dy);
    final pipe = _seg(a, b)..['spatialDirection'] = ray.toJson();
    await _seed(
        'manual-spatial', _sketch('Spatial manual', [pipe])..['format'] = 4);
    await _boot(tester);
    final c = await _open(tester);
    final view = c.debugVisibleWorld!, rect = tester.getRect(_canvas);
    Offset screen(Offset point) => Offset(
        rect.left + (point.dx - view.left) / view.width * rect.width,
        rect.top + (point.dy - view.top) / view.height * rect.height);
    await tester.dragFrom(
        screen(b), screen(b + const Offset(128, 0)) - screen(b));
    await tester.pumpAndSettle();
    final saved = await _stored(tester);
    expect(_pipes(saved), hasLength(2));
    expect(_comps(saved, 'elbow45'), hasLength(1), reason: jsonEncode(saved));
    expect(_comps(saved, 'elbow90'), isEmpty);
    final bend = IsoSpatialElbow.fromJson(
        _comps(saved, 'elbow45').single['spatialBend'])!;
    expect(bend.degrees, closeTo(45, 1e-7));
    expect(_comps(saved, 'weld'), hasLength(2));
    c.undo();
    await tester.pumpAndSettle();
    expect(_pipes(await _stored(tester)), hasLength(1));
    expect(_comps(await _stored(tester), 'elbow45'), isEmpty);
    await _leave(tester);
  });

  testWidgets(
      'standalone tee symbol keeps exact spatial cursor without inventing a branch',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    await c.draw(
        const [IsoPipe(), IsoTurn(degrees: 45, toDir: IsoDir.up), IsoPipe()],
        stepDelay: Duration.zero);
    final before = await _stored(tester);
    final end = _pipes(before).last['b'];
    final report = await c.draw(const [
      IsoFitting('tee', symbolOnly: true, dir: IsoDir.back, dn: 100, dnOut: 80)
    ], stepDelay: Duration.zero);
    expect(report.ok, isTrue);
    expect(report.fittings, 1);
    final tee = _comps(await _stored(tester), 'tee').single;
    expect(tee['pos'], end);
    expect(tee['dir'], IsoDir.back.index);
    expect(tee['spatialDirection'], isNull);
    c.undo();
    await tester.pumpAndSettle();
    expect(await _stored(tester), before);
    await _leave(tester);
  });

  testWidgets(
      'spatial tee run branches only perpendicular, survives reopen and restores pending roll on undo',
      (tester) async {
    await _boot(tester);
    var c = await _open(tester);
    final report = await c.draw(const [
      IsoPipe(lengthMm: 1000),
      IsoTurn(degrees: 45, toDir: IsoDir.up, dn: 100),
      IsoPipe(lengthMm: 1000),
      IsoFitting('tee', dn: 100, dnOut: 80),
      IsoPipe(lengthMm: 1000)
    ], stepDelay: Duration.zero);
    expect(report.ok, isTrue, reason: report.toString());
    expect(report.fittings, 1);
    final before = await _stored(tester);
    final tee = _comps(before, 'tee').single;
    expect(before!['format'], 6);
    expect((tee['spatialTee'] as Map)['branch'], isNull);
    expect(_comps(before, 'weld'), hasLength(4));
    await _leave(tester);
    c = await _open(tester);
    final invalid = await c.draw(
        const [IsoPipe(dir: IsoDir.up, lengthMm: 1000)],
        fromLastTee: true, stepDelay: Duration.zero);
    expect(invalid.problem, IsoDrawProblem.invalidBranch);
    expect(await _stored(tester), before);
    final branch = await c.draw(
        const [IsoPipe(dir: IsoDir.back, lengthMm: 1000)],
        fromLastTee: true, stepDelay: Duration.zero);
    expect(branch.ok, isTrue, reason: branch.toString());
    expect(branch.elbows, 0);
    final after = await _stored(tester);
    final actual = _comps(after, 'tee').single;
    final geometry = IsoSpatialTee.fromJson(actual['spatialTee'])!;
    expect(geometry.run.dot(geometry.branch!), closeTo(0, 1e-8));
    expect(_pipes(after).last['a'], tee['pos']);
    expect(_pipes(after), hasLength(4));
    expect(actual['dn'], 100);
    expect(actual['dnOut'], 80);
    expect(_comps(after, 'weld'), hasLength(5));
    final duplicate = await c.draw(const [IsoPipe(dir: IsoDir.forward)],
        fromLastTee: true, stepDelay: Duration.zero);
    expect(duplicate.problem, IsoDrawProblem.invalidBranch);
    expect(await _stored(tester), after);
    c.undo();
    await tester.pumpAndSettle();
    expect(await _stored(tester), before);
    await _leave(tester);
  });

  testWidgets(
      'manual branch snaps to a fractional spatial tee node and preserves its reducing sizes',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    await c.draw(const [
      IsoPipe(),
      IsoTurn(degrees: 45, toDir: IsoDir.up, dn: 100),
      IsoPipe(),
      IsoFitting('tee', dn: 100, dnOut: 80),
      IsoPipe()
    ], stepDelay: Duration.zero);
    final before = await _stored(tester);
    final tee = _comps(before, 'tee').single;
    final node = _pt(tee['pos']);
    final view = c.debugVisibleWorld!, rect = tester.getRect(_canvas);
    Offset screen(Offset p) => Offset(
        rect.left + (p.dx - view.left) / view.width * rect.width,
        rect.top + (p.dy - view.top) / view.height * rect.height);
    final axis = IsoSpatialVector.gridHeading(2).projected;
    await tester.dragFrom(screen(node),
        screen(node + Offset(axis.x, axis.y) * 96) - screen(node));
    await tester.pumpAndSettle();
    final after = await _stored(tester);
    expect(_pipes(after), hasLength(4));
    expect(_pipes(after).last['a'], tee['pos']);
    final updated = _comps(after, 'tee').single;
    expect((updated['spatialTee'] as Map)['branch'], [0.0, -1.0, 0.0]);
    expect(updated['dn'], 100);
    expect(updated['dnOut'], 80);
    c.undo();
    await tester.pumpAndSettle();
    expect(await _stored(tester), before);
    await _leave(tester);
  });

  testWidgets(
      'physically perpendicular tee legs keep separate welds and correct CUT when their paper rays overlap',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    final run = await c.draw(const [
      IsoPipe(lengthMm: 1000),
      IsoTurn(degrees: 45, toDir: IsoDir.back, dn: 100),
      IsoPipe(lengthMm: 1000),
      IsoFitting('tee', dn: 100, dnOut: 80),
      IsoPipe(lengthMm: 1000)
    ], stepDelay: Duration.zero);
    expect(run.ok, isTrue);
    final branch = await c.draw(const [IsoPipe(dir: IsoDir.up, lengthMm: 1000)],
        fromLastTee: true, stepDelay: Duration.zero);
    expect(branch.ok, isTrue, reason: branch.toString());
    final stored = await _stored(tester);
    expect(_comps(stored, 'weld'), hasLength(5));
    expect(_comps(stored, 'weld').map((w) => w['label']).toSet(), hasLength(5));
    expect(_comps(stored, 'tee').single['cteMm'], 105);
    expect(find.text('Suma CUT: 3564.0 mm'), findsOneWidget,
        reason: '4000 - two elbow take-outs64 - two tee run C105 - branch M98');
    await _leave(tester);
  });

  testWidgets(
      'a standalone tee can gain a spatial run from the actual connected pipes without paper-axis guesses',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    await c.draw(
        const [IsoPipe(), IsoTurn(degrees: 45, toDir: IsoDir.up), IsoPipe()],
        stepDelay: Duration.zero);
    await c.draw(
        const [IsoFitting('tee', symbolOnly: true, dn: 100, dnOut: 80)],
        stepDelay: Duration.zero);
    final invalid = await c.draw(const [IsoPipe(dir: IsoDir.back)],
        fromLastTee: true, stepDelay: Duration.zero);
    expect(invalid.problem, IsoDrawProblem.invalidBranch,
        reason: 'a symbol plus one pipe does not invent the other run leg');
    await c.draw(const [IsoPipe()], stepDelay: Duration.zero);
    final report = await c.draw(const [IsoPipe(dir: IsoDir.back)],
        fromLastTee: true, stepDelay: Duration.zero);
    expect(report.ok, isTrue, reason: report.toString());
    final tee = _comps(await _stored(tester), 'tee').single;
    expect(IsoSpatialTee.fromJson(tee['spatialTee'])!.branch!.toJson(),
        [0.0, -1.0, 0.0]);
    expect(tee['dnOut'], 80);
    await _leave(tester);
  });

  testWidgets('zmiana ostatniego kolana: błędny kierunek nie rusza szkicu',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    await c.draw(const [
      IsoPipe(lengthMm: 1000),
      IsoTurn(toDir: IsoDir.up),
      IsoPipe(lengthMm: 1000)
    ], stepDelay: Duration.zero);
    final before = await _stored(tester);
    final report = await c.redirectLastTurn(IsoDir.left);
    expect(report?.problem, IsoDrawProblem.reversal);
    final after = await _stored(tester);
    expect(after, before);
    c.undo();
    await tester.pumpAndSettle();
    expect(c.hasContent, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  group('rysowanie sekwencji', () {
    testWidgets(
        'rura, kolano, rura → 2 odcinki i 1 kolano, w prawo potem do przodu, '
        'z listą przyjętych założeń', (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      expect(IsoNotebookController.activeListenable.value, same(c));
      expect(c.hasContent, isFalse);

      final r = await c.draw(const [IsoPipe(), IsoTurn(), IsoPipe()],
          stepDelay: Duration.zero);
      expect(r.problem, isNull);
      expect(r.segments, 2);
      expect(r.elbows, 1);
      expect(r.fittings, 0);
      expect(r.assumedPl, isNotEmpty);
      expect(r.assumedPl, hasLength(r.assumedEn.length));
      expect(r.assumedPl.join(' '), contains('w prawo'));
      expect(r.assumedPl.join(' '), contains('do przodu'));
      expect(r.assumedPl.join(' '), contains('Bez długości'));
      expect(c.hasContent, isTrue);
      expect(c.lastEdited, isNotNull);

      final s = await _stored(tester);
      final pipes = _pipes(s);
      expect(pipes, hasLength(2));
      expect(_heading(_b(pipes[0]) - _a(pipes[0])), 0, reason: 'w prawo');
      expect(_heading(_b(pipes[1]) - _a(pipes[1])), 5, reason: 'do przodu');
      expect(_near(_b(pipes[0]), _a(pipes[1])), isTrue,
          reason: 'the second pipe starts where the first ends');
      // No length → 3 grid steps, no dimension.
      expect((_b(pipes[0]) - _a(pipes[0])).distance, closeTo(96, 1e-9));
      expect(pipes.every((p) => p['calc'] == null), isTrue);
      final elbows = _comps(s, 'elbow90');
      expect(elbows, hasLength(1));
      expect(_near(_pt(elbows.single['pos']), _b(pipes[0])), isTrue);
      expect({elbows.single['dir'], elbows.single['dir2']}, {3, 5},
          reason: 'legs: back along the first pipe, on along the second');
      await _leave(tester);
    });

    testWidgets('jeden undo() cofa całe polecenie, a nie ostatnią rurę',
        (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      await c
          .draw(const [IsoPipe(dir: IsoDir.right)], stepDelay: Duration.zero);
      await c.draw(const [IsoPipe(), IsoTurn(toDir: IsoDir.up), IsoPipe()],
          stepDelay: Duration.zero);
      expect(_pipes(await _stored(tester)), hasLength(3));

      c.undo();
      final s = await _stored(tester);
      expect(_pipes(s), hasLength(1),
          reason: 'the whole second command goes, the first one stays');
      expect(_comps(s, 'elbow90'), isEmpty);
      expect(_comps(s, 'weld'), isEmpty);

      c.undo();
      expect(c.hasContent, isFalse);
      expect(_items(await _stored(tester)), isEmpty);
      await _leave(tester);
    });

    testWidgets(
        'lengthMm 1500 → wymiar „1500” i 3 kroki siatki; '
        'długości przycięte do 2…8 kroków', (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      final r = await c.draw(const [
        IsoPipe(lengthMm: 1500),
        IsoTurn(toDir: IsoDir.up),
        IsoPipe(lengthMm: 600),
        IsoTurn(toDir: IsoDir.right),
        IsoPipe(lengthMm: 12000),
      ], stepDelay: Duration.zero);
      expect(r.problem, isNull);
      expect(r.assumedPl.join(' '), isNot(contains('Bez długości')));
      final pipes = _pipes(await _stored(tester));
      expect(pipes.map((p) => (p['calc'] as Map)['iso']),
          ['1500', '600', '12000']);
      expect(pipes.map((p) => (_b(p) - _a(p)).distance / 32),
          [closeTo(3, 1e-9), closeTo(2, 1e-9), closeTo(8, 1e-9)]);
      await _leave(tester);
    });

    testWidgets(
        'DN z kolana trafia do kolana (CTE B16.9 LR) i do pamięci ostatniego DN',
        (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      final r = await c.draw(const [
        IsoPipe(lengthMm: 1500),
        IsoTurn(toDir: IsoDir.up, dn: 100),
        IsoPipe(lengthMm: 1000),
      ], stepDelay: Duration.zero);
      expect(r.elbows, 1);
      final s = await _stored(tester);
      final elbow = _comps(s, 'elbow90').single;
      expect(elbow['dn'], 100);
      expect(elbow['elbowSubtype'], 'lr90');
      expect(elbow['cteMm'], isoStandardElbowCteMm(100, 'lr90'));
      final memory = s!['takeoutMemory'] as Map;
      expect((memory['lastDn'] as Map)['elbow90'], 100);
      await _leave(tester);
    });

    testWidgets(
        'kształtka osiowa staje na kursorze ze specyfikacją z tablic, '
        'bez żadnego okna', (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      final r = await c.draw(const [
        IsoPipe(lengthMm: 1000),
        IsoFitting('ballValve', dn: 50),
        IsoPipe(lengthMm: 1000),
        IsoFitting('flange'),
      ], stepDelay: Duration.zero);
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(r.problem, isNull);
      expect(r.segments, 2);
      expect(r.elbows, 0);
      expect(r.fittings, 2);
      expect(r.assumedPl.join(' '), contains('DN50'),
          reason: 'the flange took the run DN and says so');

      final s = await _stored(tester);
      final pipes = _pipes(s);
      final valve = _comps(s, 'ballValve').single;
      expect(_near(_pt(valve['pos']), _b(pipes[0])), isTrue);
      expect(_near(_pt(valve['pos']), _a(pipes[1])), isTrue);
      expect(valve['dn'], 50);
      expect(valve['dir'], 0, reason: 'along the run');
      expect(valve['label'], 'DN50');
      expect(valve['physicalLengthMm'], isoValveFaceToFaceMm('ballValve', 50));
      final flange = _comps(s, 'flange').single;
      expect(_near(_pt(flange['pos']), _b(pipes[1])), isTrue);
      expect(flange['dn'], 50);
      expect(flange['endA'], 'weldNeck');
      expect(flange['physicalLengthMm'],
          isoFlangeAxialLengthMm(dn: 50, type: EndConnection.weldNeck));
      expect(_comps(s, 'weld'), isNotEmpty,
          reason: 'welded ends get their weld dots like a manual placement');
      await _leave(tester);
    });

    testWidgets('kolejka: polecenia idą po kolei, a cofnięcie czeka za nimi',
        (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      final first =
          c.draw(const [IsoPipe(dir: IsoDir.right)], stepDelay: Duration.zero);
      final second = c
          .draw(const [IsoPipe(dir: IsoDir.forward)], stepDelay: Duration.zero);
      expect(c.isBusy, isTrue);
      c.undo(); // queued behind `second` → takes `second` back
      expect((await first).segments, 1);
      expect((await second).segments, 1);
      await tester.pump();
      expect(c.isBusy, isFalse);
      final pipes = _pipes(await _stored(tester));
      expect(pipes, hasLength(1));
      expect(_heading(_b(pipes.single) - _a(pipes.single)), 0);
      await _leave(tester);
    });
  });

  testWidgets('a second symbol cannot overlap a symbol already on the sheet',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    await c.draw(const [IsoFitting('elbow45', dn: 50, symbolOnly: true)],
        stepDelay: Duration.zero);
    final before = await _stored(tester);
    final r = await c.draw(const [IsoFitting('tee', dn: 50, symbolOnly: true)],
        stepDelay: Duration.zero);
    expect(r.problem, IsoDrawProblem.occupiedSymbol);
    expect(await _stored(tester), before);
    c.undo();
    expect(c.hasContent, isFalse, reason: 'rejected symbol adds no undo step');
    await _leave(tester);
  });
  testWidgets(
      'branch starts at a reducing tee, preserves DN and one undo restores the run',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    await c.draw(const [IsoPipe(dir: IsoDir.right, lengthMm: 1000)],
        stepDelay: Duration.zero);
    await c.draw(const [IsoFitting('tee', dn: 80, dnOut: 50, symbolOnly: true)],
        stepDelay: Duration.zero);
    await c.draw(const [IsoPipe(dir: IsoDir.right, lengthMm: 1000)],
        stepDelay: Duration.zero);
    final before = await _stored(tester);
    final tee = _comps(before, 'tee').single;
    final anchor = _pt(tee['pos']);
    final r = await c.draw(const [IsoPipe(dir: IsoDir.up, lengthMm: 1000)],
        fromLastTee: true, stepDelay: Duration.zero);
    expect(r.ok, isTrue);
    final after = await _stored(tester);
    final branch = _pipes(after).last;
    expect(_near(_a(branch), anchor), isTrue);
    expect(_heading(_b(branch) - _a(branch)), IsoDir.up.index);
    expect(_comps(after, 'tee').single['dn'], 80);
    expect(_comps(after, 'tee').single['dnOut'], 50);
    expect(_comps(after, 'tee').single['dir'], IsoDir.up.index);
    final duplicate = await c.draw(const [IsoPipe(dir: IsoDir.back)],
        fromLastTee: true, stepDelay: Duration.zero);
    expect(duplicate.problem, IsoDrawProblem.invalidBranch);
    c.undo();
    final restored = await _stored(tester);
    expect(_items(restored), _items(before));
    await _leave(tester);
  });
  testWidgets(
      'branch rejects missing tees, incomplete runs, axial directions and new-sheet conflicts atomically',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    expect(
        (await c.draw(const [IsoPipe(dir: IsoDir.up)],
                fromLastTee: true, stepDelay: Duration.zero))
            .problem,
        IsoDrawProblem.invalidBranch);
    await c.draw(const [IsoPipe(dir: IsoDir.right)], stepDelay: Duration.zero);
    await c.draw(const [IsoFitting('tee', dn: 50, symbolOnly: true)],
        stepDelay: Duration.zero);
    expect(
        (await c.draw(const [IsoPipe(dir: IsoDir.up)],
                fromLastTee: true, stepDelay: Duration.zero))
            .problem,
        IsoDrawProblem.invalidBranch);
    await c.draw(const [IsoPipe(dir: IsoDir.right)], stepDelay: Duration.zero);
    final before = await _stored(tester);
    for (final direction in [IsoDir.right, IsoDir.left]) {
      expect(
          (await c.draw([IsoPipe(dir: direction)],
                  fromLastTee: true, stepDelay: Duration.zero))
              .problem,
          IsoDrawProblem.invalidBranch);
    }
    expect(
        (await c.draw(const [IsoPipe(dir: IsoDir.up)],
                fromLastTee: true, newSketch: true, stepDelay: Duration.zero))
            .problem,
        IsoDrawProblem.invalidBranch);
    expect(_items(await _stored(tester)), _items(before));
    await _leave(tester);
  });
  testWidgets(
      'multiple tees require an explicit last tee and use its actual position',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    await c.draw(const [IsoPipe(dir: IsoDir.right)], stepDelay: Duration.zero);
    await c.draw(const [IsoFitting('tee', dn: 80, symbolOnly: true)],
        stepDelay: Duration.zero);
    await c.draw(const [IsoPipe(dir: IsoDir.right)], stepDelay: Duration.zero);
    await c.draw(const [IsoFitting('tee', dn: 80, dnOut: 50, symbolOnly: true)],
        stepDelay: Duration.zero);
    await c.draw(const [IsoPipe(dir: IsoDir.right)], stepDelay: Duration.zero);
    final before = await _stored(tester);
    final position = _comps(before, 'tee').last['pos'];
    expect(
        (await c.draw(const [IsoPipe(dir: IsoDir.up)],
                fromLastTee: true, stepDelay: Duration.zero))
            .problem,
        IsoDrawProblem.invalidBranch);
    final r = await c.draw(const [IsoPipe(dir: IsoDir.up)],
        fromLastTee: true, explicitLastTee: true, stepDelay: Duration.zero);
    expect(r.ok, isTrue);
    expect(_pipes(await _stored(tester)).last['a'], position);
    await _leave(tester);
  });
  testWidgets(
      'correcting an elbow on a branch keeps its tee anchor and restores the whole command with undo',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    await c.draw(const [IsoPipe(dir: IsoDir.right)], stepDelay: Duration.zero);
    await c.draw(const [IsoFitting('tee', dn: 80, dnOut: 50, symbolOnly: true)],
        stepDelay: Duration.zero);
    await c.draw(const [IsoPipe(dir: IsoDir.right)], stepDelay: Duration.zero);
    final before = await _stored(tester);
    final position = _comps(before, 'tee').single['pos'];
    await c.draw(const [
      IsoPipe(dir: IsoDir.up),
      IsoTurn(toDir: IsoDir.right, dn: 50),
      IsoPipe()
    ], fromLastTee: true, stepDelay: Duration.zero);
    final pending = c.redirectLastTurn(IsoDir.back);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect((await pending)!.ok, isTrue);
    final after = await _stored(tester);
    expect(_pipes(after)[2]['a'], position);
    expect(_heading(_b(_pipes(after).last) - _a(_pipes(after).last)),
        IsoDir.back.index);
    c.undo();
    expect(_items(await _stored(tester)), _items(before));
    await _leave(tester);
  });
  testWidgets(
      'inline tee rejects overlapping fittings and changed run direction without partial drawing',
      (tester) async {
    await _boot(tester);
    final c = await _open(tester);
    for (final steps in [
      <IsoStep>[
        const IsoPipe(dir: IsoDir.right),
        const IsoFitting('tee', dn: 80),
        const IsoPipe(dir: IsoDir.up)
      ],
      <IsoStep>[
        const IsoPipe(dir: IsoDir.right),
        const IsoFitting('tee', dn: 80),
        const IsoFitting('ballValve', dn: 80)
      ],
    ]) {
      expect(
          (await c.draw(steps, stepDelay: Duration.zero)).problem, isNotNull);
      expect(c.hasContent, isFalse);
      expect(await _stored(tester), isNull);
    }
    await _leave(tester);
  });
  group('niepusty szkic i nowy rysunek', () {
    testWidgets(
        'invalid new drawing preserves active sketch, database and undo',
        (tester) async {
      final original = await _seed('old', _onePipe());
      await _boot(tester);
      final c = await _open(tester);
      final edited = c.lastEdited;
      for (final steps in [
        <IsoStep>[
          const IsoPipe(dir: IsoDir.right),
          const IsoPipe(dir: IsoDir.left)
        ],
        <IsoStep>[const IsoPipe(), const IsoTurn()],
        <IsoStep>[const IsoFitting('olet')],
      ]) {
        final r =
            await c.draw(steps, newSketch: true, stepDelay: Duration.zero);
        expect(r.problem, isNotNull);
        expect(c.hasContent, isTrue);
        expect(c.sketchName, 'Linia testowa');
        expect(c.lastEdited, edited);
        expect((await IsoDrawingDao().getById('old'))!.json, original.json);
        expect(await IsoDrawingDao().listAll(), hasLength(1));
      }
      await expectLater(
          c.draw(const [IsoFitting('not-a-tool')],
              newSketch: true, stepDelay: Duration.zero),
          throwsArgumentError);
      expect(c.sketchName, 'Linia testowa');
      expect((await IsoDrawingDao().getById('old'))!.json, original.json);
      c.undo();
      expect(c.hasContent, isTrue,
          reason: 'failed validation added no undo step');
      await _leave(tester);
    });
    testWidgets(
        'valid new drawing starts with empty axes and keeps the previous record',
        (tester) async {
      final original = await _seed(
          'old',
          _sketch('Stary z północą', [
            _northArrow(Offset(416, 2 * _dy), 1),
            _seg(Offset(64, 4 * _dy), Offset(192, 4 * _dy)),
          ]));
      await _boot(tester);
      final c = await _open(tester);
      final r = await c.draw(const [IsoPipe(dir: IsoDir.up, lengthMm: 1500)],
          newSketch: true, stepDelay: Duration.zero);
      expect(r.ok, isTrue);
      final fresh = await _stored(tester);
      expect(_heading(_b(_pipes(fresh).single) - _a(_pipes(fresh).single)), 1,
          reason: 'new sheet does not inherit old north mapping');
      expect(_comps(fresh, 'northArrow'), isEmpty);
      final old = await IsoDrawingDao().getById('old');
      expect(old!.json, original.json);
      expect(old.updatedAt, original.updatedAt);
      expect(await IsoDrawingDao().listAll(), hasLength(2));
      c.undo();
      expect(c.hasContent, isFalse);
      expect((await IsoDrawingDao().getById('old'))!.json, original.json);
      await _leave(tester);
    });
    testWidgets(
        'failed new preview restores diameter memory; a valid new sheet clears it',
        (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      await c.draw(const [
        IsoPipe(dir: IsoDir.right),
        IsoTurn(toDir: IsoDir.up, dn: 80),
        IsoPipe()
      ], stepDelay: Duration.zero);
      final r = await c.draw(
          const [IsoPipe(dir: IsoDir.right), IsoPipe(dir: IsoDir.left)],
          newSketch: true, stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.reversal);
      await c.draw(const [IsoFitting('ballValve')], stepDelay: Duration.zero);
      final current = await _stored(tester);
      expect(_comps(current, 'ballValve').single['dn'], 80);
      await c.draw(const [IsoFitting('ballValve')],
          newSketch: true, stepDelay: Duration.zero);
      final fresh = await _stored(tester);
      expect(_comps(fresh, 'ballValve').single['dn'], isNull);
      await _leave(tester);
    });

    testWidgets(
        'niepusty szkic: rysunek startuje z wolnego końca ostatniej rury, '
        'stare elementy zostają nietknięte', (tester) async {
      final seeded = _onePipe();
      await _seed('old', seeded);
      await _boot(tester);
      final c = await _open(tester);
      expect(c.hasContent, isTrue);
      expect(c.sketchName, 'Linia testowa');
      expect(c.lastEdited, DateTime.fromMillisecondsSinceEpoch(1000));

      final r = await c.draw(
          const [IsoPipe(dir: IsoDir.forward, lengthMm: 1000)],
          stepDelay: Duration.zero);
      expect(r.problem, isNull);
      expect(r.elbows, 1, reason: 'corner at the old pipe’s end');

      final s = await _stored(tester);
      final items = _items(s);
      expect(items.first, (seeded['items'] as List).first,
          reason: 'the old pipe is stored exactly as before');
      final pipes = _pipes(s);
      expect(pipes, hasLength(2));
      expect(_near(_a(pipes[1]), Offset(192, 4 * _dy)), isTrue,
          reason: 'start = free end of the last pipe');
      expect(_heading(_b(pipes[1]) - _a(pipes[1])), 5);
      expect(s!['name'], 'Linia testowa');
      expect((await IsoDrawingDao().listAll()), hasLength(1),
          reason: 'drawn into the same sketch');
      await _leave(tester);
    });

    testWidgets(
        'startNew(): stary szkic w bazie bajt w bajt nietknięty, pusty arkusz '
        'nie zostawia wpisu, wpis powstaje przy pierwszym elemencie',
        (tester) async {
      final original = await _seed('old', _onePipe());
      await _boot(tester);
      final c = await _open(tester);
      expect(c.hasContent, isTrue);

      await c.startNew();
      expect(c.hasContent, isFalse);
      expect(c.sketchName, isNull);
      expect(c.lastEdited, isNull);
      await tester.pump(const Duration(milliseconds: 600));
      expect(await IsoDrawingDao().listAll(), hasLength(1),
          reason: 'an untouched new sheet is never written');
      var old = await IsoDrawingDao().getById('old');
      expect(old!.json, original.json);
      expect(old.updatedAt, original.updatedAt);

      final r = await c
          .draw(const [IsoPipe(lengthMm: 1500)], stepDelay: Duration.zero);
      expect(r.segments, 1);
      await tester.pump(const Duration(milliseconds: 600));
      final all = await IsoDrawingDao().listAll();
      expect(all, hasLength(2));
      final fresh = await IsoDrawingDao()
          .getById(all.firstWhere((e) => e.id != 'old').id);
      final pipes =
          _pipes((jsonDecode(fresh!.json) as Map).cast<String, Object?>());
      expect(pipes, hasLength(1));
      expect((pipes.single['calc'] as Map)['iso'], '1500');
      old = await IsoDrawingDao().getById('old');
      expect(old!.json, original.json, reason: 'byte for byte');
      expect(old.updatedAt, original.updatedAt);

      // One undo cannot reach back into the previous sketch.
      c.undo();
      c.undo();
      expect(c.hasContent, isFalse);
      await _leave(tester);
      old = await IsoDrawingDao().getById('old');
      expect(old!.json, original.json);
    });
  });

  group('problemy zatrzymują przed rysowaniem i nic nie zapisują', () {
    testWidgets('zawrócenie → reversal, nic nie dodane', (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      var r = await c.draw(
          const [IsoPipe(dir: IsoDir.right), IsoPipe(dir: IsoDir.left)],
          stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.reversal);
      expect(r.problemStep, 1);
      expect(r.segments, 0);
      expect(r.assumedPl, isEmpty);
      expect(c.hasContent, isFalse,
          reason: 'not even the first, valid pipe is drawn');

      r = await c.draw(
          const [IsoPipe(), IsoTurn(toDir: IsoDir.left), IsoPipe()],
          stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.reversal);
      expect(r.problemStep, 1, reason: 'the turn is what has to change');
      expect(c.hasContent, isFalse);
      expect(await _stored(tester), isNull);
      await _leave(tester);
    });

    testWidgets('zawrócenie na niepustym szkicu → zapis w bazie bez zmian',
        (tester) async {
      final original = await _seed('old', _onePipe());
      await _boot(tester);
      final c = await _open(tester);
      final r = await c
          .draw(const [IsoPipe(dir: IsoDir.left)], stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.reversal);
      expect(r.problemStep, 0);
      await tester.pump(const Duration(milliseconds: 600));
      final old = await IsoDrawingDao().getById('old');
      expect(old!.json, original.json);
      expect(old.updatedAt, original.updatedAt);
      c.undo(); // nothing to undo: the command never pushed a step
      await tester.pump(const Duration(milliseconds: 600));
      expect((await IsoDrawingDao().getById('old'))!.json, original.json);
      await _leave(tester);
    });

    testWidgets('ten sam kierunek po skręcie → sameDirectionAfterTurn',
        (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      final r = await c.draw(
          const [IsoPipe(), IsoTurn(toDir: IsoDir.right), IsoPipe()],
          stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.sameDirectionAfterTurn);
      expect(r.problemStep, 1);
      expect(c.hasContent, isFalse);
      await _leave(tester);
    });

    testWidgets('skręt na końcu (albo przed kształtką) → trailingTurn',
        (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      var r =
          await c.draw(const [IsoPipe(), IsoTurn()], stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.trailingTurn);
      expect(r.problemStep, 1);
      r = await c.draw(
          const [IsoPipe(), IsoTurn(), IsoFitting('ballValve', dn: 50)],
          stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.trailingTurn);
      expect(c.hasContent, isFalse);
      expect(await _stored(tester), isNull);
      await _leave(tester);
    });

    testWidgets(
        'legacy elbow fitting without a bend plane and unsupported olet do not mutate the drawing',
        (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      var r = await c.draw(const [IsoPipe(), IsoFitting('elbow45'), IsoPipe()],
          stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.unsupported45);
      expect(r.problemStep, 1);
      r = await c.draw(const [IsoPipe(), IsoFitting('olet', dn: 50)],
          stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.unsupportedTee);
      expect(c.hasContent, isFalse);
      await expectLater(
          c.draw(const [IsoFitting('banana')], stepDelay: Duration.zero),
          throwsArgumentError);
      await _leave(tester);
    });

    testWidgets('skręt tuż za kształtką → turnAtFitting', (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      final r = await c.draw(const [
        IsoPipe(),
        IsoFitting('gateValve', dn: 50),
        IsoPipe(dir: IsoDir.up),
      ], stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.turnAtFitting);
      expect(r.problemStep, 2);
      expect(r.problemPl, contains('kształtka'));
      expect(r.problemEn, isNotEmpty);
      expect(c.hasContent, isFalse);
      await _leave(tester);
    });

    testWidgets(
        'w górę nad górną krawędź siatki na niepustym szkicu → '
        'outOfCanvas, zapis bez zmian', (tester) async {
      // Row 1 is odd: grid points sit half a step to the right.
      final original = await _seed('top', _onePipe(row: 1, x0: 48));
      await _boot(tester);
      final c = await _open(tester);
      final r = await c.draw(const [IsoTurn(toDir: IsoDir.up), IsoPipe()],
          stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.outOfCanvas);
      expect(r.problemStep, 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect((await IsoDrawingDao().getById('top'))!.json, original.json);
      await _leave(tester);
    });
  });

  group('kierunki zgodne z legendą osi', () {
    testWidgets(
        'bez strzałki N: „w górę” = oś III („pion” w legendzie), w górę ekranu',
        (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      expect(find.text('pion'), findsOneWidget);
      expect(c.dirForCompass(IsoCompass.north), isNull);
      await c.draw(const [IsoPipe(dir: IsoDir.up)], stepDelay: Duration.zero);
      expect(c.debugPipeAxisTags, ['III']);
      final pipe = _pipes(await _stored(tester)).single;
      final v = _b(pipe) - _a(pipe);
      expect(v.dy, lessThan(0), reason: 'up the screen');
      expect(_heading(v), IsoDir.up.index);
      await _leave(tester);
    });

    testWidgets(
        'strzałka N na osi III: pion przechodzi na oś II — „w górę” idzie za '
        'legendą („góra/dół”, znacznik ↑), północ = znacznik N',
        (tester) async {
      await _seed(
          'arrow',
          _sketch('Z północą', [
            _northArrow(Offset(416, 2 * _dy), 1), // N up-right = axis III
          ]));
      await _boot(tester);
      final c = await _open(tester);
      expect(find.text('góra/dół'), findsOneWidget);
      expect(find.text('pion'), findsNothing);

      await c.draw(const [IsoPipe(dir: IsoDir.up)], stepDelay: Duration.zero);
      expect(c.debugPipeAxisTags, ['↑']);
      var pipe = _pipes(await _stored(tester)).single;
      expect(_b(pipe).dy, lessThan(_a(pipe).dy), reason: 'up the screen');
      expect(_heading(_b(pipe) - _a(pipe)), 2);

      final north = c.dirForCompass(IsoCompass.north);
      expect(north, isNotNull);
      await c.draw([IsoTurn(toDir: north), const IsoPipe()],
          stepDelay: Duration.zero);
      expect(c.debugPipeAxisTags, ['↑', 'N']);
      final east = c.dirForCompass(IsoCompass.east);
      await c.draw([IsoTurn(toDir: east), const IsoPipe()],
          stepDelay: Duration.zero);
      expect(c.debugPipeAxisTags, ['↑', 'N', 'E']);
      pipe = _pipes(await _stored(tester)).last;
      expect(_heading(_b(pipe) - _a(pipe)), 0);
      await _leave(tester);
    });

    testWidgets(
        'rysowanie w górę na pustym arkuszu: start przesunięty, punkty w '
        'wierszach ≥ 0, widok dopasowany do całego rysunku', (tester) async {
      await _boot(tester, size: const Size(412, 860));
      final c = await _open(tester);
      final canvas = tester.getSize(_canvas);
      const up = IsoPipe(lengthMm: 4000); // 8 grid rows
      const right = IsoPipe(lengthMm: 1000);
      final r = await c.draw(const [
        IsoPipe(dir: IsoDir.up, lengthMm: 4000),
        IsoTurn(toDir: IsoDir.right),
        right,
        IsoTurn(toDir: IsoDir.up),
        up,
        IsoTurn(toDir: IsoDir.right),
        right,
        IsoTurn(toDir: IsoDir.up),
        up,
        IsoTurn(toDir: IsoDir.right),
        right,
        IsoTurn(toDir: IsoDir.up),
        up,
        IsoTurn(toDir: IsoDir.right),
        right,
        IsoTurn(toDir: IsoDir.up),
        up,
      ], stepDelay: Duration.zero);
      expect(r.problem, isNull);
      expect(r.segments, 9);
      expect(r.elbows, 8);

      final s = await _stored(tester);
      final pts = [
        for (final p in _pipes(s)) ...[_a(p), _b(p)],
        for (final i in _items(s))
          if (i['kind'] == 'comp') _pt(i['pos']),
      ];
      final top = _pipes(s).map((p) => _b(p).dy).reduce(math.min);
      expect(top, greaterThanOrEqualTo(0));
      for (final p in _pipes(s)) {
        for (final q in [_a(p), _b(p)]) {
          final row = q.dy / _dy;
          expect(row, closeTo(row.roundToDouble(), 1e-9),
              reason: 'on a grid row');
          expect(row.round(), greaterThanOrEqualTo(0));
        }
      }
      // 40 rows (≈ 1110 px) do not fit a 412 × 860 phone at 100 %: the
      // view zooms out until the whole drawing is on screen.
      expect(canvas.height, lessThan(40 * _dy));
      final visible = c.debugVisibleWorld!;
      expect(visible.height, greaterThan(canvas.height));
      for (final p in pts) {
        expect(visible.contains(p), isTrue, reason: '$p off screen');
      }
      await _leave(tester);
    });
  });

  group('animacja i gest', () {
    testWidgets(
        'podgląd rośnie w osobnym polu; gest palca w trakcie kończy polecenie '
        'od razu — bez psucia podglądu, zapisu ani Cofnij', (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      final pending = c.draw(const [IsoPipe(), IsoTurn(), IsoPipe()],
          stepDelay: const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 150));
      expect(c.debugGhost, isNotNull, reason: 'the first pipe is growing');
      expect(c.hasContent, isFalse, reason: 'nothing committed mid-pipe yet');

      // The fitter draws a line far above the route while it animates.
      final start = tester.getCenter(_canvas) - const Offset(64, 400);
      final g = await tester.startGesture(start);
      await g.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(c.debugGhost, isNull, reason: 'the gesture ended the animation');
      expect(c.isBusy, isTrue, reason: 'the run returns after its timer');
      await g.moveBy(const Offset(80, 0));
      await g.up();
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 200));
      final r = await pending;
      expect(r.segments, 2);
      expect(r.elbows, 1);
      expect(c.debugGhost, isNull);
      expect(c.isBusy, isFalse);
      expect(_pipes(await _stored(tester)), hasLength(3),
          reason: 'command (2) + the finger line (1)');

      c.undo();
      expect(_pipes(await _stored(tester)), hasLength(2),
          reason: 'first undo takes the finger line');
      c.undo();
      expect(_pipes(await _stored(tester)), isEmpty,
          reason: 'second undo takes the whole command');
      await _leave(tester);
    });

    testWidgets(
        'uszczypnięcie w trakcie animacji: polecenie kompletne, '
        'widok należy do palców', (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      final pending = c.draw(const [IsoPipe(), IsoTurn(), IsoPipe()],
          stepDelay: const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 150));
      expect(c.debugGhost, isNotNull);

      final centre = tester.getCenter(_canvas);
      final f1 = await tester.startGesture(centre - const Offset(60, 0));
      final f2 = await tester.startGesture(centre + const Offset(60, 0));
      await f1.moveBy(const Offset(-40, 0));
      await f2.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(c.debugGhost, isNull);
      await f1.up();
      await f2.up();
      await tester.pump(const Duration(milliseconds: 200));

      final r = await pending;
      expect(r.segments, 2);
      expect(r.elbows, 1);
      final s = await _stored(tester);
      expect(_pipes(s), hasLength(2));
      expect(_comps(s, 'elbow90'), hasLength(1));
      await _leave(tester);
    });

    testWidgets(
        'wyjście z zeszytu w trakcie animacji zapisuje całe polecenie; '
        'kolejne wywołanie na zamkniętym ekranie → StateError', (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      final pending = c.draw(const [IsoPipe(), IsoTurn(), IsoPipe()],
          stepDelay: const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(IsoNotebookController.active, isNull);

      final r = await pending;
      expect(r.segments, 2);
      expect(r.elbows, 1);
      final rec = await IsoDrawingDao().latest();
      final s = (jsonDecode(rec!.json) as Map).cast<String, Object?>();
      expect(_pipes(s), hasLength(2));
      expect(_comps(s, 'elbow90'), hasLength(1));

      await expectLater(c.draw(const [IsoPipe()], stepDelay: Duration.zero),
          throwsStateError);
    });
  });

  group('poprawki z przeglądu', () {
    testWidgets(
        'krok podglądu nie przebudowuje ekranu — przebudowy nie rosną z liczbą '
        'kroków podglądu, a warstwa podglądu się przemalowuje', (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      await tester.pump();
      final builds0 = c.debugScreenBuilds;
      final paints0 = IsoNotebookController.debugGhostPaints;

      const step = Duration(milliseconds: 40);
      final pending = c.draw(const [
        IsoPipe(),
        IsoTurn(),
        IsoPipe(),
        IsoTurn(toDir: IsoDir.up),
        IsoPipe(),
      ], stepDelay: step);
      // Three preview steps of the first pipe, a frame after each.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(c.debugGhost, isNotNull);
      expect(c.hasContent, isFalse, reason: 'still previewing pipe 1');
      expect(c.debugScreenBuilds, builds0,
          reason: 'a preview step must not rebuild the screen');
      expect(IsoNotebookController.debugGhostPaints, greaterThan(paints0),
          reason: 'the preview layer itself does repaint');

      // The rest of the run: 3 pipes × 4 preview steps = 12 steps.
      for (var i = 0; i < 40 && c.isBusy; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      final r = await pending;
      expect(r.segments, 3);
      final builds = c.debugScreenBuilds - builds0;
      expect(builds, lessThanOrEqualTo(r.segments + 1),
          reason: 'one rebuild per committed pipe, none per preview step '
              '(12 steps → $builds rebuilds)');
      await _leave(tester);
    });

    testWidgets(
        'otwarcie innego szkicu w trakcie animacji: stary szkic w bazie ma '
        'wszystkie rury polecenia', (tester) async {
      await _seed('old', _onePipe());
      await IsoDrawingDao().upsert(IsoDrawingRecord(
        id: 'other',
        name: 'Inny rysunek',
        json: jsonEncode(_sketch('Inny rysunek', [
          _seg(Offset(64, 10 * _dy), Offset(192, 10 * _dy)),
        ])),
        createdAt: 500,
        updatedAt: 500, // older: the notebook opens 'old'
      ));
      await _boot(tester);
      final c = await _open(tester);
      expect(c.sketchName, 'Linia testowa');

      final pending = c.draw(const [
        IsoPipe(dir: IsoDir.forward),
        IsoTurn(toDir: IsoDir.right),
        IsoPipe(),
        IsoTurn(toDir: IsoDir.forward),
        IsoPipe(),
      ], stepDelay: const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 150));
      expect(c.debugGhost, isNotNull, reason: 'mid-animation');

      await tester.tap(find.byTooltip('Szkice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Zapisane szkice…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Inny rysunek').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      expect((await pending).segments, 3);
      expect(c.sketchName, 'Inny rysunek');
      final old = await IsoDrawingDao().getById('old');
      final pipes =
          _pipes((jsonDecode(old!.json) as Map).cast<String, Object?>());
      expect(pipes, hasLength(4),
          reason: 'the original pipe + all 3 of the command, none lost');
      await _leave(tester);
    });

    testWidgets(
        '„Nowy szkic” w trakcie animacji: stary szkic w bazie ma wszystkie '
        'rury polecenia', (tester) async {
      await _seed('old', _onePipe());
      await _boot(tester);
      final c = await _open(tester);

      final pending = c.draw(const [
        IsoPipe(dir: IsoDir.forward),
        IsoTurn(toDir: IsoDir.right),
        IsoPipe(),
      ], stepDelay: const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 150));
      expect(c.debugGhost, isNotNull);

      await tester.tap(find.byTooltip('Szkice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Nowy szkic'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(TextButton, 'Nowy szkic'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect((await pending).segments, 2);
      expect(c.hasContent, isFalse, reason: 'a fresh sheet');
      final old = await IsoDrawingDao().getById('old');
      final pipes =
          _pipes((jsonDecode(old!.json) as Map).cast<String, Object?>());
      expect(pipes, hasLength(3));
      await _leave(tester);
    });

    testWidgets(
        'kolano stojące na wolnym końcu blokuje rurę i kształtkę '
        '(turnAtFitting, „na końcu stoi już kolano”), zapis bez zmian',
        (tester) async {
      final original = await _seed(
          'elbow',
          _sketch('Z kolanem', [
            _seg(Offset(64, 4 * _dy), Offset(192, 4 * _dy)),
            _elbow(Offset(192, 4 * _dy), 3, 1),
          ]));
      await _boot(tester);
      final c = await _open(tester);

      for (final steps in const [
        [IsoTurn(toDir: IsoDir.forward), IsoPipe()], // a turn
        [IsoPipe(dir: IsoDir.right)], // straight on through the elbow
        [IsoFitting('ballValve', dn: 50)], // a fitting on top of it
      ]) {
        final r = await c.draw(steps, stepDelay: Duration.zero);
        expect(r.problem, IsoDrawProblem.turnAtFitting, reason: '$steps');
        expect(r.problemStep, 0);
        expect(r.problemPl, contains('Na końcu stoi już kolano'));
        expect(r.problemPl, contains('cofnij'));
        expect(r.segments, 0);
      }
      await tester.pump(const Duration(milliseconds: 600));
      expect((await IsoDrawingDao().getById('elbow'))!.json, original.json);
      await _leave(tester);
    });
  });
}
