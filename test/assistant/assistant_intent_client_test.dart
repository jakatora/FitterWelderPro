// Klient POST /api/fitter/ai/intent i silnik asystenta (parser lokalny →
// ewentualnie serwer → TEN SAM walidator). Transport to atrapa
// (http.runWithClient + MockClient) — zero połączeń z prawdziwym serwerem.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/assistant/assistant_engine.dart';
import 'package:cut_list_app/assistant/assistant_intent_client.dart';
import 'package:cut_list_app/assistant/assistant_intents.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/premium_service.dart';

const _deviceId = '0123456789abcdef0123456789abcdef';
const _secret = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  final requests = <http.Request>[];

  Future<T> withServer<T>(
    Future<T> Function() body,
    Future<http.Response> Function(http.Request) handler,
  ) =>
      http.runWithClient(body, () => MockClient((r) async {
            requests.add(r);
            return handler(r);
          }));

  setUp(() {
    requests.clear();
    SharedPreferences.setMockInitialValues({
      'fitter_device_id': _deviceId,
      'fitter_install_secret': _secret,
    });
    PremiumService.instance.resetForTest();
  });

  group('klient /ai/intent', () {
    const client = AssistantIntentClient();

    test('temporary API throttle does not claim a daily limit', () async {
      final result = await withServer(
        () => client.classify('Co oznacza DN?', AppLanguage.pl),
        (_) async => _json({'error': {'code': 'API_RATE_LIMITED'}}, 429),
      );
      expect(result, isA<RemoteIntentUnavailable>().having(
          (r) => r.kind, 'kind', RemoteUnavailableKind.busy));
    });

    test('kształt żądania: nagłówki tożsamości, text, lang, intents_version',
        () async {
      final r = await withServer(
        () => client.classify('zapisz coś', AppLanguage.en),
        (_) async => _json({
          'intent': 'open_tool',
          'fields': {'query': 'heat input'},
          'question': null,
        }),
      );
      final req = requests.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/api/fitter/ai/intent');
      expect(req.headers[kDeviceIdHeader], _deviceId);
      expect(req.headers[kInstallSecretHeader], _secret);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body, {'text': 'zapisz coś', 'lang': 'en', 'intents_version': 1});

      expect(r, isA<RemoteIntentProposal>());
      final p = r as RemoteIntentProposal;
      expect(p.intent, 'open_tool');
      expect(p.fields, {'query': 'heat input'});
      expect(p.question, isNull);
    });

    final statusCases = <int, RemoteUnavailableKind>{
      402: RemoteUnavailableKind.premiumRequired,
      429: RemoteUnavailableKind.dailyLimit,
      503: RemoteUnavailableKind.busy,
      401: RemoteUnavailableKind.unauthorized,
      404: RemoteUnavailableKind.offline, // stary backend bez trasy
      500: RemoteUnavailableKind.error,
    };
    statusCases.forEach((status, kind) {
      test('HTTP $status → $kind', () async {
        final r = await withServer(
          () => client.classify('x', AppLanguage.pl),
          (_) async => _json({
            'error': {'code': 'X', 'message': 'x'}
          }, status),
        );
        expect((r as RemoteIntentUnavailable).kind, kind);
      });
    });

    test('brak sieci → offline', () async {
      final r = await withServer(
        () => client.classify('x', AppLanguage.pl),
        (_) async => throw const SocketException('offline'),
      );
      expect((r as RemoteIntentUnavailable).kind, RemoteUnavailableKind.offline);
    });

    test('odpowiedź nie-JSON albo bez intencji → malformed', () async {
      for (final body in [
        http.Response('<html>', 200),
        _json({'fields': {}}),
        _json({'intent': 'save_weld_parameter', 'fields': 'current=60'}),
        _json(['save_weld_parameter']),
      ]) {
        final r = await withServer(
          () => client.classify('x', AppLanguage.pl),
          (_) async => body,
        );
        expect((r as RemoteIntentUnavailable).kind,
            RemoteUnavailableKind.malformed,
            reason: body.body);
      }
    });
  });

  group('silnik: parser lokalny najpierw', () {
    test('kompletne zdanie → gotowe bez pytania serwera', () async {
      var asked = 0;
      final engine = AssistantEngine(remoteAllowed: () async {
        asked++;
        return true;
      });
      final out = await withServer(
        () => engine.interpret(
            'Zapisz, że spawam stal nierdzewną, ściankę 2 mm, TIG bez drutu na 60 amperach',
            lang: AppLanguage.pl),
        (_) async => fail('nie wolno pytać serwera'),
      );
      expect(out.check, isA<AssistantReadyToSave>());
      expect(out.usedRemote, isFalse);
      expect(asked, 0);
      expect(requests, isEmpty);
    });

    test('intencje tylko lokalne nigdy nie idą na serwer (nawet ze zgodą)',
        () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      for (final text in [
        'dopisz spoinę numer 12 do dziennika', // brak projektu → pytanie
        'jaki prąd mam zapisany na nierdzewkę 2 mm',
        'jaki prąd na TIG nierdzewka 2 mm',
      ]) {
        final out = await withServer(
          () => engine.interpret(text, lang: AppLanguage.pl),
          (_) async => fail('intencja lokalna nie może pytać serwera: $text'),
        );
        expect(out.usedRemote, isFalse, reason: text);
        expect(out.check, isNotNull, reason: text);
      }
      expect(requests, isEmpty);
    });

    test('serwer nie może zwrócić intencji tylko lokalnej', () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await withServer(
        () => engine.interpret('coś niejasnego', lang: AppLanguage.pl),
        (_) async => _json({
          'intent': 'add_weld_journal_entry',
          'fields': {'weld_no': '1', 'project': 'X'},
        }),
      );
      expect((out.check as AssistantRejected).reason,
          AssistantRejectReason.unknownIntent);
    });

    test('nierozpoznane, bez zgody → nie pyta serwera', () async {
      final engine = AssistantEngine(remoteAllowed: () async => false);
      final out = await withServer(
        () => engine.interpret('zrób mi kawę', lang: AppLanguage.pl),
        (_) async => fail('bez zgody nic nie wychodzi'),
      );
      expect(out.check, isNull);
      expect(out.remoteUnavailable, RemoteUnavailableKind.notAllowed);
      expect(requests, isEmpty);
    });

    test('nierozpoznane, zgoda → wynik serwera przez walidator', () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await withServer(
        () => engine.interpret('spawałem wczoraj rurkę', lang: AppLanguage.pl),
        (_) async => _json({
          'intent': 'save_weld_parameter',
          'fields': {
            'material': 'SS',
            'process': 'TIG',
            'filler': true,
            'wall_mm': 2,
            'current_a': 70,
          },
          'question': null,
        }),
      );
      expect(out.usedRemote, isTrue);
      final d = (out.check as AssistantReadyToSave).draft;
      expect(d.currentA, 70.0);
      expect(d.wallMm, 2.0);
    });

    test('model zwraca pole spoza listy → odrzucone', () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await withServer(
        () => engine.interpret('coś niejasnego', lang: AppLanguage.pl),
        (_) async => _json({
          'intent': 'save_weld_parameter',
          'fields': {
            'material': 'SS',
            'process': 'TIG',
            'filler': true,
            'wall_mm': 2,
            'current_a': 70,
            'sql': 'DELETE FROM weld_params',
          },
        }),
      );
      expect(out.check, isA<AssistantRejected>());
      expect((out.check as AssistantRejected).reason,
          AssistantRejectReason.extraField);
      expect(out.remoteRejected, AssistantRejectReason.extraField);
    });

    test('model zwraca prąd 5000 A → odrzucone', () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await withServer(
        () => engine.interpret('coś niejasnego', lang: AppLanguage.pl),
        (_) async => _json({
          'intent': 'save_weld_parameter',
          'fields': {
            'material': 'SS',
            'process': 'TIG',
            'filler': true,
            'wall_mm': 2,
            'current_a': 5000,
          },
        }),
      );
      expect((out.check as AssistantRejected).reason,
          AssistantRejectReason.outOfRange);
    });

    test('model zwraca intencję spoza listy → odrzucone', () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await withServer(
        () => engine.interpret('coś niejasnego', lang: AppLanguage.pl),
        (_) async => _json({'intent': 'delete_all_params', 'fields': {}}),
      );
      expect((out.check as AssistantRejected).reason,
          AssistantRejectReason.unknownIntent);
    });

    test('model: unknown z pytaniem → nie rozumiem + pytanie serwera', () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await withServer(
        () => engine.interpret('hmm', lang: AppLanguage.pl),
        (_) async => _json({
          'intent': 'unknown',
          'fields': {},
          'question': 'Co mam zapisać?',
        }),
      );
      expect(out.check, isNull);
      expect(out.remoteQuestion, 'Co mam zapisać?');
    });

    test('brak ściany lokalnie → serwer uzupełnia, lokalne wartości wygrywają',
        () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await withServer(
        () => engine.interpret('Zapisz nierdzewka TIG bez drutu 60 A, ta cienka',
            lang: AppLanguage.pl),
        (_) async => _json({
          'intent': 'save_weld_parameter',
          'fields': {
            'material': 'CS', // lokalnie rozpoznano SS — lokalne wygrywa
            'process': 'TIG',
            'filler': false,
            'wall_mm': 1.5,
            'current_a': 60,
          },
        }),
      );
      final d = (out.check as AssistantReadyToSave).draft;
      expect(d.material, 'SS');
      expect(d.wallMm, 1.5);
      expect(out.usedRemote, isTrue);
    });

    test('brak ściany, serwer zwraca śmieci → pytanie lokalne, śmieci odrzucone',
        () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await withServer(
        () => engine.interpret('Zapisz nierdzewka TIG bez drutu 60 A',
            lang: AppLanguage.pl),
        (_) async => _json({
          'intent': 'save_weld_parameter',
          'fields': {'wall_mm': 2, 'owner': 'admin'},
        }),
      );
      expect((out.check as AssistantNeedsField).field, 'wall_mm');
      expect(out.remoteRejected, AssistantRejectReason.extraField);
      expect(out.fields.containsKey('owner'), isFalse);
    });

    test('brak ściany, serwer niedostępny (402) → pytanie lokalne', () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await withServer(
        () => engine.interpret('Zapisz nierdzewka TIG bez drutu 60 A',
            lang: AppLanguage.pl),
        (_) async => _json({
          'error': {'code': 'PREMIUM_REQUIRED'}
        }, 402),
      );
      expect((out.check as AssistantNeedsField).field, 'wall_mm');
      expect(out.remoteUnavailable, RemoteUnavailableKind.premiumRequired);
    });

    test('odpowiedź na pytanie o pole łączy się z poprzednimi polami',
        () async {
      final engine = AssistantEngine(remoteAllowed: () async => false);
      final first = await engine.interpret(
          'Zapisz nierdzewka TIG bez drutu 60 A',
          lang: AppLanguage.pl);
      expect((first.check as AssistantNeedsField).field, 'wall_mm');
      final second = await engine.interpret('dwa milimetry',
          lang: AppLanguage.pl,
          carried: first.fields,
          carriedIntent: kIntentSaveWeldParameter,
          answeringField: 'wall_mm');
      final d = (second.check as AssistantReadyToSave).draft;
      expect(d.wallMm, 2.0);
      expect(d.currentA, 60.0);
      expect(d.material, 'SS');
    });
  });
}
