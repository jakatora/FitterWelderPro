import 'dart:async';
import 'dart:convert';

import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/features/cooling_time/cooling_time_page.dart';
import 'package:cut_list_app/features/hardness/hardness_page.dart';
import 'package:cut_list_app/features/mitre_bend/mitre_bend_page.dart';
import 'package:cut_list_app/features/power_source/power_source_page.dart';
import 'package:cut_list_app/features/shade/shade_page.dart';
import 'package:cut_list_app/screens/bolt_torque_screen.dart';
import 'package:cut_list_app/screens/quick_converter_screen.dart';
import 'package:cut_list_app/screens/tungsten_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const cooling = <String, Object?>{
  'q_kj_mm': .96,
  'input_mode': 'parameters',
  'process': 'GMAW',
  'volts': 28,
  'amps': 250,
  'travel_mm_min': 350,
  'preheat_c': 100,
  'thickness_mm': 20,
  'shape': 'buttFillRun',
  'window_min_s': 5,
  'window_max_s': 15,
};
const duty = <String, Object?>{
  'plate': [
    {'current_a': 200, 'duty_pct': 35},
    {'current_a': 160, 'duty_pct': 60},
    {'current_a': 130, 'duty_pct': 100},
  ],
  'weld_current_a': 180,
};
const cable = <String, Object?>{
  'cable_mode': 'check',
  'weld_current_a': 160,
  'weld_lead_m': 12,
  'return_lead_m': 18,
  'section_mm2': 35,
  'duty_pct': 60,
  'ambient_c': 30,
  'drop_limit_v': 2,
};

Map<String, Object?> inputs(String id) => ToolBridge.instance.inputFields(id)!;
Future<void> edit(WidgetTester t, Finder field, String value) async {
  AssistantPanelController.instance.setExpanded(false);
  await settle(t);
  await t.enterText(field, value);
  await settle(t);
  AssistantPanelController.instance.setExpanded(true);
  await settle(t);
}

