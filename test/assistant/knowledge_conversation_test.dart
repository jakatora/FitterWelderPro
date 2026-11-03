import 'dart:convert';
import 'dart:async';
import 'package:cut_list_app/assistant/correction_memory.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/screens/bolt_torque_screen.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSkill;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'speech_session_lifecycle_test.dart' show HeldSpeech;
import 'voice_session_screen_test.dart' show VoiceFake;

void main() {
  useGuestAccount();
  useTestDatabase();
  setUp(() => CorrectionMemoryStore.instance.resetForTest());
  testWidgets('real research response becomes an openable source in the voice assistant', (t) async {
    const source = 'https://www.twi-global.com/media-and-events/press-releases/2021/sigma-phase-embrittlement-of-super-duplex-stainless-steels';
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final opened = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'launch') throw StateError('Unexpected launcher method');
      opened.add((call.arguments as Map)['url'] as String);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final speech = HeldSpeech();
    final voice = VoiceFake();
    var requests = 0;
    await http.runWithClient(() async {
      await mount(t, speech: speech, voice: voice,
          interpret: (_) async => throw StateError('Not a command'));
      PremiumService.instance.resetForTest();
      await t.tap(find.byKey(const Key('assistant-voice-session')));
      await settle(t);
      speech.results.single('Wyszukaj w internecie wpływ fazy sigma na super duplex', true);
      await settle(t);
      expect(requests, 1);
      expect(voice.spoken.single, contains('Faza sigma obniża odporność korozyjną'));
      expect(voice.spoken.single, isNot(contains(source)));
      voice.playback!.complete();
      await settle(t);
      await t.tap(find.byKey(const Key('assistant-voice-session')));
      await settle(t);
      final sourceButton = find.byKey(const Key('assistant-visible-source-0'));
      expect(sourceButton, findsOneWidget);
      expect(find.text('Źródła odpowiedzi'), findsOneWidget);
      await t.tap(sourceButton);
      await settle(t);
      expect(find.textContaining(source), findsOneWidget);
      await t.tap(find.text('Otwórz źródło'));
      await settle(t);
      expect(opened, [source]);
      expect(t.takeException(), isNull);
    }, () => MockClient((request) async {
      if (!request.url.path.endsWith('/ai/chat')) throw StateError('Unexpected request');
      requests++;
      // Sanitized response returned by the local, real-model research probe.
      return http.Response(jsonEncode({
        'text': 'Faza sigma obniża odporność korozyjną: materiały z sigmą mają zmniejszoną odporność na korozję w porównaniu z oczekiwanymi właściwościami materiału rodzimego. [1]',
        'citations': [],
        'web_sources': [{'url': source, 'title': 'Sigma Phase Embrittlement of Super Duplex Stainless Steels'}],
        'research_status': 'verified_sources',
        'needs_clarification': false,
        if ((jsonDecode(request.body) as Map)['calculator_context'] != null) 'calculator_context_used': true,
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });

  testWidgets('voice research speaks the answer and keeps sources clickable',
      (t) async {
    var requests = 0;
    final speech = HeldSpeech();
    final voice = VoiceFake();
    await http.runWithClient(() async {
      await mount(t, speech: speech, voice: voice,
          interpret: (_) async => throw StateError('Not a command'));
      PremiumService.instance.resetForTest();
      await t.tap(find.byKey(const Key('assistant-voice-session')));
      await settle(t);
      speech.results.single('Wyszukaj informacje o spawaniu hybrydowym', true);
      await settle(t);
      expect(requests, 1);
      expect(voice.spoken, ['Potwierdzona informacja [1].']);
      expect(voice.spoken.single, isNot(contains('https://')));
      expect(find.byKey(const Key('assistant-visible-source-0')), findsOneWidget);
      voice.playback!.complete();
      await settle(t);
      await t.tap(find.byKey(const Key('assistant-voice-session')));
      await settle(t);
      await t.tap(find.byKey(const Key('assistant-visible-source-0')));
      await settle(t);
      expect(find.textContaining('twi-global.com'), findsWidgets);
      expect(t.takeException(), isNull);
    }, () => MockClient((request) async {
      if (!request.url.path.endsWith('/ai/chat')) {
        throw StateError('Unexpected request');
      }
      requests++;
      return http.Response(jsonEncode({
        'text': 'Potwierdzona informacja [1].',
        'research_status': 'verified_sources',
        'web_sources': [
          {'title': 'Źródło testowe', 'url': 'https://www.twi-global.com/fixture'}
        ],
        'calculator_context_used': true,
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  testWidgets('past-tense correction is answered and remembered', (t) async {
    var requests = 0;
    await mount(t, interpret: (_) async => throw StateError('Not an app command'),
      chatSender: (_, __) async {
        requests++;
        return ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź testowa', kind: AiReplyKind.live);
      });
    await say(t, 'Co to jest TIG?');
    await say(t, 'Nie, chodziło mi o stal nierdzewną');
    expect(requests, 2);
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    final records = await saved;
    expect(records.single.question, 'Co to jest TIG?');
    expect(records.single.correction, 'Nie, chodziło mi o stal nierdzewną');
  });
  testWidgets('a natural disagreement asks for detail and remembers the clarification', (t) async {
    var requests = 0;
    await mount(t, interpret: (_) async => throw StateError('Not an app command'),
      chatSender: (_, __) async {
        requests++;
        return ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź testowa', kind: AiReplyKind.live);
      });
    await say(t, 'Co to jest TIG?');
    await say(t, 'Nie, to raczej tak nie będzie');
    expect(requests, 1);
    expect(find.textContaining('Co konkretnie mam poprawić'), findsWidgets);
    await say(t, 'Chodzi o stal nierdzewną');
    expect(requests, 2);
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    final records = await saved;
    expect(records, hasLength(1));
    expect(records.single.question, 'Co to jest TIG?');
    expect(records.single.correction, 'Chodzi o stal nierdzewną');
  });
  testWidgets('repeated disagreement asks for details before saving', (t) async {
    var requests = 0;
    await mount(t, interpret: (_) async => throw StateError('Not an app command'),
      chatSender: (_, __) async {
        requests++;
        return ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź testowa', kind: AiReplyKind.live);
      });
    await say(t, 'Co to jest TIG?');
    await say(t, 'Źle mówisz, nie o to mi chodzi');
    expect(requests, 1);
    expect(find.textContaining('Co konkretnie mam poprawić'), findsWidgets);
    final before = CorrectionMemoryStore.instance.list();
    await settle(t);
    expect(await before, isEmpty);
    await say(t, 'Chodzi o stal nierdzewną');
    expect(requests, 2);
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    final records = await saved;
    expect(records.single.question, 'Co to jest TIG?');
    expect(records.single.correction, 'Chodzi o stal nierdzewną');
  });
  testWidgets('spoken repeated disagreement asks before remembering details', (t) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    var requests = 0;
    await mount(t, speech: speech, voice: voice,
      interpret: (_) async => throw StateError('Not an app command'),
      chatSender: (_, __) async {
        requests++;
        return ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź testowa', kind: AiReplyKind.live);
      });
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.results.last('Co to jest TIG?', true);
    await settle(t);
    expect(requests, 1);
    voice.playback!.complete();
    await settle(t);
    speech.results.last('Źle mówisz, nie o to mi chodzi', true);
    await settle(t);
    expect(requests, 1);
    expect(voice.spoken.last, contains('Co konkretnie mam poprawić'));
    final before = CorrectionMemoryStore.instance.list();
    await settle(t);
    expect(await before, isEmpty);
    voice.playback!.complete();
    await settle(t);
    speech.results.last('Chodzi o stal nierdzewną', true);
    await settle(t);
    expect(requests, 2);
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    final records = await saved;
    expect(records.single.question, 'Co to jest TIG?');
    expect(records.single.correction, 'Chodzi o stal nierdzewną');
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(t.takeException(), isNull);
  });
  testWidgets('correction survives further questions and retains user details', (t) async {
    var requests = 0;
    await mount(t, interpret: (_) async => throw StateError('Not an app command'),
      chatSender: (_, __) async {
        requests++;
        return ChatMessage(role: ChatRole.assistant,
            text: requests == 2 ? 'Jaka grubość?' : 'Odpowiedź testowa',
            kind: AiReplyKind.live, needsClarification: requests == 2);
      });
    await say(t, 'Jak spawać TIG?');
    await say(t, 'Nie o to mi chodzi, chodzi mi o aluminium');
    final before = CorrectionMemoryStore.instance.list();
    await settle(t);
    expect(await before, isEmpty);
    await say(t, '3 mm');
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    final record = (await saved).single;
    expect(record.question, 'Jak spawać TIG?');
    expect(record.correction, 'Nie o to mi chodzi, chodzi mi o aluminium\n3 mm');
  });
  testWidgets('vague disagreement during clarification asks locally and keeps correction', (t) async {
    var requests = 0;
    await mount(t, interpret: (_) async => throw StateError('Not an app command'),
      chatSender: (_, __) async {
        requests++;
        return ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź testowa',
            kind: AiReplyKind.live, needsClarification: requests == 2);
      });
    await say(t, 'Jak spawać TIG?');
    await say(t, 'Nie o to mi chodzi, chodzi mi o aluminium');
    await say(t, 'Źle mówisz');
    expect(requests, 2);
    expect(find.textContaining('Co konkretnie mam poprawić'), findsWidgets);
    await say(t, '3 mm');
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    expect((await saved).single.correction,
        'Nie o to mi chodzi, chodzi mi o aluminium\n3 mm');
  });
  testWidgets('clearing memory while clarification is pending prevents saving it', (t) async {
    var requests = 0;
    await mount(t, interpret: (_) async => throw StateError('Not an app command'),
      chatSender: (_, __) async {
        requests++;
        return ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź testowa',
            kind: AiReplyKind.live, needsClarification: requests == 2);
      });
    await say(t, 'Jak spawać TIG?');
    await say(t, 'Nie o to mi chodzi, chodzi mi o aluminium');
    final clearing = CorrectionMemoryStore.instance.clear();
    await settle(t);
    await clearing;
    await say(t, '3 mm');
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    expect(await saved, isEmpty);
  });
  testWidgets('a correction is saved after the user retries a failed answer', (t) async {
    var requests = 0;
    await mount(t, interpret: (_) async => throw StateError('Not an app command'),
      chatSender: (_, __) async {
        requests++;
        if (requests == 2) throw StateError('Connection lost');
        return ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź testowa', kind: AiReplyKind.live);
      });
    await say(t, 'Co to jest TIG?');
    await say(t, 'Nie o to mi chodzi, chodzi mi o stal nierdzewną');
    expect(find.textContaining('Zapamiętano poprawkę'), findsNothing);
    expect(requests, 2);
    final retry = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
    retry();
    await settle(t);
    expect(requests, 3);
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    final records = await saved;
    expect(records, hasLength(1));
    expect(records.single.question, 'Co to jest TIG?');
    expect(records.single.correction, 'Nie o to mi chodzi, chodzi mi o stal nierdzewną');
  });
  testWidgets('retry does not save a correction to a different account', (t) async {
    var requests = 0;
    await mount(t, interpret: (_) async => throw StateError('Not an app command'),
      chatSender: (_, __) async {
        if (++requests == 2) throw StateError('Connection lost');
        return ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź testowa', kind: AiReplyKind.live);
      });
    await say(t, 'Co to jest TIG?');
    await say(t, 'Nie o to mi chodzi, chodzi mi o stal nierdzewną');
    final retry = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
    final old = AccountService.instance;
    final client = MockClient((_) async => http.Response('{}', 500));
    final other = AccountService.forTesting(client);
    await other.load();
    other.account = {'id': 'other-account'};
    AccountService.instance = other;
    addTearDown(() { AccountService.instance = old; other.dispose(); client.close(); });
    retry();
    await settle(t);
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    expect(await saved, isEmpty);
  });
  testWidgets('retry cannot restore a correction after memory was cleared', (t) async {
    var requests = 0;
    await mount(t, interpret: (_) async => throw StateError('Not an app command'),
      chatSender: (_, __) async {
        if (++requests == 2) throw StateError('Connection lost');
        return ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź testowa', kind: AiReplyKind.live);
      });
    await say(t, 'Co to jest TIG?');
    await say(t, 'Nie o to mi chodzi, chodzi mi o stal nierdzewną');
    final retry = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
    final clearing = CorrectionMemoryStore.instance.clear();
    await settle(t);
    await clearing;
    retry();
    await settle(t);
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    expect(await saved, isEmpty);
  });
  testWidgets('natural corrections follow the answer; vague feedback is clarified locally', (t) async {
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async => throw StateError('Not an app command'));
      PremiumService.instance.resetForTest();
      await say(t, 'Co to jest TIG?');
      await say(t, 'Nie o to mi chodzi, chodzi mi o stal nierdzewną');
      expect(chats, hasLength(2));
      expect(chats.last['message'], 'Nie o to mi chodzi, chodzi mi o stal nierdzewną');
      final history = chats.last['history'] as List;
      expect(history.any((m) => m['text'] == 'Co to jest TIG?'), isTrue);
      expect(history.any((m) => m['text'] == 'Pierwsza odpowiedź'), isTrue);
      await say(t, 'Źle mówisz');
      expect(chats, hasLength(2));
      expect(find.textContaining('Co konkretnie mam poprawić'), findsWidgets);
      await say(t, 'Chodzi o spawanie aluminium');
      expect(chats, hasLength(3));
      expect(chats.last['question_clarification'], {
        'user_turns': ['Nie o to mi chodzi, chodzi mi o stal nierdzewną', 'Źle mówisz']
      });
      await say(t, 'Jak spawać TIG?');
      expect(chats, hasLength(4));
      expect(chats.last['remembered_corrections'], [{
        'question': 'Co to jest TIG?',
        'correction': 'Nie o to mi chodzi, chodzi mi o stal nierdzewną',
      }]);
      expect(t.takeException(), isNull);
    }, () => MockClient((r) async {
      if (!r.url.path.endsWith('/ai/chat')) throw StateError('Unexpected request');
      chats.add(jsonDecode(r.body) as Map);
      return http.Response(jsonEncode({
        'text': chats.length == 1 ? 'Pierwsza odpowiedź' : 'Doprecyzowana odpowiedź',
        if (chats.length == 3) 'question_clarification_used': true,
        if ((chats.last['remembered_corrections'] as List?)?.isNotEmpty == true)
          'remembered_corrections_received': true,
        'calculator_context_used': true,
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  testWidgets('a natural correction is recalled when the technical term is inflected', (t) async {
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async => throw StateError('Not an app command'));
      PremiumService.instance.resetForTest();
      await say(t, 'Jaki gaz osłonowy wybrać?');
      await say(t, 'Nie o to mi chodzi, chodziło mi o hel');
      await say(t, 'Jaki przepływ gazu osłonowego?');
      expect(chats, hasLength(3));
      expect(chats.last['remembered_corrections'], [{
        'question': 'Jaki gaz osłonowy wybrać?',
        'correction': 'Nie o to mi chodzi, chodziło mi o hel',
      }]);
      expect(t.takeException(), isNull);
    }, () => MockClient((request) async {
      if (!request.url.path.endsWith('/ai/chat')) throw StateError('Unexpected request');
      chats.add(jsonDecode(request.body) as Map);
      return http.Response(jsonEncode({
        'text': 'Odpowiedź testowa',
        if ((chats.last['remembered_corrections'] as List?)?.isNotEmpty == true)
          'remembered_corrections_received': true,
        'calculator_context_used': true,
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  testWidgets('unverified web research can be retried in the embedded assistant',
      (t) async {
    var requests = 0;
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async =>
          throw StateError('Research is not a module command'));
      PremiumService.instance.resetForTest();
      await say(t, 'Wyszukaj informacje o spawaniu hybrydowym');
      expect(requests, 1);
      expect(find.textContaining('Nie udało mi się potwierdzić'), findsWidgets);
      expect(find.textContaining('Źródła internetowe'), findsNothing);
      final retry = find.byKey(const Key('assistant-persistent-retry'));
      expect(retry, findsOneWidget);
      await t.ensureVisible(retry);
      await t.tap(retry);
      await settle(t);
      expect(requests, 2);
      expect(find.textContaining('Potwierdzona informacja testowa'), findsWidgets);
      expect(find.textContaining('Źródła internetowe'), findsNothing);
      expect(find.byKey(const Key('assistant-visible-source-0')), findsOneWidget);
      await t.tap(find.byKey(const Key('assistant-visible-source-0')));
      await settle(t);
      expect(find.textContaining('twi-global.com'), findsWidgets);
      expect(t.takeException(), isNull);
    }, () => MockClient((r) async {
      if (!r.url.path.endsWith('/ai/chat')) {
        throw StateError('Unexpected request');
      }
      requests++;
      return http.Response(jsonEncode({
        'text': requests == 1 ? 'Nie udało mi się potwierdzić informacji.'
            : 'Potwierdzona informacja testowa [1].',
        'research_status': requests == 1 ? 'unverified' : 'verified_sources',
        'web_sources': requests == 1 ? [] : [
          {'title': 'Źródło testowe', 'url': 'https://www.twi-global.com/fixture'}
        ],
        'calculator_context_used': true,
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  testWidgets('offline gas advice gives a command that opens the selector',
      (t) async {
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async =>
          throw StateError('Both steps should stay out of command AI'));
      PremiumService.instance.resetForTest();
      await say(t, 'Pomóż mi dobrać gaz osłonowy do nierdzewki');
      expect(find.textContaining('Otwórz dobór spoiwa'), findsWidgets);
      await say(t, 'Otwórz dobór spoiwa');
      expect(ToolBridge.instance.activeToolId, 'filler_selector');
      expect(find.byKey(const ValueKey('filler-material-a')), findsOneWidget);
      expect(t.takeException(), isNull);
    }, () => MockClient((_) async => throw http.ClientException('Offline test')));
  });
  testWidgets('offline gas advice reaches the user and offers a retry',
      (t) async {
    var chatRequests = 0;
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async =>
          throw StateError('Advice must not enter the module interpreter'));
      PremiumService.instance.resetForTest();
      await say(t, 'Pomóż mi dobrać gaz osłonowy do nierdzewki');
      expect(chatRequests, 1);
      expect(find.textContaining('Tryb offline'), findsWidgets);
      expect(find.textContaining('Dobór spoiwa'), findsWidgets);
      expect(find.textContaining('WPS'), findsWidgets);
      expect(find.textContaining('Które narzędzie'), findsNothing);
      final retry = find.byKey(const Key('assistant-persistent-retry'));
      expect(retry, findsOneWidget);
      await t.enterText(find.byKey(const Key('assistant-command')), 'Nowy szkic');
      await t.ensureVisible(retry);
      await t.tap(retry);
      await settle(t);
      expect(chatRequests, 2);
      expect(find.textContaining('Podaj metodę i gatunek materiału'), findsWidgets);
      expect(t.widget<TextField>(find.byKey(const Key('assistant-command')))
          .controller!.text, 'Nowy szkic');
      expect(t.takeException(), isNull);
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/ai/chat')) {
        chatRequests++;
        if (chatRequests == 1) throw http.ClientException('Offline test');
        expect((jsonDecode(r.body) as Map)['message'],
            'Pomóż mi dobrać gaz osłonowy do nierdzewki');
        return http.Response(jsonEncode({
          'text': 'Podaj metodę i gatunek materiału',
          'needs_clarification': true,
          'calculator_context_used': true,
        }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      throw StateError('Unexpected network request in offline test');
    }));
  });
  testWidgets('mixed request answers the question then performs the action', (t) async {
    var interpretations = 0;
    var answers = 0;
    var actions = 0;
    await mount(t, interpret: (_) async {
      interpretations++;
      return const AiCommandPlan('answer', [], '');
    }, skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
      actions++;
      return const AnswerResult(AssistantAnswer(text: AssistantText.same('Kalkulator otwarty')));
    })], chatSender: (question, __) async {
      answers++;
      expect(question, 'Opowiedz mi o TIG');
      return ChatMessage(role: ChatRole.assistant, text: 'TIG wykorzystuje wolfram', kind: AiReplyKind.live);
    });
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    expect(interpretations, 0);
    expect(answers, 1);
    expect(actions, 1);
    expect(find.textContaining('TIG wykorzystuje wolfram'), findsWidgets);
    expect(find.textContaining('Kalkulator otwarty'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('mixed request answers then opens the real bolt torque calculator', (t) async {
    var answers = 0;
    await mount(t, interpret: (_) async => throw StateError('Native open should not need AI planning'),
      chatSender: (question, __) async {
        answers++;
        expect(question, 'Opowiedz mi o TIG');
        return ChatMessage(role: ChatRole.assistant,
            text: 'TIG wykorzystuje wolfram', kind: AiReplyKind.live);
      });
    await say(t, 'Opowiedz mi o TIG i otwórz moment śrub');
    expect(answers, 1);
    expect(find.byType(BoltTorqueScreen), findsOneWidget);
    expect(find.textContaining('TIG wykorzystuje wolfram'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('show in a mixed request opens the real calculator', (t) async {
    await mount(t, interpret: (_) async => throw StateError('Native open should not need AI planning'),
      chatSender: (_, __) async => ChatMessage(role: ChatRole.assistant,
          text: 'TIG wykorzystuje wolfram', kind: AiReplyKind.live));
    await say(t, 'Opowiedz mi o TIG i pokaż moment śrub');
    expect(find.byType(BoltTorqueScreen), findsOneWidget);
    expect(find.textContaining('TIG wykorzystuje wolfram'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('mixed voice request opens the real calculator and says both results', (t) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    await mount(t, speech: speech, voice: voice,
      interpret: (_) async => throw StateError('Native open should not need AI planning'),
      chatSender: (_, __) async => ChatMessage(role: ChatRole.assistant,
          text: 'TIG wykorzystuje wolfram', kind: AiReplyKind.live));
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.results.single('Opowiedz mi o TIG i otwórz moment śrub', true);
    await settle(t);
    expect(find.byType(BoltTorqueScreen), findsOneWidget);
    expect(voice.spoken.single, contains('TIG wykorzystuje wolfram'));
    expect(voice.spoken.single.toLowerCase(), contains('moment śrub'));
    voice.playback!.complete();
    await settle(t);
    expect(speech.results, hasLength(2));
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(t.takeException(), isNull);
  });
  testWidgets('mixed spoken request speaks the answer and action result', (t) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    var actions = 0;
    await mount(t, speech: speech, voice: voice, interpret: (_) async {
      return const AiCommandPlan('answer', [], '');
    }, skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
      actions++;
      return const AnswerResult(AssistantAnswer(text: AssistantText.same('Kalkulator otwarty')));
    })], chatSender: (_, __) async => ChatMessage(
        role: ChatRole.assistant, text: 'TIG wykorzystuje wolfram', kind: AiReplyKind.live));
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.results.single('Opowiedz mi o TIG i otwórz kalkulator', true);
    await settle(t);
    expect(actions, 1);
    expect(voice.spoken.single, contains('TIG wykorzystuje wolfram'));
    expect(voice.spoken.single, contains('Kalkulator otwarty'));
    voice.playback!.complete();
    await settle(t);
    expect(speech.results, hasLength(2));
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(t.takeException(), isNull);
  });
  testWidgets('mixed request does not perform action when answer needs clarification', (t) async {
    var actions = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Otwarty')));
      })], chatSender: (_, __) async => ChatMessage(role: ChatRole.assistant,
          text: 'O jaką metodę chodzi?', kind: AiReplyKind.live, needsClarification: true));
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    expect(actions, 0);
    expect(find.textContaining('O jaką metodę chodzi?'), findsWidgets);
    expect(find.textContaining('Po doprecyzowaniu wrócę'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('clarification resumes the pending action after the resolved answer', (t) async {
    var actions = 0;
    var answers = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Kalkulator otwarty')));
      })], chatSender: (_, __) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant,
            text: answers == 1 ? 'Jaki materiał?' : 'Dla stali nierdzewnej stosuj WPS.',
            kind: AiReplyKind.live, needsClarification: answers == 1);
      });
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    expect(actions, 0);
    await say(t, 'Stal nierdzewna');
    expect(answers, 2);
    expect(actions, 1);
    expect(find.textContaining('Dla stali nierdzewnej'), findsWidgets);
    expect(find.textContaining('Kalkulator otwarty'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('two clarifications retain the action and open the real calculator', (t) async {
    var answers = 0;
    await mount(t, interpret: (_) async => throw StateError('Native open needs no AI planning'),
      chatSender: (_, __) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant,
            text: answers == 1 ? 'Jaki materiał?' : answers == 2 ? 'Jaka grubość?' : 'Sprawdź WPS.',
            kind: AiReplyKind.live, needsClarification: answers < 3);
      });
    await say(t, 'Opowiedz mi o TIG i otwórz moment śrub');
    await say(t, 'Stal nierdzewna');
    expect(find.byType(BoltTorqueScreen), findsNothing);
    await say(t, '3 mm');
    expect(answers, 3);
    expect(find.byType(BoltTorqueScreen), findsOneWidget);
    expect(find.textContaining('Sprawdź WPS.'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('a vague correction asks for detail before saving and resuming', (t) async {
    var actions = 0;
    var answers = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Kalkulator otwarty')));
      })], chatSender: (_, __) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant,
            text: answers == 1 ? 'Jaki materiał?' : 'Sprawdź WPS dla nierdzewki.',
            kind: AiReplyKind.live, needsClarification: answers == 1);
      });
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    await say(t, 'Źle mówisz');
    expect(answers, 1);
    expect(actions, 0);
    expect(find.textContaining('Co konkretnie mam poprawić'), findsWidgets);
    await say(t, 'Chodzi o stal nierdzewną');
    expect(answers, 2);
    expect(actions, 1);
    final pending = CorrectionMemoryStore.instance.list();
    await settle(t);
    final records = await pending;
    expect(records.single.question, 'Opowiedz mi o TIG');
    expect(records.single.correction, 'Chodzi o stal nierdzewną');
    expect(t.takeException(), isNull);
  });
  testWidgets('a direct correction is remembered before the deferred action', (t) async {
    var actions = 0;
    var answers = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Kalkulator otwarty')));
      })], chatSender: (_, __) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant,
            text: answers == 1 ? 'Jaki materiał?' : 'Sprawdź WPS dla aluminium.',
            kind: AiReplyKind.live, needsClarification: answers == 1);
      });
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    await say(t, 'Nie, chodziło mi o aluminium');
    expect(answers, 2);
    expect(actions, 1);
    final pending = CorrectionMemoryStore.instance.list();
    await settle(t);
    final records = await pending;
    expect(records.single.question, 'Opowiedz mi o TIG');
    expect(records.single.correction, 'Nie, chodziło mi o aluminium');
    expect(t.takeException(), isNull);
  });
  testWidgets('pending correction and action survive another clarification', (t) async {
    var actions = 0;
    var answers = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Kalkulator otwarty')));
      })], chatSender: (_, __) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant, text: 'Odpowiedź testowa',
            kind: AiReplyKind.live, needsClarification: answers < 3);
      });
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    await say(t, 'Nie o to mi chodzi, chodzi mi o aluminium');
    expect(actions, 0);
    await say(t, 'Źle mówisz');
    expect(answers, 2);
    expect(actions, 0);
    await say(t, '3 mm');
    expect(answers, 3);
    expect(actions, 1);
    final saved = CorrectionMemoryStore.instance.list();
    await settle(t);
    expect((await saved).single.correction,
        'Nie o to mi chodzi, chodzi mi o aluminium\n3 mm');
  });
  testWidgets('a corrected request with a new command cancels the old pending action', (t) async {
    var actions = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Kalkulator otwarty')));
      })], chatSender: (_, __) async => ChatMessage(role: ChatRole.assistant,
          text: 'Jaki materiał?', kind: AiReplyKind.live, needsClarification: true));
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    await say(t, 'Nie o to mi chodzi, otwórz moment śrub');
    expect(actions, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('spoken clarification resumes the pending action and says the result', (t) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    var actions = 0;
    var answers = 0;
    await mount(t, speech: speech, voice: voice,
      interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Kalkulator otwarty')));
      })], chatSender: (_, __) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant,
            text: answers == 1 ? 'Jaki materiał?' : 'Dla nierdzewki sprawdź WPS.',
            kind: AiReplyKind.live, needsClarification: answers == 1);
      });
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.results.single('Opowiedz mi o TIG i otwórz kalkulator', true);
    await settle(t);
    expect(actions, 0);
    expect(voice.spoken.single, contains('Jaki materiał?'));
    voice.playback!.complete();
    await settle(t);
    speech.results.last('Stal nierdzewna', true);
    await settle(t);
    expect(actions, 1);
    expect(voice.spoken.last, contains('Dla nierdzewki sprawdź WPS.'));
    expect(voice.spoken.last, contains('Kalkulator otwarty'));
    voice.playback!.complete();
    await settle(t);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    expect(t.takeException(), isNull);
  });
  testWidgets('stopping voice discards its deferred action', (t) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    var actions = 0;
    var answers = 0;
    await mount(t, speech: speech, voice: voice,
      interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Otwarty')));
      })], chatSender: (_, __) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant,
            text: answers == 1 ? 'Jaki materiał?' : 'Odpowiedź',
            kind: AiReplyKind.live, needsClarification: answers == 1);
      });
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.results.single('Opowiedz mi o TIG i otwórz kalkulator', true);
    await settle(t);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    await say(t, 'Stal nierdzewna');
    expect(actions, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('changing app context prevents a deferred action', (t) async {
    var actions = 0;
    var answers = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Otwarty')));
      })], chatSender: (_, __) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant, text: 'Jaki materiał?',
            kind: AiReplyKind.live, needsClarification: true);
      });
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    ToolBridge.reset();
    await say(t, 'Stal nierdzewna');
    expect(actions, 0);
    expect(answers, 1);
    expect(find.textContaining('Kontekst aplikacji się zmienił'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('editing calculator inputs prevents a deferred action', (t) async {
    var actions = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Otwarty')));
      })], chatSender: (_, __) async => ChatMessage(role: ChatRole.assistant,
          text: 'Jaki materiał?', kind: AiReplyKind.live, needsClarification: true));
    await ToolBridge.instance.current!.apply({
      'rise_mm': 25.0, 'spread_mm': 400.0, 'angle_deg': 45.0, 'dn': 100, 'gap_mm': 3.0,
    });
    await settle(t);
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    expect(find.textContaining('Po doprecyzowaniu wrócę'), findsWidgets);
    expect(ToolBridge.instance.inputFields('rolling_offset')!['rise_mm'], 25.0);
    await ToolBridge.instance.current!.apply({
      'rise_mm': 50.0, 'spread_mm': 400.0, 'angle_deg': 45.0, 'dn': 100, 'gap_mm': 3.0,
    });
    await settle(t);
    expect(ToolBridge.instance.inputFields('rolling_offset')!['rise_mm'], 50.0);
    await say(t, 'Stal nierdzewna');
    expect(actions, 0);
    expect(find.textContaining('Kontekst aplikacji się zmienił'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('an explicit new topic cancels a deferred action', (t) async {
    var actions = 0;
    var answers = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Otwarty')));
      })], chatSender: (_, __) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant, text: answers == 1 ? 'Jaki materiał?' : 'Nowa odpowiedź',
            kind: AiReplyKind.live, needsClarification: answers == 1);
      });
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    await say(t, 'Nowe pytanie: co to jest MAG?');
    expect(actions, 0);
    expect(answers, 2);
    expect(find.textContaining('Nowa odpowiedź'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('mixed request does not perform action if the answer is unavailable', (t) async {
    var actions = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Otwarty')));
      })], chatSender: (_, __) async => ChatMessage(role: ChatRole.assistant,
          text: 'Brak połączenia', kind: AiReplyKind.unavailable));
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    expect(actions, 0);
    expect(find.textContaining('Nie wykonałem jeszcze drugiej części'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('mixed request does not perform action after an empty answer', (t) async {
    var actions = 0;
    await mount(t, interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Otwarty')));
      })], chatSender: (_, __) async => ChatMessage(role: ChatRole.assistant,
          text: ' ', kind: AiReplyKind.live));
    await say(t, 'Opowiedz mi o TIG i otwórz kalkulator');
    expect(actions, 0);
    expect(find.textContaining('Nie wykonałem jeszcze drugiej części'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('ending voice during the answer prevents the queued action', (t) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    final response = Completer<ChatMessage>();
    var actions = 0;
    await mount(t, speech: speech, voice: voice,
      interpret: (_) async => const AiCommandPlan('answer', [], ''),
      skills: [FixtureSkill('fixture.open', 'otwórz kalkulator', (_) async {
        actions++;
        return const AnswerResult(AssistantAnswer(text: AssistantText.same('Otwarty')));
      })], chatSender: (_, __) => response.future);
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await settle(t);
    speech.results.single('Opowiedz mi o TIG i otwórz kalkulator', true);
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.byKey(const Key('assistant-voice-session')));
    await t.pump(const Duration(milliseconds: 50));
    response.complete(ChatMessage(role: ChatRole.assistant,
        text: 'Odpowiedź', kind: AiReplyKind.live));
    await settle(t);
    expect(actions, 0);
    expect(voice.spoken, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('tell me about a welding topic starts a conversation', (t) async {
    const question = 'Opowiedz mi o spawaniu TIG';
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async => throw StateError('This asks for information'));
      PremiumService.instance.resetForTest();
      await say(t, question);
      expect(chats, hasLength(1));
      expect(chats.single['message'], question);
      expect(find.textContaining('elektrodę wolframową'), findsWidgets);
      expect(find.textContaining('Które narzędzie'), findsNothing);
      expect(t.takeException(), isNull);
    }, () => MockClient((request) async {
      if (!request.url.path.endsWith('/ai/chat')) throw StateError('Unexpected request');
      chats.add(jsonDecode(request.body) as Map);
      return http.Response(jsonEncode({
        'text': 'TIG wykorzystuje nietopliwą elektrodę wolframową.',
        'calculator_context_used': true,
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  testWidgets('show me how requests an explanation without opening a module', (t) async {
    const question = 'Pokaż mi, jak obliczyć spadek rury';
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async => throw StateError('This asks for an explanation'));
      PremiumService.instance.resetForTest();
      await say(t, question);
      expect(chats, hasLength(1));
      expect(chats.single['message'], question);
      expect(find.textContaining('Podziel różnicę wysokości'), findsWidgets);
      expect(find.textContaining('Które narzędzie'), findsNothing);
      expect(t.takeException(), isNull);
    }, () => MockClient((request) async {
      if (!request.url.path.endsWith('/ai/chat')) throw StateError('Unexpected request');
      chats.add(jsonDecode(request.body) as Map);
      return http.Response(jsonEncode({
        'text': 'Podziel różnicę wysokości przez długość trasy.',
        'calculator_context_used': true,
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  testWidgets('help choosing a gas goes to AI and accepts a clarification',
      (t) async {
    const question = 'Pomóż mi dobrać gaz osłonowy do nierdzewki';
    const clarification = 'TIG, blacha 2 mm';
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t,
          interpret: (_) async =>
              throw StateError('Advice must not enter the module interpreter'));
      PremiumService.instance.resetForTest();
      await say(t, question);
      expect(chats, hasLength(1));
      expect(find.textContaining('Jaka metoda i grubość?'), findsWidgets);
      await say(t, clarification);
      expect(chats, hasLength(2));
      expect(chats.last['message'], clarification);
      expect(chats.last['question_clarification'], {
        'user_turns': [question]
      });
      expect(find.textContaining('Sprawdź WPS i specyfikację'), findsWidgets);
      expect(find.textContaining('Które narzędzie'), findsNothing);
      expect(t.takeException(), isNull);
    },
        () => MockClient((r) async {
              if (r.url.path.endsWith('/ai/chat')) {
                chats.add(jsonDecode(r.body) as Map);
              }
              return http.Response(
                  jsonEncode({
                    'text': chats.length == 1
                        ? 'Jaka metoda i grubość?'
                        : 'Sprawdź WPS i specyfikację.',
                    'needs_clarification': chats.length == 1,
                    if (chats.length > 1) 'question_clarification_used': true,
                    'calculator_context_used': true,
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
  });
  testWidgets('explanation with a follow-up retains the whole question across turns', (t) async {
    const first = 'Jaką grubość ścianki rury mam zastosować?';
    const second = 'Stal 316L, DN50, 10 bar';
    const third = 'Temperatura projektowa 80 stopni i naddatek 1 mm';
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async => throw StateError('Knowledge is not a module command'));
      PremiumService.instance.resetForTest();
      await say(t, first);
      await say(t, second);
      expect(chats, hasLength(2));
      expect(chats[1]['question_clarification'], {'user_turns': [first]});
      expect(find.textContaining('Dane jeszcze nie wystarczają'), findsWidgets);
      await t.tap(find.byKey(const Key('assistant-conversation')));
      await settle(t);
      expect(find.text('Pipe Schedules'), findsOneWidget);
      await t.tap(find.text('Pipe Schedules'));
      await settle(t);
      expect(find.text('Kontekst z aplikacji'), findsOneWidget);
      await t.tap(find.text('OK'));
      await settle(t);
      await t.binding.handlePopRoute();
      await settle(t);
      await say(t, third);
      expect(chats, hasLength(3));
      expect(chats[2]['message'], third);
      expect(chats[2]['question_clarification'], {'user_turns': [first, second]});
      expect(find.textContaining('Należy sprawdzić pełną specyfikację'), findsWidgets);
      expect(t.takeException(), isNull);
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/ai/chat')) chats.add(jsonDecode(r.body) as Map);
      final reply = switch (chats.length) {
        1 => {'text': 'Jakie są materiał i warunki?', 'needs_clarification': true, 'citations': <String>[]},
        2 => {'text': 'Dane jeszcze nie wystarczają. Czy masz temperaturę projektową i naddatek?\n\nWPS i specyfikacja projektu.',
          'needs_clarification': true, 'citations': ['Pipe Schedules'], 'question_clarification_used': true},
        _ => {'text': 'Należy sprawdzić pełną specyfikację.', 'needs_clarification': false,
          'citations': ['Pipe Schedules'], 'question_clarification_used': true},
      };
      reply['calculator_context_used'] = true;
      return http.Response(jsonEncode(reply), 200, headers: {'content-type':'application/json; charset=utf-8'});
    }));
  });
  testWidgets('DN inference sends prior exchange to chat without asking for a module', (t) async {
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async => throw StateError('A contextual inference is not a module command'));
      PremiumService.instance.resetForTest();
      await say(t, 'Co oznacza DN na rurze?');
      await say(t, 'Czyli to zmierzona średnica w milimetrach?');
      expect(chats, hasLength(2));
      expect(chats.last['message'], 'Czyli to zmierzona średnica w milimetrach?');
      expect(chats.last['history'], [
        {'role': 'user', 'text': 'Co oznacza DN na rurze?'},
        {'role': 'assistant', 'text': 'DN to rozmiar nominalny.'},
      ]);
      expect(find.textContaining('Nie, DN jest oznaczeniem nominalnym.'), findsWidgets);
      expect(find.textContaining('Które narzędzie'), findsNothing);
      expect(t.takeException(), isNull);
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/ai/chat')) chats.add(jsonDecode(r.body) as Map);
      return http.Response(jsonEncode({
        'text': chats.length == 1 ? 'DN to rozmiar nominalny.' : 'Nie, DN jest oznaczeniem nominalnym.',
        'calculator_context_used': true,
        'needs_clarification': false,
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  testWidgets('bare topic change asks locally and clears the old clarification', (t) async {
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async => throw StateError('Topic change must stay local'));
      PremiumService.instance.resetForTest();
      await say(t, 'Jak dobrać gaz do spawania?');
      expect(chats, hasLength(1));
      await say(t, 'Mam inne pytanie');
      expect(chats, hasLength(1));
      expect(find.textContaining('Jasne — o co chcesz zapytać?'), findsWidgets);
      await say(t, 'Jak spawać aluminium?');
      expect(chats, hasLength(2));
      expect(chats.last.containsKey('question_clarification'), isFalse);
      expect(t.takeException(), isNull);
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/ai/chat')) chats.add(jsonDecode(r.body) as Map);
      return http.Response(jsonEncode({
        'text': chats.length == 1 ? 'Jaka metoda i materiał?' : 'Nowe wyjaśnienie',
        'needs_clarification': chats.length == 1,
        'question_clarification_used': true, 'calculator_context_used': true,
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  for (final newQuestion in [
    'Mam inne pytanie: dlaczego powstają pory?',
    'New question: why does porosity occur?',
  ]) {
    testWidgets('explicit new topic does not carry a previous clarification: $newQuestion', (t) async {
      final chats = <Map>[];
      await http.runWithClient(() async {
        await mount(t, interpret: (_) async => throw StateError('A new knowledge topic is not a command'));
        PremiumService.instance.resetForTest();
        await say(t, 'Jak dobrać gaz do spawania?');
        await say(t, newQuestion);
        expect(chats, hasLength(2));
        expect(chats.last['message'], newQuestion);
        expect(chats.last.containsKey('question_clarification'), isFalse);
        expect((chats.last['history'] as List).any((m) => m['text'] == 'Jak dobrać gaz do spawania?'), isTrue);
        expect(find.textContaining('Wyjaśnienie nowego tematu'), findsWidgets);
        expect(t.takeException(), isNull);
      }, () => MockClient((r) async {
        if (r.url.path.endsWith('/ai/chat')) chats.add(jsonDecode(r.body) as Map);
        return http.Response(jsonEncode({
          'text': chats.length == 1 ? 'Jaka metoda i materiał?' : 'Wyjaśnienie nowego tematu',
          'needs_clarification': chats.length == 1,
          'question_clarification_used': true,
          'calculator_context_used': true,
        }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }));
    });
  }
  for (final failureKind in [AiReplyKind.unavailable, AiReplyKind.offlineHelp]) {
    testWidgets('temporary initial knowledge failure has one explicit retry: $failureKind', (t) async {
      final questions = <String>[];
      await mount(t, interpret: (_) async => throw StateError('No command expected'),
          chatSender: (text, _) async {
        questions.add(text);
        return ChatMessage(role: ChatRole.assistant,
            text: questions.length == 1 ? 'Chwilowy brak połączenia' : 'Odpowiedź po przywróceniu połączenia',
            kind: questions.length == 1 ? failureKind : AiReplyKind.live);
      });
      await say(t, 'Wyjaśnij spawanie TIG');
      expect(questions, hasLength(1), reason: 'never retry automatically');
      final retry = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
      retry();
      retry();
      await settle(t);
      expect(questions, ['Wyjaśnij spawanie TIG', 'Wyjaśnij spawanie TIG']);
      expect(find.textContaining('Odpowiedź po przywróceniu połączenia'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('old knowledge retry cannot repeat after a native command', (t) async {
    var questions = 0;
    await mount(t, interpret: (_) async => throw StateError('Native calculation must stay local'),
        chatSender: (_, __) async { questions++; throw StateError('Fixture offline'); });
    await say(t, 'Wyjaśnij spawanie TIG');
    final retry = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
    await say(t, 'spadek 1% na 6 metrów');
    await t.enterText(find.byKey(const Key('assistant-command')), 'Nie usuwaj tego szkicu');
    retry();
    await settle(t);
    expect(questions, 1);
    expect(t.widget<TextField>(find.byKey(const Key('assistant-command'))).controller!.text,
        'Nie usuwaj tego szkicu');
    expect(t.takeException(), isNull);
  });
  testWidgets('an old retry cannot mix a failed question with a newer clarification', (t) async {
    final questions = <String>[];
    await mount(t, interpret: (_) async => throw StateError('No command expected'),
        chatSender: (text, _) async {
      questions.add(text);
      if (questions.length == 1) throw StateError('Fixture connection lost');
      return ChatMessage(role: ChatRole.assistant, text: 'Jaki materiał?',
          kind: AiReplyKind.live, needsClarification: true);
    });
    await say(t, 'Wyjaśnij spawanie TIG');
    final oldRetry = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
    await say(t, 'Jak dobrać gaz do spawania?');
    expect(questions, hasLength(2));
    oldRetry();
    await settle(t);
    expect(questions, ['Wyjaśnij spawanie TIG', 'Jak dobrać gaz do spawania?']);
    expect(find.textContaining('Jaki materiał?'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  for (final question in [
    'Jak spawać nierdzewkę metodą TIG?',
    'Jaki gaz dobrać do spawania nierdzewki?',
    'Dlaczego powstają pory w spoinie?',
    'How do I weld stainless steel with TIG?',
    'Explain the difference between MIG and MAG',
    'Wyszukaj w internecie informacje o spawaniu hybrydowym',
    'Search the web for hybrid welding information',
    'Pomóż mi zrozumieć, dlaczego spoina ma pory',
    'Czy możesz mi pomóc zrozumieć spawanie TIG?',
    'Can you help me understand TIG welding?',
    'Czy możesz doradzić, jaki gaz wybrać?',
    'Can you recommend a shielding gas?',
  ]) {
    testWidgets('answers question instead of asking for a module: $question',
        (t) async {
      var interpretations = 0;
      final chats = <Map>[];
      await http.runWithClient(() async {
        await mount(t, interpret: (_) async {
          interpretations++;
          throw StateError('A knowledge question is not a module command');
        });
        PremiumService.instance.resetForTest();
        await say(t, question);
        expect(interpretations, 0);
        expect(chats, hasLength(1));
        expect(chats.single['message'], question);
        expect(chats.single['conversation_mode'], true);
        expect(find.textContaining('Odpowiedź oparta na wiedzy aplikacji'),
            findsWidgets);
        expect(t.takeException(), isNull);
      },
          () => MockClient((r) async {
                if (r.url.path.endsWith('/ai/chat')) {
                  chats.add(jsonDecode(r.body) as Map);
                }
                return http.Response(
                    jsonEncode({
                      'text': 'Odpowiedź oparta na wiedzy aplikacji',
                      'citations': ['TIG'],
                      'needs_clarification': false,
                      'calculator_context_used': true
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }));
    });
  }
  testWidgets(
      'short answer continues the AI question instead of selecting a module',
      (t) async {
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t,
          interpret: (_) async =>
              throw StateError('Unexpected interpretation'));
      PremiumService.instance.resetForTest();
      await say(t, 'Jak dobrać gaz do spawania?');
      expect(find.textContaining('Jaka metoda i materiał?'), findsWidgets);
      await say(t, 'TIG, stal nierdzewna 316L');
      expect(chats, hasLength(2));
      expect(chats.last['question_clarification'], {
        'user_turns': ['Jak dobrać gaz do spawania?'],
      });
      expect(chats.last['message'], 'TIG, stal nierdzewna 316L');
      expect(find.textContaining('Uwzględniam TIG i 316L'), findsWidgets);
      expect(t.takeException(), isNull);
    },
        () => MockClient((r) async {
              if (r.url.path.endsWith('/ai/chat')) {
                chats.add(jsonDecode(r.body) as Map);
              }
              final clarifying = chats.length == 1;
              return http.Response(
                  jsonEncode({
                    'text': clarifying
                        ? 'Jaka metoda i materiał?'
                        : 'Uwzględniam TIG i 316L',
                    'citations': [],
                    'needs_clarification': clarifying,
                    'calculator_context_used': true,
                    'question_clarification_used': true,
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
  });

  for (final followUp in [
    'A 316L?',
    'A 316L',
    'And stainless steel',
    'And stainless steel?',
    'A dla aluminium?',
    'A jeśli spoina ma pory?',
    'What about aluminium?',
    'And for thicker material?',
  ]) {
    testWidgets('follow-up stays in the conversation: $followUp', (t) async {
      final chats = <Map>[];
      var interpretations = 0;
      await http.runWithClient(() async {
        await mount(t, interpret: (_) async {
          interpretations++;
          throw StateError('A follow-up is not a module request');
        });
        PremiumService.instance.resetForTest();
        await say(t, 'Jak spawać nierdzewkę metodą TIG?');
        await say(t, followUp);
        expect(interpretations, 0);
        expect(chats, hasLength(2));
        expect(chats.last['message'], followUp);
        expect(chats.last['history'], [
          {'role': 'user', 'text': 'Jak spawać nierdzewkę metodą TIG?'},
          {'role': 'assistant', 'text': 'Odpowiedź do pierwszego pytania.'},
        ]);
        expect(find.textContaining('Odpowiedź do kontynuacji.'), findsWidgets);
        expect(t.takeException(), isNull);
      },
          () => MockClient((request) async {
                if (request.url.path.endsWith('/ai/chat')) {
                  chats.add(jsonDecode(request.body) as Map);
                }
                return http.Response(
                    jsonEncode({
                      'text': chats.length == 1
                          ? 'Odpowiedź do pierwszego pytania.'
                          : 'Odpowiedź do kontynuacji.',
                      'citations': [],
                      'needs_clarification': false,
                      'calculator_context_used': true,
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }));
    });
  }
  for (final failures in [1, 2]) {
    testWidgets('short follow-up keeps failed questions: $failures', (t) async {
      final chats = <Map>[];
      await http.runWithClient(() async {
        await mount(t,
            interpret: (_) async =>
                throw StateError('A follow-up is not a module request'));
        PremiumService.instance.resetForTest();
        await say(t, 'Jak dobrać gaz do spawania TIG?');
        if (failures == 2) await say(t, 'A dla 316L');
        await say(t, 'A dla aluminium');
        expect(chats, hasLength(failures + 1));
        expect(chats.last['message'], 'A dla aluminium');
        expect(chats.last['question_clarification'], {
          'user_turns': [
            'Jak dobrać gaz do spawania TIG?',
            if (failures == 2) 'A dla 316L'
          ]
        });
        expect(find.textContaining('Odpowiedź o gazie dla aluminium'),
            findsWidgets);
        expect(t.takeException(), isNull);
      },
          () => MockClient((r) async {
                chats.add(jsonDecode(r.body) as Map);
                if (chats.length <= failures) {
                  return http.Response('{"error":{"code":"AI_BUSY"}}', 503);
                }
                return http.Response(
                    jsonEncode({
                      'text': 'Odpowiedź o gazie dla aluminium',
                      'question_clarification_used': true,
                      'calculator_context_used': true,
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }));
    });
  }
}
