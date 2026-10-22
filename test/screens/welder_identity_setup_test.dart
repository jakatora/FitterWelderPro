// Tożsamość spawacza po v21: bez pola „Nr WPQR / WPS" (mieszało uprawnienie
// spawacza z kwalifikacją procedury), z wejściem do rejestru uprawnień —
// i bez utraty tego, co spawacz wpisał wcześniej.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/services/account_service.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/welder_identity_setup_screen.dart';
import 'package:cut_list_app/services/welder_qualification_service.dart';

import '../support/test_account.dart';

void main() {
  // Tożsamość należy do właściciela danych (gość / konto) — test działa jako
  // gość, więc czyta i zapisuje dawny klucz `welder_identity_v1`.
  useGuestAccount();
  // UWAGA: WelderIdentityService to singleton bez resetu — w tym pliku tylko
  // ten jeden test czyta tożsamość z zasianych preferencji.
  testWidgets(
      'formularz nie pyta o WPQR, prowadzi do rejestru, a zapis zachowuje '
      'stare pola', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final legacy = {
      'stamp': 'JK-014',
      'wpqrNo': 'PL-UDT-0142/2026',
      'wpqrExpiry': '2028-06-09T00:00:00.000Z',
      'certBody': 'udt',
      'displayName': 'Jan Kowalski',
      'email': 'jan@example.pl',
      'gdprConsentAt': '2026-06-09T14:32:00.000',
      'qualificationDeclaredAt': '2026-06-09T14:33:00.000',
    };
    SharedPreferences.setMockInitialValues({
      'welder_identity_v1': jsonEncode(legacy),
      kLegacyCertMigratedPrefsKey: true,
    });

    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const WelderIdentitySetupScreen())),
              child: const Text('otwórz'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('otwórz'));
    await tester.pumpAndSettle();

    // Stempel wczytany — to on zostaje domyślnym spawaczem w dzienniku.
    expect(find.text('JK-014'), findsOneWidget);
    // Stare pola zniknęły z formularza; nazwa jest poprawna.
    expect(find.textContaining('WPQR'), findsNothing);
    expect(
        find.text('Uprawnienia spawacza (ISO 9606-1 / ASME WPQ)'), findsOneWidget);
    expect(find.byKey(const ValueKey('identity-open-qualifications')),
        findsOneWidget);

    await tester.ensureVisible(find.text('Zapisz'));
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('welder_identity_v1')!)
        as Map<String, Object?>;
    expect(saved['stamp'], 'JK-014');
    // Zero utraty danych: pola sprzed v21 przeżywają ponowny zapis.
    expect(saved['wpqrNo'], 'PL-UDT-0142/2026');
    expect(DateTime.parse(saved['wpqrExpiry'] as String),
        DateTime.parse('2028-06-09T00:00:00.000Z'));
    expect(saved['certBody'], 'udt');
    expect(saved['gdprConsentAt'], '2026-06-09T14:32:00.000');
  });

  testWidgets(
      'po zmianie konta formularz poprzedniego chowa się i nic nie zapisuje',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'welder_identity_v1': jsonEncode({
        'stamp': 'GUEST-1',
        'gdprConsentAt': '2026-06-09T14:32:00.000',
        'qualificationDeclaredAt': '2026-06-09T14:33:00.000',
      }),
      kLegacyCertMigratedPrefsKey: true,
    });
    // Jeden obiekt konta, jak w aplikacji: gość, potem logowanie na nim.
    final previous = AccountService.instance;
    FlutterSecureStorage.setMockInitialValues({});
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'token': 'test-b',
          'account': {'id': 'b', 'role': 'user'}
        }),
        200));
    final account = AccountService.forTesting(client);
    AccountService.instance = account;
    addTearDown(() {
      AccountService.instance = previous;
      account.dispose();
      client.close();
    });

    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: WelderIdentitySetupScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('GUEST-1'), findsOneWidget);

    await account.signIn('b@example.test', 'test-password');
    await tester.pumpAndSettle();

    expect(find.text('GUEST-1'), findsNothing,
        reason: 'dane gościa nie mogą zostać na ekranie innego konta');
    expect(find.text('Konto zmieniło się. Otwórz rejestr ponownie.'),
        findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('welder_identity_v1.')),
        isEmpty,
        reason: 'konto B nie dostało tożsamości gościa');
  });
}
