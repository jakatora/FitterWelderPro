import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pumpAndSettle();
}

Future<void> _boot(WidgetTester t) async {
  seedFreshInstall();
  addTearDown(() => _close(t));
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.reset);
  await t.pumpWidget(const CutListApp());
  await settle(t);
  await t.tap(find.byTooltip('Powiedz, co zrobić'));
  await settle(t);
}

Future<void> _say(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('assistant-command')), text);
  await t.tap(find.byKey(const Key('assistant-go')));
  await settle(t);
  // Longer routes animate several pipes. Observe the real busy button,
  // rather than inspecting an autosave taken halfway through the command.
  bool busy() {
    final button = t.widget(find.byKey(const Key('assistant-go')));
    return switch (button) {
      IconButton(:final onPressed) => onPressed == null,
      FilledButton(:final onPressed) => onPressed == null,
      _ => throw StateError('Unexpected assistant execute button'),
    };
  }

  for (var i = 0; i < 20 && busy(); i++) {
    await settle(t);
  }
  expect(busy(), isFalse, reason: 'assistant command must finish');
  await settle(t); // Drain the final SQLite snapshot after animation.
}

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await settle(t);
  AssistantPanelController.instance.setExpanded(false);
}

Future<ShowOutcome> _showSteps(
    WidgetTester t, Map<String, Object?> fields) async {
  ShowOutcome? outcome;
  Object? error;
  final done =
      showInModule(ShowInModule('iso_notebook', fields), explicit: true).then(
          (value) {
    outcome = value;
  }, onError: (Object e) {
    error = e;
  });
  for (var i = 0; i < 40 && outcome == null && error == null; i++) {
    await settle(t);
  }
  expect(error, isNull);
  expect(outcome, isNotNull, reason: 'native field application must complete');
  await done;
  return outcome!;
}

