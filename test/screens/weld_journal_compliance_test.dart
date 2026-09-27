// Dziennik spoin ↔ Biblioteka WPS i rejestr uprawnień, na prawdziwym SQLite:
//  * WPS wybierana z biblioteki (nazwa z rewizją w polu, wolny tekst dalej
//    działa);
//  * niezgodność = ostrzeżenie przed zapisem z listą punktów — „Popraw"
//    wraca do karty, „Zapisz mimo to" zapisuje, a ostrzeżenie idzie do
//    historii spoiny;
//  * znaczki „poza WPS" / „spawacz bez ważnych uprawnień w dniu spawania"
//    na liście i na karcie;
//  * brak WPS / certyfikatów — bez okna, zapis jak dotąd.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/database/wps_dao.dart';
import 'package:cut_list_app/domain/qualification/weld_process.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/domain/weld_journal/weld_history.dart';
import 'package:cut_list_app/domain/welding/heat_input.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/weld_journal_screen.dart';

import '../support/test_database.dart';
import '../support/weld_fixtures.dart';

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

Future<void> _settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(const WeldJournalScreen()));
  await _settle(tester);
  await tester.pumpAndSettle();
}

const WpsRecord _wps = WpsRecord(
  id: 'wps-1',
  wpsNo: 'WPS-141-01',
  revision: 'B',
  processes: '141',
  thicknessMinMm: 1.5,
  thicknessMaxMm: 6,
  positions: 'PA, PC, PF',
  jointKinds: {WeldJointKind.bw},
  heatInputMinKjMm: 0.3,
  heatInputMaxKjMm: 1.2,
  heatInputMethod: HeatInputStandard.asmeIx,
  createdAt: 0,
  updatedAt: 0,
);

WelderCertificate _cert({DateTime? expiry}) => WelderCertificate(
      id: 'c1',
      standard: QualificationStandard.iso9606_1,
      welderStamp: 'JK-12',
      certNo: 'UDT/123/2026',
      testDate: DateTime(2026, 1, 10),
      expiryDate: expiry ?? DateTime(2028, 1, 10),
      // Potwierdzenie w terminie (egzamin 2026-01-10 + 6 mies. = 2026-07-10).
      lastConfirmedDate: DateTime(2026, 7, 1),
      processes: '141',
      positions: 'wszystkie',
      createdAt: 0,
      updatedAt: 0,
    );

Finder _field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);

