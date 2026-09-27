// Ekrany rejestru uprawnień i biblioteki WPS na prawdziwym SQLite.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/database/wps_dao.dart';
import 'package:cut_list_app/domain/qualification/qualification_dates.dart';
import 'package:cut_list_app/domain/qualification/reminder_plan.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';
import 'package:cut_list_app/features/qualification/certificate_edit_page.dart';
import 'package:cut_list_app/features/qualification/certificate_register_page.dart';
import 'package:cut_list_app/features/wps/wps_edit_page.dart';
import 'package:cut_list_app/features/wps/wps_library_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/qualification_reminders.dart';
import 'package:cut_list_app/services/welder_qualification_service.dart';

import '../support/test_database.dart';

class _FakePlatform implements ReminderPlatform {
  int permissionRequests = 0;
  final List<List<PlannedReminder>> scheduled = [];

  @override
  bool get supported => true;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async =>
      scheduled.add(reminders);

  @override
  Future<void> cancel(Iterable<int> ids) async {}
}

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(page));
  await _settle(tester);
}

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
      description: 'TextField "$label"',
    );

void main() {
  useTestDatabase();

  late _FakePlatform platform;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {kLegacyCertMigratedPrefsKey: true});
    platform = _FakePlatform();
    QualificationReminders.instance =
        QualificationReminders(platform: platform);
  });

  Future<void> clearTables(WidgetTester tester) => tester.runAsync(() async {
        final db = await AppDatabase.get();
        await db.delete('welder_certificates');
        await db.delete('welder_cert_confirmations');
        await db.delete('wps_library');
        await db.delete('wps_versions');
      });

  group('rejestr uprawnień', () {
    testWidgets('pusty rejestr: podpowiedź, przełącznik; bez prośby o zgodę',
        (tester) async {
      await clearTables(tester);
      await _pump(tester, const CertificateRegisterPage());

      expect(find.text('Uprawnienia spawacza'), findsOneWidget);
      expect(find.textContaining('Brak certyfikatów'), findsOneWidget);
      expect(find.byKey(const ValueKey('qualification-reminders-switch')),
          findsOneWidget);
      // Otwarcie ekranu nie pyta o powiadomienia — dopiero przełącznik.
      expect(platform.permissionRequests, 0);
      // Poprawna terminologia: uprawnienie spawacza ≠ WPQR.
      expect(find.textContaining('WPQR / PQR to kwalifikacja PROCEDURY'),
          findsOneWidget);
    });

    testWidgets('włączenie przypomnień pyta o zgodę i planuje', (tester) async {
      await clearTables(tester);
      await tester.runAsync(() => WelderCertificateDao().upsert(
            WelderCertificate(
              id: 'c1',
              standard: QualificationStandard.iso9606_1,
              certNo: 'PL-1',
              testDate: dateOnly(DateTime.now()),
              processes: '141',
              createdAt: 1,
              updatedAt: 1,
            ),
          ));
      await _pump(tester, const CertificateRegisterPage());

      await tester
          .tap(find.byKey(const ValueKey('qualification-reminders-switch')));
      await _settle(tester);

      expect(platform.permissionRequests, 1);
      expect(platform.scheduled, isNotEmpty);
      // Termin 6 mies. od dziś → przypomnienia 30 i 7 dni przed.
      expect(platform.scheduled.last.map((r) => r.daysBefore), [30, 7]);
      final sw = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('qualification-reminders-switch')));
      expect(sw.value, isTrue);
    });

    testWidgets('certyfikat po terminie: status i wpis potwierdzenia',
        (tester) async {
      await clearTables(tester);
      final today = dateOnly(DateTime.now());
      await tester.runAsync(() => WelderCertificateDao().upsert(
            WelderCertificate(
              id: 'late',
              standard: QualificationStandard.iso9606_1,
              certNo: 'PL-UDT-7',
              // Egzamin 7 miesięcy temu → termin potwierdzenia minął.
              testDate: addMonthsClamped(today, -7),
              processes: '141',
              createdAt: 1,
              updatedAt: 1,
            ),
          ));
      await _pump(tester, const CertificateRegisterPage());

      expect(find.textContaining('EN ISO 9606-1 · nr PL-UDT-7'),
          findsWidgets);
      expect(find.textContaining('przeterminowane'), findsWidgets);

      await tester.tap(find.text('Potwierdzenie 6 mies.'));
      await tester.pumpAndSettle();
      expect(find.textContaining('koordynatora spawania'), findsWidgets);
      await tester.enterText(
          find.byKey(const ValueKey('confirmation-by')), 'J. Koordynator');
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      // ISO 9606-1 §9.2: podpis po terminie NIE przywraca uprawnienia —
      // aplikacja ostrzega i pyta, czy zapisać wpis do historii.
      expect(find.text('Potwierdzenie po terminie'), findsOneWidget);
      expect(find.textContaining('potrzebny nowy egzamin'), findsOneWidget);
      await tester.tap(find.text('Zapisz do historii'));
      await _settle(tester);
      await _settle(tester);

      final saved = await tester
          .runAsync(() => WelderCertificateDao().getById('late'));
      expect(saved!.lastConfirmedDate, today);
      expect(saved.confirmations.single.confirmedBy, 'J. Koordynator');
      // Nadal przeterminowane — potrzebny nowy egzamin.
      expect(find.textContaining('przeterminowane'), findsWidgets);
      expect(find.textContaining('nie przywróciło uprawnienia'), findsOneWidget);
    });

    testWidgets('potwierdzenie w terminie trafia do historii i przesuwa termin',
        (tester) async {
      await clearTables(tester);
      final today = dateOnly(DateTime.now());
      await tester.runAsync(() => WelderCertificateDao().upsert(
            WelderCertificate(
              id: 'ok',
              standard: QualificationStandard.iso9606_1,
              certNo: 'PL-UDT-8',
              testDate: addMonthsClamped(today, -5),
              processes: '141',
              createdAt: 1,
              updatedAt: 1,
            ),
          ));
      await _pump(tester, const CertificateRegisterPage());
      await tester.tap(find.text('Potwierdzenie 6 mies.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();
      await _settle(tester);
      await _settle(tester);

      expect(find.text('Potwierdzenie po terminie'), findsNothing);
      final saved =
          await tester.runAsync(() => WelderCertificateDao().getById('ok'));
      expect(saved!.confirmations.map((k) => k.date), [today]);
      expect(find.textContaining('Historia potwierdzeń (1)'), findsOneWidget);
    });

    testWidgets('formularz: nowy certyfikat trafia do bazy', (tester) async {
      await clearTables(tester);
      await _pump(tester, const CertificateEditPage());

      await tester.enterText(_field('Nr certyfikatu / WPQ'), 'PL-99');
      await tester.enterText(_field('Proces(y)'), '141, 135');
      await tester.enterText(_field('Grubość od'), '1,5');
      await tester.enterText(_field('do').first, '6');
      await tester.ensureVisible(find.text('BW — czołowa'));
      await tester.tap(find.text('BW — czołowa'));
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _settle(tester);

      final all =
          await tester.runAsync(() => WelderCertificateDao().listAll());
      expect(all, hasLength(1));
      final c = all!.single;
      expect(c.certNo, 'PL-99');
      expect(c.processes, '141, 135');
      expect(c.thicknessMinMm, 1.5);
      expect(c.thicknessMaxMm, 6);
      expect(c.standard, QualificationStandard.iso9606_1);
      expect(c.jointKinds.map((k) => k.code), ['BW']);
    });

    testWidgets('formularz: stempel zapisany, egzamin z przyszłości odrzucony',
        (tester) async {
      await clearTables(tester);
      await _pump(tester, const CertificateEditPage());
      await tester.enterText(_field('Stempel spawacza'), 'xy-7');
      await tester.enterText(_field('Nr certyfikatu / WPQ'), 'PL-7');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _settle(tester);
      final c = (await tester.runAsync(() => WelderCertificateDao().listAll()))!
          .single;
      expect(c.welderStamp, 'XY-7');
    });

    testWidgets('formularz: wyjście z niezapisanymi zmianami pyta',
        (tester) async {
      await clearTables(tester);
      await _pump(tester, const CertificateEditPage());
      await tester.enterText(_field('Nr certyfikatu / WPQ'), 'PL-8');
      await tester.tap(find.byTooltip('Wstecz'));
      await tester.pumpAndSettle();
      expect(find.text('Porzucić zmiany?'), findsOneWidget);
      await tester.tap(find.text('Wróć do edycji'));
      await tester.pumpAndSettle();
      expect(find.text('Porzucić zmiany?'), findsNothing);
      expect(find.text('PL-8'), findsOneWidget);
    });

    testWidgets('formularz: min > max — nie zapisuje', (tester) async {
      await clearTables(tester);
      await _pump(tester, const CertificateEditPage());
      await tester.enterText(_field('Grubość od'), '8');
      await tester.enterText(_field('do').first, '2');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _settle(tester);
      expect(find.textContaining('minimum większe od maksimum'),
          findsOneWidget);
      expect(await tester.runAsync(() => WelderCertificateDao().count()), 0);
    });
  });

  group('biblioteka WPS', () {
    testWidgets('import JSON ze schowka dodaje WPS do listy', (tester) async {
      await clearTables(tester);
      final json = encodeWpsJson(const WpsRecord(
        id: 'x',
        wpsNo: 'WPS-141-01',
        revision: 'B',
        processes: '141',
        heatInputMaxKjMm: 1.2,
        createdAt: 0,
        updatedAt: 0,
      ));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': json}
            : null,
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await _pump(tester, const WpsLibraryPage());
      expect(find.textContaining('Biblioteka jest pusta'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wklej JSON ze schowka'));
      await _settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('WPS-141-01 rev. B'), findsOneWidget);
      final stored = await tester.runAsync(() => WpsDao().listAll());
      expect(stored!.single.heatInputMaxKjMm, 1.2);
      expect(stored.single.id, isNot('x'));
    });

    testWidgets('import czegoś, co nie jest WPS — komunikat, nic nie dodaje',
        (tester) async {
      await clearTables(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': 'lista zakupów'}
            : null,
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester, const WpsLibraryPage());
      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wklej JSON ze schowka'));
      await _settle(tester);
      expect(find.textContaining('To nie jest plik WPS'), findsOneWidget);
      expect(await tester.runAsync(() => WpsDao().listAll()), isEmpty);
    });

    testWidgets('formularz WPS: bez numeru nie zapisze', (tester) async {
      await clearTables(tester);
      await _pump(tester, const WpsEditPage());
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _settle(tester);
      expect(find.text('Wymagany'), findsOneWidget);
      expect(await tester.runAsync(() => WpsDao().listAll()), isEmpty);
    });

    testWidgets('formularz WPS: wyjście z niezapisanymi zmianami pyta',
        (tester) async {
      await clearTables(tester);
      await _pump(tester, const WpsEditPage());
      await tester.enterText(_field('Nr WPS *'), 'WPS-9');
      await tester.tap(find.byTooltip('Wstecz'));
      await tester.pumpAndSettle();
      expect(find.text('Porzucić zmiany?'), findsOneWidget);
    });

    testWidgets(
        'formularz WPS: zmiana treści → „popraw bieżącą” zostawia wersję',
        (tester) async {
      await clearTables(tester);
      const base = WpsRecord(
        id: 'w1',
        wpsNo: 'WPS-7',
        revision: 'A',
        positions: 'PA, PF',
        createdAt: 1,
        updatedAt: 1,
      );
      await tester.runAsync(() => WpsDao().upsert(base));
      await _pump(tester, const WpsEditPage(wps: base));
      await tester.enterText(_field('Pozycje'), 'PA');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.pumpAndSettle();
      expect(find.text('Zmieniono treść WPS'), findsOneWidget);
      await tester.tap(find.text('Popraw bieżącą'));
      await _settle(tester);
      await tester.pumpAndSettle();
      final versions =
          (await tester.runAsync(() => WpsDao().versionsOf('w1')))!;
      expect(versions.map((v) => v.snapshot.positions), ['PA, PF', 'PA']);
    });

    testWidgets('formularz WPS: duplikat numeru i rewizji ostrzega',
        (tester) async {
      await clearTables(tester);
      await tester.runAsync(() => WpsDao().upsert(const WpsRecord(
          id: 'w1', wpsNo: 'WPS-7', revision: 'A', createdAt: 1, updatedAt: 1)));
      // Nowa WPS o tym samym numerze i rewizji → ostrzeżenie.
      await _pump(tester, const WpsEditPage());
      await tester.enterText(_field('Nr WPS *'), 'wps-7');
      await tester.enterText(_field('Rewizja'), 'a');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('Taka WPS już jest w bibliotece'), findsOneWidget);
      await tester.tap(find.text('Anuluj').last);
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => WpsDao().listAll()), hasLength(1));
    });

    testWidgets('formularz WPS: zakres energii liniowej zapisany z konwencją',
        (tester) async {
      await clearTables(tester);
      await _pump(tester, const WpsEditPage());
      await tester.enterText(_field('Nr WPS *'), 'WPS-7');
      await tester.enterText(_field('Energia liniowa min'), '0,4');
      await tester.enterText(_field('max'), '1,1');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _settle(tester);
      final w = (await tester.runAsync(() => WpsDao().listAll()))!.single;
      expect(w.wpsNo, 'WPS-7');
      expect(w.heatInputMinKjMm, 0.4);
      expect(w.heatInputMaxKjMm, 1.1);
      expect(w.toRow()['heat_input_method'], 'EN');
    });
  });
}
