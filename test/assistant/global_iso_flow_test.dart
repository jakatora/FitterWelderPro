import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
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

void main() {
  useTestDatabase();
  setUp(() async {
    final db = await AppDatabase.get();
    await db.delete('iso_drawings');
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