void main() {
  testWidgets('assistant edits only numbered ISO dimension and undo preserves the run', (t) async {
    await _boot(t);
    await _say(t,'narysuj rura metr w prawo kolano DN50 w górę rura dwa metry');
    final controller=IsoNotebookController.active!;
    Future<List<Map<String,dynamic>>> items() async {
      await settle(t);
      final record=await t.runAsync(()=>IsoDrawingDao().latest());
      return ((jsonDecode(record!.json) as Map)['items'] as List).cast<Map<String,dynamic>>();
    }
    final before=await items();
    expect(before.where((e)=>e['tool']=='pipe'),hasLength(2));
    await _say(t,'Zmień wymiar ISO rury numer 1 na 500 mm');
    expect(find.textContaining('Ustawiłem wymiar ISO rury numer 1'),findsOneWidget);
    final edited=await items();
    final expected=jsonDecode(jsonEncode(before)) as List;
    (expected.firstWhere((e)=>e['tool']=='pipe')['calc'] as Map)['iso']='500';
    expect(edited,expected);
    final revision=controller.revision;
    await _say(t,'Zmień wymiar ISO rury numer 99 na 500 mm');
    expect(controller.revision,revision);
    expect(await items(),edited);
    await _say(t,'cofnij');
    expect(await items(),before);
    final stale=await t.runAsync(()=>controller.setPipeIsoDimension(700,
      ordinal:1,expectedRevision:revision));
    expect(stale,isNull);
    expect(await items(),before);
    await _say(t,'Zmień wymiar ISO ostatniej rury na 250 cm');
    final lastEdit=await items();
    final pipes=lastEdit.where((e)=>e['tool']=='pipe').toList();
    expect(pipes.first['calc'],before.firstWhere((e)=>e['tool']=='pipe')['calc']);
    expect((pipes.last['calc'] as Map)['iso'],'2500');
    expect(t.takeException(),isNull);
  });
  useTestDatabase();
  testWidgets('dimension edit retains reference status, stops, deductions and pipe annotations', (t) async {
    await t.runAsync(()=>IsoDrawingDao().upsert(IsoDrawingRecord(
      id:'dimension-reference',name:'Reference',createdAt:1,updatedAt:1,
      json:jsonEncode({'format':2,'name':'Reference','items':[
        {'kind':'seg','tool':'pipe','a':[64.0,200.0],'b':[192.0,200.0],
          'slope':'1:100','insulated':true,'calc':{'iso':'(1000)',
            'ref':'centreToEnd','stopA':'centre','stopB':'end',
            'deducts':[{'name':'Gasket','value':'3+2'}]}}
      ]}))));
    await _boot(t);
    await _say(t,'Zmień wymiar ISO ostatniej rury na 500 mm');
    final stored=await t.runAsync(()=>IsoDrawingDao().latest());
    final pipe=((jsonDecode(stored!.json) as Map)['items'] as List).single;
    expect(pipe['slope'],'1:100');expect(pipe['insulated'],isTrue);
    expect(pipe['calc'],{'iso':'(500)','ref':'centreToEnd','stopA':'centre','stopB':'end',
      'deducts':[{'name':'Gasket','value':'3+2'}]});
    await _say(t,'cofnij');
    final undone=await t.runAsync(()=>IsoDrawingDao().latest());
    expect(((jsonDecode(undone!.json) as Map)['items'] as List).single['calc']['iso'],'(1000)');
  });
  setUp(() async {
    final db = await AppDatabase.get();
    await db.delete('iso_drawings');
  });
  testWidgets(
      'mitred bend drawing request cannot silently create an ordinary elbow',
      (t) async {
    await _boot(t);
    expect(
        await FeedbackConsent.instance.grant(now: DateTime.utc(2026, 10, 21)),
        isTrue);
    await _say(t, 'narysuj rura metr w prawo');
    final c = IsoNotebookController.active!;
    final before = c.debugPipeAxisTags.toList();
    await _say(t, 'dorysuj rura metr kolano segmentowe w górę rura metr');
    expect(find.textContaining('nie ma jeszcze symbolu kolana segmentowego'),
        findsOneWidget);
    expect(c.debugPipeAxisTags, before);
    final reports = await FeedbackStore.instance.list();
    expect(reports, hasLength(1));
    expect(reports.single.skill, 'iso.unsupported');
    await _say(t, 'cofnij');
    expect(c.hasContent, isFalse,
        reason: 'refused drawing must not consume an Undo step');
  });
  testWidgets(
      '45 degree command draws actual spatial elbows through the common assistant',
      (t) async {
    await _boot(t);
    await _say(t,
        'narysuj rura metr w prawo kolano 45 stopni DN100 w górę rura metr kolano 45 stopni DN100 w górę rura metr');
    final c = IsoNotebookController.active!;
    expect(c.debugPipeAxisTags, hasLength(3));
    expect(c.debugPipeAxisTags[1], '3D');
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.where((x) => x['tool'] == 'elbow45'), hasLength(2));
    expect(items.where((x) => x['tool'] == 'elbow90'), isEmpty);
    expect(
        items
            .where((x) => x['tool'] == 'elbow45')
            .every((x) => x['spatialBend'] != null),
        isTrue);
    await _say(t, 'cofnij');
    expect(c.hasContent, isFalse);
    expect(await FeedbackStore.instance.list(), isEmpty);
    await _close(t);
  });
  testWidgets(
      'missing 45 degree plane asks before any drawing then keeps the complete sequence',
      (t) async {
    await _boot(t);
    await _say(
        t, 'narysuj rura metr w prawo kolano 45 stopni DN50 rura dwa metry');
    expect(find.textContaining('W którą stronę skręcić kolano 45'),
        findsOneWidget);
    expect(IsoNotebookController.active?.hasContent ?? false, isFalse);
    await _say(t, 'w górę');
    final c = IsoNotebookController.active!;
    expect(c.debugPipeAxisTags, hasLength(2));
    expect(c.debugPipeAxisTags.last, '3D');
    await _say(t, 'dorysuj rura metr');
    expect(c.debugPipeAxisTags, hasLength(3));
    await _say(t, 'cofnij');
    expect(c.debugPipeAxisTags, hasLength(2));
    await _say(t, 'cofnij');
    expect(c.hasContent, isFalse);
    expect(await FeedbackStore.instance.list(), isEmpty);
    await _close(t);
  });
  testWidgets(
      'a pending bend direction yields to another command and cannot execute later',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj rura metr kolano 45 rura metr');
    expect(find.textContaining('W którą stronę skręcić kolano 45'),
        findsOneWidget);
    await _say(t, 'NDS manganu');
    expect(find.textContaining('0,05 mg/m³'), findsWidgets);
    await _say(t, 'w górę');
    expect(IsoNotebookController.active?.hasContent ?? false, isFalse);
    await _close(t);
  });
  testWidgets(
      'the common assistant places a real valve along a spatial pipe and undoes only that command',
      (t) async {
    await _boot(t);
    await _say(
        t, 'narysuj rura metr w prawo kolano 45 stopni DN100 w górę rura metr');
    await _say(t, 'dorysuj zawór kulowy DN100');
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final sketch = jsonDecode(saved!.json) as Map;
    expect(sketch['format'], 5);
    final items = sketch['items'] as List;
    final valve = items.singleWhere((x) => x['tool'] == 'ballValve');
    final pipe = items.where((x) => x['tool'] == 'pipe').last;
    expect(valve['spatialDirection'], pipe['spatialDirection']);
    expect(valve['dn'], 100);
    expect(items.where((x) => x['tool'] == 'weld'), hasLength(4));
    await _say(t, 'cofnij');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(2));
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final undone = await t.runAsync(() => IsoDrawingDao().latest());
    expect(
        ((jsonDecode(undone!.json) as Map)['items'] as List)
            .where((x) => x['tool'] == 'ballValve'),
        isEmpty);
    expect(await FeedbackStore.instance.list(), isEmpty);
    await _close(t);
  });
  testWidgets(
      'spatial tee branch asks, rejects a nonperpendicular axis, accepts correction and undoes',
      (t) async {
    await _boot(t);
    await _say(t,
        'narysuj rura metr w prawo kolano 45 stopni DN100 w górę rura metr trójnik DN100 na DN80 rura metr');
    final c = IsoNotebookController.active!;
    expect(c.debugPipeAxisTags, hasLength(3));
    await _say(t, 'od trójnika rura metr');
    expect(find.textContaining('W jakim kierunku ma iść odgałęzienie'),
        findsOneWidget);
    await _say(t, 'w górę');
    expect(c.debugPipeAxisTags, hasLength(3));
    await _say(t, 'do tyłu');
    expect(c.debugPipeAxisTags, hasLength(4));
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final sketch = jsonDecode(saved!.json) as Map;
    expect(sketch['format'], 6);
    final items = sketch['items'] as List;
    final tee = items.singleWhere((x) => x['tool'] == 'tee');
    expect(tee['dnOut'], 80);
    expect((tee['spatialTee'] as Map)['branch'], [0.0, -1.0, 0.0]);
    await _say(t, 'do przodu');
    expect(find.textContaining('Zmieniłem kierunek odgałęzienia.'),
        findsOneWidget);
    await _say(t, 'cofnij');
    expect(c.debugPipeAxisTags, hasLength(3));
    expect(await FeedbackStore.instance.list(), isEmpty);
    await _close(t);
  });
  testWidgets(
      'ShowInModule steps opens the real notebook, preserves symbols and refuses ambiguous or invalid mutations',
      (t) async {
    await _boot(t);
    final symbol = await _showSteps(t, {
      'steps': encodeIsoSteps(const [
        IsoFitting('elbow45', dn: 50, symbolOnly: true, dir: IsoDir.up)
      ])
    });
    expect(symbol, ShowOutcome.opened);
    final c = IsoNotebookController.active!;
    expect(ToolBridge.instance.current?.toolId, 'iso_notebook');
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.single['tool'], 'elbow45');
    expect(items.single['dir'], IsoDir.up.index);
    c.undo();
    await settle(t);
    expect(c.hasContent, isFalse);
    final route = await _showSteps(t, {
      'steps': encodeIsoSteps(const [
        IsoPipe(lengthMm: 1000.125),
        IsoTurn(degrees: 45, toDir: IsoDir.up, dn: 100),
        IsoPipe(lengthMm: 1000)
      ])
    });
    expect(route, ShowOutcome.appliedInPlace);
    expect(c.debugPipeAxisTags, hasLength(2));
    await settle(t);
    final precise = await t.runAsync(() => IsoDrawingDao().latest());
    final preciseItems = (jsonDecode(precise!.json) as Map)['items'] as List;
    expect(
        (preciseItems.firstWhere((e) => e['tool'] == 'pipe')['calc']
            as Map)['iso'],
        '1000.125');
    for (final fields in <Map<String, Object?>>[
      {
        'steps': encodeIsoSteps(const [IsoPipe()])
      },
      {
        'new_sketch': true,
        'steps': [
          {'kind': 'pipe'},
          {'kind': 'turn', 'dn': 50.9}
        ]
      },
      {
        'new_sketch': true,
        'steps': encodeIsoSteps(const [IsoPipe(), IsoTurn()])
      },
      {
        'steps': encodeIsoSteps(const [IsoPipe()]),
        'append': 'true'
      },
      {
        'steps': encodeIsoSteps(const [IsoPipe()]),
        'append': true,
        'future': 1
      },
    ]) {
      expect(await _showSteps(t, fields), ShowOutcome.unsupportedFields);
      expect(c.debugPipeAxisTags, hasLength(2));
    }
    expect(
        await _showSteps(t, {
          'append': true,
          'steps': encodeIsoSteps(const [IsoPipe(lengthMm: 500)])
        }),
        ShowOutcome.appliedInPlace);
    expect(c.debugPipeAxisTags, hasLength(3));
    c.undo();
    await settle(t);
    expect(c.debugPipeAxisTags, hasLength(2));
    await _close(t);
  });
  testWidgets(
      'conversation refuses an unsupported explicit DN instead of substituting a remembered fitting size',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj rura metr w prawo kolano DN50 w górę rura metr');
    final c = IsoNotebookController.active!;
    expect(c.debugPipeAxisTags, hasLength(2));
    await _say(t, 'dorysuj zawór kulowy DN400');
    expect(find.textContaining('Podaj DN z listy zeszytu'), findsOneWidget);
    await settle(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.where((e) => e['tool'] == 'ballValve'), isEmpty);
    expect(c.debugPipeAxisTags, hasLength(2));
    await _close(t);
  });
  for (final (tool, noun, size) in [
    ('ballValve', 'zaworu kulowego', 'DN50'),
    ('gateValve', 'zasuwy', 'DN50'),
    ('checkValve', 'zaworu zwrotnego', 'DN50'),
    ('globeValve', 'zaworu grzybkowego', 'DN50'),
    ('butterflyValve', 'przepustnicy', 'DN50'),
    ('flange', 'kołnierza', 'DN50'),
    ('blindFlange', 'kołnierza zaślepiającego', 'DN50'),
    ('cap', 'zaślepki', 'DN50'),
    ('reducer', 'redukcji', 'DN100 na DN80'),
    ('weld', 'spoiny', ''),
    ('fieldWeld', 'spoiny montażowej', ''),
    ('support', 'podpory', ''),
  ]) {
    testWidgets(
        'standalone $tool keeps requested direction through chat, native screen and SQLite',
        (t) async {
      await _boot(t);
      await _say(t, 'narysuj symbol $noun $size w górę');
      await settle(t);
      final saved = await t.runAsync(() => IsoDrawingDao().latest());
      final items = (jsonDecode(saved!.json) as Map)['items'] as List;
      final fitting = items.singleWhere((x) => x['tool'] == tool);
      expect(fitting['dir'], IsoDir.up.index,
          reason:
              'an explicit symbol must not flip like an inferred run terminal');
      expect(items.where((x) => x['tool'] == 'pipe'), isEmpty);
      await _say(t, 'cofnij');
      expect(IsoNotebookController.active!.hasContent, isFalse);
      await _close(t);
    });
  }
  testWidgets(
      'valve question preserves compass and size until the actual drawing north arrow resolves it',
      (t) async {
    await t.runAsync(() => IsoDrawingDao().upsert(IsoDrawingRecord(
        id: 'axial-compass',
        name: 'North',
        createdAt: 1000,
        updatedAt: 1000,
        json: jsonEncode({
          'format': 1,
          'name': 'North',
          'items': [
            {
              'kind': 'comp',
              'tool': 'northArrow',
              'pos': [416.0, 64.0],
              'dir': 3,
              'dir2': null,
              'label': ''
            }
          ]
        }))));
    await _boot(t);
    await _say(t, 'dorysuj symbol zaworu DN50 na północ');
    expect(find.textContaining('Jaki rodzaj zaworu'), findsWidgets);
    await _say(t, 'kulowy');
    await settle(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final valve = ((jsonDecode(saved!.json) as Map)['items'] as List)
        .singleWhere((x) => x['tool'] == 'ballValve');
    expect(valve['dir'], 3);
    expect(valve['dn'], 50);
    await _close(t);
  });
  testWidgets(
      'conflicting route orientation and alternative directions ask without any drawing or gap report',
      (t) async {
    await _boot(t);
    expect(
        await FeedbackConsent.instance.grant(now: DateTime.utc(2026, 10, 21)),
        isTrue);
    await _say(t, 'narysuj rura metr w prawo');
    final c = IsoNotebookController.active!;
    await _say(t, 'dorysuj rura metr zawór kulowy DN50 w górę rura metr');
    expect(find.textContaining('w trasie biegnie wzdłuż rury'), findsOneWidget);
    await _say(t, 'dorysuj symbol kołnierza DN50 w lewo albo w prawo');
    expect(find.textContaining('Podaj jeden kierunek'), findsOneWidget);
    await _say(t, 'dorysuj symbol zaworu DN50 DN80 w górę');
    expect(find.textContaining('Podaj jedno dodatnie DN'), findsOneWidget);
    expect(c.debugPipeAxisTags, hasLength(1));
    expect(await FeedbackStore.instance.list(), isEmpty);
    c.undo();
    await settle(t);
    expect(c.hasContent, isFalse);
    await _close(t);
  });
  testWidgets(
      'a genuinely unsupported angle retains the sketch and queues its capability gap with consent',
      (t) async {
    await _boot(t);
    expect(
        await FeedbackConsent.instance.grant(now: DateTime.utc(2026, 10, 21)),
        isTrue);
    await _say(t, 'narysuj rura metr w prawo');
    final c = IsoNotebookController.active!;
    await _say(t, 'dorysuj rura metr kolano 30 stopni w górę rura metr');
    expect(find.textContaining('Trasy obsługują kolana 45° i 90°'),
        findsOneWidget);
    expect(c.debugPipeAxisTags, hasLength(1));
    final reports = await FeedbackStore.instance.list();
    expect(reports, hasLength(1));
    expect(reports.single.tool, 'iso_notebook');
    expect(reports.single.skill, 'iso.unsupported');
    await _close(t);
  });
  testWidgets(
      'compass directions and a short correction follow the actual north arrow',
      (t) async {
    await t.runAsync(() => IsoDrawingDao().upsert(IsoDrawingRecord(
        id: 'compass-seed',
        name: 'Z północą',
        createdAt: 1000,
        updatedAt: 1000,
        json: jsonEncode({
          'format': 1,
          'name': 'Z północą',
          'items': [
            {
              'kind': 'comp',
              'tool': 'northArrow',
              'pos': [416.0, 64.0],
              'dir': 1,
              'dir2': null,
              'label': ''
            }
          ]
        }))));
    await _boot(t);
    await _say(t, 'dorysuj rura metr na północ kolano na wschód rura metr');
    expect(IsoNotebookController.active!.debugPipeAxisTags, ['N', 'E']);
    await _say(t, 'narysuj rura metr na północ');
    expect(find.textContaining('Na arkuszu jest już rysunek'), findsOneWidget);
    await _say(t, 'nowy');
    expect(find.textContaining('strzałki północy'), findsOneWidget);
    expect(IsoNotebookController.active!.debugPipeAxisTags, ['N', 'E']);
    await _say(t, 'na zachód');
    expect(IsoNotebookController.active!.debugPipeAxisTags, ['N', 'W']);
    await _say(t, 'cofnij');
    expect(IsoNotebookController.active!.debugPipeAxisTags, isEmpty);
    await _close(t);
  });
  testWidgets(
      'no north arrow asks for orientation without drawing or reporting a missing feature',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj rura metr na północ');
    expect(IsoNotebookController.active!.hasContent, isFalse);
    expect(find.textContaining('strzałki północy'), findsOneWidget);
    expect(await FeedbackStore.instance.list(), isEmpty);
    await _close(t);
  });
  testWidgets('an ISO target question yields to a new domain command',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj rura metr w prawo');
    await _say(t, 'narysuj rura metr w górę');
    expect(find.textContaining('Na arkuszu jest już rysunek'), findsOneWidget);
    final before = IsoNotebookController.active!.debugPipeAxisTags.toList();
    await _say(t, 'NDS manganu');
    expect(find.textContaining('0,05 mg/m³'), findsWidgets);
    expect(IsoNotebookController.active!.debugPipeAxisTags, before);
    await _say(t, 'dorysuj');
    expect(IsoNotebookController.active!.debugPipeAxisTags, before);
    await _close(t);
  });
  for (final e in {
    'Kulowy': 'ballValve',
    'Zasuwa': 'gateValve',
    'Zwrotny': 'checkValve',
    'Grzybkowy': 'globeValve',
    'Przepustnica': 'butterflyValve'
  }.entries) {
    testWidgets('valve choice ${e.key} completes the stored ISO sequence',
        (t) async {
      await _boot(t);
      await _say(t, 'narysuj rura metr w prawo zawór DN50');
      expect(IsoNotebookController.active, isNull);
      expect(find.textContaining('Jaki rodzaj zaworu'), findsOneWidget);
      final chip = find.widgetWithText(ActionChip, e.key);
      await t.ensureVisible(chip);
      await t.pumpAndSettle();
      expect(chip.hitTestable(), findsOneWidget);
      await t.tap(chip);
      await settle(t);
      expect(IsoNotebookController.active!.hasContent, isTrue);
      await t.pump(const Duration(milliseconds: 600));
      await flushTestDatabase(t);
      final stored = await t.runAsync(() => IsoDrawingDao().latest());
      final items = (jsonDecode(stored!.json) as Map)['items'] as List;
      expect(items.where((x) => x['kind'] == 'seg' && x['tool'] == 'pipe'),
          hasLength(1));
      final valve = items.singleWhere((x) => x['tool'] == e.value);
      expect(valve['dn'], 50);
      expect(await FeedbackStore.instance.list(), isEmpty);
      if (e.value == 'ballValve') {
        await _say(t, 'cofnij');
        expect(IsoNotebookController.active!.hasContent, isFalse);
      }
    });
  }
  testWidgets('two unnamed valves are clarified before any part is drawn',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj rura metr w prawo zawór DN50 rura metr zawór DN80');
    await _say(t, 'narysuj zawór kulowy');
    expect(IsoNotebookController.active, isNull);
    expect(find.textContaining('Jaki rodzaj zaworu'), findsOneWidget);
    await _say(t, 'dodaj zawór zwrotny');
    expect(IsoNotebookController.active, isNotNull,
        reason: find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .whereType<String>()
            .join(' | '));
    expect(IsoNotebookController.active!.hasContent, isTrue);
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final stored = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(stored!.json) as Map)['items'] as List;
    expect(items.singleWhere((x) => x['tool'] == 'ballValve')['dn'], 50);
    expect(items.singleWhere((x) => x['tool'] == 'checkValve')['dn'], 80);
  });
  testWidgets(
      'a valve question accepts a new command or cancel without drawing',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj rura metr zawór DN50');
    await _say(t, 'anuluj');
    expect(IsoNotebookController.active, isNull);
    await _say(t, 'narysuj rura metr zawór DN50');
    await _say(t, 'NDS manganu');
    expect(find.textContaining('0,05 mg/m³'), findsWidgets);
    await _say(t, 'kulowy');
    expect(IsoNotebookController.active, isNull);
  });
  testWidgets(
      'a valve question keeps its sequence after an incomplete drawing reply',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj rura metr w prawo zawór DN50');
    await _say(t, 'rura metr');
    expect(find.textContaining('Jaki rodzaj zaworu'), findsOneWidget);
    expect(IsoNotebookController.active, isNull);
    await _say(t, 'kulowy');
    expect(IsoNotebookController.active!.hasContent, isTrue);
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(1));
  });

  testWidgets('bare append choice and English append keep the existing sheet',
      (t) async {
    await _boot(t);
    await _say(t, 'Draw pipe one meter right');
    final id = (await t.runAsync(() => IsoDrawingDao().latest()))!.id;
    await _say(t, 'narysuj rura metr w górę');
    expect(find.textContaining('Na arkuszu jest już rysunek'), findsOneWidget);
    await _say(t, 'dorysuj');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(2));
    await _say(t, 'Append pipe one meter right');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(3));
    expect((await t.runAsync(() => IsoDrawingDao().latest()))!.id, id);
    await _say(t, 'undo');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(2));
  });

  testWidgets(
      'an invalid new voice drawing leaves the active sketch and next append intact',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj rura metr w prawo');
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final before = await t.runAsync(() => IsoDrawingDao().latest());
    await _say(t, 'narysuj rura metr w prawo rura metr w lewo');
    await _say(t, 'nowy');
    expect(IsoNotebookController.active!.hasContent, isTrue);
    final after = await t.runAsync(() => IsoDrawingDao().latest());
    expect(after!.id, before!.id);
    expect(after.json, before.json);
    await _say(t, 'dorysuj rura metr w górę');
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final stored = await t.runAsync(() => IsoDrawingDao().latest());
    expect(stored!.id, before.id);
    final items = (jsonDecode(stored.json) as Map)['items'] as List;
    expect(items.where((x) => x['kind'] == 'seg' && x['tool'] == 'pipe'),
        hasLength(2));
  });
  testWidgets(
      'a failed save keeps the drawing and releases the assistant for retry',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj rura metr w prawo');
    await t.runAsync(() async {
      final db = await AppDatabase.get();
      await db.execute(
          "CREATE TRIGGER iso_test_fail BEFORE UPDATE ON iso_drawings BEGIN SELECT RAISE(FAIL, 'test write failure'); END");
    });
    addTearDown(() async {
      final db = await AppDatabase.get();
      await db.execute('DROP TRIGGER IF EXISTS iso_test_fail');
    });
    await IsoNotebookController.active!.draw(
        const [IsoPipe(dir: IsoDir.up, lengthMm: 1000)],
        stepDelay: Duration.zero);
    final before = IsoNotebookController.active!.debugPipeAxisTags.toList();
    await _say(t, 'narysuj rura metr w prawo');
    await _say(t, 'nowy');
    expect(IsoNotebookController.active!.debugPipeAxisTags, before);
    expect(find.textContaining('Bieżący arkusz pozostaje otwarty'),
        findsOneWidget);
    expect(
        t.widget<TextField>(find.byKey(const Key('assistant-command'))).enabled,
        isTrue);
    await t.runAsync(() async {
      final db = await AppDatabase.get();
      await db.execute('DROP TRIGGER iso_test_fail');
    });
    await _say(t, 'dorysuj rura metr w prawo');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(3));
    expect(t.takeException(), isNull);
  });
  for (final e in {
    'wstaw symbol kolana 45 DN50': 'elbow45',
    'umieść symbol trójnika DN80 na DN50': 'tee'
  }.entries) {
    testWidgets(
        'voice places ${e.value} as an editable symbol and undo removes it',
        (t) async {
      await _boot(t);
      await _say(t, e.key);
      expect(IsoNotebookController.active!.hasContent, isTrue);
      await t.pump(const Duration(milliseconds: 600));
      await flushTestDatabase(t);
      final saved = await t.runAsync(() => IsoDrawingDao().latest());
      final items = (jsonDecode(saved!.json) as Map)['items'] as List;
      final symbol = items.singleWhere((x) => x['tool'] == e.value);
      expect(items.where((x) => x['tool'] == 'pipe'), isEmpty);
      if (e.value == 'elbow45') {
        expect(symbol['dn'], 50);
        expect(symbol['elbowSubtype'], 'lr45');
        expect(symbol['cteMm'], isoStandardElbowCteMm(50, 'lr45'));
      } else {
        expect(symbol['dn'], 80);
        expect(symbol['dnOut'], 50);
        expect(symbol['elbowSubtype'], isNull);
      }
      expect(await FeedbackStore.instance.list(), isEmpty);
      await _say(t, 'cofnij');
      expect(IsoNotebookController.active!.hasContent, isFalse);
    });
  }
  testWidgets(
      'invalid tee sizes do not change the drawing or create a gap report',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj symbol trójnika DN50 na DN80');
    expect(IsoNotebookController.active!.hasContent, isFalse);
    await _say(t, 'narysuj symbol kolana 45 DN0');
    expect(IsoNotebookController.active!.hasContent, isFalse);
    expect(await FeedbackStore.instance.list(), isEmpty);
    await _say(t, 'narysuj symbol kolana 45 DN50 w górę');
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.singleWhere((x) => x['tool'] == 'elbow45')['dir'],
        IsoDir.up.index);
  });
  testWidgets(
      'voice routes a branch from the tee and undo preserves the main run',
      (t) async {
    await _boot(t);
    await _say(t, 'narysuj rura metr w prawo');
    await _say(t, 'dorysuj symbol trójnika DN80 na DN50');
    await _say(t, 'dorysuj rura metr w prawo');
    await _say(t, 'od trójnika rura metr');
    expect(find.textContaining('W jakim kierunku ma iść odgałęzienie'),
        findsOneWidget);
    await _say(t, 'w prawo');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(2));
    await _say(t, 'w górę');
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    final pipes = items.where((x) => x['tool'] == 'pipe').toList();
    final tee = items.singleWhere((x) => x['tool'] == 'tee');
    expect(pipes, hasLength(3));
    expect(pipes.last['a'], tee['pos']);
    expect(tee['dnOut'], 50);
    await _say(t, 'w dół');
    expect(find.textContaining('Zmieniłem kierunek odgałęzienia.'),
        findsOneWidget);
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final changed = await t.runAsync(() => IsoDrawingDao().latest());
    final changedItems = (jsonDecode(changed!.json) as Map)['items'] as List;
    expect(changedItems.singleWhere((x) => x['tool'] == 'tee')['dir'],
        IsoDir.down.index);
    await _say(t, 'cofnij');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(2));
  });
  testWidgets(
      'one command draws a tee run, supports a branch, and undoes each complete command',
      (t) async {
    await _boot(t);
    await _say(
        t, 'narysuj rura metr w prawo trójnik DN80 na DN50 rura metr w prawo');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(2));
    await _say(t, 'od trójnika rura metr w górę');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(3));
    await _say(t, 'cofnij');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(2));
    await _say(t, 'cofnij');
    expect(IsoNotebookController.active!.hasContent, isFalse);
    expect(await FeedbackStore.instance.list(), isEmpty);
  });
  testWidgets('jedna rozmowa otwiera ISO, rysuje, dorysowuje i cofa',
      (tester) async {
    seedFreshInstall();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const CutListApp());
    await settle(tester);
    expect(find.byTooltip('Powiedz, co zrobić'), findsOneWidget);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    Future<void> say(String text) async {
      await tester.enterText(find.byKey(const Key('assistant-command')), text);
      await tester.tap(find.byKey(const Key('assistant-go')));
      await settle(tester);
    }

    await say('narysuj rura metr w prawo kolano w górę rura metr');
    expect(IsoNotebookController.active, isNotNull);
    expect(IsoNotebookController.active!.hasContent, isTrue);
    expect(find.textContaining('Narysowałem: rury 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(tester);
    final stored = await tester.runAsync(() => IsoDrawingDao().latest());
    expect(stored, isNotNull);
    final items = (jsonDecode(stored!.json) as Map)['items'] as List;
    expect(items.where((x) => x['kind'] == 'seg' && x['tool'] == 'pipe'),
        hasLength(2));
    await say('w dół');
    expect(find.textContaining('Zmieniłem kierunek ostatniego kolana.'),
        findsOneWidget);
    await say('dorysuj rura metr');
    expect(find.textContaining('Narysowałem: rury 1'), findsOneWidget);
    await say('cofnij');
    expect(find.text('Cofnąłem ostatni krok rysunku.'), findsOneWidget);
    await appNavigatorKey.currentState!.maybePop();
    await settle(tester);
    expect(IsoNotebookController.active, isNotNull);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    expect(find.text('Cofnąłem ostatni krok rysunku.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    AssistantPanelController.instance.setExpanded(false);
  });
}
