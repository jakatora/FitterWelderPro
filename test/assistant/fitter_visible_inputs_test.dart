import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'fitter_tools_handles_test.dart' show cases, mount;

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
Future<void> open(WidgetTester t, String id) async {
  await mount(t);
  addTearDown(() => t.binding.setSurfaceSize(null));
  final pending = showInModule(ShowInModule(id, cases[id]!), explicit: true);
  await t.pumpAndSettle();
  await pending;
}

void main() {
  for (final entry in cases.entries) {
    testWidgets(
        '${entry.key} exports real selected-tab inputs and manual edits',
        (t) async {
      await mount(t);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final showing =
          showInModule(ShowInModule(entry.key, entry.value), explicit: true);
      await t.pumpAndSettle();
      await showing;
      final snapshot = ToolBridge.instance.inputFields(entry.key)!;
      for (final field in entry.value.entries) {
        expect(snapshot[field.key], field.value, reason: field.key);
      }
      final request = assistantAiRequest(
          text: 'Zmień tylko jeden parametr',
          context: AssistantContext(
              lang: AppLanguage.pl, modules: ToolBridge.instance),
          skills: buildSkillCatalog());
      expect((request['context'] as Map)['active_tool'], entry.key);
      expect((request['context'] as Map)['inputs'], snapshot);
      final numeric = t.widgetList<TextField>(find.byType(TextField)).first;
      final original = numeric.controller!.text;
      await t.enterText(find.byWidget(numeric), '');
      await t.pumpAndSettle();
      final updated = ToolBridge.instance.inputFields(entry.key)!;
      expect(updated, isNot(equals(snapshot)));
      expect(numeric.controller!.text, isEmpty);
      await t.enterText(find.byType(TextField).first, original);
      await t.pumpAndSettle();
      expect(ToolBridge.instance.inputFields(entry.key), snapshot);
      final tab = ToolBridge.instance.current! as TabbedToolHandle;
      final other = entry.key == 'pipe_weight' ? 'slope_cut' : 'pipe_weight';
      expect(tab.selectTool(other), isTrue);
      await t.pumpAndSettle();
      expect(ToolBridge.instance.inputFields(entry.key), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
  }
  testWidgets(
      'insert exposes only its selected radius mode and native gap semantics',
      (t) async {
    await open(t, 'insert');
    final dropdown =
        find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>);
    await t.tap(dropdown);
    await t.pumpAndSettle();
    expect(ToolBridge.instance.inputFields('insert'), isNull);
    await t.tap(find.text('Ręcznie — wpisz R').last);
    await t.pumpAndSettle();
    await t.enterText(field('Promień kolanka R — oś gięcia (mm)'), '123');
    await t.pumpAndSettle();
    expect(ToolBridge.instance.inputFields('insert'), {
      'mode': 'manual',
      'radius_mm': 123,
      'angle_deg': 45,
      'offset_mm': 300,
      'gap_mm': 3
    });
    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(find.text('1.5D — długi promień LR (B16.9) ← typowy').last);
    await t.pumpAndSettle();
    expect(ToolBridge.instance.inputFields('insert'), cases['insert']);
    final gap = find.byWidgetPredicate((w) =>
        w is TextField &&
        (w.decoration?.labelText?.contains('Szczelina') ?? false));
    await t.enterText(gap, '');
    await t.pumpAndSettle();
    expect(ToolBridge.instance.inputFields('insert')!['gap_mm'], 0);
    await t.enterText(gap, '.');
    await t.pumpAndSettle();
    expect(ToolBridge.instance.inputFields('insert')!['gap_mm'], isNull);
  });
  testWidgets(
      'expansion context preserves actual signed temperature precision beyond rounded delta display',
      (t) async {
    await open(t, 'thermal_expansion');
    await t.enterText(field('T montażu (°C)'), '-20.04');
    await t.enterText(field('T pracy (°C)'), '-20');
    await t.pumpAndSettle();
    expect(t.widget<TextField>(field('ΔT (°C)')).controller!.text, '0.0');
    final current = ToolBridge.instance.inputFields('thermal_expansion')!;
    expect(current['temperature_start_c'], -20.04);
    expect(current['temperature_end_c'], -20);
    expect(current['delta_k'], closeTo(0.04, 1e-12));
    expect(current['length_m'], 50);
    expect(current['material'], 'ss304L');
  });
}
