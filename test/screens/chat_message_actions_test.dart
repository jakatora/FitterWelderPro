// Czat: zgłoś / zablokuj muszą być WIDOCZNE, nie tylko pod długim
// przytrzymaniem (czytnik ekranu go nie ogłaszał, recenzent Apple mógł go nie
// znaleźć), „Wyślij" ma etykietę, a podpis i godzina w dymkach spełniają
// WCAG AA (4,5:1). Atrapa HTTP — zero prawdziwych połączeń.

import 'dart:convert';
import 'dart:async';
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
import 'package:cut_list_app/services/account_service.dart';
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
  var otherText = 'Kto ma P91?';
  List<Map<String, dynamic>>? customMessages;
  Completer<http.Response>? delayedSend;
  List<http.Response>? sendResponses;

  setUp(() async {
    requests.clear();
    otherText = 'Kto ma P91?';
    customMessages = null;
    delayedSend = null;
    sendResponses = null;
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
          'messages': customMessages ?? [
            _msg(1, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', otherText,
                false),
            _msg(2, _myDevice, 'a_me', 'Marek Kowalczyk', 'Ja mam', true),
          ]
        });
      }
      if (r.method == 'POST' && r.url.path == '/api/fitter/chat/report') {
        return _json(201, {'ok': true});
      }
      if (r.method == 'POST' && r.url.path == '/api/fitter/chat/messages' && delayedSend != null) {
        return delayedSend!.future;
      }
      if (r.method == 'POST' && r.url.path == '/api/fitter/chat/messages' && sendResponses != null) {
        return sendResponses!.removeAt(0);
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

  Future<void> openRoom(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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

  testWidgets('krótkie wiadomości mają zwarte dymki po przeciwnych stronach',
      (tester) async {
    await openRoom(tester);
    final other = find.byKey(const ValueKey('chat-bubble-1'));
    final mine = find.byKey(const ValueKey('chat-bubble-2'));
    expect(other, findsOneWidget);
    expect(mine, findsOneWidget);
    final otherRect = tester.getRect(other);
    final mineRect = tester.getRect(mine);
    expect(otherRect.left, lessThan(mineRect.left));
    expect(mineRect.width, lessThan(tester.view.physicalSize.width * 0.5));
    expect(otherRect.right, lessThan(mineRect.right));
    final listRect = tester.getRect(find.byKey(const Key('chat-message-list')));
    expect(mineRect.right, closeTo(listRect.right - 12, 0.1));
    await close(tester);
  });

  testWidgets('własna wiadomość jest przy prawej krawędzi na wąskim ekranie', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openRoom(tester);
    final listRect = tester.getRect(find.byKey(const Key('chat-message-list')));
    final mineRect = tester.getRect(find.byKey(const ValueKey('chat-bubble-2')));
    expect(mineRect.right, closeTo(listRect.right - 12, 0.1));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('wysłanie nie usuwa nowego szkicu wpisanego w czasie oczekiwania', (tester) async {
    delayedSend = Completer<http.Response>();
    await openRoom(tester);
    await tester.enterText(find.byType(TextField), 'Pierwsza wiadomość');
    await tester.tap(find.byTooltip('Send'));
    await pumpFor(tester, 3);
    await tester.enterText(find.byType(TextField), 'Kolejna wiadomość');
    delayedSend!.complete(_json(201, {'message': _msg(3, _myDevice, 'a_me', 'Marek Kowalczyk', 'Pierwsza wiadomość', true)}));
    await pumpFor(tester, 5);
    expect(find.text('Kolejna wiadomość'), findsOneWidget);
    expect(requests.where((r) => r.method == 'POST' && r.url.path == '/api/fitter/chat/messages'), hasLength(1));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('ponów wysyła pierwotną wiadomość i zachowuje nowy szkic', (tester) async {
    sendResponses = [
      _json(500, {'error': {'code': 'SERVER_ERROR', 'message': 'temporary'}}),
      _json(201, {'message': _msg(3, _myDevice, 'a_me', 'Marek Kowalczyk', 'Pierwsza wiadomość', true)}),
    ];
    await openRoom(tester);
    await tester.enterText(find.byType(TextField), 'Pierwsza wiadomość');
    await tester.tap(find.byTooltip('Send'));
    await pumpFor(tester, 4);
    await tester.enterText(find.byType(TextField), 'Nowy szkic');
    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await pumpFor(tester, 6);
    final sent = requests.where((r) => r.method == 'POST' && r.url.path == '/api/fitter/chat/messages').toList();
    expect(sent, hasLength(2));
    expect((jsonDecode(sent[0].body) as Map)['text'], 'Pierwsza wiadomość');
    expect((jsonDecode(sent[1].body) as Map)['text'], 'Pierwsza wiadomość');
    expect(sent[0].headers[kIdempotencyKeyHeader], isNotNull);
    expect(sent[1].headers[kIdempotencyKeyHeader], sent[0].headers[kIdempotencyKeyHeader]);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Nowy szkic');
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('stare ponowienie nie wysyła po zmianie konta', (tester) async {
    sendResponses = [_json(500, {'error': {'code': 'SERVER_ERROR', 'message': 'temporary'}})];
    await openRoom(tester);
    await tester.enterText(find.byType(TextField), 'Pierwsza wiadomość');
    await tester.tap(find.byTooltip('Send'));
    await pumpFor(tester, 4);
    final retry = tester.widget<SnackBarAction>(find.widgetWithText(SnackBarAction, 'Retry')).onPressed;
    final previous = AccountService.instance;
    final client = MockClient((_) async => _json(500, {}));
    final other = AccountService.forTesting(client);
    AccountService.instance = other;
    addTearDown(() { AccountService.instance = previous; other.dispose(); client.close(); });
    retry();
    await pumpFor(tester, 4);
    expect(requests.where((r) => r.method == 'POST' && r.url.path == '/api/fitter/chat/messages'), hasLength(1));
    expect(find.textContaining('account or pending message changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('stare ponowienie nie wraca po wysłaniu innej wiadomości', (tester) async {
    sendResponses = [
      _json(500, {'error': {'code': 'SERVER_ERROR', 'message': 'temporary'}}),
      _json(201, {'message': _msg(3, _myDevice, 'a_me', 'Marek Kowalczyk', 'Nowa wiadomość', true)}),
    ];
    await openRoom(tester);
    await tester.enterText(find.byType(TextField), 'Pierwsza wiadomość');
    await tester.tap(find.byTooltip('Send'));
    await pumpFor(tester, 4);
    final retry = tester.widget<SnackBarAction>(find.widgetWithText(SnackBarAction, 'Retry')).onPressed;
    await tester.enterText(find.byType(TextField), 'Nowa wiadomość');
    ScaffoldMessenger.of(tester.element(find.byType(TextField))).hideCurrentSnackBar();
    await pumpFor(tester, 4);
    await tester.tap(find.byTooltip('Send'));
    await pumpFor(tester, 4);
    retry();
    await pumpFor(tester, 4);
    final sent = requests.where((r) => r.method == 'POST' && r.url.path == '/api/fitter/chat/messages').toList();
    expect(sent, hasLength(2));
    expect((jsonDecode(sent.last.body) as Map)['text'], 'Nowa wiadomość');
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('wysłany tekst znika, gdy szkic nie został zmieniony', (tester) async {
    delayedSend = Completer<http.Response>();
    await openRoom(tester);
    await tester.enterText(find.byType(TextField), 'Pierwsza wiadomość');
    await tester.tap(find.byTooltip('Send'));
    await pumpFor(tester, 3);
    delayedSend!.complete(_json(201, {'message': _msg(3, _myDevice, 'a_me', 'Marek Kowalczyk', 'Pierwsza wiadomość', true)}));
    await pumpFor(tester, 5);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('zamknięcie pokoju podczas wysyłania nie używa zamkniętego pola', (tester) async {
    delayedSend = Completer<http.Response>();
    await openRoom(tester);
    await tester.enterText(find.byType(TextField), 'Pierwsza wiadomość');
    await tester.tap(find.byTooltip('Send'));
    await pumpFor(tester, 3);
    await close(tester);
    delayedSend!.complete(_json(201, {'message': _msg(3, _myDevice, 'a_me', 'Marek Kowalczyk', 'Pierwsza wiadomość', true)}));
    await pumpFor(tester, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wiadomości z różnych dni mają czytelne daty lokalne', (tester) async {
    Map<String, dynamic> at(int id, DateTime date) => {
      ..._msg(id, _otherAuthor, _otherAuthor, 'Zbigniew Hałas', 'Wiadomość $id', false),
      'created_at': date.toUtc().toIso8601String(),
    };
    customMessages = [
      at(1, DateTime(2026, 9, 24, 10)),
      at(2, DateTime(2026, 9, 24, 11)),
      at(3, DateTime(2026, 9, 25, 10)),
    ];
    await openRoom(tester);
    expect(find.text('09/24/2026'), findsOneWidget);
    expect(find.text('09/25/2026'), findsOneWidget);
    expect(find.text('Wiadomość 1'), findsOneWidget);
    expect(find.text('Wiadomość 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('długa wiadomość zawija się na wąskim ekranie', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    otherText = List.filled(35, 'Wymiary rury i spoiny').join(' ');
    await openRoom(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, 1800));
    await pumpFor(tester, 3);
    final bubble = find.byKey(const ValueKey('chat-bubble-1'));
    expect(bubble, findsOneWidget);
    expect(tester.getSize(bubble).width, lessThanOrEqualTo(320 * 0.72));
    expect(find.text(otherText), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('duża czcionka i długi ciąg mieszczą się w wąskim czacie', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final longText = 'DN50' * 80;
    customMessages = [_msg(1, _otherAuthor, _otherAuthor,
        'BardzoDługaNazwaUżytkownikaBezSpacji', longText, false)];
    await openRoom(tester, textScale: 2);
    await tester.drag(find.byType(ListView).last, const Offset(0, 1800));
    await pumpFor(tester, 3);
    expect(find.text(longText), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-actions-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('nietrwała blokada autora pokazuje ostrzeżenie', (tester) async {
    await (await SharedPreferences.getInstance())
        .setString('blocked_authors_v1', '{broken');
    await openRoom(tester);
    await tester.tap(find.byTooltip('Message actions: Zbigniew Hałas'));
    await pumpFor(tester, 4);
    await tester.tap(find.text('Block author'));
    await pumpFor(tester, 4);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Block'));
    await pumpFor(tester, 6);
    expect(find.text('Kto ma P91?'), findsNothing);
    expect(
        find.text(
            'Blocked for this session. Could not save the block for later.'),
        findsOneWidget);
    await close(tester);
  });

  testWidgets('zgłoszenie bez trwałego ukrycia pokazuje ostrzeżenie',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ReportedMessages.prefsKey, '{broken');
    await openRoom(tester);
    await tester.tap(find.byTooltip('Message actions: Zbigniew Hałas'));
    await pumpFor(tester, 4);
    await tester.tap(find.text('Report message'));
    await pumpFor(tester, 4);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Report'));
    await pumpFor(tester, 6);
    expect(find.text('Kto ma P91?'), findsNothing);
    expect(
        find.text(
            'Reported. Hidden for this session; could not save it for later.'),
        findsOneWidget);
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
