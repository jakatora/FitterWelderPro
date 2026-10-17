// Ekran „Zakres uprawnień z próbki” (EN ISO 9606-1:2017): wpisanie próbki →
// zakres z punktami normy, braki danych → komunikat, granica s = 12 (3
// warstwy), dwa procesy, ukryty wybór nie liczy się do wyniku, zapis do
// rejestru (formularz CertificateEditPage ze szkicem, prawdziwy SQLite),
// udostępnianie tekstu i PDF przez wstrzyknięte funkcje, EN, 320×640 przy
// tekście ×1,3, cele dotyku ≥ 48 dp.
//
// Liczby (jak w test/domain/qualification/iso9606_range_test.dart):
//  • 141 T BW FM1 S s3 D60,3 PH ss nb → s 3–6 mm, D ≥ 30,15 mm,
//    pozycje PA, PE, PF, PH, procesy 141 (S), 142 (nm), 143 (M), 145 (S);
//  • 141 s₁ 3 + 111 B s₂ 9 → 3–6, 3–18, złącze 3–24 mm.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/domain/qualification/iso9606_range.dart';
import 'package:cut_list_app/domain/qualification/reminder_plan.dart';
import 'package:cut_list_app/domain/qualification/weld_process.dart';
import 'package:cut_list_app/features/qualification/certificate_edit_page.dart';
import 'package:cut_list_app/features/qualification_range/qualification_range_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/qualification_reminders.dart';
import 'package:cut_list_app/services/welder_qualification_service.dart';
import 'package:cut_list_app/theme/app_theme.dart';

import '../../support/test_database.dart';

class _ShareSpy {
  final List<(String, String)> texts = [];
  final List<(Iso9606Range, bool)> pdfs = [];

  Future<void> text(String t, String subject) async => texts.add((t, subject));
  Future<void> pdf(Iso9606Range r, bool english) async => pdfs.add((r, english));
}

class _FakePlatform implements ReminderPlatform {
  @override
  bool get supported => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {}

  @override
  Future<void> cancel(Iterable<int> ids) async {}
}

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  _ShareSpy? spy,
  Size size = const Size(1080, 2400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = spy ?? _ShareSpy();
  // Świeży stan ekranu przy każdym _pump (inaczej Flutter użyłby starego).
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: QualificationRangePage(shareText: s.text, sharePdf: s.pdf),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

/// Przewija listę, aż element powstanie i będzie widoczny — ListView buduje
/// leniwie, na wąskim ekranie dalsze (albo wcześniejsze) sekcje nie istnieją.
Future<void> _reveal(WidgetTester tester, String key) async {
  final f = _key(key);
  final scrollable = find
      .descendant(of: _key('qr-list'), matching: find.byType(Scrollable))
      .first;
  if (f.evaluate().isEmpty) {
    await tester.drag(scrollable, const Offset(0, 30000));
    await tester.pumpAndSettle();
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 200, scrollable: scrollable);
    }
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, key);
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await _reveal(tester, key);
  await tester.enterText(_key(key), text);
  await tester.pumpAndSettle();
}

String _value(WidgetTester tester, String lineKey) =>
    tester.widget<Text>(_key('qr-value-$lineKey')).data!;

/// 141 T BW FM1 S s3 D60,3 PH ss nb.
Future<void> _fillPipe141(WidgetTester tester, {String d = '60,3'}) async {
  await _tap(tester, 'qr-product-pipe');
  await _tap(tester, 'qr-pos-PH');
  await _enter(tester, 'qr-d', d);
  await _tap(tester, 'qr-p1-141');
  await _enter(tester, 'qr-s1', '3');
  await _tap(tester, 'qr-fm-FM1');
  await _tap(tester, 'qr-back-ssNb');
}

