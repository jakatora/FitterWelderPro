import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/fitter/tube_bending.dart';
import 'package:cut_list_app/features/tube_bending/tube_bending_page.dart';
import 'package:cut_list_app/features/tube_bending/tube_bending_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/readout.dart';
import 'support/assistant_test_support.dart';
import 'tube_bending_skill_test.dart' show singleCommand, multiCommand;

class SlowStore extends TubeBendingStore {
  final gate = Completer<void>();
  @override
  Future<TubeBendingLoad> load() async {
    await gate.future;
    return super.load();
  }
}

Future<void> mount(WidgetTester t,
    {Widget home = const Scaffold(body: Text('Start')),
    AppLanguage lang = AppLanguage.pl}) async {
  ToolBridge.reset();
  t.view.physicalSize = const Size(1080, 6000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  await t.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(lang),
      child: MaterialApp(
          navigatorKey: appNavigatorKey,
          navigatorObservers: [appRoutes],
          home: home)));
  await t.pumpAndSettle();
}

Future<TubeBendingSaved> saved() async => decodeTubeBending(
        (await SharedPreferences.getInstance()).getString(TubeBendingStore.key))
    .state!;
String field(WidgetTester t, String key) =>
    t.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final commands = [
    (AppLanguage.pl, singleCommand, 'single', '334'),
    (
      AppLanguage.en,
      'tube bending single CLR 38 mm angle 90 degrees leg A 200 mm leg B 150 mm',
      'single',
      '334'
    ),
    (
      AppLanguage.pl,
      'gięcie rurki odsadzka CLR 38 mm wysokość 100 mm kąt 45 stopni ramię A 200 mm ramię B 200 mm',
      'offset',
      '538,5'
    ),
    (AppLanguage.pl, multiCommand, 'multi', '582,5'),
    (
      AppLanguage.en,
      'tube bending multi CLR 38 mm segments 150 mm 200 mm 250 mm angles 90 45',
      'multi',
      '582.5'
    ),
  ];
  for (final (lang, text, mode, cut) in commands) {
    testWidgets('actual module executes and persists $mode ${lang.name}',
        (t) async {
      await mount(t, lang: lang);
      final h = BrainHarness(lang: lang);
      addTearDown(h.timer.dispose);
      final a = (await h.say(text, byVoice: true)).result as AnswerResult;
      final opening = showInModule(a.show!, explicit: true);
      await t.pumpAndSettle();
      expect(await opening, ShowOutcome.opened);
      final handle = ToolBridge.instance.current!;
      expect(handle.toolId, 'tube_bending');
      expect(ToolBridge.instance.isReady(handle), isTrue);
      expect(
          t.widget<ChoiceChip>(find.byKey(ValueKey('tb-mode-$mode'))).selected,
          isTrue);
      expect(
          t.widget<Readout>(find.byKey(const ValueKey('tb-cut'))).value, cut);
      expect(field(t, 'tb-clr'), '38');
      final s = await saved();
      expect(s.mode.name, mode);
      expect(s.clrMm, 38);
      expect(s.minStraightMm, 0);
      expect(s.markerOffsetMm, 0);
      expect(s.springbackDeg, 0);
      final before = (await SharedPreferences.getInstance())
          .getString(TubeBendingStore.key);
      for (final patch in <Map<String, Object?>>[
        {'clr_mm': 0},
        {'unit': 'cm'},
        {'marker_offset_mm': double.nan},
        {'unexpected': 1},
        {'clr_mm': double.infinity},
      ]) {
        expect(await handle.apply({...a.show!.fields, ...patch}), isNotEmpty);
        await t.pumpAndSettle();
        expect(
            (await SharedPreferences.getInstance())
                .getString(TubeBendingStore.key),
            before);
        expect(
            t.widget<Readout>(find.byKey(const ValueKey('tb-cut'))).value, cut);
      }
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'readiness waits for restored settings; hidden geometry remains and reopen preserves command',
      (t) async {
    final old = TubeBendingSaved(
        mode: TubeBendingMode.single,
        unit: TubeUnit.inch,
        clrMm: 100,
        minStraightMm: 40,
        markerOffsetMm: 10,
        springbackDeg: 3,
        singleAngleDeg: 45,
        singleLegAMm: 800,
        singleLegBMm: 900,
        segmentsMm: const [900, 1000],
        anglesDeg: const [45],
        rotationsDeg: const [0]);
    SharedPreferences.setMockInitialValues(
        {TubeBendingStore.key: encodeTubeBending(old)});
    final store = SlowStore();
    await mount(t, home: TubeBendingPage(store: store));
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final a = (await h.say(singleCommand)).result as AnswerResult;
    final handle = ToolBridge.instance.current!;
    expect(ToolBridge.instance.isReady(handle), isFalse);
    expect(ToolBridge.instance.inputFields('tube_bending'), isNull);
    expect(await handle.apply(a.show!.fields), isNotEmpty);
    final waiter = ToolBridge.instance.whenReady('tube_bending');
    store.gate.complete();
    await t.pumpAndSettle();
    expect(await waiter, same(handle));
    expect(await handle.apply(a.show!.fields), isEmpty);
    await t.pumpAndSettle();
    expect(field(t, 'tb-clr'), '38');
    expect(field(t, 'tb-s-a'), '200');
    final s = await saved();
    expect(s.unit, TubeUnit.mm);
    expect(s.singleAngleDeg, 90);
    expect(s.singleLegBMm, 150);
    expect(s.minStraightMm, 0);
    expect(s.markerOffsetMm, 0);
    expect(s.springbackDeg, 0);
    expect(s.segmentsMm, [900, 1000]);
    expect(s.anglesDeg, [45]);
    await t.pump(const Duration(milliseconds: 500));
    expect(field(t, 'tb-clr'), '38');
    appNavigatorKey.currentState!.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const TubeBendingPage()));
    await t.pumpAndSettle();
    expect(field(t, 'tb-clr'), '38');
    expect(field(t, 'tb-s-a'), '200');
    expect(
        t.widget<Readout>(find.byKey(const ValueKey('tb-cut'))).value, '334');
    expect(t.takeException(), isNull);
  });
  for (final mode in ['single', 'offset', 'multi']) {
    testWidgets('precise $mode angles survive apply, save and reopen',
        (t) async {
      await mount(t);
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final initial = (await h.say(multiCommand)).result as AnswerResult;
      final open = showInModule(initial.show!, explicit: true);
      await t.pumpAndSettle();
      expect(await open, ShowOutcome.opened);
      final fields = <String, Object?>{
        'mode': mode,
        'unit': 'mm',
        'clr_mm': 38.123456789,
        'min_straight_mm': 0.0,
        'marker_offset_mm': 0.123456789,
        'springback_deg': 1.23456789,
        if (mode != 'multi') ...{
          'angle_deg': 45.123456789,
          'leg_a_mm': 200.123456789,
          'leg_b_mm': 250.987654321
        },
        if (mode == 'offset') ...{
          'height_mm': 100.123456789,
          'spread_mm': 50.987654321
        },
        if (mode == 'multi') ...{
          'segments_mm': [150.123456789, 200.234567891, 250.345678912],
          'angles_deg': [90.123456789, 45.987654321],
          'rotations_deg': [0.0, 123.456789]
        },
      };
      expect(await ToolBridge.instance.current!.apply(fields), isEmpty);
      await t.pumpAndSettle();
      final before = await saved();
      expect(before.springbackDeg, 1.23456789);
      if (mode == 'single') expect(before.singleAngleDeg, 45.123456789);
      if (mode == 'offset') expect(before.offsetAngleDeg, 45.123456789);
      if (mode == 'multi') {
        expect(before.anglesDeg, [90.123456789, 45.987654321]);
        expect(before.rotationsDeg, [0, 123.456789]);
      }
      appNavigatorKey.currentState!.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const TubeBendingPage()));
      await t.pumpAndSettle();
      String angle(String key) => field(t, key).replaceAll(',', '.');
      expect(double.parse(angle('tb-springback')), 1.23456789);
      if (mode == 'single') {
        expect(double.parse(angle('tb-s-angle')), 45.123456789);
      }
      if (mode == 'offset') {
        expect(double.parse(angle('tb-o-angle')), 45.123456789);
      }
      if (mode == 'multi') {
        expect(double.parse(angle('tb-angle-1')), 90.123456789);
        expect(double.parse(angle('tb-rot-2')), 123.456789);
      }
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('input precision cannot add a false half millimetre to the cut',
      (t) async {
    await mount(t);
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final a = (await h.say(singleCommand)).result as AnswerResult;
    final opening = showInModule(a.show!, explicit: true);
    await t.pumpAndSettle();
    expect(await opening, ShowOutcome.opened);
    const angle = 45.0049;
    final gain = bendGeometry(angleDeg: angle, clrMm: 38).gainMm;
    final fields = {
      ...a.show!.fields,
      'angle_deg': angle,
      'leg_a_mm': 200.0,
      'leg_b_mm': 100 + gain - 0.0002
    };
    expect(await ToolBridge.instance.current!.apply(fields), isEmpty);
    await t.pumpAndSettle();
    expect(
        t.widget<Readout>(find.byKey(const ValueKey('tb-cut'))).value, '300');
    appNavigatorKey.currentState!.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const TubeBendingPage()));
    await t.pumpAndSettle();
    expect(
        t.widget<Readout>(find.byKey(const ValueKey('tb-cut'))).value, '300');
    expect(double.parse(field(t, 'tb-s-angle').replaceAll(',', '.')), angle);
  });
  testWidgets('input snapshots belong only to the ready current route',
      (t) async {
    await mount(t, home: const TubeBendingPage());
    final bridge = ToolBridge.instance;
    final values = bridge.inputFields('tube_bending')!;
    expect(values['mode'], 'multi');
    expect(
        () => (values['segments_mm'] as List)[0] = 1.0, throwsUnsupportedError);
    expect(bridge.inputFields('account'), isNull);
    appNavigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page'))));
    await t.pumpAndSettle();
    expect(bridge.inputFields('tube_bending'), isNull);
    appNavigatorKey.currentState!.pop();
    await t.pumpAndSettle();
    expect(bridge.inputFields('tube_bending'), isNotNull);
    unawaited(showDialog<void>(
        context: appNavigatorKey.currentState!.overlay!.context,
        builder: (_) => const AlertDialog(title: Text('Dialog'))));
    await t.pumpAndSettle();
    expect(bridge.inputFields('tube_bending'), isNull);
    appNavigatorKey.currentState!.pop();
    await t.pumpAndSettle();
    expect(bridge.inputFields('tube_bending'), isNotNull);
  });
  testWidgets('inch command keeps canonical values across native unit switches',
      (t) async {
    await mount(t);
    final h = BrainHarness(lang: AppLanguage.en);
    addTearDown(h.timer.dispose);
    final a = (await h.say(
            'tube bending single CLR 1 inch angle 90 degrees leg A 8 inches leg B 6 inches units inch'))
        .result as AnswerResult;
    final open = showInModule(a.show!, explicit: true);
    await t.pumpAndSettle();
    expect(await open, ShowOutcome.opened);
    expect(field(t, 'tb-clr'), '1');
    final before = await saved();
    expect(before.clrMm, 25.4);
    expect(before.singleLegAMm, 203.2);
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const ValueKey('tb-unit-mm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('tb-unit-in')));
      await t.pumpAndSettle();
    }
    final after = await saved();
    expect(after.clrMm, before.clrMm);
    expect(after.singleLegAMm, before.singleLegAMm);
    expect(after.singleLegBMm, before.singleLegBMm);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'native multi supports twelve bends and disposes replaced fields safely',
      (t) async {
    await mount(t);
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final a = (await h.say(multiCommand)).result as AnswerResult;
    final open = showInModule(a.show!, explicit: true);
    await t.pumpAndSettle();
    expect(await open, ShowOutcome.opened);
    final handle = ToolBridge.instance.current!;
    final full = {
      ...a.show!.fields,
      'segments_mm': List<double>.filled(13, 200),
      'angles_deg': List<double>.filled(12, 30),
      'rotations_deg': List<double>.filled(12, 0)
    };
    expect(await handle.apply(full), isEmpty);
    await t.pumpAndSettle();
    expect((await saved()).anglesDeg, hasLength(12));
    expect(await handle.apply(a.show!.fields), isEmpty);
    await t.pumpAndSettle();
    expect((await saved()).anglesDeg, [90, 45]);
    expect(t.takeException(), isNull);
  });
}
