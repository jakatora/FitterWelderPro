import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';
import 'global_pipe_slope_flow_test.dart' show settle, say;
import 'rolling_offset_current_test.dart' show input, geometry;

void main() {
  useTestDatabase();
  testWidgets(
      'common rolling chat asks gap, preserves native edits, refuses unsupported cuts and clears actual page',
      (t) async {
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
    await say(t, '$geometry DN100');
    expect(find.textContaining('Jaka szczelina spoiny'), findsOneWidget);
    await say(t, '3 mm');
    expect(ToolBridge.instance.current?.toolId, 'rolling_offset');
    expect(find.text('573.1'), findsOneWidget);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.ensureVisible(input('Rise'));
    await t.enterText(input('Rise'), '600');
    await settle(t);
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    await say(t, 'zmień kąt na 30 stopni');
    final b = ToolBridge.instance;
    expect(b.inputFields('rolling_offset')!['rise_mm'], 600);
    expect(b.inputFields('rolling_offset')!['dn'], 100);
    expect(b.inputFields('rolling_offset')!['gap_mm'], 3);
    expect(find.text('1354.8'), findsOneWidget);
    await say(t, 'a szczelina 2 mm');
    expect(b.inputFields('rolling_offset')!['rise_mm'], 600);
    expect(b.inputFields('rolling_offset')!['gap_mm'], 2);
    expect(await FeedbackStore.instance.list(), isEmpty);
    final before = Map.of(b.inputFields('rolling_offset')!);
    await say(t, 'nie zmieniaj DN na 50');
    expect(b.inputFields('rolling_offset'), before);
    await say(t, '$geometry DN100 SR szczelina 3 mm');
    expect(find.textContaining('nie kolana SR/3D'), findsOneWidget);
    expect(b.inputFields('rolling_offset'), before);
    final reports = await FeedbackStore.instance.list();
    expect(reports, hasLength(1));
    expect(reports.single.skill, 'rolling.offset');
    await say(t, '$geometry SR tylko geometria');
    expect(b.inputFields('rolling_offset')!['dn'], isNull);
    expect(await FeedbackStore.instance.list(), hasLength(1));
    await say(t, 'wyczyść rolling offset');
    expect(b.inputFields('rolling_offset')!['rise_mm'], isNull);
    expect(b.inputFields('rolling_offset')!['gap_mm'], 0);
    expect(t.takeException(), isNull);
  });
}
