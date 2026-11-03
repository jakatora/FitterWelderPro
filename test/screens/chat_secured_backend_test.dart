// Ekran czatu na nowym backendzie: własne wiadomości po `mine`, blokada po
// `author_id`, rejestracja urządzenia przy wejściu (po zgodzie) i zrozumiały
// komunikat, gdy serwer odrzuci sekret instalacji. Atrapa HTTP.

import 'dart:async';
import 'dart:convert';
import '../support/test_account.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/screens/chat_screen.dart';
import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/blocked_users.dart';
import 'package:cut_list_app/services/chat_service.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/services/user_profile.dart';

const _myDevice = '0123456789abcdef0123456789abcdef';
const _secret = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';
const _otherAuthor = 'a_22222222222222222222222222222222';

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _msg(int id, String device, String author, String nick,
        String text, bool mine) =>
    {
      'id': id,
      'room': 'general',
      'device_id': device,
      'author_id': author,
      'nickname': nick,
      'text': text,
      'flags': 0,
      'created_at': '2026-09-24T10:0$id:00.000Z',
      'mine': mine,
    };

void main() {
  final requests = <http.Request>[];
  String? retainedSince;
  List<Map<String, dynamic>>? messageBatch;
  bool strictSince = false;
  bool idCursor = false;
  Map<String, dynamic>? postResult;
  Completer<http.Response>? delayedGet;

  setUp(() async {
    requests.clear();
    retainedSince = null;
    messageBatch = null;
    strictSince = false;
    idCursor = false;
    postResult = null;
    delayedGet = null;
    SharedPreferences.setMockInitialValues({
      'user_profile_v1':
          jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
      'legal_consent_v1': jsonEncode({
        'version': kLegalVersion,
        'acceptedAt': '2026-09-24T12:00:00.000',
      }),
      'fitter_device_id': _myDevice,
      'fitter_install_secret': _secret,
    });
    UserProfileService.instance.resetForTest();
    await seedSignedInAccount();
    LegalConsent.instance.resetForTest();
    BlockedUsers.instance.resetForTest();
    PremiumService.instance.resetForTest();
    ApiClient.instance.debugSetClient(MockClient((r) async {
      requests.add(r);
      if (r.url.path == '/api/fitter/device/register') {
        return _json(201, {'registered': true, 'author_id': 'a_me'});
      }
      if (r.method == 'GET' && r.url.path == '/api/fitter/chat/messages') {
        if (delayedGet != null) return delayedGet!.future;
        final messages = messageBatch ?? [
          _msg(1, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', 'Kto ma P91?', false),
          _msg(2, _myDevice, 'a_me', 'Marek Kowalczyk', 'Ja mam', true),
        ];
        final since = r.url.queryParameters['since'];
        final afterId = int.tryParse(r.url.queryParameters['after_id'] ?? '');
        final limit = int.tryParse(r.url.queryParameters['limit'] ?? '') ?? 100;
        return _json(200, {
          if (retainedSince != null) 'retained_since': retainedSince,
          if (idCursor) 'cursor_version': 1,
          'messages': idCursor && afterId != null
              ? messages.where((m) => (m['id'] as int) > afterId).take(limit).toList()
              : strictSince && since != null
              ? messages.where((m) => DateTime.parse(m['created_at'] as String)
                  .isAfter(DateTime.parse(since))).toList()
              : messages,
        });
      }
      if (r.method == 'POST' && r.url.path == '/api/fitter/chat/messages') {
        if (postResult != null) return _json(201, {'message': postResult});
        return _json(401, {
          'error': {
            'code': 'INSTALL_SECRET_INVALID',
            'message': 'Nieprawidłowy sekret instalacji dla tego urządzenia.'
          }
        });
      }
      return _json(404, {
        'error': {'code': 'NOT_FOUND', 'message': 'x'}
      });
    }));
  });

  tearDown(() => ApiClient.instance.debugSetClient(null));

  Future<void> pumpFor(WidgetTester tester, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openRoom(WidgetTester tester) async {
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(
        home: ChatScreen(
          loadRooms: () async => const [
            ChatRoom(
              id: 'general',
              namePl: 'Ogólny',
              nameEn: 'General',
              descPl: 'Wszystko',
              descEn: 'Anything',
            ),
          ],
        ),
      ),
    ));
    await pumpFor(tester, 4);
    await tester.tap(find.text('General'));
    await pumpFor(tester, 8);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpFor(tester, 2);
  }

  testWidgets('wejście na czat rejestruje urządzenie; własne po mine',
      (tester) async {
    await openRoom(tester);

    final register = requests
        .where((r) => r.url.path == '/api/fitter/device/register')
        .toList();
    expect(register, hasLength(1));
    expect(register.single.headers[kInstallSecretHeader], _secret);

    final get = requests.firstWhere(
        (r) => r.method == 'GET' && r.url.path == '/api/fitter/chat/messages');
    expect(get.headers[kDeviceIdHeader], _myDevice);
    expect(get.headers[kInstallSecretHeader], _secret);

    // Cudza wiadomość ma podpis, własna — nie (dymek „mój").
    expect(find.text('Zbigniew Hałas'), findsOneWidget);
    expect(find.text('Marek Kowalczyk'), findsNothing);
    expect(find.text('Ja mam'), findsOneWidget);
    await close(tester);
  });

  testWidgets('nowa wiadomość z tym samym czasem nie znika przy odpytywaniu', (tester) async {
    final first = _msg(1, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', 'Pierwsza', false);
    final second = _msg(2, _myDevice, 'a_me', 'Marek Kowalczyk', 'Druga w tym samym czasie', true)
      ..['created_at'] = first['created_at'];
    strictSince = true;
    messageBatch = [first];
    await openRoom(tester);
    messageBatch = [first, second];
    await tester.pump(const Duration(seconds: 8));
    await pumpFor(tester, 8);
    expect(find.text('Pierwsza'), findsOneWidget);
    expect(find.text('Druga w tym samym czasie'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await pumpFor(tester, 4);
    expect(find.text('Druga w tym samym czasie'), findsOneWidget);
    await close(tester);
  });

  testWidgets('kursor pobiera ponad sto wiadomości z tym samym czasem', (tester) async {
    final first = _msg(1, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', 'Pierwsza', false);
    idCursor = true;
    messageBatch = [first];
    await openRoom(tester);
    messageBatch = [first, for (var i = 2; i <= 126; i++)
      _msg(i, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', 'Wiadomość $i', false)
        ..['created_at'] = first['created_at']];
    await tester.pump(const Duration(seconds: 8));
    await pumpFor(tester, 8);
    await tester.pump(const Duration(seconds: 8));
    await pumpFor(tester, 8);
    await tester.pump(const Duration(seconds: 8));
    await pumpFor(tester, 4);
    final cursors = requests.where((r) => r.method == 'GET' &&
        r.url.path == '/api/fitter/chat/messages' && r.url.queryParameters.containsKey('after_id'))
        .map((r) => r.url.queryParameters['after_id']).toList();
    expect(cursors, ['1', '101', '126']);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('własny wpis nie przesuwa kursora przed pobraniem cudzej wiadomości', (tester) async {
    final first = _msg(1, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', 'Pierwsza', false);
    final other = _msg(2, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', 'Wiadomość innej osoby', false);
    final own = _msg(3, _myDevice, 'a_me', 'Marek Kowalczyk', 'Moja wiadomość', true);
    idCursor = true;
    messageBatch = [first];
    postResult = own;
    await openRoom(tester);
    await tester.enterText(find.byType(TextField), 'Moja wiadomość');
    await tester.tap(find.byTooltip('Send'));
    await pumpFor(tester, 5);
    messageBatch = [first, other, own];
    await tester.pump(const Duration(seconds: 8));
    await pumpFor(tester, 8);
    expect(find.text('Wiadomość innej osoby'), findsOneWidget);
    expect(find.text('Moja wiadomość'), findsOneWidget);
    final delta = requests.lastWhere((r) => r.method == 'GET' &&
        r.url.path == '/api/fitter/chat/messages');
    expect(delta.url.queryParameters['after_id'], '1');
    await close(tester);
  });

  testWidgets('starsze odświeżenie nie usuwa wiadomości wysłanej w trakcie ładowania', (tester) async {
    final first = _msg(1, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', 'Wcześniejsza', false);
    final own = _msg(2, _myDevice, 'a_me', 'Marek Kowalczyk', 'Nowa podczas ładowania', true);
    idCursor = true;
    delayedGet = Completer<http.Response>();
    postResult = own;
    await openRoom(tester);
    await tester.enterText(find.byType(TextField), 'Nowa podczas ładowania');
    await tester.tap(find.byTooltip('Send'));
    await pumpFor(tester, 5);
    delayedGet!.complete(_json(200, {'messages': [first], 'cursor_version': 1}));
    await pumpFor(tester, 8);
    expect(find.text('Wcześniejsza'), findsOneWidget);
    expect(find.text('Nowa podczas ładowania'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('otwarty czat usuwa wygasłą wiadomość po odświeżeniu serwera',
      (tester) async {
    await openRoom(tester);
    expect(find.text('Kto ma P91?'), findsOneWidget);
    expect(find.text('Ja mam'), findsOneWidget);
    expect(find.text('Messages are periodically deleted after one month.'), findsNothing);
    retainedSince = '2026-09-24T10:01:30.000Z';
    await tester.pump(const Duration(seconds: 8));
    await pumpFor(tester, 5);
    expect(find.text('Kto ma P91?'), findsNothing);
    expect(find.text('Ja mam'), findsOneWidget);
    expect(find.text('Messages are periodically deleted after one month.'), findsOneWidget);
    retainedSince = null;
    await tester.pump(const Duration(seconds: 8));
    await pumpFor(tester, 5);
    expect(find.text('Messages are periodically deleted after one month.'), findsNothing);
    await close(tester);
  });

  for (final atBottom in [false, true]) {
    testWidgets('nowa wiadomość ${atBottom ? 'śledzi koniec' : 'nie odrywa od historii'}',
        (tester) async {
      Map<String, dynamic> message(int id) => {
        ..._msg(id, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', 'Wiadomość numer $id', false),
        'created_at': DateTime.utc(2026, 9, 24, 10).add(Duration(minutes: id)).toIso8601String(),
      };
      messageBatch = [for (var i = 1; i <= 30; i++) message(i)];
      await openRoom(tester);
      final list = find.byKey(const Key('chat-message-list'));
      final controller = tester.widget<ListView>(list).controller!;
      await pumpFor(tester, 5);
      expect(controller.position.maxScrollExtent, greaterThan(500));
      if (!atBottom) {
        await tester.drag(list, const Offset(0, 500));
        await pumpFor(tester, 5);
        expect(controller.position.extentAfter, greaterThan(96));
      }
      final previousOffset = controller.offset;
      messageBatch = [...messageBatch!, message(31)];
      await tester.pump(const Duration(seconds: 8));
      await pumpFor(tester, 8);
      if (atBottom) {
        expect(controller.position.extentAfter, lessThan(1));
        expect(controller.offset, greaterThan(previousOffset));
        expect(find.byKey(const Key('chat-new-messages')), findsNothing);
      } else {
        expect(controller.offset, closeTo(previousOffset, 1));
        expect(controller.position.extentAfter, greaterThan(96));
        final newMessages = find.byKey(const Key('chat-new-messages'));
        expect(newMessages, findsOneWidget);
        await tester.tap(newMessages);
        await pumpFor(tester, 5);
        expect(controller.position.extentAfter, lessThan(1));
        expect(newMessages, findsNothing);
      }
      await close(tester);
    });
  }

  testWidgets('blokada zapisuje author_id i ukrywa autora', (tester) async {
    await openRoom(tester);
    await tester.longPress(find.text('Kto ma P91?'));
    await pumpFor(tester, 4);
    await tester.tap(find.text('Block author'));
    await pumpFor(tester, 4);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Block'));
    await pumpFor(tester, 4);

    expect(BlockedUsers.instance.isBlocked(_otherAuthor), isTrue);
    expect(BlockedUsers.instance.all.single.name, 'Zbigniew Hałas');
    expect(find.text('Kto ma P91?'), findsNothing);
    await close(tester);
  });

  testWidgets('401 INSTALL_SECRET_INVALID: zrozumiały komunikat bez „Ponów"',
      (tester) async {
    await openRoom(tester);
    await tester.enterText(find.byType(TextField), 'Dzień dobry');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await pumpFor(tester, 6);

    expect(find.textContaining('did not recognise this app installation'),
        findsOneWidget);
    expect(find.textContaining('INSTALL_SECRET'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsNothing);
    // Tekst zostaje w polu — nic nie zginęło.
    expect(find.text('Dzień dobry'), findsOneWidget);
    await close(tester);
  });

  test('ChatFailure.installSecret dla odrzuconego sekretu', () {
    expect(
      classifyChatError(ApiException(
          statusCode: 401,
          path: '/api/fitter/chat/messages',
          backendCode: 'INSTALL_SECRET_INVALID')),
      ChatFailure.installSecret,
    );
  });
}
