import 'dart:async';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/correction_memory.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';
import '../support/test_account.dart';
import '../test_prefs.dart';
import 'ai_chat_execution_test.dart' show FixtureSkill;
import 'global_pipe_slope_flow_test.dart' show settle;
import 'speech_session_lifecycle_test.dart' show HeldSpeech;
import 'voice_session_screen_test.dart' show VoiceFake;

void main() {
  useTestDatabase();
  useGuestAccount();
  setUp(seedFreshInstall);
  setUp(() => CorrectionMemoryStore.instance.resetForTest());

  Future<void> openScreen(
    WidgetTester tester, {
    required AssistantMode mode,
    required HeldSpeech speech,
    required VoiceFake voice,
    AssistantChatSender? sender,
    List<AssistantSkill>? skills,
    Size physicalSize = const Size(1080, 2400),
    double pixelRatio = 2.5,
    double textScale = 1,
  }) async {
    await LegalConsent.instance.accept();
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final language = AppLanguageController(AppLanguage.pl);
    addTearDown(language.dispose);
    await tester.pumpWidget(AppLanguageScope(
      controller: language,
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          home: AiChatScreen(
            initialMode: mode,
            speechInput: speech,
            speechOutput: voice,
            chatSender: sender,
            skills: skills,
            aiInterpreter: (_) async => const AiCommandPlan('answer', [], ''),
          )),
    ));
    await settle(tester);
  }

  testWidgets('wybór głosu Windows zapisuje wybrany głos', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('flutter_tts');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'getVoices'
          ? [{'name': 'Polski testowy', 'locale': 'pl-PL'}]
          : 1;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await LegalConsent.instance.accept();
    final language = AppLanguageController(AppLanguage.pl);
    addTearDown(language.dispose);
    await tester.pumpWidget(AppLanguageScope(
      controller: language,
      child: MaterialApp(home: AiChatScreen(
        speechInput: HeldSpeech(), speechOutput: SystemSpeechOutput(),
      )),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const Key('assistant-voice-settings')));
    await settle(tester);
    expect(find.text('Polski testowy'), findsOneWidget);
    expect(find.text('pl-PL'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-voice-preview-0')));
    await settle(tester);
    expect(find.text('Polski testowy'), findsOneWidget);
    expect(calls.where((c) => c.method == 'setVoice').single.arguments,
        {'name': 'Polski testowy', 'locale': 'pl-PL'});
    expect(calls.where((c) => c.method == 'speak').single.arguments,
        'Dzień dobry, jestem Twoim asystentem.');
    expect(await SystemSpeechOutput().preferredVoice(AppLanguage.pl), isNull);
    await tester.tap(find.text('Polski testowy'));
    await settle(tester);
    expect(await SystemSpeechOutput().preferredVoice(AppLanguage.pl),
        {'name': 'Polski testowy', 'locale': 'pl-PL'});
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('brak głosu języka jest wyjaśniony użytkownikowi', (tester) async {
    final speech = HeldSpeech();
    final voice = VoiceFake()..failure = const SpeechLanguageUnavailable();
    await openScreen(tester, mode: AssistantMode.answer, speech: speech,
        voice: voice, sender: (_, __) async => ChatMessage(
            role: ChatRole.assistant, text: 'Odpowiedź', kind: AiReplyKind.live));
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    speech.results.single('Co to jest TIG?', true);
    await settle(tester);
    expect(find.textContaining('Brakuje głosu dla wybranego języka'), findsOneWidget);
    expect(speech.results, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ponowienie po błędzie czeka na zamknięcie mikrofonu', (tester) async {
    final speech = HeldSpeech();
    await openScreen(tester, mode: AssistantMode.answer, speech: speech,
        voice: VoiceFake());
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    speech.cancellation = Completer<void>();
    speech.completions.single('error_network');
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    expect(speech.results, hasLength(1));
    speech.cancellation!.complete();
    await settle(tester);
    expect(speech.results, hasLength(2));
    expect(find.text('Słucham…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mikrofon można wyciszyć i wznowić bez kończenia rozmowy', (tester) async {
    final speech = HeldSpeech();
    await openScreen(tester, mode: AssistantMode.answer, speech: speech, voice: VoiceFake());
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    expect(find.text('Słucham…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-mute-microphone')));
    await settle(tester);
    expect(find.text('Mikrofon wyciszony'), findsOneWidget);
    expect(find.text('Włącz mikrofon'), findsOneWidget);
    expect(find.byKey(const Key('assistant-voice-session')), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-mute-microphone')));
    await settle(tester);
    expect(find.text('Słucham…'), findsOneWidget);
    expect(speech.results, hasLength(2));
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wyciszenie podczas odpowiedzi nie włącza potem mikrofonu', (tester) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    await openScreen(tester, mode: AssistantMode.answer, speech: speech, voice: voice,
        sender: (_, __) async => ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź', kind: AiReplyKind.live));
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    speech.results.single('Co to jest TIG?', true);
    await settle(tester);
    expect(find.text('Odpowiadam…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-mute-microphone')));
    await settle(tester);
    expect(find.text('Mikrofon wyciszony'), findsOneWidget);
    expect(find.byKey(const Key('assistant-interrupt-voice')), findsNothing);
    voice.playback!.complete();
    await settle(tester);
    expect(find.text('Mikrofon wyciszony'), findsOneWidget);
    expect(speech.results, hasLength(1));
    await tester.tap(find.byKey(const Key('assistant-mute-microphone')));
    await settle(tester);
    expect(find.text('Słucham…'), findsOneWidget);
    expect(speech.results, hasLength(2));
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pełny czat prowadzi dwie tury głosowe', (tester) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    final questions = <String>[];
    await openScreen(tester,
        mode: AssistantMode.answer,
        speech: speech,
        voice: voice, sender: (question, _) async {
      questions.add(question);
      return ChatMessage(
          role: ChatRole.assistant, text: 'Odpowiedź', kind: AiReplyKind.live);
    });
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    speech.results.single('Co oznacza', false);
    await settle(tester);
    expect(find.text('Co oznacza'), findsOneWidget);
    speech.results.single('Co oznacza DN?', true);
    await settle(tester);
    expect(questions, ['Co oznacza DN?']);
    expect(voice.spoken, ['Odpowiedź']);
    expect(find.text('Odpowiedź'), findsWidgets);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const Key('assistant-question-input')))
            .readOnly,
        isTrue);
    voice.playback!.complete();
    await settle(tester);
    expect(speech.results, hasLength(2));
    expect(find.byKey(const Key('assistant-voice-transcript')), findsNothing);
    speech.results.last('A dla nierdzewki?', true);
    await settle(tester);
    expect(questions, ['Co oznacza DN?', 'A dla nierdzewki?']);
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('szkic w czacie nie jest zastępowany mową', (tester) async {
    final speech = HeldSpeech();
    await openScreen(tester,
        mode: AssistantMode.answer, speech: speech, voice: VoiceFake());
    await tester.enterText(
        find.byKey(const Key('assistant-question-input')), 'Mój szkic');
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    expect(speech.initializes, 0);
    expect(find.text('Mój szkic'), findsOneWidget);
    expect(
        find.textContaining('Wyślij lub usuń wpisany tekst'), findsOneWidget);
  });

  testWidgets('zmiana trybu kończy aktywną rozmowę', (tester) async {
    final speech = HeldSpeech();
    await openScreen(tester,
        mode: AssistantMode.answer, speech: speech, voice: VoiceFake());
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    expect(find.byKey(const Key('assistant-voice-status')), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-mode-act')));
    await settle(tester);
    expect(find.byKey(const Key('assistant-voice-status')), findsNothing);
    expect(find.byKey(const Key('assistant-voice-session')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pełny ekran poleceń obsługuje polecenie głosowe',
      (tester) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    var calls = 0;
    await openScreen(tester,
        mode: AssistantMode.act,
        speech: speech,
        voice: voice,
        skills: [
          FixtureSkill('fixture.send', 'fixture send', (_) async {
            calls++;
            return const AnswerResult(
                AssistantAnswer(text: AssistantText.same('Gotowe')));
          })
        ]);
    final button = find.byKey(const Key('assistant-voice-session'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester);
    speech.results.single('fixture send', true);
    await settle(tester);
    expect(calls, 1);
    expect(voice.spoken, ['Gotowe']);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('polecenie głosowe działa również w trybie czatu',
      (tester) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    var actions = 0;
    var questions = 0;
    await openScreen(tester,
        mode: AssistantMode.answer,
        speech: speech,
        voice: voice, sender: (_, __) async {
      questions++;
      return ChatMessage(
          role: ChatRole.assistant, text: 'Pytanie', kind: AiReplyKind.live);
    }, skills: [
      FixtureSkill('fixture.send', 'fixture send', (_) async {
        actions++;
        return const AnswerResult(
            AssistantAnswer(text: AssistantText.same('Gotowe')));
      })
    ]);
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    speech.results.single('fixture send', true);
    await settle(tester);
    expect(actions, 1);
    expect(questions, 0);
    expect(voice.spoken, ['Gotowe']);
    voice.playback!.complete();
    await settle(tester);
    expect(speech.results, hasLength(2));
    speech.results.last('fixture send', true);
    await settle(tester);
    expect(actions, 2);
    expect(questions, 0);
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('głosowa poprawka w czacie jest zapamiętywana po odpowiedzi',
      (tester) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    await openScreen(tester,
        mode: AssistantMode.answer,
        speech: speech,
        voice: voice,
        sender: (_, __) async => ChatMessage(
            role: ChatRole.assistant,
            text: 'Odpowiedź',
            kind: AiReplyKind.live));
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    speech.results.single('Co to jest TIG?', true);
    await settle(tester);
    voice.playback!.complete();
    await settle(tester);
    speech.results.last('Nie, chodziło mi o stal nierdzewną', true);
    await settle(tester);
    final pending = CorrectionMemoryStore.instance.list();
    await settle(tester);
    final records = await pending;
    expect(records.single.question, 'Co to jest TIG?');
    expect(records.single.correction, 'Nie, chodziło mi o stal nierdzewną');
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('długi zapis głosu mieści się na wąskim ekranie z dużą czcionką',
      (tester) async {
    final speech = HeldSpeech();
    await openScreen(tester,
        mode: AssistantMode.answer,
        speech: speech,
        voice: VoiceFake(),
        physicalSize: const Size(320, 640),
        pixelRatio: 1,
        textScale: 1.6);
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
    speech.results.single(
        'Jaka jest średnica zewnętrzna rury i jak ją poprawnie zmierzyć w warsztacie?',
        false);
    await settle(tester);
    expect(find.byKey(const Key('assistant-voice-transcript')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(tester);
  });
}
