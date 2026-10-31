// Wysyłka feedbacku: bez zgody zero żądań, partie po 20, nagłówek
// X-Feedback-Id, kody odpowiedzi. Atrapa HTTP — zero prawdziwych połączeń.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
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

class _RefusedQueueRemoval extends InMemorySharedPreferencesStore {
  _RefusedQueueRemoval() : super.empty();
  @override
  Future<bool> remove(String key) async {
    if (key == 'flutter.${FeedbackStore.prefsKey}') return false;
    return super.remove(key);
  }
}

class _UnpersistedIdDisk extends InMemorySharedPreferencesStore {
  _UnpersistedIdDisk(this.refuse) : super.empty();
  final bool refuse;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.${FeedbackConsent.installIdKey}') return !refuse;
    return super.setValue(type, key, value);
  }
}

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

  for (final refuse in [false, true]) {
    for (final explicit in [false, true]) {
      test('błąd ID zatrzymuje HTTP (odmowa: $refuse, jawne: $explicit)',
          () async {
        SharedPreferencesStorePlatform.instance = _UnpersistedIdDisk(refuse);
        await FeedbackConsent.instance.grant();
        await fill(0, 1, kind: FeedbackKind.explicit);
        final out = explicit
            ? await uploader.sendExplicit(uid(0), client: ok())
            : await uploader.flush(client: ok());
        expect(out.status, UploadStatus.serverError);
        expect(out.requests, 0);
        expect(requests, isEmpty);
        expect(await queued(), 1);
        expect(await FeedbackConsent.instance.storedInstallId(), isNull);
      });
    }
  }

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
    expect(sentIds, [for (var i = 0; i < 45; i++) uid(i)]);
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

  test(
      'nieudane lokalne usunięcie nie zgłasza sukcesu i zachowuje identyfikator',
      () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _RefusedQueueRemoval();
    await FeedbackStore.instance.add(sig(1));
    final id = await FeedbackConsent.instance.installId();
    final result = await eraseAllFeedback(deleteOnServer: (_) async => true);
    expect(result, FeedbackEraseResult.localFailed);
    expect(await FeedbackConsent.instance.storedInstallId(), id);
    expect(await FeedbackStore.instance.list(), hasLength(1));
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
      expect(sentIds, [uid(0), uid(1), uid(2), uid(3), uid(4)]);
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

  /// Serwer jak backend 5fb551c: 400 INVALID_ITEM z `index` (pierwszy zły)
  /// i `indices` (wszystkie złe, rosnąco) albo 200.
  http.Response judge(http.Request r, Set<String> badIds) {
    final ids = _items(r).map((e) => e['id']).toList();
    final bad = [
      for (var i = 0; i < ids.length; i++)
        if (badIds.contains(ids[i])) i,
    ];
    if (bad.isEmpty) {
      return _json(200, {'accepted': ids.length, 'duplicates': 0});
    }
    return _json(400, {
      'error': {
        'code': kFeedbackInvalidItemCode,
        'message': 'Element ${bad.first}: …',
        'index': bad.first,
        'indices': bad,
      },
    });
  }

  http.Response invalidItem() => _json(400, {
        'error': {
          'code': kFeedbackInvalidItemCode,
          'message': 'zły element',
          'index': 0,
          'indices': [0],
        },
      });

  group(
      '400 INVALID_ITEM: odrzucone dokładnie wskazane indeksy, reszta ponowiona',
      () {
    test('złe automatyczne: tylko one usunięte, reszta partii wysłana raz',
        () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 20);
      final out = await uploader.flush(
          client: backend((r) => judge(r, {uid(4), uid(13)})));

      expect(out.status, UploadStatus.done);
      expect(out.requests, 2, reason: 'bez dzielenia na pół');
      expect(out.rejected, 2);
      expect(out.sent, 18);
      expect(await queued(), 0);
      final st = await FeedbackStore.instance.stats();
      expect(st.rejected, 2);
      expect(st.sent, 18);
      final retried = _items(requests[1]).map((e) => e['id']).toList();
      expect(retried, [
        for (var i = 0; i < 20; i++)
          if (i != 4 && i != 13) uid(i),
      ]);
    });

    test('tylko `index` bez `indices` też wystarcza', () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 3);
      var first = true;
      final out = await uploader.flush(client: backend((r) {
        if (first) {
          first = false;
          return _json(400, {
            'error': {'code': kFeedbackInvalidItemCode, 'index': 1},
          });
        }
        return _json(200, {'accepted': _items(r).length, 'duplicates': 0});
      }));
      expect(out.rejected, 1);
      expect(out.sent, 2);
      expect(_items(requests[1]).map((e) => e['id']), [uid(0), uid(2)]);
    });

    test(
        'INVALID_ITEM bez poprawnych indeksów → protocolError, nic nie '
        'skasowane', () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 3);
      for (final err in <Map<String, Object?>>[
        {'code': kFeedbackInvalidItemCode},
        {
          'code': kFeedbackInvalidItemCode,
          'index': 7,
          'indices': [7, -1]
        },
        {'code': kFeedbackInvalidItemCode, 'indices': 'x'},
      ]) {
        final out = await uploader.flush(
            client: backend((_) => _json(400, {'error': err})));
        expect(out.status, UploadStatus.protocolError, reason: '$err');
        expect(await queued(), 3);
      }
    });

    test('zły JAWNY: zablokowany, nie skasowany, kolejna wysyłka go pomija',
        () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 3);
      await fill(3, 4, kind: FeedbackKind.explicit);
      final out =
          await uploader.flush(client: backend((r) => judge(r, {uid(3)})));

      expect(out.status, UploadStatus.done);
      expect(out.blocked, 1);
      expect(out.rejected, 0);
      expect(out.sent, 3);
      expect((await FeedbackStore.instance.list()).map((e) => e.id), [uid(3)]);
      expect(await FeedbackStore.instance.blockedIds(), {uid(3)});

      requests.clear();
      final again = await uploader.flush(client: ok());
      expect(again.status, UploadStatus.empty);
      expect(requests, isEmpty);
    });
  });

  group('400 bez wskazania elementu = błąd protokołu, nic nie skasowane', () {
    final bodies = <String, Object>{
      'BAD_REQUEST': {
        'error': {'code': 'BAD_REQUEST', 'message': 'Niepoprawne zgłoszenia'},
      },
      'BAD_JSON': {
        'error': {'code': 'BAD_JSON', 'message': 'zły JSON'},
      },
      'BAD_FEEDBACK_ID': {
        'error': {'code': 'BAD_FEEDBACK_ID', 'message': 'zły nagłówek'},
      },
      'UNSUPPORTED_VERSION': {
        'error': {'code': 'UNSUPPORTED_VERSION', 'message': 'version: 1'},
      },
      'bez kodu': {'error': 'oops'},
      'puste ciało': '',
    };
    bodies.forEach((name, body) {
      test(name, () async {
        await FeedbackConsent.instance.grant();
        await fill(0, 5);
        await fill(5, 7, kind: FeedbackKind.explicit);
        final out = await uploader.flush(
            client: backend((_) =>
                body is String ? http.Response(body, 400) : _json(400, body)));

        expect(out.status, UploadStatus.protocolError);
        expect(out.requests, 1, reason: 'bez dzielenia partii');
        expect(out.rejected, 0);
        expect(out.blocked, 0);
        expect(await queued(), 7);
        expect(await FeedbackStore.instance.blockedIds(), isEmpty);
      });
    });

    test('413 PAYLOAD_TOO_LARGE też: nic nie skasowane', () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 3);
      final out = await uploader.flush(
          client: backend((_) => _json(413, {
                'error': {'code': 'PAYLOAD_TOO_LARGE', 'message': 'za duże'},
              })));
      expect(out.status, UploadStatus.protocolError);
      expect(await queued(), 3);
    });
  });

  group('pule limitów: jawne osobnymi partiami i przed automatycznymi', () {
    List<String> kinds(http.Request r) =>
        _items(r).map((e) => e['kind'] as String).toSet().toList();

    test('kolejka mieszana → najpierw same jawne, potem same automatyczne',
        () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 3); // starsze automatyczne
      await fill(3, 25, kind: FeedbackKind.explicit); // 22 jawne
      await fill(25, 27);

      final out = await uploader.flush(client: ok());

      expect(out.status, UploadStatus.done);
      expect(requests.map((r) => _items(r).length), [20, 2, 5]);
      expect(kinds(requests[0]), ['explicit']);
      expect(kinds(requests[1]), ['explicit']);
      expect(kinds(requests[2]), ['notUnderstood']);
      expect(await queued(), 0);
    });

    test('429 w puli jawnych nie wstrzymuje automatycznych', () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 2);
      await fill(2, 3, kind: FeedbackKind.explicit);
      final out = await uploader.flush(client: backend((r) {
        if (kinds(r).contains('explicit')) {
          return http.Response(
              jsonEncode({
                'error': {'code': 'RATE_LIMITED'}
              }),
              429,
              headers: {'retry-after': '600'});
        }
        return _json(200, {'accepted': _items(r).length, 'duplicates': 0});
      }));

      expect(out.status, UploadStatus.rateLimited);
      expect(out.retryAfter, const Duration(seconds: 600));
      expect(out.sent, 2);
      expect((await FeedbackStore.instance.list()).map((e) => e.id), [uid(2)]);
    });

    test('429 w puli automatycznych: jawne już wysłane', () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 2);
      await fill(2, 3, kind: FeedbackKind.explicit);
      final out = await uploader.flush(client: backend((r) {
        if (kinds(r).contains('explicit')) {
          return _json(200, {'accepted': 1, 'duplicates': 0});
        }
        return _json(429, {
          'error': {'code': 'RATE_LIMITED'}
        });
      }));
      expect(out.status, UploadStatus.rateLimited);
      expect(out.sent, 1);
      expect((await FeedbackStore.instance.list()).map((e) => e.id),
          [uid(0), uid(1)]);
    });

    test('503 FEEDBACK_FULL przy jawnych zatrzymuje całą wysyłkę', () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 2);
      await fill(2, 3, kind: FeedbackKind.explicit);
      final out = await uploader.flush(
          client: backend((_) => http.Response(
              jsonEncode({
                'error': {'code': 'FEEDBACK_FULL'}
              }),
              503,
              headers: {'retry-after': '3600'})));
      expect(out.status, UploadStatus.serverFull);
      expect(out.requests, 1);
      expect(out.retryAfter, const Duration(hours: 1));
      expect(await queued(), 3);
    });
  });

  group('„Wyślij” przy jawnym zgłoszeniu (sendExplicit)', () {
    test('bez zgody: wysyła tylko ten jeden element, automatyczne zostają',
        () async {
      await fill(0, 3);
      await fill(3, 4, kind: FeedbackKind.explicit);
      await fill(4, 5, kind: FeedbackKind.explicit);
      expect(await FeedbackConsent.instance.isGranted(), isFalse);

      final out = await uploader.sendExplicit(uid(3), client: ok());

      expect(out.status, UploadStatus.done);
      expect(out.requests, 1);
      expect(out.sent, 1);
      final sent = _items(requests.single);
      expect(sent, hasLength(1));
      expect(sent.single['id'], uid(3));
      expect(sent.single['kind'], 'explicit');
      expect(requests.single.headers['X-Feedback-Id'],
          matches(RegExp(r'^[A-Za-z0-9_-]{22,64}$')));
      expect((await FeedbackStore.instance.list()).map((e) => e.id),
          [uid(0), uid(1), uid(2), uid(4)]);
      expect(await FeedbackConsent.instance.isGranted(), isFalse,
          reason: '„Wyślij” nie włącza zgody na wysyłkę automatyczną');

      // Automatyczne nadal nie idą bez zgody.
      requests.clear();
      final auto = await uploader.flush(client: ok());
      expect(auto.status, UploadStatus.noConsent);
      expect(requests, isEmpty);
    });

    test('automatyczny albo nieznany id → notFound, zero żądań', () async {
      await fill(0, 1);
      expect((await uploader.sendExplicit(uid(0), client: ok())).status,
          UploadStatus.notFound);
      expect((await uploader.sendExplicit(uid(77), client: ok())).status,
          UploadStatus.notFound);
      expect(requests, isEmpty);
      expect(await queued(), 1);
    });

    test('404 / brak sieci: zgłoszenie zostaje', () async {
      await fill(0, 1, kind: FeedbackKind.explicit);
      final out = await uploader.sendExplicit(uid(0),
          client: backend((_) => _json(404, {})));
      expect(out.status, UploadStatus.notDeployed);
      expect(await queued(), 1);
    });

    test('400 INVALID_ITEM: zablokowane, nie skasowane', () async {
      await fill(0, 1, kind: FeedbackKind.explicit);
      final out = await uploader.sendExplicit(uid(0),
          client: backend((_) => invalidItem()));
      expect(out.status, UploadStatus.blocked);
      expect(await queued(), 1);
      expect(await FeedbackStore.instance.blockedIds(), {uid(0)});

      // Ponowne „Wyślij” wolno (decyzja użytkownika); 400 → nadal blokada.
      final again = await uploader.sendExplicit(uid(0),
          client: backend((_) => invalidItem()));
      expect(again.status, UploadStatus.blocked);
      expect(await queued(), 1);
    });

    test('niezgodne z kontraktem: blokada bez żądania', () async {
      seedFeedback({
        FeedbackStore.prefsKey: queueJson([
          {
            ...sig(0, kind: FeedbackKind.explicit).toJson(),
            'app': 'wersja próbna',
          },
        ]),
      });
      final out = await uploader.sendExplicit(uid(0), client: ok());
      expect(out.status, UploadStatus.blocked);
      expect(requests, isEmpty);
      expect(await queued(), 1);
    });
  });

  test('flush: niezgodne JAWNE są blokowane, nie kasowane', () async {
    seedFeedback({
      FeedbackStore.prefsKey: queueJson([
        sig(0),
        {...sig(1, kind: FeedbackKind.explicit).toJson(), 'lang': 'de'},
        {...sig(2).toJson(), 'lang': 'de'},
      ]),
    });
    await FeedbackConsent.instance.grant();
    final out = await uploader.flush(client: ok());
    expect(out.status, UploadStatus.done);
    expect(out.rejected, 1);
    expect(out.blocked, 1);
    expect(_items(requests.single).map((e) => e['id']), [uid(0)]);
    expect((await FeedbackStore.instance.list()).map((e) => e.id), [uid(1)]);
  });

  group('„Usuń moje dane” bez wyścigu z wysyłką (eraseAllFeedback)', () {
    test(
        'POST w toku dochodzi PRZED kasowaniem na serwerze; potem wszystko '
        'lokalnie znika', () async {
      await FeedbackConsent.instance.grant();
      await fill(0, 25);
      final events = <String>[];
      final postStarted = Completer<void>();
      final slow = MockClient((r) async {
        events.add('post-start');
        if (!postStarted.isCompleted) postStarted.complete();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        events.add('post-end');
        return _json(200, {'accepted': _items(r).length, 'duplicates': 0});
      });

      final flushing = FeedbackUploader.instance.flush(client: slow);
      await postStarted.future;
      final id = await FeedbackConsent.instance.storedInstallId();
      expect(id, isNotNull);

      final result = await eraseAllFeedback(deleteOnServer: (feedbackId) async {
        events.add('delete:$feedbackId');
        return true;
      });

      expect(result, FeedbackEraseResult.erased);
      expect(events, ['post-start', 'post-end', 'delete:$id'],
          reason: 'druga partia nie rusza po cofnięciu zgody');
      expect((await flushing).status, UploadStatus.noConsent);
      expect(await FeedbackConsent.instance.isGranted(), isFalse);
      expect(await FeedbackConsent.instance.storedInstallId(), isNull);
      expect(await queued(), 0);
    });

    test('w trakcie kasowania nic nie wychodzi', () async {
      await fill(0, 1, kind: FeedbackKind.explicit);
      await FeedbackConsent.instance.installId();
      final gate = Completer<bool>();
      final erasing = uploader.eraseAll(deleteOnServer: (_) => gate.future);
      await Future<void>.delayed(Duration.zero);

      expect((await uploader.flush(client: ok())).status, UploadStatus.erasing);
      expect((await uploader.sendExplicit(uid(0), client: ok())).status,
          UploadStatus.erasing);
      expect(requests, isEmpty);

      gate.complete(true);
      expect(await erasing, FeedbackEraseResult.erased);
    });

    test('serwer zawiódł: identyfikator ZOSTAJE, zgoda cofnięta, kolejka pusta',
        () async {
      await FeedbackConsent.instance.grant();
      final id = await FeedbackConsent.instance.installId();
      await fill(0, 3);

      for (final failing in <Future<bool> Function(String)>[
        (_) async => false,
        (_) async => throw http.ClientException('offline'),
      ]) {
        final result = await uploader.eraseAll(deleteOnServer: failing);
        expect(result, FeedbackEraseResult.serverFailed);
        expect(await FeedbackConsent.instance.storedInstallId(), id);
        expect(await FeedbackConsent.instance.isGranted(), isFalse);
        expect(await queued(), 0);
      }

      // Ponowienie z działającym serwerem kasuje już wszystko.
      String? deleted;
      final retry = await uploader.eraseAll(deleteOnServer: (fid) async {
        deleted = fid;
        return true;
      });
      expect(retry, FeedbackEraseResult.erased);
      expect(deleted, id);
      expect(await FeedbackConsent.instance.storedInstallId(), isNull);
    });

    test('bez identyfikatora: serwer nie jest wołany', () async {
      await fill(0, 2);
      var called = false;
      final result = await uploader.eraseAll(deleteOnServer: (_) async {
        called = true;
        return true;
      });
      expect(result, FeedbackEraseResult.nothingOnServer);
      expect(called, isFalse);
      expect(await queued(), 0);
    });

    test('waitIdle czeka na „Wyślij” w toku', () async {
      await fill(0, 1, kind: FeedbackKind.explicit);
      final release = Completer<void>();
      final sending = uploader.sendExplicit(uid(0), client: backend((r) async {
        await release.future;
        return _json(200, {'accepted': 1, 'duplicates': 0});
      }));
      var idle = false;
      final waiting = uploader.waitIdle().then((_) => idle = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(idle, isFalse);
      release.complete();
      await waiting;
      expect(idle, isTrue);
      expect((await sending).status, UploadStatus.done);
      await uploader.waitIdle(); // bezczynny → od razu
    });
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
