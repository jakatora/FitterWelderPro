import 'dart:async';

import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/utils/clipboard_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'fitter_tools_handles_test.dart' as native show cases, results, mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

Future<void> openNative(WidgetTester t, String id) async {
  ToolBridge.reset();
  await native.mount(t);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await t.binding.setSurfaceSize(null);
  });
  final opening =
      showInModule(ShowInModule(id, native.cases[id]!), explicit: true);
  await t.pumpAndSettle();
  expect(await opening, ShowOutcome.opened);
}

Map<String, Object?> weightInputs() =>
    ToolBridge.instance.inputFields('pipe_weight')!;
const copy =
    AiCommandStep('calculator.action', 'Skopiuj wyniki bieżącego kalkulatora');
const clear =
    AiCommandStep('calculator.action', 'Wyczyść pola bieżącego kalkulatora');

void main() {
  useTestDatabase();
  late List<String> copied;
  var failClipboard = false;
  Completer<void>? clipboardGate;
  setUp(() {
    copied = [];
    failClipboard = false;
    clipboardGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (failClipboard) throw PlatformException(code: 'unavailable');
        copied.add((call.arguments as Map)['text'] as String);
        final gate = clipboardGate;
        if (gate != null) await gate.future;
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  const edited = {
    'slope_cut': '120',
    'elbow_cut': '200',
    'elbow_rotation': '120',
    'insert': '114.3',
    'reducer': '168.3',
    'pipe_weight': '114.3',
    'bevel': '12',
    'thermal_expansion': '60'
  };
  for (final id in native.cases.keys) {
    testWidgets(
        '$id copies actual results, tracks manual edits and shares toolbar clearing',
        (t) async {
      await openNative(t, id);
      final bridge = ToolBridge.instance;
      final first = await bridge.performModuleAction(id, 'copy');
      expect(first.completed, isTrue, reason: first.message.pl);
      expect(copied, hasLength(1));
      expect(copied.single, contains(native.results[id]!));
      final original = copied.single;
      final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields, isNotEmpty);
      final firstField = find.byWidgetPredicate((w) =>
          w is TextField && identical(w.controller, fields.first.controller));
      await t.enterText(firstField, edited[id]!);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('fitter-copy-results')));
      await t.pumpAndSettle();
      expect(copied, hasLength(2));
      expect(copied.last, isNot(original));
      final current = bridge.inputFields(id);
      expect(
          (await bridge.performModuleAction(id, 'copy', field: 'password'))
              .completed,
          isFalse);
      expect(
          (await bridge.performModuleAction(id, 'unknown')).completed, isFalse);
      expect(bridge.inputFields(id), current);
      expect(copied, hasLength(2));
      await t.enterText(firstField, '.');
      await t.pumpAndSettle();
      expect((await bridge.performModuleAction(id, 'copy')).completed, isFalse);
      expect(copied, hasLength(2),
          reason: 'Invalid input must not copy an old cached result.');
      await t.tap(find.byKey(const Key('fitter-clear-inputs')));
      await t.pumpAndSettle();
      expect(fields.every((f) => f.controller!.text.isEmpty), isTrue);
      expect((await bridge.performModuleAction(id, 'copy')).completed, isFalse);
      expect(copied, hasLength(2));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
      'wrong tab, popup, hidden route and a changed lazy tab cannot act on another form',
      (t) async {
    await openNative(t, 'pipe_weight');
    final bridge = ToolBridge.instance;
    final handle = bridge.current! as TabbedToolHandle;
    final before = weightInputs();
    expect((await bridge.performModuleAction('slope_cut', 'clear')).completed,
        isFalse);
    final dialog = showDialog<void>(
        context: appNavigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Dialog')));
    await t.pumpAndSettle();
    expect((await bridge.performModuleAction('pipe_weight', 'copy')).completed,
        isFalse);
    expect((await bridge.performModuleAction('pipe_weight', 'clear')).completed,
        isFalse);
    appNavigatorKey.currentState!.pop();
    await dialog;
    await t.pumpAndSettle();
    final cover = appNavigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cover'))));
    await t.pumpAndSettle();
    expect((await bridge.performModuleAction('pipe_weight', 'clear')).completed,
        isFalse);
    appNavigatorKey.currentState!.pop();
    await cover;
    await t.pumpAndSettle();
    expect(weightInputs(), before);
    handle.selectTool('elbow_rotation');
    final pending = (handle as ModuleActionHandle).performAction('clear');
    handle.selectTool('pipe_weight');
    await t.pumpAndSettle();
    expect((await pending).completed, isFalse);
    expect(weightInputs(), before);
    expect(copied, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'exact common chat copy and clear execute locally and do not create capability reports',
      (t) async {
    var calls = 0;
    await mount(t, home: const FitterToolsScreen(initialTab: 5),
        interpret: (_) async {
      calls++;
      throw StateError('Exact actions are local');
    });
    expect(
        await ToolBridge.instance.current!.apply(native.cases['pipe_weight']!),
        isEmpty);
    await settle(t);
    await say(t, 'Skopiuj wyniki');
    expect(copied.single, contains('5.541 kg/m'));
    await say(t, 'Wyczyść pola');
    expect(weightInputs()['od_mm'], isNull);
    expect(weightInputs()['length_mm'], isNull);
    await say(t, 'Skopiuj wyniki');
    expect(copied, hasLength(1));
    expect(calls, 0);
    expect(await FeedbackStore.instance.list(), isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('natural copy and mocked speech operate on current native values',
      (t) async {
    var calls = 0;
    final speech = FixtureSpeech();
    await mount(t, home: const FitterToolsScreen(initialTab: 5), speech: speech,
        interpret: (r) async {
      calls++;
      expect(((r['context'] as Map)['inputs'] as Map)['od_mm'], 88.9);
      return const AiCommandPlan('execute', [copy], '');
    });
    await ToolBridge.instance.current!.apply(native.cases['pipe_weight']!);
    await settle(t);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    final field = find
        .descendant(
            of: find.byType(FitterToolsScreen),
            matching: find.byType(TextField))
        .first;
    await t.enterText(field, '88.9');
    await settle(t);
    final value =
        t.widgetList<CopyOnLongPress>(find.byType(CopyOnLongPress)).first.value;
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    await t.tap(find.byKey(const Key('assistant-mic')));
    await t.pump();
    speech.emit('Żebym nie musiał przepisywać, wrzuć te wyniki do schowka');
    await settle(t);
    expect(calls, 1);
    expect(copied.single, contains(value));
    expect(weightInputs()['od_mm'], 88.9);
    expect(t.takeException(), isNull);
  });

  for (final connector in ['potem', 'i']) {
    testWidgets(
        'calculate $connector copy $connector clear executes ordered native actions',
        (t) async {
      var calls = 0;
      await mount(t, home: const Scaffold(body: Text('Start')),
          interpret: (_) async {
        calls++;
        return const AiCommandPlan(
            'execute',
            [
              AiCommandStep('pipe.weight',
                  'Oblicz ciężar rury OD 60.3 mm ścianka 3.91 mm długość 1000 mm ilość 2 materiał 316L'),
              copy,
              clear
            ],
            '');
      });
      await say(t,
          'Oblicz ciężar rury OD 60.3 mm ścianka 3.91 mm długość 1000 mm ilość 2 materiał 316L $connector skopiuj wyniki $connector wyczyść pola');
      expect(calls, 1);
      expect(copied.single, contains('5.541 kg/m'));
      expect(weightInputs()['od_mm'], isNull);
      expect(weightInputs()['quantity'], isNull);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('compound without consent performs none of its partial actions',
      (t) async {
    await mount(t,
        home: const FitterToolsScreen(initialTab: 5),
        consent: false,
        interpret: (_) async => throw StateError('No consent'));
    final before = weightInputs();
    await say(t,
        'Oblicz ciężar rury OD 60.3 mm ścianka 3.91 mm materiał 316L i skopiuj wyniki');
    expect(weightInputs(), before);
    expect(copied, isEmpty);
  });

  testWidgets(
      'copy failure cancels queued clearing and preserves the invalid form',
      (t) async {
    await mount(t,
        home: const FitterToolsScreen(initialTab: 5),
        interpret: (_) async =>
            const AiCommandPlan('execute', [copy, clear], ''));
    await ToolBridge.instance.current!.apply(native.cases['pipe_weight']!);
    await settle(t);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.enterText(
        find
            .descendant(
                of: find.byType(FitterToolsScreen),
                matching: find.byType(TextField))
            .first,
        '.');
    await settle(t);
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    final before = weightInputs();
    await say(t, 'Najpierw skopiuj wyniki, potem wyczyść pola');
    expect(weightInputs(), before);
    expect(weightInputs()['wall_mm'], 3.91);
    expect(copied, isEmpty);
  });

  testWidgets(
      'clipboard platform failure reports no completion and cancels the remaining plan',
      (t) async {
    await mount(t,
        home: const FitterToolsScreen(initialTab: 5),
        interpret: (_) async =>
            const AiCommandPlan('execute', [copy, clear], ''));
    await ToolBridge.instance.current!.apply(native.cases['pipe_weight']!);
    await settle(t);
    final before = weightInputs();
    failClipboard = true;
    await say(t, 'Skopiuj wyniki, potem wyczyść pola');
    expect(copied, isEmpty);
    expect(weightInputs(), before);
    expect(find.textContaining('Nie udało się skopiować'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('late interpretation cannot clear a newer manual edit',
      (t) async {
    final pending = Completer<AiCommandPlan>();
    var calls = 0;
    await mount(t, home: const FitterToolsScreen(initialTab: 5),
        interpret: (_) {
      calls++;
      return pending.future;
    });
    await ToolBridge.instance.current!.apply(native.cases['pipe_weight']!);
    await settle(t);
    await t.enterText(find.byKey(const Key('assistant-command')),
        'Możesz wyczyścić wszystkie pola tego kalkulatora?');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    AssistantPanelController.instance.setExpanded(false);
    await t.pump();
    await t.enterText(
        find
            .descendant(
                of: find.byType(FitterToolsScreen),
                matching: find.byType(TextField))
            .first,
        '88.9');
    await t.pump();
    pending.complete(const AiCommandPlan('execute', [clear], ''));
    await settle(t);
    expect(weightInputs()['od_mm'], 88.9);
    expect(copied, isEmpty);
  });

  for (final source in [
    'Skopiuj proszę te wyniki do schowka',
    'Wyczyść projekt wraz z zapisami'
  ]) {
    testWidgets(
        'model cannot turn another explicit action into clearing inputs: $source',
        (t) async {
      var calls = 0;
      await mount(t, home: const FitterToolsScreen(initialTab: 5),
          interpret: (_) async {
        calls++;
        return const AiCommandPlan('execute', [clear], '');
      });
      await ToolBridge.instance.current!.apply(native.cases['pipe_weight']!);
      await settle(t);
      final before = weightInputs();
      await say(t, source);
      expect(calls, 1);
      expect(weightInputs(), before);
      expect(copied, isEmpty);
    });
  }

  testWidgets(
      'copy recalculates native results after controller autofill and refuses overflow',
      (t) async {
    await openNative(t, 'pipe_weight');
    final controller =
        t.widget<TextField>(find.byType(TextField).first).controller!;
    expect(
        t.widgetList<CopyOnLongPress>(find.byType(CopyOnLongPress)).first.value,
        '5.541 kg/m');
    controller.text = '88.9';
    expect(
        (await ToolBridge.instance.performModuleAction('pipe_weight', 'copy'))
            .completed,
        isTrue);
    await t.pumpAndSettle();
    final current =
        t.widgetList<CopyOnLongPress>(find.byType(CopyOnLongPress)).first.value;
    expect(current, isNot('5.541 kg/m'));
    expect(copied.single, contains(current));
    controller.text = '9' * 308;
    expect(
        (await ToolBridge.instance.performModuleAction('pipe_weight', 'copy'))
            .completed,
        isFalse);
    await t.pumpAndSettle();
    expect(copied, hasLength(1));
    expect(t.takeException(), isNull);
  });

  testWidgets('clearing insert also clears the retained hidden manual radius',
      (t) async {
    await openNative(t, 'insert');
    final dropdown =
        find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>);
    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(find.text('Ręcznie — wpisz R').last);
    await t.pumpAndSettle();
    final radius = find.byWidgetPredicate((w) =>
        w is TextField &&
        w.decoration?.labelText == 'Promień kolanka R — oś gięcia (mm)');
    await t.enterText(radius, '123');
    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(find.text('1.5D — długi promień LR (B16.9) ← typowy').last);
    await t.pumpAndSettle();
    expect(
        (await ToolBridge.instance.performModuleAction('insert', 'clear'))
            .completed,
        isTrue);
    await t.pumpAndSettle();
    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(find.text('Ręcznie — wpisz R').last);
    await t.pumpAndSettle();
    expect(ToolBridge.instance.inputFields('insert')!['radius_mm'], isNull);
    expect(t.widget<TextField>(radius).controller!.text, isEmpty);
  });

  for (final (source, step) in [
    ('Wyczyść formularz redukcji', clear),
    ('Copy the bevel calculator results', copy),
    ('Wyczyść formularz czasu stygnięcia', clear),
    ('Skopiuj hasło do konta', copy),
    ('Clear only wall thickness', clear),
    ('Wyczyść pole średnicy', clear),
  ]) {
    testWidgets(
        'a model cannot redirect another named scope to the visible calculator: $source',
        (t) async {
      var calls = 0;
      await mount(t, home: const FitterToolsScreen(initialTab: 5),
          interpret: (_) async {
        calls++;
        return AiCommandPlan('execute', [step], '');
      });
      await ToolBridge.instance.current!.apply(native.cases['pipe_weight']!);
      await settle(t);
      final before = weightInputs();
      await say(t, source);
      expect(calls, 1);
      expect(weightInputs(), before);
      expect(copied, isEmpty);
    });
  }

  testWidgets(
      'an explicit target can be opened and cleared while the other cached form is preserved',
      (t) async {
    var calls = 0;
    await mount(t, home: const FitterToolsScreen(initialTab: 5),
        interpret: (_) async {
      calls++;
      return const AiCommandPlan('execute',
          [AiCommandStep('tool.open', 'Otwórz redukcję'), clear], '');
    });
    final tabs = ToolBridge.instance.current! as TabbedToolHandle;
    tabs.selectTool('reducer');
    await settle(t);
    await tabs.apply(native.cases['reducer']!);
    tabs.selectTool('pipe_weight');
    await settle(t);
    await tabs.apply(native.cases['pipe_weight']!);
    await settle(t);
    final before = weightInputs();
    await say(t, 'Wyczyść formularz redukcji');
    expect(calls, 1);
    expect(ToolBridge.instance.activeToolId, 'reducer');
    expect(ToolBridge.instance.inputFields('reducer')!['d1_mm'], isNull);
    tabs.selectTool('pipe_weight');
    await settle(t);
    expect(weightInputs(), before);
    expect(copied, isEmpty);
  });

  for (final change in ['tab', 'input', 'consent']) {
    testWidgets(
        'a $change change during delayed native copying cancels later clearing',
        (t) async {
      await mount(t,
          home: const FitterToolsScreen(initialTab: 5),
          interpret: (_) async =>
              const AiCommandPlan('execute', [copy, clear], ''));
      final tabs = ToolBridge.instance.current! as TabbedToolHandle;
      tabs.selectTool('reducer');
      await settle(t);
      await tabs.apply(native.cases['reducer']!);
      final reducerBefore = ToolBridge.instance.inputFields('reducer');
      tabs.selectTool('pipe_weight');
      await settle(t);
      await tabs.apply(native.cases['pipe_weight']!);
      await settle(t);
      final weightBefore = weightInputs();
      final gate = Completer<void>();
      clipboardGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await t.enterText(find.byKey(const Key('assistant-command')),
          'Skopiuj wyniki, potem wyczyść pola');
      await t.tap(find.byKey(const Key('assistant-go')));
      for (var i = 0; i < 20 && copied.isEmpty; i++) {
        await flushTestDatabase(t);
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(copied, hasLength(1));
      if (change == 'tab') {
        tabs.selectTool('reducer');
        await t.pump(const Duration(milliseconds: 500));
      } else if (change == 'input') {
        AssistantPanelController.instance.setExpanded(false);
        await t.pump(const Duration(milliseconds: 200));
        final field = find
            .descendant(
                of: find.byType(FitterToolsScreen),
                matching: find.byType(TextField))
            .hitTestable()
            .first;
        await t.enterText(field, '88.9');
        await t.pump();
      } else {
        await LegalConsent.instance.clear();
      }
      gate.complete();
      await settle(t);
      if (change == 'tab') {
        expect(ToolBridge.instance.inputFields('reducer'), reducerBefore);
        tabs.selectTool('pipe_weight');
        await settle(t);
      }
      if (change == 'input') {
        expect(weightInputs()['od_mm'], 88.9);
        expect(weightInputs()['wall_mm'], 3.91);
      } else {
        expect(weightInputs(), weightBefore);
      }
      AssistantPanelController.instance.setExpanded(true);
      await settle(t);
      expect(find.textContaining('Pozostałe kroki anulowano'), findsWidgets);
      expect(copied, hasLength(1));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
      'English toolbar shares native results and fits 320px with large text',
      (t) async {
    ToolBridge.reset();
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await t.binding.setSurfaceSize(null);
    });
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.en),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!),
            home: const FitterToolsScreen(initialTab: 5))));
    await t.pumpAndSettle();
    await ToolBridge.instance.current!.apply(native.cases['pipe_weight']!);
    await t.pumpAndSettle();
    for (final key in ['fitter-copy-results', 'fitter-clear-inputs']) {
      final size = t.getSize(find.byKey(Key(key)));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    await t.tap(find.byTooltip('Copy results'));
    await t.pumpAndSettle();
    expect(copied.single, startsWith('Pipe weight\n'));
    expect(copied.single, contains('Mass per metre: 5.541 kg/m'));
    await t.tap(find.byTooltip('Clear inputs'));
    await t.pumpAndSettle();
    expect(weightInputs()['od_mm'], isNull);
    expect(t.takeException(), isNull);
  });
}
