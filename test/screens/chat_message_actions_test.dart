// Czat: zgłoś / zablokuj muszą być WIDOCZNE, nie tylko pod długim
// przytrzymaniem (czytnik ekranu go nie ogłaszał, recenzent Apple mógł go nie
// znaleźć), „Wyślij" ma etykietę, a podpis i godzina w dymkach spełniają
// WCAG AA (4,5:1). Atrapa HTTP — zero prawdziwych połączeń.

import 'dart:convert';
import '../support/test_account.dart';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'package:cut_list_app/theme/app_theme.dart';

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

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

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
    ReportedMessages.instance.resetForTest();
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
      if (r.method == 'POST' && r.url.path == '/api/fitter/chat/report') {
        return _json(201, {'ok': true});
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

  testWidgets('widoczny przycisk ⋮ przy cudzej wiadomości, ≥ 48 dp',
      (tester) async {
    await openRoom(tester);

    // Tylko przy cudzej wiadomości — siebie się nie zgłasza.
    final more = find.byTooltip('Message actions: Zbigniew Hałas');
    expect(more, findsOneWidget);
    expect(find.byTooltip('Message actions: Marek Kowalczyk'), findsNothing);
    final size = tester.getSize(more);
    expect(size.width, greaterThanOrEqualTo(kMinTapTarget));
    expect(size.height, greaterThanOrEqualTo(kMinTapTarget));

    await tester.tap(more);
    await pumpFor(tester, 4);
    expect(find.text('Report message'), findsOneWidget);
    expect(find.text('Block author'), findsOneWidget);
    await close(tester);
  });

  testWidgets('dymek ogłasza akcję przytrzymania czytnikowi ekranu',
      (tester) async {
    final handle = tester.ensureSemantics();
    await openRoom(tester);
    final node = tester.getSemantics(find.text('Kto ma P91?'));
    // Przytrzymanie to skrót — akcja ma podpowiedź, a nie jest ukryta.
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.longPress), isTrue);
    expect(node.hintOverrides?.onLongPressHint, 'Report or block');
    await close(tester);
    handle.dispose();
  });

  testWidgets('„Wyślij" ma etykietę i cel dotyku ≥ 48 dp', (tester) async {
    await openRoom(tester);
    final send = find.byTooltip('Send');
    expect(send, findsOneWidget);
    expect(tester.getSize(send).height, greaterThanOrEqualTo(kMinTapTarget));
    await close(tester);
  });

  testWidgets('zgłoszona wiadomość znika u zgłaszającego od razu',
      (tester) async {
    await openRoom(tester);
    await tester.tap(find.byTooltip('Message actions: Zbigniew Hałas'));
    await pumpFor(tester, 4);
    await tester.tap(find.text('Report message'));
    await pumpFor(tester, 4);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Report'));
    await pumpFor(tester, 6);

    final report = requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path == '/api/fitter/chat/report');
    expect(jsonDecode(report.body)['id'], 1);
    expect(find.text('Kto ma P91?'), findsNothing);
    expect(ReportedMessages.instance.isReported(1), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ReportedMessages.prefsKey), isNotNull);
    // Własna wiadomość zostaje.
    expect(find.text('Ja mam'), findsOneWidget);
    await close(tester);
  });

  group('kontrast w dymkach (WCAG AA 4,5:1)', () {
    // Własny dymek to fiolet 50% na tle ekranu — kolor, który naprawdę widać.
    final mineBubble = Color.alphaBlend(kChatMineBubble, kBg);

    test('podpis autora na cudzym dymku', () {
      expect(_contrast(kChatAuthorName, kCard), greaterThanOrEqualTo(4.5));
    });

    test('godzina we własnym dymku', () {
      expect(_contrast(kChatTimeOnMine, mineBubble), greaterThanOrEqualTo(4.5));
    });

    test('godzina w cudzym dymku', () {
      expect(_contrast(kChatTimeOnOthers, kCard), greaterThanOrEqualTo(4.5));
    });

    test('treść we własnym dymku', () {
      expect(_contrast(kText, mineBubble), greaterThanOrEqualTo(4.5));
    });

    test('stare wartości były za słabe (3,7:1 i 3,3:1)', () {
      expect(_contrast(const Color(0xFFAB47BC), kCard), lessThan(4.5));
      expect(_contrast(kTextMut, mineBubble), lessThan(4.5));
    });
  });
}
