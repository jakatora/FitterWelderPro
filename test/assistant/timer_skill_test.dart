import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/welder_tools_screen.dart';
import 'package:cut_list_app/services/weld_timer_service.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/fake_weld_timer_effects.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('stopwatch starts, pauses with time kept, and resumes the same service',
      () async {
    final h = BrainHarness();
    expect(
        (await h.say('Uruchom stoper spawania', byVoice: true)).match!.skill.id,
        'timer.start');
    h.wait(const Duration(seconds: 23));
    expect(h.timer.running, isTrue);
    expect(h.timer.elapsed.inSeconds, 23);
    await h.say('Zatrzymaj timer');
    h.wait(const Duration(seconds: 50));
    expect(h.timer.running, isFalse);
    expect(h.timer.elapsed.inSeconds, 23);
    await h.say('Wznów timer');
    h.wait(const Duration(seconds: 7));
    expect(h.timer.elapsed.inSeconds, 30);
  });
  test(
      'cooldown uses supplied time, clears inherited 150 C, and alarms via service',
      () async {
    final h = BrainHarness();
    await h.say('Uruchom chłodzenie 1 minuta 30 sekund');
    expect(h.timer.mode, WeldTimerMode.cool);
    expect(h.timer.target!.inSeconds, 90);
    expect(h.timer.maxInterpassC, isNull);
    h.wait(const Duration(seconds: 90));
    h.timer.tick();
    expect(h.timer.finished, isTrue);
    expect(h.timer.alarmActive, isTrue);
    expect(weldTimerAlarmText(h.timer.currentAlarm, english: false).body,
        contains('Zmierz temperaturę'));
  });
  test('missing duration asks and no default is started', () async {
    final h = BrainHarness();
    expect((await h.say('Uruchom chłodzenie')).result, isA<AskResult>());
    expect(h.timer.running, isFalse);
    await h.say('2,5 minuty');
    expect(h.timer.target!.inSeconds, 150);
    expect(h.timer.running, isTrue);
  });
  for (final duration in [
    '-2 minuty',
    '0 sekund',
    '601 minut',
    '2 minuty 3 minuty',
    '2 albo 3 minuty'
  ]) {
    test('invalid or ambiguous duration does not start: $duration', () async {
      final h = BrainHarness();
      expect((await h.say('Uruchom chłodzenie $duration')).result,
          isA<AskResult>());
      expect(h.timer.running, isFalse);
    });
  }
  test('generic start asks mode; supplied duration survives mode answer',
      () async {
    final h = BrainHarness();
    expect((await h.say('Uruchom timer 90 sekund')).result, isA<AskResult>());
    await h.say('formowanie');
    expect(h.timer.mode, WeldTimerMode.purge);
    expect(h.timer.target!.inSeconds, 90);
    expect(h.timer.running, isTrue);
  });
  test('changing a timer requires confirmation; rejection keeps progress',
      () async {
    final h = BrainHarness();
    await h.say('Uruchom stoper');
    h.wait(const Duration(seconds: 20));
    final r = (await h.say('Uruchom chłodzenie 2 minuty')).result as AskResult;
    expect(r.slot, 'replace');
    expect(h.timer.mode, WeldTimerMode.weld);
    await h.say('nie zostaw timer');
    expect(h.timer.mode, WeldTimerMode.weld);
    expect(h.timer.elapsed.inSeconds, 20);
    await h.say('Uruchom chłodzenie 2 minuty');
    await h.say('tak zastąp timer');
    expect(h.timer.mode, WeldTimerMode.cool);
    expect(h.timer.remaining!.inSeconds, 120);
  });
  test('manual control invalidates pending replacement confirmation', () async {
    final h = BrainHarness();
    await h.say('Uruchom stoper');
    await h.say('Uruchom chłodzenie 2 minuty');
    h.wait(const Duration(seconds: 5));
    h.timer.pause();
    final r = await h.say('tak zastąp timer');
    expect(r.result, isA<AskResult>());
    expect(h.timer.mode, WeldTimerMode.weld);
    expect(h.timer.running, isFalse);
  });
  test('reset asks before destroying progress and clears it only after yes',
      () async {
    final h = BrainHarness();
    await h.say('Uruchom stoper');
    h.wait(const Duration(seconds: 30));
    expect((await h.say('Wyzeruj timer')).result, isA<AskResult>());
    await h.say('tak');
    expect(h.timer.elapsed, Duration.zero);
    expect(h.timer.running, isFalse);
  });
  test('negative instructions and quoted commands never start timer', () async {
    final h = BrainHarness();
    await h.say('nie uruchamiaj timera chłodzenia 2 minuty');
    expect(h.timer.running, isFalse);
    await h.say('Przetłumacz start cooldown timer 2 minutes');
    expect(h.timer.running, isFalse);
  });
  test(
      'explicit WPS temperature is preserved but is never a measured temperature',
      () async {
    final h = BrainHarness();
    await h.say('Uruchom chłodzenie 2 minuty limit 150 C');
    expect(h.timer.maxInterpassC, 150);
    expect(h.timer.target!.inSeconds, 120);
  });
  test('resume never silently drops a requested duration change', () async {
    final h = BrainHarness();
    await h.say('Uruchom chłodzenie 2 minuty');
    await h.say('Zatrzymaj timer');
    final r = await h.say('Wznów timer chłodzenia 3 minuty');
    expect(r.result, isA<FailedResult>());
    expect(h.timer.running, isFalse);
    expect(h.timer.target!.inSeconds, 120);
  });
  test('ticks keep confirmation revision but controls invalidate it', () async {
    final h = BrainHarness();
    await h.say('Uruchom stoper');
    final revision = h.timer.controlRevision;
    h.wait(const Duration(seconds: 5));
    h.timer.tick();
    expect(h.timer.controlRevision, revision);
    await h.say('nie uruchom chłodzenia 3 minuty');
    expect(h.timer.controlRevision, revision);
    await h.say('do not stop timer');
    expect(h.timer.running, isTrue);
    h.timer.pause();
    expect(h.timer.controlRevision, greaterThan(revision));
  });
  testWidgets(
      'handle selects timer and refreshes fields after an external command',
      (tester) async {
    ToolBridge.reset();
    final service = WeldTimerService(
        effects: FakeEffects(notificationsSupported: false),
        startTicker: (_) => null,
        observeLifecycle: false);
    WeldTimerService.instance = service;
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(),
        child: const MaterialApp(home: WelderToolsScreen())));
    await tester.pumpAndSettle();
    final handle = ToolBridge.instance.current!;
    service.setMode(WeldTimerMode.cool);
    service.setCoolTime(const Duration(seconds: 150));
    service.setMaxInterpass(null);
    final refreshing = handle.apply({'tab': 'timer'});
    await tester.pumpAndSettle();
    expect(await refreshing, isEmpty,
        reason:
            'tab=${DefaultTabController.of(tester.element(find.byType(TabBar))).index}; fields=${tester.widgetList<TextField>(find.byType(TextField)).map((f) => f.controller!.text).toList()}');
    expect(DefaultTabController.of(tester.element(find.byType(TabBar))).index,
        WelderToolsScreen.tabTimer);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text);
    expect(fields, contains('2.5'));
    expect(fields, contains(''));
    expect(await handle.apply({'tab': 'timer', 'unexpected': 1}),
        {'tab', 'unexpected'});
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });
}
