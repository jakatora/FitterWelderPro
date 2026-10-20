import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/app_navigator.dart';

class _DelayedScreen extends StatefulWidget {
  const _DelayedScreen();
  @override
  State<_DelayedScreen> createState() => _DelayedState();
}

class _DelayedState extends State<_DelayedScreen>
    with ToolHandleHost<_DelayedScreen> {
  Timer? timer;
  String value = 'loading';
  @override
  String get toolId => 'delayed';
  @override
  Set<String> get supportedFields => {'value'};
  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 200), () {
      setState(() => value = 'preferences');
      markReady();
    });
  }

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    setState(() => value = fields['value'] as String);
    return {};
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(value));
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}

void main() {
  setUp(ToolBridge.reset);
  testWidgets(
      'uchwyt jest gotowy dopiero po ustawieniach; nie nadpisują polecenia',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _DelayedScreen()));
    var completed = false;
    final wait = ToolBridge.instance.whenReady('delayed').then((h) {
      completed = true;
      return h;
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(completed, isFalse);
    await tester.pump(const Duration(milliseconds: 101));
    final handle = await wait;
    expect(completed, isTrue);
    await handle!.apply({'value': 'command'});
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('command'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(ToolBridge.instance.current, isNull);
  });
  testWidgets('dialog w trakcie wczytywania anuluje ustawianie pól',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        navigatorKey: appNavigatorKey,
        navigatorObservers: [appRoutes],
        home: const _DelayedScreen()));
    final operation =
        showInModule(const ShowInModule('delayed', {'value': 'command'}));
    unawaited(showDialog<void>(
        context: appNavigatorKey.currentState!.overlay!.context,
        builder: (_) => const AlertDialog(content: Text('Dialog'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(await operation, ShowOutcome.blockedByPopup);
    appNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('preferences'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('timeout kończy czekanie bez osieroconego timera',
      (tester) async {
    final wait = ToolBridge.instance
        .whenReady('absent', timeout: const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 31));
    expect(await wait, isNull);
  });
  testWidgets('ukryta kopia tego samego modułu nie odbiera polecenia',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
        MaterialApp(navigatorKey: key, home: const _DelayedScreen()));
    await tester.pump(const Duration(milliseconds: 201));
    final first = ToolBridge.instance.current;
    unawaited(key.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const _DelayedScreen())));
    await tester.pumpAndSettle();
    final second = await ToolBridge.instance.whenReady('delayed');
    expect(identical(second, first), isFalse);
    await second!.apply({'value': 'visible'});
    await tester.pump();
    expect(find.text('visible'), findsOneWidget);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(identical(ToolBridge.instance.current, first), isTrue);
    expect(find.text('preferences'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
