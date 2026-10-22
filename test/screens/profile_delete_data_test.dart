// „Usuń moje dane" pod zabezpieczony backend: NAJPIERW serwer
// (DELETE /api/fitter/me), POTEM telefon — i jasne podsumowanie, co gdzie
// zniknęło. Stary backend (404), brak sieci i limit (429) mają własne ścieżki.
// Atrapa HTTP — zero prawdziwych połączeń.

import '../support/test_account.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/screens/home_screen.dart';
import 'package:cut_list_app/screens/profile_screen.dart';
import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/blocked_users.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/services/user_profile.dart';
import 'package:cut_list_app/widgets/scan_consent_gate.dart';

const _deviceId = '0123456789abcdef0123456789abcdef';
const _secret = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void _seed() {
  SharedPreferences.setMockInitialValues({
    'user_profile_v1':
        jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
    'legal_consent_v1': jsonEncode({
      'version': kLegalVersion,
      'acceptedAt': '2026-09-24T12:00:00.000',
    }),
    'fitter_device_id': _deviceId,
    'fitter_install_secret': _secret,
  });
  UserProfileService.instance.resetForTest();
  LegalConsent.instance.resetForTest();
  BlockedUsers.instance.resetForTest();
  PremiumService.instance.resetForTest();
}

Future<void> _pumpFor(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _openProfile(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(AppLanguage.en),
    child: const MaterialApp(home: ProfileScreen()),
  ));
  await _pumpFor(tester, 6);
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.text('Delete my data'));
  await _pumpFor(tester, 6);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
  await _pumpFor(tester, 12);
}

Finder _inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.textContaining(text),
    );

