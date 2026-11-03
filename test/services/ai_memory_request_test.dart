import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/correction_memory.dart';
import 'package:cut_list_app/assistant/ai_clarification.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/ai_professional_context.dart';
import 'package:cut_list_app/services/premium_service.dart';
import '../support/test_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useGuestAccount();
  setUp(() {
    AppLanguageController.current = AppLanguage.pl;
    SharedPreferences.setMockInitialValues({
      'fitter_device_id': '0123456789abcdef0123456789abcdef',
      'fitter_install_secret': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE',
    });
    PremiumService.instance.resetForTest();
    AiProfessionalContext.instance.resetForTest();
    CorrectionMemoryStore.instance.resetForTest();
  });
  const entry = RememberedCorrection(
      question: 'Co to TIG?', correction: 'Chodzi mi o aluminium');

  test('a technical subject from a correction is sent only for a related question', () async {
    await CorrectionMemoryStore.instance.remember(entry);
    final bodies = <Map>[];
    await http.runWithClient(() async {
      await AiChatService.instance.sendMessage('Jak spawać aluminiową rurę?');
      await AiChatService.instance.sendMessage('Jak obliczyć ciężar kołnierza?');
    }, () => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map);
      return http.Response('{"text":"Odpowiedź","remembered_corrections_received":true}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    expect(bodies, hasLength(2));
    expect(bodies.first['remembered_corrections'], [entry.toJson()]);
    expect(bodies.last.containsKey('remembered_corrections'), isFalse);
  });

  test('short clarification carries memory from the original user question', () async {
    await CorrectionMemoryStore.instance.remember(entry);
    late Map body;
    await http.runWithClient(
      () => AiChatService.instance.sendMessage('3 mm',
          questionClarification: AiClarification(
              question: 'Jaka grubość?', userTurns: ['Jak spawać TIG?'])),
      () => MockClient((request) async {
        body = jsonDecode(request.body) as Map;
        return http.Response('{"text":"Odpowiedź","remembered_corrections_received":true,"question_clarification_used":true}', 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }));
    expect(body['remembered_corrections'], [entry.toJson()]);
  });

  test('latest clarification prevents carrying TIG memory to MAG', () async {
    const tig = RememberedCorrection(
        question: 'Jaki gaz do TIG?', correction: 'Chodzi o argon');
    await CorrectionMemoryStore.instance.remember(tig);
    late Map body;
    await http.runWithClient(
      () => AiChatService.instance.sendMessage('Nie TIG, tylko MAG',
          questionClarification: AiClarification(
              question: 'Jaki proces?', userTurns: ['Jaki gaz do TIG?'])),
      () => MockClient((request) async {
        body = jsonDecode(request.body) as Map;
        return http.Response('{"text":"Odpowiedź","question_clarification_used":true}', 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }));
    expect(body.containsKey('remembered_corrections'), isFalse);
  });

  test('declined gas topic is supplied for a later inflected gas question', () async {
    const gas = RememberedCorrection(
        question: 'Jaki gaz osłonowy wybrać?', correction: 'Chodziło mi o hel');
    await CorrectionMemoryStore.instance.remember(gas);
    final bodies = <Map>[];
    await http.runWithClient(() async {
      await AiChatService.instance.sendMessage('Jaki przepływ gazu osłonowego?');
      await AiChatService.instance.sendMessage('Jak zmierzyć średnicę rury?');
    }, () => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map);
      return http.Response('{"text":"Odpowiedź","remembered_corrections_received":true}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    expect(bodies.first['remembered_corrections'], [gas.toJson()]);
    expect(bodies.last.containsKey('remembered_corrections'), isFalse);
  });

  test('a generic method word does not send a TIG correction with a MIG question', () async {
    const tig = RememberedCorrection(
        question: 'Jaka metoda do TIG?', correction: 'Chodzi o aluminium');
    await CorrectionMemoryStore.instance.remember(tig);
    late Map body;
    await http.runWithClient(
        () => AiChatService.instance.sendMessage('Jaką metodę stosować przy MIG?'),
        () => MockClient((request) async {
              body = jsonDecode(request.body) as Map;
              return http.Response('{"text":"Odpowiedź"}', 200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
    expect(body.containsKey('remembered_corrections'), isFalse);
  });

  test('gas correction is sent for TIG but not an explicit MAG question', () async {
    const tig = RememberedCorrection(
        question: 'Jaki gaz osłonowy do TIG?', correction: 'Chodzi o argon');
    await CorrectionMemoryStore.instance.remember(tig);
    final bodies = <Map>[];
    await http.runWithClient(() async {
      await AiChatService.instance.sendMessage('Jaki gaz osłonowy do MAG?');
      await AiChatService.instance.sendMessage('Jaki gaz osłonowy do TIG?');
    }, () => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map);
      return http.Response('{"text":"Odpowiedź","remembered_corrections_received":true}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    expect(bodies.first.containsKey('remembered_corrections'), isFalse);
    expect(bodies.last['remembered_corrections'], [tig.toJson()]);
  });

  test('gas replacement is not sent as context for a different gas', () async {
    const correction = RememberedCorrection(
        question: 'Jaki gaz do TIG?', correction: 'Nie argon, tylko hel');
    await CorrectionMemoryStore.instance.remember(correction);
    final bodies = <Map>[];
    await http.runWithClient(() async {
      await AiChatService.instance.sendMessage('Jaki przepływ argonu do TIG?');
      await AiChatService.instance.sendMessage('Jaki przepływ helu do TIG?');
      await AiChatService.instance.sendMessage('Jaki gaz do TIG?');
    }, () => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map);
      return http.Response('{"text":"Odpowiedź","remembered_corrections_received":true}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    expect(bodies[0].containsKey('remembered_corrections'), isFalse);
    expect(bodies[1]['remembered_corrections'], [correction.toJson()]);
    expect(bodies[2]['remembered_corrections'], [correction.toJson()]);
  });

  test('a not TIG but MAG correction is not sent back with a TIG question', () async {
    const correction = RememberedCorrection(
        question: 'Jaki gaz do TIG?', correction: 'Nie TIG, tylko MAG');
    await CorrectionMemoryStore.instance.remember(correction);
    final bodies = <Map>[];
    await http.runWithClient(() async {
      await AiChatService.instance.sendMessage('Jaki gaz do TIG?');
      await AiChatService.instance.sendMessage('Jaki gaz do MAG?');
    }, () => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map);
      return http.Response('{"text":"Odpowiedź","remembered_corrections_received":true}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    expect(bodies.first.containsKey('remembered_corrections'), isFalse);
    expect(bodies.last['remembered_corrections'], [correction.toJson()]);
  });

  test('older server cannot silently ignore supplied memory', () async {
    await CorrectionMemoryStore.instance.remember(entry);
    final reply = await http.runWithClient(
        () => AiChatService.instance.sendMessage('Jak działa TIG?'),
        () => MockClient((request) async {
              final body = jsonDecode(request.body) as Map;
              expect(body['remembered_corrections'], [entry.toJson()]);
              return http.Response('{"text":"Niepotwierdzona odpowiedź"}', 200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
    expect(reply.kind, AiReplyKind.unavailable);
    expect(reply.text, contains('nie potwierdził'));
  });

  test('deleting memory while request is in flight invalidates its answer',
      () async {
    await CorrectionMemoryStore.instance.remember(entry);
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final pending = http.runWithClient(
        () => AiChatService.instance.sendMessage('Jak działa TIG?'),
        () => MockClient((request) async {
              expect(
                  (jsonDecode(request.body) as Map)['remembered_corrections'],
                  [entry.toJson()]);
              started.complete();
              return response.future;
            }));
    await started.future;
    await CorrectionMemoryStore.instance.clear();
    response.complete(http.Response(
        '{"text":"Odpowiedź","remembered_corrections_received":true}', 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    final reply = await pending;
    expect(reply.kind, AiReplyKind.unavailable);
    expect(reply.text, contains('Pamięć asystenta zmieniła się'));
  });
}