void main() {
  testWidgets('wpisanie próbki → zakres z punktami normy', (tester) async {
    await _pump(tester);
    await _fillPipe141(tester);
    await _reveal(tester, 'qr-result');
    expect(_key('qr-problems'), findsNothing);
    expect(find.text('EN ISO 9606-1 141 T BW FM1 S s3 D60,3 PH ss nb'),
        findsOneWidget);
    expect(_value(tester, 'process-0'), '141 (S), 142 (nm), 143 (M), 145 (S)');
    await _reveal(tester, 'qr-value-positions');
    expect(_value(tester, 'thickness'), '3–6 mm');
    expect(_value(tester, 'diameter'), '≥ 30,15 mm');
    expect(_value(tester, 'positions'), 'PA, PE, PF, PH');
    expect(_value(tester, 'backing-0'), 'ss nb, ss mb, bs, ss gb, ss fb');
    expect(find.text('§5.8, tab. 9'), findsOneWidget);
    expect(find.text('§5.7, tab. 7'), findsOneWidget);
  });

  testWidgets('brak danych i nieczytelne pole → komunikat, nie wynik',
      (tester) async {
    await _pump(tester);
    expect(_key('qr-result'), findsNothing);
    await _reveal(tester, 'qr-problems');
    expect(find.textContaining('Wybierz proces spawania próbki.'), findsOneWidget);
    expect(find.textContaining('Podaj grubość próbki'), findsOneWidget);
    expect(find.textContaining('Wybierz pozycję spawania'), findsOneWidget);

    await _fillPipe141(tester);
    expect(_key('qr-problems'), findsNothing);
    // Nieczytelna grubość — wynik znika, komunikat mówi co poprawić.
    await _enter(tester, 'qr-s1', '1,2,3');
    expect(_key('qr-result'), findsNothing);
    await _reveal(tester, 'qr-problems');
    expect(find.textContaining('Grubość próbki: wpisz liczbę większą od 0.'),
        findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    // Pusta średnica.
    await _enter(tester, 'qr-s1', '3');
    await _enter(tester, 'qr-d', '');
    expect(_key('qr-result'), findsNothing);
    await _reveal(tester, 'qr-problems');
    expect(find.textContaining('Podaj średnicę zewnętrzną rury D'),
        findsOneWidget);
  });

  testWidgets('granica s = 12: bez 3 warstw brak wyniku; z 3 warstwami ≥ 3 mm',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'qr-pos-PA');
    await _tap(tester, 'qr-p1-135');
    await _tap(tester, 'qr-tr1-dip');
    await _enter(tester, 'qr-s1', '11,99');
    await _tap(tester, 'qr-fm-FM1');
    await _tap(tester, 'qr-back-ssMb');
    await _reveal(tester, 'qr-value-thickness');
    expect(_value(tester, 'thickness'), '3–23,98 mm');
    await _enter(tester, 'qr-s1', '12');
    expect(_key('qr-result'), findsNothing);
    await _reveal(tester, 'qr-problems');
    expect(find.textContaining('Podaj liczbę warstw'), findsOneWidget);
    await _tap(tester, 'qr-layers-two');
    await _reveal(tester, 'qr-problems');
    expect(find.textContaining('co najmniej 3 warstwy'), findsOneWidget);
    await _tap(tester, 'qr-layers-threeOrMore');
    await _reveal(tester, 'qr-value-thickness');
    expect(_value(tester, 'thickness'), '≥ 3 mm');
    // Notka o rozbieżności z dawną EN 287-1 (≥ 5 mm) — „sprawdź”.
    await _reveal(tester, 'qr-share');
    expect(find.textContaining('EN 287-1', skipOffstage: false),
        findsOneWidget);
    expect(find.textContaining('Sprawdź: ', skipOffstage: false),
        findsWidgets);
  });

  testWidgets('dwa procesy: 141 grań + 111 wypełnienie — s każdego osobno',
      (tester) async {
    await _pump(tester);
    await _fillPipe141(tester, d: '168,3');
    await _tap(tester, 'qr-second');
    await _tap(tester, 'qr-p2-111');
    await _tap(tester, 'qr-f2-coveringBasic');
    await _enter(tester, 'qr-s2', '9');
    await _reveal(tester, 'qr-value-thickness');
    expect(_value(tester, 'thickness-0'), '3–6 mm');
    expect(_value(tester, 'thickness-1'), '3–18 mm');
    expect(_value(tester, 'thickness'), '3–24 mm');
    expect(_value(tester, 'backing-1'), 'ss mb, bs');
  });

  testWidgets('zmiana wyrobu kasuje niepasującą pozycję — bez ukrytego wyboru',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'qr-pos-PE');
    await _tap(tester, 'qr-p1-141');
    await _enter(tester, 'qr-s1', '3');
    await _tap(tester, 'qr-fm-FM1');
    await _tap(tester, 'qr-back-ssNb');
    await _reveal(tester, 'qr-value-positions');
    expect(_value(tester, 'positions'), 'PA, PC, PE');
    // PE nie ma wiersza dla rury — wybór znika, wynik też.
    await _tap(tester, 'qr-product-pipe');
    await _enter(tester, 'qr-d', '60,3');
    expect(_key('qr-pos-PE'), findsNothing);
    expect(_key('qr-result'), findsNothing);
    await _reveal(tester, 'qr-problems');
    expect(find.textContaining('Wybierz pozycję spawania'), findsOneWidget);
    // Podkładka gazowa znika po zmianie procesu na 111 (tab. 11).
    await _tap(tester, 'qr-pos-PH');
    await _tap(tester, 'qr-back-ssGb');
    await _tap(tester, 'qr-p1-111');
    expect(_key('qr-back-ssGb'), findsNothing);
    await _reveal(tester, 'qr-problems');
    expect(find.textContaining('Wybierz prowadzenie grani'), findsOneWidget);
  });

  testWidgets('udostępnianie tekstu i PDF przez wstrzyknięte funkcje',
      (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _fillPipe141(tester);
    await _tap(tester, 'qr-share');
    expect(spy.texts, hasLength(1));
    final (text, subject) = spy.texts.single;
    expect(subject, 'Zakres uprawnień z próbki');
    expect(text, contains('EN ISO 9606-1 141 T BW FM1 S s3 D60,3 PH ss nb'));
    expect(text, contains('• Pozycje (BW): PA, PE, PF, PH [§5.8, tab. 9]'));
    expect(text, contains(iso9606Disclaimer(en: false)));
    await _tap(tester, 'qr-pdf');
    expect(spy.pdfs, hasLength(1));
    expect(spy.pdfs.single.$2, isFalse);
    expect(_pos(spy.pdfs.single.$1.positions), ['PA', 'PE', 'PF', 'PH']);
  });

  testWidgets('wersja EN: kropka dziesiętna, ten sam zakres', (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, language: AppLanguage.en, spy: spy);
    expect(find.text('Range of qualification from a test piece'), findsOneWidget);
    await _fillPipe141(tester, d: '60.3');
    await _reveal(tester, 'qr-value-positions');
    expect(_value(tester, 'diameter'), '≥ 30.15 mm');
    expect(_value(tester, 'positions'), 'PA, PE, PF, PH');
    await _reveal(tester, 'qr-disclaimer');
    expect(find.text(iso9606Disclaimer(en: true)), findsOneWidget);
    await _tap(tester, 'qr-share');
    expect(spy.texts.single.$1, contains(iso9606Disclaimer(en: true)));
    expect(spy.texts.single.$2, 'Range of qualification from a test piece');
  });

  testWidgets('wąski ekran 320×640, tekst ×1,3 — bez przepełnień',
      (tester) async {
    for (final lang in AppLanguage.values) {
      await _pump(tester,
          language: lang, size: const Size(320, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await _tap(tester, 'qr-product-pipe');
      await _tap(tester, 'qr-pos-H-L045');
      await _enter(tester, 'qr-d', '168');
      await _tap(tester, 'qr-p1-141');
      await _enter(tester, 'qr-s1', '3');
      await _tap(tester, 'qr-second');
      await _tap(tester, 'qr-p2-136');
      await _tap(tester, 'qr-f2-otherCored');
      await _enter(tester, 'qr-s2', '12');
      await _tap(tester, 'qr-fm-FM5');
      await _tap(tester, 'qr-back-ssGb');
      await _tap(tester, 'qr-layers-threeOrMore');
      await _tap(tester, 'qr-supplementary');
      await _reveal(tester, 'qr-result');
      await _reveal(tester, 'qr-save');
      await _reveal(tester, 'qr-disclaimer');
      expect(tester.takeException(), isNull, reason: lang.name);
      // FW na rurze z pozycją PH.
      await _tap(tester, 'qr-type-fw');
      await _tap(tester, 'qr-pos-PH');
      await _tap(tester, 'qr-fl-ml');
      await _reveal(tester, 'qr-result');
      await _reveal(tester, 'qr-disclaimer');
      expect(tester.takeException(), isNull, reason: lang.name);
    }
  });

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester);
    await _fillPipe141(tester);
    await _tap(tester, 'qr-p1-135');
    final keys = [
      'qr-product-plate',
      'qr-product-pipe',
      'qr-type-bw',
      'qr-type-fw',
      for (final p in ['PA', 'PC', 'PH', 'PJ', 'H-L045', 'J-L045']) 'qr-pos-$p',
      'qr-companion',
      'qr-d',
      for (final p in Iso9606Process.values) 'qr-p1-${p.code}',
      'qr-tr1-dip',
      'qr-tr1-other',
      'qr-s1',
      'qr-second',
      for (final g in Iso9606FmGroup.values) 'qr-fm-${g.code}',
      'qr-back-ssNb',
      'qr-back-ssMb',
      'qr-back-bs',
      'qr-back-ssGb',
      'qr-back-ssFb',
      'qr-layers-one',
      'qr-layers-two',
      'qr-layers-threeOrMore',
      'qr-supplementary',
    ];
    for (final k in keys) {
      await _reveal(tester, k);
      final size = tester.getSize(_key(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await _tap(tester, 'qr-tr1-dip');
    for (final k in ['qr-share', 'qr-pdf', 'qr-save']) {
      await _reveal(tester, k);
      expect(tester.getSize(_key(k)).height,
          greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    // Typy spoiwa 111 (krótkie etykiety „B”, „C”).
    await _tap(tester, 'qr-p1-111');
    for (final f in Iso9606Process.p111.fillers) {
      final k = 'qr-f1-${f.name}';
      await _reveal(tester, k);
      final size = tester.getSize(_key(k));
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
  });

  group('zapis do rejestru', () {
    useTestDatabase();

    setUp(() {
      SharedPreferences.setMockInitialValues(
          {kLegacyCertMigratedPrefsKey: true});
      QualificationReminders.instance =
          QualificationReminders(platform: _FakePlatform());
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await flushTestDatabase(tester);
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Finder field(String label) => find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label,
          description: 'TextField "$label"',
        );

    testWidgets('„Zapisz jako uprawnienie” → formularz ze szkicem → baza',
        (tester) async {
      await tester.runAsync(() async {
        final db = await AppDatabase.get();
        await db.delete('welder_certificates');
        await db.delete('welder_cert_confirmations');
      });
      await _pump(tester, size: const Size(900, 2600));
      await _fillPipe141(tester);
      await _tap(tester, 'qr-save');

      // Nowy certyfikat (nie edycja istniejącego) z wypełnionym zakresem.
      expect(find.byType(CertificateEditPage), findsOneWidget);
      expect(find.text('Nowy certyfikat'), findsOneWidget);
      String text(String label) =>
          tester.widget<TextField>(field(label)).controller!.text;
      expect(text('Proces(y)'), '141, 142, 143, 145');
      expect(text('Grubość od'), '3');
      expect(text('Średnica D od'), '30,15');
      expect(text('Pozycje (zakres)'), 'PA, PE, PF, PH');
      expect(text('Spoiwo / typ'), 'FM1, FM2 · 141: S, M, bez spoiwa (nm)');

      // Szkic to praca do stracenia — wyjście pyta.
      await tester.tap(find.byTooltip('Wstecz'));
      await tester.pumpAndSettle();
      expect(find.text('Porzucić zmiany?'), findsOneWidget);
      await tester.tap(find.text('Wróć do edycji'));
      await tester.pumpAndSettle();

      await tester.enterText(field('Nr certyfikatu / WPQ'), 'PL-141-7');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await settle(tester);
      await tester.pumpAndSettle();

      final all =
          await tester.runAsync(() => WelderCertificateDao().listAll());
      expect(all, hasLength(1));
      final c = all!.single;
      expect(c.id, isNotEmpty);
      expect(c.certNo, 'PL-141-7');
      expect(c.processes, '141, 142, 143, 145');
      expect(c.thicknessMinMm, 3);
      expect(c.thicknessMaxMm, 6);
      expect(c.diameterMinMm, 30.15);
      expect(c.diameterMaxMm, isNull);
      expect(c.positions, 'PA, PE, PF, PH');
      expect(c.jointKinds, {WeldJointKind.bw});
      expect(c.notes, contains('EN ISO 9606-1 141 T BW FM1 S s3 D60,3 PH ss nb'));
      // Z powrotem na ekranie zakresu, z potwierdzeniem.
      expect(find.byType(QualificationRangePage), findsOneWidget);
      expect(find.text('Zapisano w rejestrze uprawnień.'), findsOneWidget);
    });
  });
}

List<String> _pos(List<Iso6947Position> p) => p.map((e) => e.code).toList();
