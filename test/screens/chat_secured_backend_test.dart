// Ekran czatu na nowym backendzie: własne wiadomości po `mine`, blokada po
// `author_id`, rejestracja urządzenia przy wejściu (po zgodzie) i zrozumiały
// komunikat, gdy serwer odrzuci sekret instalacji. Atrapa HTTP.

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

  setUp(() async {
    requests.clear();
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
        return _json(200, {
          'messages': [
            _msg(1, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', 'Kto ma P91?',
                false),
            _msg(2, _myDevice, 'a_me', 'Marek Kowalczyk', 'Ja mam', true),
          ]
        });
      }
      if (r.method == 'POST' && r.url.path == '/api/fitter/chat/messages') {
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
