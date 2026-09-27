// Zmiana stempla w tożsamości: certyfikaty ze starym stemplem przestałyby
// pasować do spoin nowego stempla — ekran mówi o tym i (za zgodą) przepisuje
// stempel certyfikatów. Spoin nie rusza (to dowód).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/welder_identity_setup_screen.dart';
import 'package:cut_list_app/services/welder_qualification_service.dart';

import '../support/test_database.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useTestDatabase();

  testWidgets(
      'zmiana stempla ostrzega o certyfikatach i przepisuje je za zgodą',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'welder_identity_v1': jsonEncode({
        'stamp': 'JK-014',
        'gdprConsentAt': '2026-06-09T14:32:00.000',
        'qualificationDeclaredAt': '2026-06-09T14:33:00.000',
      }),
      kLegacyCertMigratedPrefsKey: true,
    });
    await tester.runAsync(() async {
      final db = await AppDatabase.get();
      await db.delete('welder_certificates');
      await db.delete('weld_journal');
      await WelderCertificateDao().upsert(const WelderCertificate(
        id: 'c1',
        welderStamp: 'JK-014',
        standard: QualificationStandard.iso9606_1,
        createdAt: 1,
        updatedAt: 1,
      ));
      await db.insert('weld_journal', {
        'id': 'w1',
        'weld_no': 'W-1',
        'welder': 'jk-014',
      });
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
    expect(find.text('JK-014'), findsOneWidget);

    await tester.enterText(find.text('JK-014'), 'JK-015');
    await tester.ensureVisible(find.text('Zapisz'));
    await tester.tap(find.text('Zapisz'));
    await _settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Zmiana stempla JK-014 → JK-015'), findsOneWidget);
    expect(find.textContaining('Certyfikatów ze stemplem JK-014: 1'),
        findsOneWidget);
    expect(find.textContaining('Spoin w dzienniku ze stemplem JK-014: 1'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('identity-reassign-certs')));
    await _settle(tester);
    await tester.pumpAndSettle();

    final cert =
        (await tester.runAsync(() => WelderCertificateDao().getById('c1')))!;
    expect(cert.welderStamp, 'JK-015');
    final weld = (await tester.runAsync(() async =>
        (await AppDatabase.get()).query('weld_journal')))!;
    expect(weld.single['welder'], 'jk-014', reason: 'spoin nie ruszamy');
  });
}
