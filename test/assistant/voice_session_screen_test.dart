import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSkill;
import 'global_pipe_slope_flow_test.dart' show settle;
import 'speech_session_lifecycle_test.dart' show HeldSpeech;

class VoiceFake implements SpeechOutput {
  final spoken = <String>[];
  Completer<void>? playback;
  Object? failure;
  @override Future<void> speak(String text, AppLanguage language) async {
    if (failure != null) throw failure!;
    spoken.add(text);
    playback = Completer<void>();
    await playback!.future;
  }
  @override Future<void> stop() async { if (playback?.isCompleted == false) playback!.complete(); }
}

void main() {
  useTestDatabase();
  testWidgets('można zatrzymać rozmowę podczas uruchamiania mikrofonu', (t) async {
    final speech = HeldSpeech()..initialization = Completer<bool>();
    await mount(t, speech: speech, voice: VoiceFake(),
      interpret: (_) async => const AiCommandPlan('answer', [], ''));
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(find.text('Uruchamiam mikrofon…'), findsOneWidget);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(find.byKey(const Key('assistant-voice-status')), findsNothing);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(speech.initializes, 1);
    expect(find.textContaining('Mikrofon kończy uruchamianie'), findsOneWidget);
    speech.initialization!.complete(true);
    await settle(t);
    expect(speech.results, isEmpty);
    expect(find.byKey(const Key('assistant-voice-status')), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('szkic wpisany podczas przełączania mikrofonu nie uruchamia rozmowy', (t) async {
    final speech = HeldSpeech();
    await mount(t, speech: speech, voice: VoiceFake(),
      interpret: (_) async => const AiCommandPlan('answer', [], ''));
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    expect(speech.results, hasLength(1));
    speech.cancellation = Completer<void>();
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    await t.enterText(find.byKey(const Key('assistant-command')), 'Mój szkic');
    speech.cancellation!.complete();
    await settle(t);
    expect(speech.results, hasLength(1));
    expect(find.text('Mój szkic'), findsOneWidget);
    expect(find.textContaining('Wyślij lub usuń wpisany tekst'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('niedokończone rozpoznawanie prosi o powtórzenie bez wysłania', (t) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    var commands = 0;
    await mount(t, speech: speech, voice: voice,
      interpret: (_) async { commands++; return const AiCommandPlan('answer', [], ''); });
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.results.single('jak spawać', false);
    await t.pump();
    expect(find.text('jak spawać'), findsOneWidget);
    speech.completions.single('error_no_match');
    await settle(t);
    expect(find.text('Nie zrozumiałem wypowiedzi. Powiedz jeszcze raz.'), findsOneWidget);
    expect(find.text('jak spawać'), findsNothing);
    expect(commands, 0);
    expect(voice.spoken, ['Nie zrozumiałem wypowiedzi. Powiedz jeszcze raz.']);
    expect(speech.results, hasLength(1));
    voice.playback!.complete();
    await settle(t);
    expect(speech.results, hasLength(2));
    expect(find.text('Nie zrozumiałem wypowiedzi. Powiedz jeszcze raz.'), findsOneWidget);
    speech.results.last('nowe pytanie', false);
    await t.pump();
    expect(find.text('Słucham…'), findsOneWidget);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
  });

  testWidgets('cisza nie jest traktowana jako niezrozumiała wypowiedź', (t) async {
    final speech = HeldSpeech();
    await mount(t, speech: speech, voice: VoiceFake(),
      interpret: (_) async => const AiCommandPlan('answer', [], ''));
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.completions.single('error_speech_timeout');
    await t.pump();
    expect(find.text('Uruchamiam mikrofon…'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 550));
    await settle(t);
    expect(find.text('Słucham…'), findsOneWidget);
    expect(find.textContaining('Powiedz jeszcze raz'), findsNothing);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
  });

  testWidgets('panel umożliwia wyciszenie mikrofonu i wznowienie rozmowy', (t) async {
    final speech = HeldSpeech();
    await mount(t, speech: speech, voice: VoiceFake(),
        interpret: (_) async => const AiCommandPlan('answer', [], ''));
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    await t.tap(find.byKey(const Key('assistant-mute-microphone')));
    await settle(t);
    expect(find.text('Mikrofon wyciszony'), findsOneWidget);
    speech.results.first('spóźnione', true);
    await settle(t);
    expect(find.text('Mikrofon wyciszony'), findsOneWidget);
    await t.tap(find.byKey(const Key('assistant-mute-microphone')));
    await settle(t);
    expect(find.text('Słucham…'), findsOneWidget);
    expect(speech.results, hasLength(2));
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('utrata sieci wyjaśnia przyczynę przerwania rozmowy', (t) async {
    final speech = HeldSpeech();
    await mount(t, speech: speech, voice: VoiceFake(),
      interpret: (_) async => const AiCommandPlan('answer', [], ''));
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.completions.single('error_network');
    await settle(t);
    expect(find.textContaining('Sprawdź internet'), findsOneWidget);
    expect(find.byKey(const Key('assistant-voice-status')), findsNothing);
  });

  testWidgets('głos: dwie tury używają asystenta, po odczycie wraca nasłuch', (t) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    var calls = 0;
    await mount(t, speech: speech, voice: voice,
      interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.send', 'fixture send', (_) async {
        calls++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Gotowe')));
      })]);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(speech.results, hasLength(1));
    speech.results[0]('fixture send', true);
    await settle(t);
    expect(calls, 1);
    expect(voice.spoken, ['Gotowe']);
    expect(speech.results, hasLength(1));
    voice.playback!.complete();
    await settle(t);
    expect(speech.results, hasLength(2));
    speech.results[1]('fixture send', true);
    await settle(t);
    expect(calls, 2);
    expect(voice.spoken, ['Gotowe', 'Gotowe']);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(find.byKey(const Key('assistant-voice-status')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('przerwanie odczytu przywraca mikrofon bez kończenia rozmowy', (t) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    await mount(t, speech: speech, voice: voice,
      interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.send', 'fixture send', (_) async =>
        const AnswerResult(AssistantAnswer(text: AssistantText.same('Długa odpowiedź'))))]);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.results.single('fixture send', true);
    await settle(t);
    final interrupt = find.byKey(const Key('assistant-interrupt-voice'));
    expect(interrupt, findsOneWidget);
    await t.ensureVisible(interrupt);
    await t.tap(interrupt);
    await settle(t);
    expect(speech.results, hasLength(2));
    expect(find.byKey(const Key('assistant-interrupt-voice')), findsNothing);
    expect(find.text('Słucham…'), findsWidgets);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('przejście w tło zatrzymuje rozmowę i późną odpowiedź głosową', (t) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    final pending = Completer<void>();
    await mount(t, speech: speech, voice: voice,
      interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.send', 'fixture send', (_) async {
        await pending.future;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Gotowe')));
      })]);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.results[0]('fixture send', true);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(milliseconds: 50));
    pending.complete();
    await settle(t);
    expect(voice.spoken, isEmpty);
    expect(speech.results, hasLength(1));
    expect(find.byKey(const Key('assistant-voice-status')), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t);
    expect(speech.results, hasLength(1));
    expect(t.takeException(), isNull);
  });
}
