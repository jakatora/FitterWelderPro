// Profil → „Zgody": widać, na co i kiedy się zgodziłeś, i można to wycofać
// tak łatwo, jak się zgodziło (RODO art. 7 ust. 3). Wcześniej zgodę na
// wysyłkę zdjęć do skanera dało się „cofnąć" tylko przez „Usuń moje dane".

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/screens/profile_screen.dart';
import 'package:cut_list_app/services/blocked_users.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/user_profile.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/scan_consent_gate.dart';

Future<void> _pumpFor(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_profile_v1':
          jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
      'legal_consent_v1': jsonEncode({
        'version': kLegalVersion,
        'acceptedAt': '2026-09-24T12:00:00.000',
      }),
      ScanConsent.prefsKey: jsonEncode({
        'version': kLegalVersion,
        'acceptedAt': '2026-09-25T08:30:00.000',
      }),
    });
    UserProfileService.instance.resetForTest();
    LegalConsent.instance.resetForTest();
    BlockedUsers.instance.resetForTest();
    ScanConsent.resetForTest();
  });

  Future<void> openProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await _pumpFor(tester, 6);
  }

  testWidgets('pokazuje obie zgody z datą', (tester) async {
    await openProfile(tester);
    expect(find.text('CONSENTS'), findsOneWidget);
    expect(find.text('Rules (chat and assistant)'), findsOneWidget);
    expect(find.text('Sending photos to the scanner'), findsOneWidget);
    expect(find.textContaining('24.09.2026'), findsOneWidget);
    expect(find.textContaining('25.09.2026'), findsOneWidget);
    final withdraw = find.byKey(const ValueKey('consent-withdraw-scanner'));
    expect(tester.getSize(withdraw).height,
        greaterThanOrEqualTo(kMinTapTarget));
  });

  testWidgets('wycofanie zgody skanera — skaner zapyta znowu', (tester) async {
    await openProfile(tester);
    await tester.tap(find.byKey(const ValueKey('consent-withdraw-scanner')));
    await _pumpFor(tester, 4);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Withdraw'));
    await _pumpFor(tester, 4);

    expect(ScanConsent.isAccepted, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ScanConsent.prefsKey), isNull);
    expect(find.byKey(const ValueKey('consent-withdraw-scanner')), findsNothing);
    // Zasady zostają nietknięte.
    expect(LegalConsent.instance.isAccepted, isTrue);
  });

  testWidgets('wycofanie zgody na zasady — czat i asystent zapytają znowu',
      (tester) async {
    await openProfile(tester);
    await tester.tap(find.byKey(const ValueKey('consent-withdraw-rules')));
    await _pumpFor(tester, 4);
    // Okno mówi, że dane na serwerze zostają (od tego jest „Usuń moje dane").
    expect(find.textContaining('Delete my data'), findsWidgets);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Withdraw'));
    await _pumpFor(tester, 4);

    expect(LegalConsent.instance.isAccepted, isFalse);
    expect(ScanConsent.isAccepted, isTrue);
  });

  testWidgets('Anuluj niczego nie wycofuje', (tester) async {
    await openProfile(tester);
    await tester.tap(find.byKey(const ValueKey('consent-withdraw-rules')));
    await _pumpFor(tester, 4);
    await tester.tap(find.text('Cancel'));
    await _pumpFor(tester, 4);
    expect(LegalConsent.instance.isAccepted, isTrue);
  });
}
