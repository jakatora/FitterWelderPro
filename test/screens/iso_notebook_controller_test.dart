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

List<Map<String, Object?>> _pipes(Map<String, Object?>? sketch) => _items(
        sketch)
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({'iso_notebook_hint_hidden': true});
    final db = await AppDatabase.get();
    await db.delete(IsoDrawingDao.table);
  });

  group('rysowanie sekwencji', () {
    testWidgets(
        'rura, kolano, rura → 2 odcinki i 1 kolano, w prawo potem do przodu, '
        'z listą przyjętych założeń', (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      expect(IsoNotebookController.activeListenable.value, same(c));
      expect(c.hasContent, isFalse);

      final r = await c.draw(
          const [IsoPipe(), IsoTurn(), IsoPipe()], stepDelay: Duration.zero);
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
      await c.draw(const [IsoPipe(dir: IsoDir.right)],
          stepDelay: Duration.zero);
      await c.draw(
          const [IsoPipe(), IsoTurn(toDir: IsoDir.up), IsoPipe()],
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

    testWidgets('lengthMm 1500 → wymiar „1500” i 3 kroki siatki; '
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
      final first = c.draw(const [IsoPipe(dir: IsoDir.right)],
          stepDelay: Duration.zero);
      final second = c.draw(const [IsoPipe(dir: IsoDir.forward)],
          stepDelay: Duration.zero);
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

  group('niepusty szkic i nowy rysunek', () {
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

      final r = await c.draw(const [IsoPipe(lengthMm: 1500)],
          stepDelay: Duration.zero);
      expect(r.segments, 1);
      await tester.pump(const Duration(milliseconds: 600));
      final all = await IsoDrawingDao().listAll();
      expect(all, hasLength(2));
      final fresh = await IsoDrawingDao().getById(
          all.firstWhere((e) => e.id != 'old').id);
      final pipes = _pipes(
          (jsonDecode(fresh!.json) as Map).cast<String, Object?>());
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
      final r = await c.draw(const [IsoPipe(dir: IsoDir.left)],
          stepDelay: Duration.zero);
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
      var r = await c.draw(const [IsoPipe(), IsoTurn()],
          stepDelay: Duration.zero);
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

    testWidgets('kolano 45° i trójnik → poza zakresem, nic nie dodane',
        (tester) async {
      await _boot(tester);
      final c = await _open(tester);
      var r = await c.draw(
          const [IsoPipe(), IsoFitting('elbow45'), IsoPipe()],
          stepDelay: Duration.zero);
      expect(r.problem, IsoDrawProblem.unsupported45);
      expect(r.problemStep, 1);
      r = await c.draw(const [IsoPipe(), IsoFitting('tee', dn: 50)],
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

    testWidgets('w górę nad górną krawędź siatki na niepustym szkicu → '
        'outOfCanvas, zapis bez zmian', (tester) async {
      // Row 1 is odd: grid points sit half a step to the right.
      final original = await _seed('top', _onePipe(row: 1, x0: 48));
      await _boot(tester);
      final c = await _open(tester);
      final r = await c.draw(
          const [IsoTurn(toDir: IsoDir.up), IsoPipe()],
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
        IsoTurn(toDir: IsoDir.right), right,
        IsoTurn(toDir: IsoDir.up), up,
        IsoTurn(toDir: IsoDir.right), right,
        IsoTurn(toDir: IsoDir.up), up,
        IsoTurn(toDir: IsoDir.right), right,
        IsoTurn(toDir: IsoDir.up), up,
        IsoTurn(toDir: IsoDir.right), right,
        IsoTurn(toDir: IsoDir.up), up,
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

    testWidgets('uszczypnięcie w trakcie animacji: polecenie kompletne, '
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
        'kolejne wywołanie na zamkniętym ekranie → StateError',
        (tester) async {
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

      await expectLater(
          c.draw(const [IsoPipe()], stepDelay: Duration.zero),
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
