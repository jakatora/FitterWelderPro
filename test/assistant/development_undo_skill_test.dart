import 'package:flutter/material.dart';
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'global_pipe_slope_flow_test.dart' show settle;
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/features/cone_layout/cone_layout_page.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say;
import 'cone_layout_skill_test.dart' as cone;
import 'eccentric_cone_skill_test.dart' as eccentric;
import 'transition_layout_skill_test.dart' as transition;

void main() {
  useTestDatabase();
  for (final entry in [
    (cone.command, cone.payload),
    (eccentric.command, eccentric.fields),
    (transition.command, transition.fields)
  ]) {
    testWidgets('undo restores native ${entry.$2['shape']} geometry',
        (t) async {
      await mount(t,
          home: const ConeLayoutPage(),
          interpret: (_) async => throw StateError('Undo is local'));
      await say(t, entry.$1);
      final b = ToolBridge.instance;
      final before = Map<String, Object?>.of(b.inputFields('cone_layout')!);
      await say(t, 'Ustaw wysokosc 600 mm');
      expect(b.inputFields('cone_layout'), isNot(before));
      await say(t, 'Cofnij');
      expect(b.inputFields('cone_layout'), before);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('undo follows cross-shape history and stops after manual edit',
      (t) async {
    await mount(t,
        home: const ConeLayoutPage(),
        interpret: (_) async => throw StateError('Undo is local'));
    await say(t, cone.command);
    final b = ToolBridge.instance;
    final original = Map<String, Object?>.of(b.inputFields('cone_layout')!);
    await say(t, eccentric.command);
    final eccentricInputs =
        Map<String, Object?>.of(b.inputFields('cone_layout')!);
    await say(t, transition.command);
    await say(t, 'Cofnij');
    expect(b.inputFields('cone_layout'), eccentricInputs);
    await say(t, 'Cofnij');
    expect(b.inputFields('cone_layout'), original);
      await say(t, 'Ustaw wysokosc 600 mm');
    final field = find.byKey(const ValueKey('cone-H'));
    await t.ensureVisible(field);
    await t.enterText(field, '777');
    await settle(t);
    final manual = Map<String, Object?>.of(b.inputFields('cone_layout')!);
    await say(t, 'Cofnij');
    expect(b.inputFields('cone_layout'), manual);
    expect(manual['height_mm'], 777);
  });
  testWidgets('undo history cannot cross account service replacement',
      (t) async {
    final previous = AccountService.instance;
    final replacement = AccountService.forTesting(
        MockClient((_) async => throw StateError('No network')));
    addTearDown(() {
      AccountService.instance = previous;
      replacement.dispose();
    });
    await mount(t,
        home: const ConeLayoutPage(),
        interpret: (_) async => throw StateError('Undo is local'));
    await say(t, cone.command);
      await say(t, 'Ustaw wysokosc 600 mm');
    final b = ToolBridge.instance;
    final current = Map<String, Object?>.of(b.inputFields('cone_layout')!);
    AccountService.instance = replacement;
    final result =
        await (b.current! as ModuleActionHandle).performAction('undo');
    expect(result.completed, false);
    expect(b.inputFields('cone_layout'), current);
  });
}
