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
import 'package:cut_list_app/services/weld_timer_service.dart';
import '../support/fake_weld_timer_effects.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/domain/welding/electrode_exposure.dart';

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
    await say(tester,
        'Oblicz t8/5 Q 1 kJ/mm temperatura 100 C grubość 20 mm wypełnienie');
    expect(ToolBridge.instance.activeToolId, 'cooling_time');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('cool-verdict-notSet')), 300,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('cool-list')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.byKey(const ValueKey('cool-verdict-notSet')), findsOneWidget);
    await say(tester, 'Oblicz CE C 0,2 Mn 1 pozostałe zero grubość 15 mm');
    expect(ToolBridge.instance.activeToolId, 'heat_input');
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    await say(tester, 'nie sprawdzaj przewodów spawalniczych');
    expect(ToolBridge.instance.activeToolId, 'heat_input');
    await say(tester,
        'Sprawdź przewody spawalniczy 25 m masowy 25 m 200 A 60% otoczenie 30 C próg 4 V przekrój 35 mm²');
    expect(ToolBridge.instance.activeToolId, 'power_source');
    final powerRoute = appRoutes.top;
    await say(tester,
        'Dobierz przewody spawalniczy 25 m masowy 25 m 200 A 60% otoczenie 30 C próg 4 V');
    expect(appRoutes.top, same(powerRoute));
    await say(
        tester, 'Oblicz cykl pracy tabliczka 200 A 60% prąd spawania 150 A');
    expect(ToolBridge.instance.activeToolId, 'power_source');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ps-current')))
            .controller!
            .text,
        '150.0');
    await say(tester, 'Dobierz wolfram DCEN nierdzewna 75 A');
    expect(ToolBridge.instance.activeToolId, 'tungsten');
    expect(
        tester
            .widget<TextField>(find.byWidgetPredicate((w) =>
                w is TextField &&
                w.decoration?.labelText == 'Prąd spawania (A, DC-)'))
            .controller!
            .text,
        '75.0');
    await say(tester,
        'Oblicz moment dokręcania 5/8 cala B7 smar miedziany preload 50%');
    expect(ToolBridge.instance.activeToolId, 'bolt_torque');
    await say(tester, 'nie znajdź WPS w słowniku');
    expect(ToolBridge.instance.activeToolId, 'bolt_torque');
    await say(tester, 'Znajdź w słowniku WPS');
    expect(ToolBridge.instance.activeToolId, 'glossary');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('glossary-search')))
            .controller!
            .text,
        contains('WPS'));
    await say(tester, 'nie narysuj rury 2 metry w prawo');
    expect(ToolBridge.instance.activeToolId, 'glossary');
    await close(tester);
  });
  testWidgets(
      'chat controls the shared timer and refreshes the visible timer tab',
      (tester) async {
    var now = DateTime(2026, 10, 21, 12);
    final service = WeldTimerService(
        now: () => now,
        effects: FakeEffects(notificationsSupported: false),
        startTicker: (_) => null,
        observeLifecycle: false);
    WeldTimerService.instance = service;
    await boot(tester);
    unawaited(openTool(
        appNavigatorKey.currentState!.overlay!.context, toolById('dn_mm')!));
    await settle(tester);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    await say(tester, 'Uruchom chłodzenie 2,5 minuty');
    expect(ToolBridge.instance.activeToolId, 'welder_calculators');
    expect(
        DefaultTabController.of(tester.element(find.byType(TabBar))).index, 2);
    expect(service.target!.inSeconds, 150);
    expect(service.maxInterpassC, isNull);
    now = now.add(const Duration(seconds: 10));
    await say(tester, 'Zatrzymaj timer');
    expect(service.running, isFalse);
    expect(service.elapsed.inSeconds, 10);
    await say(tester, 'Uruchom chłodzenie 3 minuty');
    expect(service.target!.inSeconds, 150);
    expect(find.textContaining('Obecny timer ma postęp.'), findsOneWidget);
    await say(tester, 'tak zastąp timer');
    expect(service.target!.inSeconds, 180);
    expect(service.running, isTrue);
    expect(
        find.byWidgetPredicate(
            (w) => w is TextField && w.controller?.text == '3'),
        findsWidgets);
    await say(tester, 'nie zatrzymuj timera');
    expect(service.running, isTrue);
    await say(tester, 'Zatrzymaj timer');
    await close(tester);
    service.dispose();
    WeldTimerService.instance = WeldTimerService();
  });
  testWidgets('chat opens defect advice with exact supplied filters',
      (tester) async {
    await boot(tester);
    unawaited(openTool(
        appNavigatorKey.currentState!.overlay!.context, toolById('dn_mm')!));
    await settle(tester);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    await say(tester, 'Pokaż przyczyny porowatości MAG stal węglowa');
    expect(ToolBridge.instance.activeToolId, 'weld_defects');
    expect(find.byKey(const ValueKey('defects-selected')), findsOneWidget);
    expect(find.textContaining('Wada spoiny: Porowatość'), findsOneWidget);
    expect(find.textContaining('Proces: 135/138 MAG'), findsOneWidget);
    await say(tester, 'porowatość TIG 60 A');
    expect(find.text('Jaki materiał spawasz?'), findsOneWidget);
    expect(ToolBridge.instance.activeToolId, 'weld_defects');
    await say(tester, 'stal nierdzewna');
    expect(find.textContaining('Proces: 141 TIG'), findsOneWidget);
    await close(tester);
  });
  testWidgets('chat shows the ISO limit then assesses a supplied measurement',
      (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    await say(tester,
        'Pokaż limit ISO 5817 2014 5011 poziom B t 10 mm spoina czołowa');
    expect(ToolBridge.instance.activeToolId, 'iso5817');
    expect(find.textContaining('Pokazuję limit; nie oceniam'), findsOneWidget);
    await say(tester, 'a pomiar 0,4 mm');
    expect(ToolBridge.instance.activeToolId, 'iso5817');
    expect(find.textContaining('Pomiar: h = 0,4 mm'), findsOneWidget);
    expect(find.textContaining('Wynik:'), findsOneWidget);
    await close(tester);
  });
  testWidgets(
      'chat opens electrode reference without creating an exposure batch',
      (tester) async {
    await boot(tester);
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(kElectrodeBatchesPrefsKey);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    await say(tester, 'Pokaż limit ekspozycji E7018 H4R z piecyka model 2020');
    expect(ToolBridge.instance.activeToolId, 'electrode_exposure');
    expect(find.byKey(const ValueKey('electrode-assistant-reference')),
        findsOneWidget);
    expect(prefs.getString(kElectrodeBatchesPrefsKey), before);
    await close(tester);
  });
  testWidgets('chat selects filler in the actual module', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    await say(tester, 'Pokaż dobór spoiwa 304L i 316L MMA');
    expect(ToolBridge.instance.activeToolId, 'filler_selector');
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('filler-process-mma')))
            .selected,
        isTrue);
    expect(find.textContaining('316L'), findsWidgets);
    await close(tester);
  });
  testWidgets(
      'chat distinguishes sling label material from abrasive stripe code',
      (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(tester);
    await say(tester, 'Pokaż niebieską etykietę zawiesia');
    expect(ToolBridge.instance.activeToolId, 'rigging');
    expect(
        find.byKey(const ValueKey('rig-assistant-reference')), findsOneWidget);
    expect(find.textContaining('poliester (PES)'), findsWidgets);
    await say(tester, 'Pokaż czerwony pasek na tarczy');
    expect(ToolBridge.instance.activeToolId, 'grinding');
    expect(
        find.byKey(const ValueKey('gr-assistant-reference')), findsOneWidget);
    expect(find.textContaining('80 m/s'), findsWidgets);
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
