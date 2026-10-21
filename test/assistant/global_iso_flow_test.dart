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
