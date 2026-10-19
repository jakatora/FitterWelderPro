// Wysyłka feedbacku: bez zgody zero żądań, partie po 20, nagłówek
// X-Feedback-Id, kody odpowiedzi. Atrapa HTTP — zero prawdziwych połączeń.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cut_list_app/config/backend_config.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_signal.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/feedback/feedback_uploader.dart';

import 'feedback_test_utils.dart';

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

List<Map<String, Object?>> _items(http.Request r) => [
      for (final e in (jsonDecode(r.body) as Map)['items'] as List)
        (e as Map).cast()
    ];

void main() {
  final requests = <http.Request>[];
  late FeedbackUploader uploader;

  MockClient backend(FutureOr<http.Response> Function(http.Request) respond) =>
      MockClient((r) async {
        requests.add(r);
        return respond(r);
      });

  MockClient ok() => backend(
      (r) => _json(200, {'accepted': _items(r).length, 'duplicates': 0}));

  Future<int> queued() async => (await FeedbackStore.instance.list()).length;

  setUp(() async {
    requests.clear();
    seedFeedback();
    uploader = FeedbackUploader();
  });

  test('BEZ ZGODY: zero żądań, kolejka nietknięta, brak identyfikatora',
      () async {
    await fill(0, 5);
    final out = await uploader.flush(client: ok());

    expect(out.status, UploadStatus.noConsent);
    expect(out.requests, 0);
    expect(requests, isEmpty);
    expect(await queued(), 5);
    expect(await FeedbackConsent.instance.storedInstallId(), isNull);
  });

  test('pusta kolejka: zero żądań', () async {
    await FeedbackConsent.instance.grant();
    final out = await uploader.flush(client: ok());
    expect(out.status, UploadStatus.empty);
    expect(requests, isEmpty);
  });

  test(
      '45 sygnałów → partie 20 + 20 + 5, nagłówek X-Feedback-Id, kolejka pusta',
      () async {
    await FeedbackConsent.instance.grant();
    await fill(0, 45);

    final out = await uploader.flush(client: ok());

    expect(out.status, UploadStatus.done);
    expect(out.requests, 3);
    expect(out.sent, 45);
    expect(out.accepted, 45);
    expect(out.remaining, 0);
    expect(requests.map((r) => _items(r).length), [20, 20, 5]);

    final feedbackId = await FeedbackConsent.instance.storedInstallId();
    expect(feedbackId, isNotNull);
    expect(feedbackId, matches(RegExp(r'^[A-Za-z0-9_-]{22,64}$')),
        reason: 'format X-Feedback-Id wymagany przez serwer (bez „=”)');
    for (final r in requests) {
      expect(r.method, 'POST');
      expect(r.url.toString(), '${BackendConfig.baseUrl}/api/fitter/feedback');
      expect(r.headers['X-Feedback-Id'], feedbackId);
      expect(r.headers['Content-Type'], startsWith('application/json'));
      expect(r.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-device-id')));
      expect(r.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-install-secret')));
      final body = jsonDecode(r.body) as Map;
      expect(body.keys, ['version', 'items']);
      expect(body['version'], 1);
    }
    // Od najstarszych, każdy element dokładnie raz.
    final sentIds = [
      for (final r in requests) ..._items(r).map((e) => e['id'])
    ];
    expect(sentIds, [for (var i = 0; i < 45; i++) 'sig-$i']);
    expect((await FeedbackStore.instance.stats()).sent, 45);
  });

  test('200: sumuje accepted i duplicates z odpowiedzi', () async {
    await FeedbackConsent.instance.grant();
    await fill(0, 3);
    final out = await uploader.flush(
        client: backend((_) => _json(200, {'accepted': 1, 'duplicates': 2})));
    expect(out.accepted, 1);
    expect(out.duplicates, 2);
    expect(out.sent, 3);
    expect(await queued(), 0);
  });

  group('kody, przy których kolejka zostaje', () {
    final cases = <int, UploadStatus>{
      404: UploadStatus.notDeployed,
      429: UploadStatus.rateLimited,
      503: UploadStatus.serverFull,
      500: UploadStatus.serverError,
      502: UploadStatus.serverError,
      401: UploadStatus.serverError,
    };
    cases.forEach((code, status) {
      test('$code → ${status.name}, jedno żądanie, nic nie usunięte', () async {
        await FeedbackConsent.instance.grant();
        await fill(0, 25);
        final out = await uploader.flush(
            client: backend((_) => _json(code, {'error': 'FEEDBACK_FULL'})));
        expect(out.status, status);
        expect(out.requests, 1);
        expect(out.remaining, 25);
        expect(await queued(), 25);
      });
    });
  });

  group('Retry-After z 429 i 503', () {
    for (final code in [429, 503]) {
      test('$code + Retry-After: 120 → retryAfter 120 s, kolejka zostaje',
          () async {
        await FeedbackConsent.instance.grant();
        await fill(0, 3);
        final out = await uploader.flush(
            client: backend((_) => http.Response(
                  jsonEncode({'error': 'FEEDBACK_FULL'}),
                  code,
                  headers: {'retry-after': '120'},
                )));
        expect(out.retryAfter, const Duration(seconds: 120));
        expect(out.remaining, 3);
      });
    }

    test('bez nagłówka → retryAfter null', () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 1);
      final out = await uploader.flush(client: backend((_) => _json(429, {})));
      expect(out.retryAfter, isNull);
    });
  });

  group(
      'odsiew przed wysyłką (serwer odrzuca całą partię za jeden zły element)',
      () {
    test('niezgodne z kontraktem usunięte z licznikiem, NIE wysłane', () async {
      final good = [for (var i = 0; i < 5; i++) sig(i)];
      final bad = [
        {...sig(10).toJson(), 'text': ''},
        {...sig(11).toJson(), 'errorType': 'E' * 81},
        {...sig(12).toJson(), 'platform': 'linux'},
        {...sig(13).toJson(), 'tool': 't' * 65},
      ];
      seedFeedback({
        FeedbackStore.prefsKey: jsonEncode({
          'v': 1,
          'items': [
            good[0].toJson(),
            bad[0],
            good[1].toJson(),
            bad[1],
            bad[2],
            good[2].toJson(),
            bad[3],
            good[3].toJson(),
            good[4].toJson(),
          ],
        }),
      });
      await FeedbackConsent.instance.grant();

      final out = await uploader.flush(client: ok());

      expect(out.status, UploadStatus.done);
      expect(out.rejected, 4);
      expect(out.sent, 5);
      expect(out.remaining, 0);
      final sentIds = [
        for (final r in requests) ..._items(r).map((e) => e['id'])
      ];
      expect(sentIds, ['sig-0', 'sig-1', 'sig-2', 'sig-3', 'sig-4']);
      expect((await FeedbackStore.instance.stats()).rejected, 4);
    });

    test('partia złożona tylko ze złych: zero żądań', () async {
      seedFeedback({
        FeedbackStore.prefsKey: jsonEncode({
          'v': 1,
          'items': [
            {...sig(1).toJson(), 'lang': 'de'},
            {...sig(2).toJson(), 'kind': 'error', 'text': 'stack'},
          ],
        }),
      });
      await FeedbackConsent.instance.grant();
      final out = await uploader.flush(client: ok());
      expect(requests, isEmpty);
      expect(out.status, UploadStatus.done);
      expect(out.rejected, 2);
      expect(out.remaining, 0);
    });
  });

  test('brak sieci → offline, kolejka zostaje', () async {
    await FeedbackConsent.instance.grant();
    await fill(0, 3);
    final out = await uploader.flush(
        client: backend((_) => throw http.ClientException('no network')));
    expect(out.status, UploadStatus.offline);
    expect(await queued(), 3);
  });

  test('timeout → offline, kolejka zostaje', () async {
    await FeedbackConsent.instance.grant();
    await fill(0, 3);
    uploader = FeedbackUploader(timeout: const Duration(milliseconds: 20));
    final out = await uploader.flush(
        client: backend((_) => Future.delayed(
            const Duration(milliseconds: 300), () => _json(200, {}))));
    expect(out.status, UploadStatus.offline);
    expect(await queued(), 3);
  });

  test('domyślny timeout to 15 s', () {
    expect(FeedbackUploader().timeout, const Duration(seconds: 15));
  });

  test('400 z jednym złym elementem: tylko on usunięty z licznikiem', () async {
    await FeedbackConsent.instance.grant();
    await fill(0, 20);
    final out = await uploader.flush(client: backend((r) {
      final ids = _items(r).map((e) => e['id']);
      return ids.contains('sig-13')
          ? _json(400, {'error': 'VALIDATION'})
          : _json(200, {'accepted': ids.length, 'duplicates': 0});
    }));

    expect(out.status, UploadStatus.done);
    expect(out.rejected, 1);
    expect(out.sent, 19);
    expect(await queued(), 0);
    final st = await FeedbackStore.instance.stats();
    expect(st.rejected, 1);
    expect(st.sent, 19);
    // Każdy dobry element przyjęty dokładnie raz.
    final accepted = [
      for (final r in requests)
        if (!_items(r).any((e) => e['id'] == 'sig-13'))
          ..._items(r).map((e) => e['id'])
    ];
    expect(accepted.toSet(), hasLength(19));
    expect(accepted, hasLength(19));
  });

  test('400 na wszystko: elementy usunięte jako odrzucone', () async {
    await FeedbackConsent.instance.grant();
    await fill(0, 4);
    final out = await uploader.flush(
        client: backend((_) => _json(400, {'error': 'VALIDATION'})));
    expect(out.rejected, 4);
    expect(out.sent, 0);
    expect(await queued(), 0);
    expect((await FeedbackStore.instance.stats()).rejected, 4);
  });

  test('cofnięcie zgody w trakcie: następna partia nie idzie', () async {
    await FeedbackConsent.instance.grant();
    await fill(0, 45);
    final out = await uploader.flush(client: backend((r) async {
      await FeedbackConsent.instance.revoke();
      return _json(200, {'accepted': _items(r).length, 'duplicates': 0});
    }));
    expect(out.status, UploadStatus.noConsent);
    expect(out.requests, 1);
    expect(await queued(), 25);
  });

  test('limit żądań na jedną wysyłkę', () async {
    await FeedbackConsent.instance.grant();
    await fill(0, 60);
    uploader = FeedbackUploader(maxRequests: 2);
    final out = await uploader.flush(client: ok());
    expect(out.status, UploadStatus.requestLimit);
    expect(out.requests, 2);
    expect(out.remaining, 20);
  });

  test('równoległe flush → jedna wysyłka', () async {
    await FeedbackConsent.instance.grant();
    await fill(0, 5);
    final client = ok();
    final results = await Future.wait(
        [uploader.flush(client: client), uploader.flush(client: client)]);
    expect(requests, hasLength(1));
    expect(identical(results[0], results[1]), isTrue);
  });

  test('sygnały z kolejki idą dokładnie w kształcie kontraktu', () async {
    await FeedbackConsent.instance.grant();
    await FeedbackStore.instance.add(FeedbackSignal.create(
      kind: FeedbackKind.error,
      text: 'nie powinno wyjść',
      tool: 'cut_list',
      errorType: 'RangeError',
    ));
    await uploader.flush(client: ok());
    final item = _items(requests.single).single;
    expect(item.keys, [
      'id', 'kind', 'text', 'tool', 'skill', 'skillsVersion', 'app', //
      'platform', 'lang', 'at', 'errorType',
    ]);
    expect(item['kind'], 'error');
    expect(item['text'], '');
    expect(item['errorType'], 'RangeError');
  });
}
