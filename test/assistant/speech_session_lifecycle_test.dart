import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show settle;

class HeldSpeech implements SpeechInput {
  Completer<bool>? initialization;
  int initializes = 0;
  bool failInitialize = false;
  bool failListen = false;
  final results = <SpeechResultCallback>[];
  final completions = <void Function(String?)>[];
  @override
  bool get isSupported => true;
  @override
  Future<bool> initialize() {
    initializes++;
    if (failInitialize) throw StateError("initialization failure");
    return initialization?.future ?? Future.value(true);
  }

  @override
  Future<void> listen(
      {required AppLanguage language,
      required SpeechResultCallback onResult,
      required void Function(String?) onDone}) async {
    if (failListen) throw StateError("listen failure");
    results.add(onResult);
    completions.add(onDone);
  }

  @override
  Future<void> stop() async => completions.lastOrNull?.call(null);
  @override
  Future<void> cancel() async => completions.lastOrNull?.call(null);
}

void main() {
  useTestDatabase();
  for (final emptyResult in ['', '   ']) {
    testWidgets('empty final speech cannot submit an existing draft: "$emptyResult"', (t) async {
      final speech = HeldSpeech();
      var calls = 0;
      await mount(t, speech: speech, interpret: (_) async {
        calls++;
        return const AiCommandPlan('answer', [], '');
      });
      const draft = 'przygotuj zamówiony wariant';
      final input = find.byKey(const Key('assistant-command'));
      await t.enterText(input, draft);
      await t.tap(find.byKey(const Key('assistant-mic')));
      await settle(t);
      speech.results.single(emptyResult, true);
      speech.completions.single(null);
      await settle(t);
      expect(calls, 0);
      expect(t.widget<TextField>(input).controller!.text, draft);
      expect(find.byKey(const Key('assistant-listening')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  for (final afterPartial in [false, true]) {
    testWidgets('manual draft edit wins over late speech: partial=$afterPartial', (t) async {
      final speech = HeldSpeech();
      var calls = 0;
      await mount(t, speech: speech, interpret: (_) async {
        calls++;
        return const AiCommandPlan('answer', [], '');
      });
      final input = find.byKey(const Key('assistant-command'));
      await t.tap(find.byKey(const Key('assistant-mic')));
      await settle(t);
      if (afterPartial) {
        speech.results.single('wstępnie rozpoznana wypowiedź', false);
        await t.pump();
      }
      const manual = 'ręcznie poprawione polecenie';
      await t.enterText(input, manual);
      speech.results.single('opóźniona końcowa wypowiedź', true);
      speech.completions.single(null);
      await settle(t);
      expect(calls, 0);
      expect(t.widget<TextField>(input).controller!.text, manual);
      expect(find.byKey(const Key('assistant-listening')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('failed speech cannot submit a late final result', (t) async {
    final speech = HeldSpeech();
    var calls = 0;
    await mount(t, speech: speech, interpret: (_) async {
      calls++;
      return const AiCommandPlan('answer', [], '');
    });
    final input = find.byKey(const Key('assistant-command'));
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.results.single('częściowa wypowiedź', false);
    await t.pump();
    speech.completions.single('error_network');
    await settle(t);
    expect(find.byKey(const Key('assistant-listening')), findsNothing);
    speech.results.single('opóźniona końcowa wypowiedź', true);
    await t.pump();
    expect(calls, 0);
    expect(t.widget<TextField>(input).controller!.text, 'częściowa wypowiedź');
    expect(t.takeException(), isNull);
  });
  testWidgets('retired speech cannot submit or stop a new microphone session',
      (t) async {
    final speech = HeldSpeech();
    var calls = 0;
    await mount(t, speech: speech, interpret: (_) async {
      calls++;
      return const AiCommandPlan('answer', [], '');
    });
    final mic = find.byKey(const Key('assistant-mic'));
    await t.tap(mic);
    await settle(t);
    await t.tap(mic);
    await settle(t);
    await t.tap(mic);
    await settle(t);
    expect(speech.results, hasLength(2));
    speech.results.first('stare prywatne polecenie', true);
    speech.completions.first('error_network');
    await settle(t);
    expect(calls, 0);
    expect(
        t
            .widget<TextField>(find.byKey(const Key('assistant-command')))
            .controller!
            .text,
        isEmpty);
    expect(find.byKey(const Key('assistant-listening')), findsOneWidget);
    speech.results.last('nowy tekst', false);
    await t.pump();
    expect(
        t
            .widget<TextField>(find.byKey(const Key('assistant-command')))
            .controller!
            .text,
        'nowy tekst');
    await t.tap(mic);
    await settle(t);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'pending microphone initialization is single and cannot start in background',
      (t) async {
    final speech = HeldSpeech()..initialization = Completer<bool>();
    await mount(t,
        speech: speech,
        interpret: (_) async => const AiCommandPlan('answer', [], ''));
    final mic = find.byKey(const Key('assistant-mic'));
    await t.tap(mic);
    await t.pump();
    await t.tap(mic);
    await t.pump();
    expect(speech.initializes, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    speech.initialization!.complete(true);
    await settle(t);
    expect(speech.results, isEmpty);
    expect(find.byKey(const Key('assistant-listening')), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    speech.initialization = null;
    await t.tap(mic);
    await settle(t);
    expect(speech.results, hasLength(1));
    await t.tap(mic);
    await settle(t);
    expect(t.takeException(), isNull);
  });
  for (final atInitialization in [true, false]) {
    testWidgets(
        'speech exception releases microphone for retry: init=$atInitialization',
        (t) async {
      final speech = HeldSpeech()
        ..failInitialize = atInitialization
        ..failListen = !atInitialization;
      await mount(t,
          speech: speech,
          interpret: (_) async => const AiCommandPlan('answer', [], ''));
      final mic = find.byKey(const Key('assistant-mic'));
      await t.tap(mic);
      await settle(t);
      expect(find.byKey(const Key('assistant-listening')), findsNothing);
      expect(t.takeException(), isNull);
      speech.failInitialize = false;
      speech.failListen = false;
      await t.tap(mic);
      await settle(t);
      expect(speech.results, hasLength(1));
      expect(find.byKey(const Key('assistant-listening')), findsOneWidget);
      await t.tap(mic);
      await settle(t);
    });
  }
}
