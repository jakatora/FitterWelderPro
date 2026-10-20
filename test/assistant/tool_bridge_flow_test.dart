import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/domain/welding/heat_input.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/screens/dn_mm_screen.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> say(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('assistant-command')), text);
  await tester.tap(find.byKey(const Key('assistant-go')));
  await settle(tester);
}

void main() {
  useTestDatabase();
  setUp(() {
    seedFreshInstall();
    ToolBridge.reset();
    AssistantPanelController.instance.setExpanded(false);
  });
  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const CutListApp());
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    expect(ToolBridge.instance.current, isNull);
  }

  testWidgets(
      'kafel i mikrofon wracają do jednej rozmowy; DN aktualizuje tę samą trasę',
      (tester) async {
    await boot(tester);
    await tester.ensureVisible(find.text('ASYSTENT'));
    await tester.tap(find.text('ASYSTENT'));
    await settle(tester);
    expect(find.byType(AiChatScreen), findsOneWidget);
    expect(appRoutes.toolId, isNull);
    await say(tester, 'Jaka jest średnica DN40?');
    expect(appRoutes.toolId, 'dn_mm');
    final route = appRoutes.top;
    final handle = ToolBridge.instance.current;
    expect(handle?.toolId, 'dn_mm');
    await say(tester, 'a dla DN50?');
    expect(identical(appRoutes.top, route), isTrue);
    expect(identical(ToolBridge.instance.current, handle), isTrue);
    expect(find.text('60.30'), findsOneWidget);
    await tester.tap(find.byTooltip('Zwiń'));
    await settle(tester);
    await appNavigatorKey.currentState!.maybePop();
    await settle(tester);
    await tester.ensureVisible(find.text('ASYSTENT'));
    await tester.tap(find.text('ASYSTENT'));
    await settle(tester);
    expect(find.textContaining('60,3'), findsWidgets);
    await close(tester);
  });
  testWidgets('kolejny moduł zastępuje przejściowy ekran asystenta',
      (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    await say(tester, 'średnica DN40');
    final firstRoute = appRoutes.top;
    await say(tester, 'ścianka DN50 sch 40');
    expect(appRoutes.toolId, 'wall_thickness');
    expect(firstRoute!.isActive, isFalse);
    expect(ToolBridge.instance.current?.toolId, 'wall_thickness');
    await close(tester);
  });
  testWidgets(
      'ręcznie otwarty kalkulator nie jest porywany; pola i wynik liczy jego domena',
      (tester) async {
    await boot(tester);
    unawaited(openTool(appNavigatorKey.currentState!.overlay!.context,
        toolById('heat_input')!));
    await settle(tester);
    final route = appRoutes.top;
    Future<ShowOutcome>? operation;
    operation = showInModule(const ShowInModule(
        'heat_input', {'volts': 24, 'amps': 230, 'travel_mm_min': 150}));
    await settle(tester);
    expect(await operation, ShowOutcome.appliedInPlace);
    final expected = heatInputKJPerMm(
        volts: 24,
        amps: 230,
        travelMmPerMin: 150,
        standard: HeatInputStandard.en1011,
        efficiency: 0.8)!;
    await tester.scrollUntilVisible(find.text(expected.toStringAsFixed(2)), 250,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    await settle(tester);
    expect(find.text(expected.toStringAsFixed(2)), findsOneWidget);
    final rejected = await ToolBridge.instance.current!
        .apply({'amps': double.nan, 'volts': 20});
    expect(rejected, contains('amps'));
    expect(find.textContaining(expected.toStringAsFixed(2)), findsWidgets);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    await say(tester, 'Oblicz energię liniową TIG EN 24 V 230 A 150 mm/min');
    expect(identical(appRoutes.top, route), isTrue);
    expect(find.textContaining('Energia liniowa TIG: 1,32'), findsOneWidget);
    expect(find.text('1.32'), findsOneWidget);
    await say(tester, 'ustaw 250 A');
    expect(find.textContaining('Ustawiam parametry kalkulatora: 250 A'),
        findsOneWidget);
    expect(find.text('1.44'), findsOneWidget);
    await say(
        tester, 'Oblicz heat input TIG EN 24 V 230 A 150 mm/min sprawność 80%');
    expect(find.textContaining('Energia liniowa TIG: 1,77'), findsOneWidget);
    expect(find.text('1.77'), findsOneWidget);
    await say(tester, 'średnica DN40');
    expect(identical(appRoutes.top, route), isTrue);
    expect(find.byType(DnMmScreen), findsNothing);
    expect(find.byKey(const Key('assistant-show-module')), findsOneWidget);
    unawaited(showDialog<void>(
        context: appNavigatorKey.currentState!.overlay!.context,
        builder: (_) => const AlertDialog(content: Text('Dialog'))));
    await settle(tester);
    expect(
        await showInModule(const ShowInModule('dn_mm', {'dn': 50}),
            explicit: true),
        ShowOutcome.blockedByPopup);
    appNavigatorKey.currentState!.pop();
    await settle(tester);
    expect(identical(appRoutes.top, route), isTrue);
    await close(tester);
  });
  testWidgets(
      'explicit calculations switch modules; negated commands never execute',
      (tester) async {
    await boot(tester);
    unawaited(openTool(appNavigatorKey.currentState!.overlay!.context,
        toolById('heat_input')!));
    await settle(tester);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    final original = appRoutes.top;
    await say(tester, 'nie przeliczaj 2 cale na mm');
    expect(appRoutes.top, same(original));
    expect(find.text('Nie wykonuję tego polecenia.'), findsOneWidget);
    await say(tester, 'Przelicz 2 cale na mm');
    expect(ToolBridge.instance.activeToolId, 'unit_converter');
    expect(find.text('50.800'), findsOneWidget);
    await say(tester,
        'Oblicz masę rury OD 60,3 mm ścianka 3,91 mm długość 1 m 316L ilość 2');
    expect(ToolBridge.instance.activeToolId, 'pipe_weight');
    expect(find.textContaining('Łącznie 2 szt.: 11,08 kg'), findsOneWidget);
    await say(tester,
        'Oblicz fazowanie V ścianka 10 mm kąt rowka 60 próg 1 mm szczelina 0 mm');
    expect(ToolBridge.instance.activeToolId, 'bevel');
    final calculatorRoute = appRoutes.top;
    await say(tester, 'Oblicz dylatację długość 50 m delta 100 C 304L');
    expect(ToolBridge.instance.activeToolId, 'thermal_expansion');
    expect(appRoutes.top, same(calculatorRoute));
    await say(tester,
        'Skróć redukcję duża 100 mm mała 50 mm długość 200 mm docelowa 75 mm');
    expect(ToolBridge.instance.activeToolId, 'reducer');
    expect(appRoutes.top, same(calculatorRoute));
    await say(tester,
        'Oblicz wstawkę promień 100 mm offset 300 mm kąt 90 stopni szczelina 2 mm');
    expect(ToolBridge.instance.activeToolId, 'insert');
    expect(appRoutes.top, same(calculatorRoute));
    expect(find.text('96.0 mm'), findsOneWidget);
    await say(tester, 'nie dobieraj filtra TIG 100 A');
    expect(ToolBridge.instance.activeToolId, 'insert');
    await say(tester, 'Dobierz filtr przyłbicy TIG 100 A');
    expect(ToolBridge.instance.activeToolId, 'shade');
    expect(find.byKey(const ValueKey('shade-en')), findsOneWidget);
    await say(tester, 'nie narysuj rury 2 metry w prawo');
    expect(ToolBridge.instance.activeToolId, 'shade');
    await close(tester);
  });
  testWidgets(
      'missing table is queued privately once; invalid input does not create a bug report',
      (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    await say(tester, 'rura sanitarna DIN 11850 seria III DN50');
    var reports = await FeedbackStore.instance.list();
    expect(reports, hasLength(1));
    expect(reports.single.tool, 'sanitary_tube');
    expect(reports.single.skill, 'sanitary.tube');
    await say(tester, 'rura sanitarna DIN 11850 seria III DN50');
    expect(await FeedbackStore.instance.list(), hasLength(1));
    await say(tester, 'rura sanitarna BPE OD minus 50,8 mm');
    expect(await FeedbackStore.instance.list(), hasLength(1));
    await close(tester);
  });
}
