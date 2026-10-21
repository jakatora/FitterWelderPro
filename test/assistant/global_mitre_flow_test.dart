import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/root_gate.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/widgets/readout.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await flushTestDatabase(t);
    await t.pump(const Duration(milliseconds: 200));
  }
  await t.pumpAndSettle();
}

Future<void> say(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('assistant-command')), text);
  await t.tap(find.byKey(const Key('assistant-go')));
  await settle(t);
}

void main() {
  useTestDatabase();
  testWidgets(
      'common assistant asks, opens real mitre module, applies correction and keeps invalid input out',
      (t) async {
    final calls = <String>[];
    await mount(t, home: const RootGate(), interpret: (request) async {
      final text = request['text'] as String;
      calls.add(text);
      final inputs = (request['context'] as Map)['inputs'] as Map;
      expect(inputs['od_mm'], 168.3);
      expect(inputs['angle_deg'], 90);
      final (welds, radius) = switch (text) {
        'a spoiny 4' => (4, 252.45),
        'a promień 50 mm' => (4, 50.0),
        'a spoiny 12' => (12, 300.0),
        _ => throw StateError('Unexpected AI request: $text'),
      };
      expect(inputs['welds'], text == 'a spoiny 4' ? 3 : 4);
      expect(inputs['radius_mm'], text == 'a spoiny 12' ? 300 : 252.45);
      return AiCommandPlan(
          'execute',
          [
            AiCommandStep('mitre.bend',
                'Oblicz kolano segmentowe OD 168.3 mm kąt 90 stopni $welds spoiny promień $radius mm prosty 0 mm')
          ],
          '');
    });
    expect(
        await FeedbackConsent.instance.grant(now: DateTime.utc(2026, 10, 21)),
        isTrue);
    await say(t, 'oblicz kolano segmentowe');
    expect(find.textContaining('Jaka średnica zewnętrzna OD'), findsOneWidget);
    expect(ToolBridge.instance.current?.toolId, isNot('mitre_bend'));
    await say(t, '168,3 mm');
    await say(t, '90');
    await say(t, '3');
    await say(t, '252,45 mm');
    await say(t, '0 mm');
    expect(ToolBridge.instance.current?.toolId, 'mitre_bend');
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('mitre-od')))
            .controller!
            .text,
        '168.3');
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('mitre-radius')))
            .controller!
            .text,
        '252.45');
    expect(find.textContaining('kąt cięcia 15°'), findsWidgets);
    await say(t, 'a spoiny 4');
    expect(
        t
            .widget<ChoiceChip>(find.byKey(const ValueKey('mitre-welds-4')))
            .selected,
        isTrue);
    await say(t, 'a promień 50 mm');
    expect(find.textContaining('Jaki promień po osi'), findsOneWidget);
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('mitre-radius')))
            .controller!
            .text,
        '252.45');
    await say(t, '300 mm');
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('mitre-radius')))
            .controller!
            .text,
        '300.0');
    await say(t, 'a spoiny 12');
    expect(
        t
            .widget<ChoiceChip>(find.byKey(const ValueKey('mitre-welds-12')))
            .selected,
        isTrue);
    expect(
        find.descendant(of: find.byType(Readout), matching: find.text('3,75')),
        findsOneWidget);
    expect(await FeedbackStore.instance.list(), isEmpty,
        reason:
            'supported calculation and invalid user dimensions are not missing capabilities');
    expect(calls, ['a spoiny 4', 'a promień 50 mm', 'a spoiny 12']);
    expect(t.takeException(), isNull);
  });
}