void main() {
  useTestDatabase();

  testWidgets(
      'power relative edit sends manually edited current and keeps cable installation',
      (t) async {
    var calls = 0;
    await mount(t, home: const PowerSourcePage(), interpret: (r) async {
      calls++;
      final visible = (r['context'] as Map)['inputs'] as Map;
      expect(visible['weld_current_a'], 170);
      expect(visible['plate_1_current_a'], 200);
      expect(visible['weld_lead_m'], 25);
      expect(
          visible.values
              .every((v) => v == null || v is num || v is String || v is bool),
          isTrue);
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('power.duty',
                'Cykl pracy tabliczka 200 A 35% 160 A 60% 130 A 100% prąd spawania 180 A')
          ],
          '');
    });
    await edit(t, find.byKey(const Key('ps-current')), '170');
    await say(t, 'Zmień tylko prąd spawania na 180 A');
    expect(calls, 1);
    final actual = inputs('power_source');
    expect(actual['weld_current_a'], 180);
    expect(actual['weld_lead_m'], 25);
    expect(actual['return_lead_m'], 25);
    expect(actual['duty_pct'], 60);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'power preservation is explicit, symmetric and rejects malformed flags atomically',
      (t) async {
    await mount(t,
        home: const PowerSourcePage(),
        interpret: (_) async =>
            const AiCommandPlan('clarify', [], 'Podaj pole.'));
    final handle = ToolBridge.instance.current!;
    expect(
        await handle.apply({...cable, 'preserve_other_inputs': true}), isEmpty);
    await settle(t);
    expect(inputs('power_source')['plate_1_current_a'], 200);
    final before = inputs('power_source');
    expect(await handle.apply({...duty, 'preserve_other_inputs': 'yes'}),
        contains('preserve_other_inputs'));
    expect(inputs('power_source'), before);
    expect(
        await handle.apply({...duty, 'preserve_other_inputs': true}), isEmpty);
    await settle(t);
    expect(inputs('power_source')['weld_lead_m'], 12);
    expect(await handle.apply(duty), isEmpty);
    await settle(t);
    expect(inputs('power_source')['weld_lead_m'], isNull);
    expect(await handle.apply(cable), isEmpty);
    await settle(t);
    expect(inputs('power_source')['plate_1_current_a'], isNull);
  });

  testWidgets(
      'cooling thickness edit retains actual parameter mode and supplied window',
      (t) async {
    var calls = 0;
    await mount(t, home: const CoolingTimePage(), interpret: (r) async {
      calls++;
      final actual = (r['context'] as Map)['inputs'] as Map;
      expect(actual['input_mode'], 'parameters');
      expect(actual['thickness_mm'], 25);
      expect(actual['q_kj_mm'], closeTo(.96, 1e-12));
      expect(actual['process'], 'GMAW');
      expect(actual['window_source'], 'visible_form_unverified');
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('cooling.t85',
                'Oblicz t8/5 Q 0.96 kJ/mm temperatura 100 C grubość 30 mm wypełnienie min 5 s max 15 s')
          ],
          '');
    });
    expect(await ToolBridge.instance.current!.apply(cooling), isEmpty);
    await settle(t);
    await edit(t, find.byKey(const Key('cool-d')), '25');
    await say(t, 'Zmień tylko grubość na 30 mm i przelicz t8/5');
    expect(calls, 1);
    final actual = inputs('cooling_time');
    expect(actual['thickness_mm'], 30);
    expect(actual['input_mode'], 'parameters');
    expect(actual['volts'], 28);
    expect(actual['amps'], 250);
    expect(actual['travel_mm_min'], 350);
    expect(actual['window_min_s'], 5);
    expect(actual['window_max_s'], 15);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'cooling invalid parameters and inconsistent Q cannot partially mutate form',
      (t) async {
    await mount(t,
        home: const CoolingTimePage(),
        interpret: (_) async =>
            const AiCommandPlan('clarify', [], 'Podaj pole.'));
    final handle = ToolBridge.instance.current!;
    expect(await handle.apply(cooling), isEmpty);
    await settle(t);
    final before = inputs('cooling_time');
    for (final invalid in [
      {...cooling, 'process': 141},
      {...cooling, 'q_kj_mm': 1.2},
      {...cooling, 'volts': -1},
      {...cooling, 'input_mode': 'heat_input'},
    ]) {
      expect(await handle.apply(invalid), isNotEmpty);
      expect(inputs('cooling_time'), before);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'cooling direct parameters stay editable in native parameter mode without AI',
      (t) async {
    var calls = 0;
    await mount(t, home: const CoolingTimePage(), interpret: (_) async {
      calls++;
      return const AiCommandPlan('clarify', [], 'Nie oczekiwano AI.');
    });
    await say(t,
        'Oblicz t8/5 MAG EN 28 V 250 A 350 mm/min temperatura 100 C grubość 30 mm wypełnienie min 5 s max 15 s');
    expect(calls, 0);
    expect(inputs('cooling_time')['input_mode'], 'parameters',
        reason: t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '));
    expect(inputs('cooling_time')['q_kj_mm'], closeTo(.96, 1e-12));
    expect(inputs('cooling_time')['thickness_mm'], 30);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'hardness AI receives actual converter value without measurement contents',
      (t) async {
    var calls = 0;
    await mount(t, home: const HardnessPage(), interpret: (r) async {
      calls++;
      final actual = (r['context'] as Map)['inputs'] as Map;
      expect(actual, {
        'value': 300,
        'scale': 'hv',
        'material': 'carbonLowAlloy',
        'has_measurements': false
      });
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('hardness.convert',
                'Przelicz twardość 150 HV na HB stal niestopowa')
          ],
          '');
    });
    await edit(t, find.byKey(const Key('hard-conv-value')), '300');
    await say(t, 'Przelicz połowę obecnej twardości HV na HB');
    expect(calls, 1);
    expect(inputs('hardness')['value'], 150);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'shade exports only active gas fields and tracks a manual flow change',
      (t) async {
    var calls = 0;
    await mount(t, home: const ShadePage(), interpret: (r) async {
      calls++;
      expect((r['context'] as Map)['inputs'],
          {'process': 'oxyCutting', 'flow_lh': 1700, 'thickness_mm': 20});
      return const AiCommandPlan('clarify', [], 'Który parametr zmienić?');
    });
    expect(
        await ToolBridge.instance.current!.apply(
            {'process': 'oxyCutting', 'flow_lh': 1500, 'thickness_mm': 20}),
        isEmpty);
    await settle(t);
    await edit(t, find.byKey(const Key('shade-flow')), '1700');
    await say(t, 'Pomóż mi zmienić obecne ustawienia filtra');
    expect(calls, 1);
    expect(inputs('shade').containsKey('current_a'), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'tungsten exports current only, excluding stamp and joint identifiers',
      (t) async {
    var calls = 0;
    await mount(t, home: const TungstenScreen(), interpret: (r) async {
      calls++;
      expect((r['context'] as Map)['inputs'], {'amps': 180});
      return const AiCommandPlan('clarify', [], 'Jak zmienić prąd?');
    });
    await edit(
        t,
        find
            .descendant(
                of: find.byType(TungstenScreen),
                matching: find.byType(TextField))
            .first,
        '180');
    await say(t, 'Pomóż mi zmienić obecne ustawienia wolframu');
    expect(calls, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'bolt context reflects native preload slider rather than last assistant packet',
      (t) async {
    var calls = 0;
    await mount(t, home: const BoltTorqueScreen(), interpret: (r) async {
      calls++;
      expect(((r['context'] as Map)['inputs'] as Map)['preload_fraction'], .6);
      return const AiCommandPlan(
          'clarify', [], 'Jak zmienić napięcie wstępne?');
    });
    final handle = ToolBridge.instance.current!;
    expect(
        await handle.apply({
          'bolt_size': '3/4',
          'grade': 'B7',
          'lube': 'dry',
          'preload_fraction': .55
        }),
        isEmpty);
    await settle(t);
    final slider = t.widget<Slider>(find.byType(Slider));
    slider.onChanged!(.6);
    await settle(t);
    await say(t, 'Zmień tylko obecne napięcie wstępne śruby');
    expect(calls, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'mitre factor radius follows manual OD; blank input never exports a fallback zero',
      (t) async {
    await mount(t,
        home: const MitreBendPage(),
        interpret: (_) async =>
            const AiCommandPlan('clarify', [], 'Podaj pole.'));
    await edit(t, find.byKey(const Key('mitre-od')), '200');
    expect(inputs('mitre_bend')['radius_mm'], 300);
    expect(inputs('mitre_bend')['radius_mode'], 'factor');
    await edit(t, find.byKey(const Key('mitre-od')), '');
    expect(inputs('mitre_bend')['od_mm'], isNull);
    expect(inputs('mitre_bend')['radius_mm'], isNull);
    expect(() => jsonEncode(inputs('mitre_bend')), returnsNormally);
    await edit(t, find.byKey(const Key('mitre-od')), '17${'0' * 307}');
    expect(inputs('mitre_bend')['od_mm'], 1.7e308);
    expect(inputs('mitre_bend')['radius_mm'], isNull);
    expect(() => jsonEncode(inputs('mitre_bend')), returnsNormally);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'converter relative change reads selected tab after a manual edit',
      (t) async {
    var calls = 0;
    await mount(t, home: const QuickConverterScreen(), interpret: (r) async {
      calls++;
      expect((r['context'] as Map)['inputs'],
          {'kind': 'temperature', 'value': 80, 'from': '°C'});
      return const AiCommandPlan('execute',
          [AiCommandStep('units.convert', 'Przelicz 40 C na F')], '');
    });
    final handle = ToolBridge.instance.current!;
    expect(await handle.apply({'kind': 'pressure', 'value': 4, 'from': 'bar'}),
        isEmpty);
    await settle(t);
    expect(
        await handle.apply({'kind': 'temperature', 'value': 60, 'from': '°C'}),
        isEmpty);
    await settle(t);
    await edit(
        t,
        find
            .descendant(
                of: find.byType(QuickConverterScreen),
                matching: find.byType(TextField))
            .hitTestable()
            .first,
        '80');
    await say(t, 'Przelicz połowę obecnej temperatury na F');
    expect(calls, 1);
    expect(inputs('unit_converter'),
        {'kind': 'temperature', 'value': 40, 'from': '°C'});
    expect(find.textContaining('104.000'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  for (final text in [
    'Przelicz twardość 100 HV mniej na HB stal niestopowa',
    'Convert hardness 100 HV less to HB carbon steel',
    'Przelicz twardość 300-100 HV na HB stal niestopowa',
  ]) {
    testWidgets(
        'relative hardness is interpreted before native execution: $text',
        (t) async {
      var calls = 0;
      await mount(t, home: const HardnessPage(), interpret: (r) async {
        calls++;
        expect(((r['context'] as Map)['inputs'] as Map)['value'], 300);
        return const AiCommandPlan(
            'execute',
            [
              AiCommandStep('hardness.convert',
                  'Przelicz twardość 200 HV na HB stal niestopowa')
            ],
            '');
      });
      await edit(t, find.byKey(const Key('hard-conv-value')), '300');
      await say(t, text);
      expect(calls, 1);
      expect(inputs('hardness')['value'], 200);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
      'relative hardness cannot execute a partial numeric match without AI consent',
      (t) async {
    var calls = 0;
    await mount(t, home: const HardnessPage(), consent: false,
        interpret: (_) async {
      calls++;
      throw StateError('No consent');
    });
    final before = inputs('hardness');
    await say(t, 'Przelicz twardość 100 HV mniej na HB stal niestopowa');
    expect(calls, 0);
    expect(inputs('hardness'), before);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'mock speech uses visible power inputs and executes the interpreted edit',
      (t) async {
    final speech = FixtureSpeech();
    var calls = 0;
    await mount(t, home: const PowerSourcePage(), speech: speech,
        interpret: (r) async {
      calls++;
      expect(((r['context'] as Map)['inputs'] as Map)['weld_current_a'], 170);
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('power.duty',
                'Cykl pracy tabliczka 200 A 35% 160 A 60% 130 A 100% prąd spawania 180 A')
          ],
          '');
    });
    await edit(t, find.byKey(const Key('ps-current')), '170');
    await t.tap(find.byKey(const Key('assistant-mic')));
    await t.pump();
    speech.emit('Zmień tylko prąd spawania na sto osiemdziesiąt amperów');
    await settle(t);
    expect(calls, 1);
    expect(inputs('power_source')['weld_current_a'], 180);
    expect(inputs('power_source')['weld_lead_m'], 25);
    expect(t.takeException(), isNull);
  });

  testWidgets('late power AI reply cannot overwrite a newer manual current',
      (t) async {
    final pending = Completer<AiCommandPlan>();
    var calls = 0;
    await mount(t, home: const PowerSourcePage(), interpret: (_) {
      calls++;
      return pending.future;
    });
    await t.enterText(find.byKey(const Key('assistant-command')),
        'Zmień tylko prąd spawania na 180 A');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    await edit(t, find.byKey(const Key('ps-current')), '190');
    pending.complete(const AiCommandPlan(
        'execute',
        [
          AiCommandStep('power.duty',
              'Cykl pracy tabliczka 200 A 35% 160 A 60% 130 A 100% prąd spawania 180 A')
        ],
        ''));
    await settle(t);
    expect(inputs('power_source')['weld_current_a'], 190);
    expect(t.takeException(), isNull);
  });
}