void main() {
  useTestDatabase();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      // Rejestr bez przeniesienia starej tożsamości — tu nie o to chodzi.
      'welder_cert_legacy_migrated_v1': true,
    });
  });

  Future<void> reset(WidgetTester tester,
          {List<WpsRecord> library = const [],
          List<WelderCertificate> certificates = const []}) =>
      tester.runAsync(() async {
        final db = await AppDatabase.get();
        for (final t in [
          'weld_journal',
          'weld_journal_history',
          'weld_repairs',
          'weld_journal_projects',
          'wps_library',
          'welder_certificates',
        ]) {
          await db.delete(t);
        }
        for (final w in library) {
          await WpsDao().upsert(w);
        }
        for (final c in certificates) {
          await WelderCertificateDao().upsert(c);
        }
      });

  Future<void> openNewWeld(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Numer spoiny'), 'W-100');
  }

  Future<void> pickWps(WidgetTester tester) async {
    await tester.ensureVisible(find.byTooltip('Wybierz z Biblioteki WPS'));
    await tester.tap(find.byTooltip('Wybierz z Biblioteki WPS'));
    await tester.pump();
    await _settle(tester, rounds: 3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WPS-141-01 rev. B'));
    await tester.pumpAndSettle();
  }

  /// Zapis czyta bibliotekę, rejestr i dziennik, potem pisze w transakcji —
  /// czekamy, aż pokaże się ostrzeżenie albo karta zamknie się i lista
  /// przeładuje.
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await tester.pump();
    bool done() =>
        find.text('Spoina poza WPS / uprawnieniami').evaluate().isNotEmpty ||
        (find.text('Nowa spoina').evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty);
    for (var i = 0; i < 60 && !done(); i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _settle(tester, rounds: 4);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'WPS z biblioteki: nazwa z rewizją w polu, konwencja energii z WPS; '
      'spoina poza WPS → ostrzeżenie; „Popraw" nic nie zapisuje, „Zapisz '
      'mimo to" zapisuje z wpisem w historii i znaczkiem na liście',
      (tester) async {
    await reset(tester, library: const [_wps], certificates: [_cert()]);
    await _pumpScreen(tester);
    await openNewWeld(tester);
    await pickWps(tester);

    String text(String label) =>
        tester.widget<TextField>(_field(label)).controller!.text;
    expect(text('Nr WPS / pWPS'), 'WPS-141-01 rev. B');
    expect(find.text('Z Biblioteki WPS — zakres sprawdzany przy zapisie'),
        findsOneWidget);

    // t poza zakresem WPS (1,5–6 mm).
    await tester.ensureVisible(_field('t (mm)'));
    await tester.enterText(_field('t (mm)'), '8');
    await tester.ensureVisible(_field('kJ/mm'));
    await tester.enterText(_field('kJ/mm'), '0,9');
    await tapSave(tester);

    expect(find.text('Spoina poza WPS / uprawnieniami'), findsOneWidget);
    expect(find.textContaining('Grubość: 8 mm — poza zakresem'),
        findsOneWidget);

    await tester.tap(find.text('Popraw'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(() => WeldJournalDao().listAll()))!,
        isEmpty,
        reason: '„Popraw" wraca do karty bez zapisu');
    expect(find.byKey(const ValueKey('weld-compliance-panel')), findsOneWidget);
    expect(find.text('poza WPS'), findsOneWidget);

    await tapSave(tester);
    await tester.tap(find.text('Zapisz mimo to'));
    await tester.pump();
    for (var i = 0;
        i < 60 &&
            (find.text('Nowa spoina').evaluate().isNotEmpty ||
                find.byType(CircularProgressIndicator).evaluate().isNotEmpty);
        i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _settle(tester, rounds: 4);
    await tester.pumpAndSettle();

    final saved =
        (await tester.runAsync(() => WeldJournalDao().listAll()))!.single;
    expect(saved.wpsRef, 'WPS-141-01 rev. B');
    expect(saved.heatInput, '0,9 ASME',
        reason: 'konwencja z WPS zapisana przy liczbie');
    final history =
        (await tester.runAsync(() => WeldJournalDao().history(saved.id)))!;
    final check =
        history.where((h) => h.action == WeldHistoryAction.check).toList();
    expect(check, hasLength(1));
    expect(check.single.newValue, contains('Zapisano mimo ostrzeżeń'));
    expect(check.single.newValue, contains('Grubość'));

    // Znaczek na liście.
    expect(find.text('poza WPS'), findsOneWidget);
  });

  testWidgets(
      'spawacz z uprawnieniem wygasłym w dniu spawania → ostrzeżenie i '
      'znaczek na karcie istniejącej spoiny', (tester) async {
    await reset(tester, certificates: [_cert(expiry: DateTime(2026, 6, 1))]);
    await tester.runAsync(() => WeldJournalDao()
        .insert(weld('w1', weldNo: 'W-001', date: '2026-09-20'), by: 'JK-12'));
    await _pumpScreen(tester);

    const badge = 'spawacz bez ważnych uprawnień w dniu spawania';
    expect(find.text(badge), findsOneWidget, reason: 'znaczek na liście');

    await tester.tap(find.text('W-001'));
    await tester.pump();
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Karta spoiny'), findsOneWidget);
    expect(find.byKey(const ValueKey('weld-compliance-panel')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('weld-compliance-panel')),
            matching: find.text(badge)),
        findsOneWidget);
    expect(find.textContaining('Ważność uprawnienia'), findsOneWidget);
  });

  testWidgets(
      'brak biblioteki WPS i rejestru: zapis bez okna, bez znaczków, wolny '
      'tekst WPS zostaje', (tester) async {
    await reset(tester);
    await _pumpScreen(tester);
    await openNewWeld(tester);
    await tester.ensureVisible(_field('Nr WPS / pWPS'));
    await tester.enterText(_field('Nr WPS / pWPS'), 'WPS-stary-7');
    await tapSave(tester);

    expect(find.text('Spoina poza WPS / uprawnieniami'), findsNothing);
    final saved =
        (await tester.runAsync(() => WeldJournalDao().listAll()))!.single;
    expect(saved.wpsRef, 'WPS-stary-7');
    final history =
        (await tester.runAsync(() => WeldJournalDao().history(saved.id)))!;
    expect(history.where((h) => h.action == WeldHistoryAction.check), isEmpty);
    expect(find.text('poza WPS'), findsNothing);
  });
}
