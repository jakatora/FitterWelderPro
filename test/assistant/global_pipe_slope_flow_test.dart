import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';

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

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
void main() {
  useTestDatabase();
  testWidgets(
      'common chat follows actual slope inputs, changes inverse mode and repairs invalid input without false reports',
      (t) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    seedFreshInstall();
    ToolBridge.reset();
    expect(
        await FeedbackConsent.instance.grant(now: DateTime.utc(2026, 10, 21)),
        true);
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await settle(t);
      AssistantPanelController.instance.setExpanded(false);
    });
    await t.pumpWidget(const CutListApp());
    await settle(t);
    await t.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(t);
    await say(t, 'spadek 1% na 6 metrów');
    expect(ToolBridge.instance.current?.toolId, 'pipe_slope');
    await t.tap(find.text('Kopiuj wynik'));
    await settle(t);
    expect(copied, ['60.0']);
    expect(find.textContaining('Skopiowano: Wznios'), findsWidgets);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.ensureVisible(field('Długość rury'));
    await t.enterText(field('Długość rury'), '12000');
    await settle(t);
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    await say(t, 'zmień nachylenie na 2%');
    expect(
        t.widget<TextField>(field('Długość rury')).controller!.text, '12000.0');
    expect(
        t.widget<TextField>(field('Wznios (Rise)')).controller!.text, '240.0');
    await say(t, 'a wznios 120 mm');
    expect(ToolBridge.instance.inputFields('pipe_slope')!['mode'],
        'slope_from_lr');
    expect(
        double.parse(t.widget<TextField>(field('Nachylenie')).controller!.text),
        1);
    await say(t, 'zmień długość na minus 1 metr');
    expect(find.textContaining('Podaj jedną dodatnią'), findsOneWidget);
    expect(
        t.widget<TextField>(field('Długość rury')).controller!.text, '12000.0');
    await say(t, '6 metrów');
    expect(
        t.widget<TextField>(field('Długość rury')).controller!.text, '6000.0');
    expect(
        double.parse(t.widget<TextField>(field('Nachylenie')).controller!.text),
        2);
    await say(t, 'zmień nachylenie na dwa stopnie');
    expect(find.textContaining('Podaj jedną dodatnią'), findsOneWidget);
    await say(t, '3%');
    expect(t.widget<TextField>(field('Nachylenie')).controller!.text, '3.0');
    expect(
        t.widget<TextField>(field('Wznios (Rise)')).controller!.text, '180.0');
    expect(copied, ['60.0']);
    await say(t, 'wyczyść spadek rury');
    expect(
        t.widget<TextField>(field('Długość rury')).controller!.text, isEmpty);
    await say(t, 'skopiuj wynik');
    expect(copied, ['60.0']);
    expect(find.textContaining('Brak aktualnego wyniku'), findsOneWidget);
    await say(t, 'oblicz');
    expect(find.textContaining('Podaj długość w rzucie'), findsOneWidget);
    await say(t, '6 m');
    await say(t, 'wznios 60 mm');
    expect(
        double.parse(t.widget<TextField>(field('Nachylenie')).controller!.text),
        1);
    expect(await FeedbackStore.instance.list(), isEmpty);
    await say(t, 'pokaż wzory');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Źródło wzorów'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
