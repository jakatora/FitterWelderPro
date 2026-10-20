import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabase();
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
