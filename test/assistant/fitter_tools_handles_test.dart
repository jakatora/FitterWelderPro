import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';

const cases = <String, Map<String, Object?>>{
  'slope_cut': {'od_mm': 100, 'slope_pct': 2},
  'elbow_cut': {
    'base_angle_deg': 90,
    'extrados_mm': 180,
    'intrados_mm': 90,
    'target_angle_deg': 45
  },
  'elbow_rotation': {'od_mm': 100, 'degrees': 90},
  'insert': {
    'mode': '1.5D',
    'od_mm': 60.3,
    'angle_deg': 45,
    'offset_mm': 300,
    'gap_mm': 3
  },
  'reducer': {
    'd1_mm': 114.3,
    'd2_mm': 60.3,
    'length_mm': 102,
    'target_mm': 88.9
  },
  'pipe_weight': {
    'od_mm': 60.3,
    'wall_mm': 3.91,
    'material': 'ss316',
    'length_mm': 1000,
    'quantity': 2
  },
  'bevel': {
    'wall_mm': 10,
    'angle_deg': 60,
    'root_face_mm': 1,
    'gap_mm': 0,
    'joint': 'v',
    'convention': 'grooveIncluded'
  },
  'thermal_expansion': {'length_m': 50, 'delta_k': 100, 'material': 'ss304L'},
};
const results = {
  'slope_cut': '2.00 mm',
  'elbow_cut': '90.0 mm',
  'elbow_rotation': '78.5 mm',
  'insert': '348.3 mm',
  'reducer': '48.0 mm',
  'pipe_weight': '5.541 kg/m',
  'bevel': '5.20 mm',
  'thermal_expansion': '80.0 mm',
};
Future<void> mount(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 2400));
  await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          navigatorKey: appNavigatorKey,
          navigatorObservers: [appRoutes],
          home: const Scaffold(body: Text('Start')))));
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in cases.entries) {
    testWidgets(
        '${entry.key}: opens, fills and calculates; rejection preserves input',
        (tester) async {
      await mount(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final showing =
          showInModule(ShowInModule(entry.key, entry.value), explicit: true);
      await tester.pumpAndSettle();
      expect(await showing, ShowOutcome.opened);
      expect(find.byType(FitterToolsScreen), findsOneWidget);
      expect(find.text(results[entry.key]!), findsWidgets);
      final handle = ToolBridge.instance.current!;
      expect(handle.toolId, entry.key);
      expect(await handle.apply({}), isNotEmpty);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller!.text)
          .toList();
      final invalid = Map<String, Object?>.of(entry.value);
      final numberKey = invalid.keys.firstWhere((k) => invalid[k] is num);
      invalid[numberKey] = double.nan;
      expect(await handle.apply(invalid), isNotEmpty);
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .map((f) => f.controller!.text)
              .toList(),
          fields);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
      'explicit command switches tabs within the same route; unsolicited one offers a chip',
      (tester) async {
    await mount(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var pending = showInModule(ShowInModule('slope_cut', cases['slope_cut']!),
        explicit: true);
    await tester.pumpAndSettle();
    expect(await pending, ShowOutcome.opened);
    final state = tester.state(find.byType(FitterToolsScreen));
    expect(
        await showInModule(
            ShowInModule('thermal_expansion', cases['thermal_expansion']!)),
        ShowOutcome.offeredChip);
    expect(ToolBridge.instance.activeToolId, 'slope_cut');
    for (final entry in cases.entries.toList().reversed) {
      pending =
          showInModule(ShowInModule(entry.key, entry.value), explicit: true);
      await tester.pumpAndSettle();
      expect(await pending, ShowOutcome.appliedInPlace, reason: entry.key);
      expect(tester.state(find.byType(FitterToolsScreen)), same(state));
      expect(ToolBridge.instance.activeToolId, entry.key);
      expect(find.text(results[entry.key]!), findsWidgets);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