void main() {
  useGuestAccount();
  final requests = <http.Request>[];

  void backend(Future<http.Response> Function(http.Request) respond) {
    ApiClient.instance.debugSetClient(MockClient((r) async {
      requests.add(r);
      return respond(r);
    }));
  }

  setUp(() {
    requests.clear();
    _seed();
  });

  tearDown(() => ApiClient.instance.debugSetClient(null));

  testWidgets('okno potwierdzenia mówi o serwerze i o telefonie',
      (tester) async {
    backend((_) async => _json(500, {}));
    await _openProfile(tester);
    await tester.tap(find.text('Delete my data'));
    await _pumpFor(tester, 6);
    expect(_inDialog('from the server your chat messages'), findsOneWidget);
    expect(_inDialog('welder identity'), findsOneWidget);
    // Od v21 numer i ważność uprawnienia są w rejestrze, nie w tożsamości.
    expect(
        _inDialog('welder qualification register (certificates, photos, '
            'reminders)'),
        findsOneWidget);
    expect(_inDialog('WPQR number'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await _pumpFor(tester, 4);
    expect(requests, isEmpty, reason: 'anulowanie nie może niczego wysłać');
  });

  testWidgets('200: serwer PRZED telefonem, podsumowanie z licznikami',
      (tester) async {
    String? profileAtRequest;
    String? deviceAtRequest;
    backend((r) async {
      final prefs = await SharedPreferences.getInstance();
      profileAtRequest = prefs.getString('user_profile_v1');
      deviceAtRequest = prefs.getString('fitter_device_id');
      return _json(200, {
        'ok': true,
        'deleted': {
          'chat_messages': 2,
          'chat_reports': 1,
          'job_listings': 0,
          'device_secret': 1,
          'rate_counters': 3,
          'premium': 0,
        },
        'premium_retained': false,
        'message': 'Usunęliśmy Twoje dane z serwera.',
      });
    });

    await _openProfile(tester);
    await _confirmDelete(tester);

    final req = requests.single;
    expect(req.method, 'DELETE');
    expect(req.url.path, '/api/fitter/me');
    expect(req.headers[kDeviceIdHeader], _deviceId);
    expect(req.headers[kInstallSecretHeader], _secret);
    // Żądanie poszło, zanim cokolwiek zniknęło z telefonu.
    expect(profileAtRequest, isNotNull);
    expect(deviceAtRequest, _deviceId);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_inDialog('Data deleted'), findsOneWidget);
    expect(_inDialog('Chat messages: 2'), findsOneWidget);
    expect(_inDialog('Reports: 1'), findsOneWidget);
    expect(_inDialog('installation identifier and secret'), findsWidgets);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_profile_v1'), isNull);
    expect(prefs.getString('legal_consent_v1'), isNull);
    // Nowa, niezwiązana z niczym tożsamość instalacji.
    expect(prefs.getString('fitter_device_id'), isNot(_deviceId));
    expect(prefs.getString('fitter_install_secret'), isNot(_secret));

    await tester.tap(find.text('Got it'));
    await _pumpFor(tester, 4);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('404 (stary backend): lokalnie usunięte, serwer — mailowo',
      (tester) async {
    backend((_) async => http.Response('Cannot DELETE /api/fitter/me', 404));
    await _openProfile(tester);
    await _confirmDelete(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_inDialog('Deleted from the phone only'), findsOneWidget);
    expect(_inDialog('does not support deletion from the app'), findsOneWidget);
    expect(_inDialog('jakatora68@gmail.com'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_profile_v1'), isNull);
  });

  testWidgets(
      'bez sieci: pyta; Anuluj nic nie kasuje, „tylko z telefonu" kasuje',
      (tester) async {
    backend((_) async => throw http.ClientException('brak zasięgu'));
    await _openProfile(tester);
    await _confirmDelete(tester);

    expect(_inDialog('No connection'), findsOneWidget);
    expect(_inDialog('only by e-mail'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _pumpFor(tester, 6);

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_profile_v1'), isNotNull);
    expect(prefs.getString('fitter_device_id'), _deviceId,
        reason:
            'bez identyfikatora nie dałoby się ponowić usunięcia z serwera');
    expect(find.byType(ProfileScreen), findsOneWidget);

    await _confirmDelete(tester);
    await tester.tap(find.text('Delete from phone only'));
    await _pumpFor(tester, 12);

    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_profile_v1'), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
        _inDialog('We did NOT delete your data on the server'), findsOneWidget);
  });

  testWidgets(
      'kasuje też zgodę skanera, historię asystenta i ukryte zgłoszenia',
      (tester) async {
    // Po „Usuń moje dane" skaner dalej wysyłał zdjęcia bez pytania o zgodę,
    // a historia asystenta (treść operacji) zostawała na telefonie.
    SharedPreferences.setMockInitialValues({
      'user_profile_v1':
          jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
      'fitter_device_id': _deviceId,
      'fitter_install_secret': _secret,
      ScanConsent.prefsKey: jsonEncode({
        'version': kLegalVersion,
        'acceptedAt': '2026-09-25T08:00:00.000',
      }),
      'assistant_history_v1': jsonEncode([
        {
          'id': 'h1',
          'kind': 'save_weld_parameter',
          'summary': 'TIG · SS · t 2 mm · 60 A',
          'recordId': 'r1',
          'at': 1790000000000,
          'byVoice': true,
          'undone': false,
        }
      ]),
      ReportedMessages.prefsKey: jsonEncode([11, 12]),
    });
    UserProfileService.instance.resetForTest();
    LegalConsent.instance.resetForTest();
    BlockedUsers.instance.resetForTest();
    PremiumService.instance.resetForTest();
    ScanConsent.resetForTest();
    AssistantHistoryStore.instance.resetForTest();
    ReportedMessages.instance.resetForTest();
    // Stan w pamięci jak po użyciu skanera i asystenta w tej sesji.
    await ScanConsent.load();
    await AssistantHistoryStore.instance.load();
    await ReportedMessages.instance.load();
    expect(ScanConsent.isAccepted, isTrue);
    expect(AssistantHistoryStore.instance.entries, hasLength(1));
    expect(ReportedMessages.instance.isReported(11), isTrue);

    backend((_) async => _json(200, {
          'ok': true,
          'deleted': {'chat_messages': 0},
          'premium_retained': false,
        }));
    await _openProfile(tester);
    await tester.tap(find.text('Delete my data'));
    await _pumpFor(tester, 6);
    // Okno mówi wprost, że te zgody i historia też znikną.
    expect(_inDialog('scanner'), findsOneWidget);
    expect(_inDialog('assistant history'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await _pumpFor(tester, 12);

    expect(ScanConsent.isAccepted, isFalse,
        reason: 'skaner nie może wysyłać zdjęć bez nowej zgody');
    expect(AssistantHistoryStore.instance.entries, isEmpty);
    expect(ReportedMessages.instance.isReported(11), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ScanConsent.prefsKey), isNull);
    expect(prefs.getString('assistant_history_v1'), isNull);
    expect(prefs.getString(ReportedMessages.prefsKey), isNull);

    // Świeży odczyt z dysku też nie odtwarza zgody.
    ScanConsent.resetForTest();
    await ScanConsent.load();
    expect(ScanConsent.isAccepted, isFalse);

    expect(_inDialog('scanner consent'), findsOneWidget);
  });

  testWidgets(
      'instalacja bez kontaktu z serwerem: bez sieci nie straszy, '
      '„nie było czego usuwać"', (tester) async {
    // Monter liczył tylko kolana — nigdy nie był na czacie, w skanerze ani w
    // asystencie. Start aplikacji nie tworzy już identyfikatora, więc nie ma
    // czego szukać na serwerze i nic nie wychodzi z telefonu.
    SharedPreferences.setMockInitialValues({
      'user_profile_v1':
          jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
    });
    UserProfileService.instance.resetForTest();
    LegalConsent.instance.resetForTest();
    BlockedUsers.instance.resetForTest();
    PremiumService.instance.resetForTest();
    await PremiumService.instance.init(); // jak main.dart przy starcie

    backend((_) async => throw http.ClientException('brak zasięgu'));
    await _openProfile(tester);
    await _confirmDelete(tester);

    expect(requests, isEmpty,
        reason: 'pierwszym kontaktem nie może być DELETE');
    expect(_inDialog('No connection'), findsNothing);
    expect(_inDialog('Data deleted'), findsOneWidget);
    expect(_inDialog('never sent data to the server'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_profile_v1'), isNull);
    expect(prefs.getString('fitter_device_id'), isNull);
  });

  testWidgets('429: „spróbuj później" i nic nie znika', (tester) async {
    backend((_) async => _json(429, {
          'error': {'code': 'RATE_LIMITED', 'message': 'Za dużo żądań'}
        }));
    await _openProfile(tester);
    await _confirmDelete(tester);

    expect(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Try again later')),
      findsOneWidget,
    );
    expect(_inDialog('Nothing was deleted on the phone'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await _pumpFor(tester, 4);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_profile_v1'), isNotNull);
    expect(prefs.getString('fitter_device_id'), _deviceId);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
