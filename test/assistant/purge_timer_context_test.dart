import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/welder_tools_screen.dart';
import 'package:cut_list_app/services/weld_timer_service.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import 'support/assistant_test_support.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say;

const inputs = <String, Object?>{
  'tab': 'purge',
  'od_mm': 60.3,
  'wall_mm': 2,
  'length_mm': 1000,
  'flow_lpm': 10,
  'initial_ppm': 210000,
  'target_ppm': 20,
};
double get expectedSeconds =>
    math.pi * math.pow(56.3 / 2, 2) * 1000 / 1e6 / 10 * 60 * math.log(10500);

class VisiblePurge implements ModuleContext, FieldModuleContext {
  Map<String, Object?>? fields = {...inputs};
  @override
  String? get activeToolId => 'welder_calculators';
  @override
  bool get onHomeOrAssistant => false;
  @override
  Map<String, Object?>? inputFields(String toolId) => fields;
}

void main() {
  useTestDatabase();
  for (final command in [
    'Uruchom timer formowania',
    'Uruchom timer formowania na obliczony czas',
    'Start purge timer using the calculated time',
  ]) {
    test('uses current native inputs without another duration: $command',
        () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final visible = VisiblePurge();
      final ctx = AssistantContext(lang: AppLanguage.pl, modules: visible);
      final r =
          await h.brain.handle(Utterance(command, lang: AppLanguage.pl), ctx);
      expect(r.result, isA<AnswerResult>());
      expect(h.timer.mode, WeldTimerMode.purge);
      expect(h.timer.target!.inSeconds, expectedSeconds.ceil());
      expect(h.timer.running, isTrue);
    });
  }
  test('manual calculator change invalidates replacement confirmation',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('Uruchom stoper spawania');
    h.wait(const Duration(seconds: 10));
    final visible = VisiblePurge();
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: visible);
    Future<SkillResult> sayCommand(String s) async =>
        (await h.brain.handle(Utterance(s, lang: AppLanguage.pl), ctx)).result;
    expect(await sayCommand('Uruchom timer formowania na obliczony czas'),
        isA<AskResult>());
    visible.fields = {...inputs, 'flow_lpm': 5};
    expect(await sayCommand('tak zastąp timer'), isA<FailedResult>());
    expect(h.timer.mode, WeldTimerMode.weld);
    expect(h.timer.elapsed.inSeconds, 10);
    expect(await sayCommand('Uruchom timer formowania na obliczony czas'),
        isA<AskResult>());
    expect(await sayCommand('tak zastąp timer'), isA<AnswerResult>());
    expect(h.timer.target!.inSeconds, (expectedSeconds * 2).ceil());
  });
  for (final bad in [
    null,
    {'tab': 'gas'},
    {...inputs, 'target_ppm': 0},
    {...inputs, 'flow_lpm': null}
  ]) {
    test('missing or invalid selected calculator cannot start: $bad', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final visible = VisiblePurge()..fields = bad;
      final ctx = AssistantContext(lang: AppLanguage.pl, modules: visible);
      final r = await h.brain.handle(
          Utterance('Uruchom timer formowania na obliczony czas',
              lang: AppLanguage.pl),
          ctx);
      expect(r.result, isA<AskResult>());
      expect(h.timer.running, isFalse);
      final reply = await h.brain
          .handle(Utterance('90 sekund', lang: AppLanguage.pl), ctx);
      expect(reply.result, isA<AnswerResult>());
      expect(h.timer.target!.inSeconds, 90);
    });
  }
  test('explicit duration overrides visible estimate', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: VisiblePurge());
    final r = await h.brain.handle(
        Utterance('Uruchom timer formowania 90 sekund', lang: AppLanguage.pl),
        ctx);
    expect(r.result, isA<AnswerResult>());
    expect(h.timer.target!.inSeconds, 90);
  });
  testWidgets('main chat starts native countdown from actual purge form',
      (t) async {
    final h = BrainHarness();
    WeldTimerService.instance = h.timer;
    addTearDown(h.timer.dispose);
    await mount(t,
        home: const WelderToolsScreen(),
        interpret: (_) async => throw StateError('Native command needs no AI'));
    await say(t,
        'Oblicz czas formowania OD 60,3 mm ścianka 2 mm długość 1 m przepływ 10 L/min start 210000 ppm cel 20 ppm');
    expect(ToolBridge.instance.inputFields('welder_calculators'), inputs);
    await say(t, 'Uruchom timer formowania na obliczony czas');
    expect(h.timer.running, isTrue);
    expect(h.timer.mode, WeldTimerMode.purge);
    expect(h.timer.target!.inSeconds, expectedSeconds.ceil());
    expect(
        ToolBridge.instance.inputFields('welder_calculators')!['tab'], 'timer');
  });
}
