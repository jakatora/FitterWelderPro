// Ekran protokołu „Tolerancje spoola”: pozycje z werdyktem (mm i cale),
// brak danych = brak werdyktu, zestawy tolerancji, zły tekst tolerancji
// nie kasuje zapisu, kalkulatory (nachylenie czoła, skręt otworów),
// usuwanie pozycji z cofnięciem, udostępnianie, EN, wąski ekran, cele
// dotyku.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/spool_check/spool_check.dart';
import 'package:cut_list_app/features/spool_check/spool_check_edit_page.dart';
import 'package:cut_list_app/features/spool_check/spool_check_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

final _now = DateTime(2026, 10, 18, 9, 0);

class _Spy {
  final List<(String, String)> texts = [];
  Future<void> text(String t, String subject) async => texts.add((t, subject));
}

Future<_Spy> _pump(
  WidgetTester tester, {
  SpoolCheck? initial,
  AppLanguage language = AppLanguage.pl,
  Size size = const Size(1080, 2400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final spy = _Spy();
  var n = 0;
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SpoolCheckEditPage(
        initial: initial ?? SpoolCheck.blank(id: 'c1', now: _now),
        now: () => _now,
        newId: () => 'it-${++n}',
        shareText: spy.text,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return spy;
}

Finder get _scrollable => find
    .descendant(
        of: find.byKey(const ValueKey('sc-edit-list')),
        matching: find.byType(Scrollable))
    .first;

Future<Finder> _show(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) {
    await tester.drag(_scrollable, const Offset(0, 20000));
    await tester.pumpAndSettle();
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 300, scrollable: _scrollable);
    }
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  return f;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(await _show(tester, key));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(await _show(tester, key), text);
  await tester.pumpAndSettle();
}

Future<String> _text(WidgetTester tester, String key) async =>
    tester.widget<Text>(await _show(tester, key)).data!;

Future<String> _field(WidgetTester tester, String key) async =>
    tester.widget<TextField>(await _show(tester, key)).controller!.text;

Future<SpoolCheck> _saved() async {
  // Zapis idzie w tle — kolejka magazynu gwarantuje, że odczyt go widzi.
  return (await const SpoolCheckStore().load()).single;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final language in AppLanguage.values) {
    testWidgets('large fractions and overflowing inches do not break the form: $language',
        (tester) async {
      await _pump(tester, language: language);
      await _tapKey(tester, 'sc-unit-inch');
      await _tapKey(tester, 'sc-add-faceToFace');
      const fraction = '9223372036854775808/9223372036854775808';
      await _enter(tester, 'sc-i-0-drawing', fraction);
      await _enter(tester, 'sc-i-0-measured', '1');
      await _enter(tester, 'sc-i-0-tol', '1/8');
      expect((await _saved()).items.single.drawingMm, 25.4);
      expect((await _saved()).evaluate().items.single.verdict, SpoolVerdict.ok);
      await _enter(tester, 'sc-i-0-measured', '1${'0' * 308}');
      expect(tester.takeException(), isNull);
      expect((await _saved()).items.single.measuredMm, isNull);
      expect((await _saved()).evaluate().items.single.verdict, SpoolVerdict.none);
      expect(await _field(tester, 'sc-i-0-measured'), '1${'0' * 308}');
    });
  }

  testWidgets(
      'pozycja F–F DN150: 1253 przy 1250 — w tolerancji, 1253,5 — '
      'poza; zapis w historii', (tester) async {
    await _pump(tester);
    expect(find.text('Protokół spoola'), findsOneWidget);
    expect(await _text(tester, 'sc-status-text'),
        'Brak pozycji pomiaru — dodaj pozycje z izometrii.');
    await _enter(tester, 'sc-f-spoolNo', '100-P-1203-S02');
    await _enter(tester, 'sc-f-dn', '150');
    await _tapKey(tester, 'sc-add-faceToFace');
    await _enter(tester, 'sc-i-0-label', 'F1–F2');
    await _enter(tester, 'sc-i-0-drawing', '1250');
    await _enter(tester, 'sc-i-0-measured', '1253');
    expect(await _text(tester, 'sc-i-0-verdict'), 'w tolerancji');
    expect(await _text(tester, 'sc-status-text'),
        'Spool w tolerancji — 1/1 poz. sprawdzonych.');
    expect(find.text('Wobec: PFI ES-3, do 10″ (DN ≤ 250)'), findsOneWidget);
    expect(find.textContaining('Odchyłka: +3 mm'), findsOneWidget);
    expect(find.textContaining('Tolerancja: ±3 mm (≈0,118″)'), findsOneWidget);

    await _enter(tester, 'sc-i-0-measured', '1253,5');
    expect(await _text(tester, 'sc-i-0-verdict'), 'POZA TOLERANCJĄ');
    expect(await _text(tester, 'sc-status-text'),
        startsWith('Spool POZA TOLERANCJĄ — pozycje poza: 1 z 1.'));

    final s = await _saved();
    expect(s.spoolNo, '100-P-1203-S02');
    expect(s.dn, 150);
    expect(s.items.single.label, 'F1–F2');
    expect(s.items.single.drawingMm, 1250);
    expect(s.items.single.measuredMm, 1253.5);
  });

  testWidgets(
      'cale: 98 1/2 i 98 5/8 przy tolerancji 1/8 — na granicy; po '
      'przełączeniu na mm werdykt i zapis bez zmian', (tester) async {
    await _pump(tester);
    await _enter(tester, 'sc-f-spoolNo', 'S-1');
    await _tapKey(tester, 'sc-unit-inch');
    await _tapKey(tester, 'sc-add-faceToFace');
    await _enter(tester, 'sc-i-0-drawing', '98 1/2');
    await _enter(tester, 'sc-i-0-measured', '98 5/8');
    // Bez DN: ES-3 nie dobierze pasma — brak werdyktu.
    expect(await _text(tester, 'sc-i-0-verdict'), 'brak werdyktu');
    await _enter(tester, 'sc-i-0-tol', '1/8');
    expect(await _text(tester, 'sc-i-0-verdict'), 'w tolerancji');
    expect(find.text('Odchyłka: +1/8″ (3,175 mm)'), findsOneWidget);

    await _tapKey(tester, 'sc-unit-mm');
    expect(await _text(tester, 'sc-i-0-verdict'), 'w tolerancji');
    expect(await _field(tester, 'sc-i-0-drawing'), '2501,9');
    expect(await _field(tester, 'sc-i-0-tol'), '3,175');
    final s = await _saved();
    expect(s.unit, SpoolUnit.mm);
    expect(s.items.single.drawingMm, closeTo(2501.9, 1e-9));
    expect(s.items.single.measuredMm, closeTo(2505.075, 1e-9));
    expect(s.items.single.toleranceMm, 3.175);

    await _tapKey(tester, 'sc-unit-inch');
    expect(await _field(tester, 'sc-i-0-drawing'), '98 1/2');
    expect(await _text(tester, 'sc-i-0-verdict'), 'w tolerancji');
  });

  testWidgets('brak wymiaru z rysunku — brak werdyktu, spool nie zielony',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'sc-f-dn', '150');
    await _tapKey(tester, 'sc-add-centerToFace');
    await _enter(tester, 'sc-i-0-measured', '600');
    expect(await _text(tester, 'sc-i-0-verdict'), 'brak werdyktu');
    expect(find.text('• brak wymiaru z rysunku'), findsOneWidget);
    expect(await _text(tester, 'sc-status-text'),
        'Bez werdyktu: 1 z 1 poz. — uzupełnij dane.');
    final card =
        tester.widget<Material>(find.byKey(const ValueKey('sc-status')));
    expect(card.color, isNot(kPass.withValues(alpha: 0.10)));
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
  });

  testWidgets(
      'zestaw „z projektu”: bez tolerancji brak werdyktu; wpisana — '
      'werdykt wobec projektu; zły tekst nie kasuje zapisanej tolerancji',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'sc-f-spoolNo', 'S-2');
    await _tapKey(tester, 'sc-set-project');
    await _tapKey(tester, 'sc-add-faceToFace');
    await _enter(tester, 'sc-i-0-drawing', '1250');
    await _enter(tester, 'sc-i-0-measured', '1252');
    expect(await _text(tester, 'sc-i-0-verdict'), 'brak werdyktu');
    expect(find.text('• brak tolerancji'), findsOneWidget);

    await _enter(tester, 'sc-i-0-tol', '2');
    expect(await _text(tester, 'sc-i-0-verdict'), 'w tolerancji');
    expect(find.text('Wobec: projekt (wpisane)'), findsOneWidget);
    expect(
        await _text(tester, 'sc-status-basis'),
        'Oceniono wobec: tolerancje z projektu — wartości wpisane przez '
        'użytkownika');

    // Nieczytelny tekst i wartość spoza zakresu — zapis zostaje.
    await _enter(tester, 'sc-i-0-tol', '2..5');
    expect(find.textContaining('Obowiązuje nadal: ±2 mm'), findsOneWidget);
    expect(await _text(tester, 'sc-i-0-verdict'), 'w tolerancji');
    await _enter(tester, 'sc-i-0-tol', '60');
    expect(find.textContaining('Obowiązuje nadal: ±2 mm'), findsOneWidget);
    expect((await _saved()).items.single.toleranceMm, 2);

    // Puste pole — brak tolerancji (bez cichego podstawienia normy).
    await _enter(tester, 'sc-i-0-tol', '');
    expect(await _text(tester, 'sc-i-0-verdict'), 'brak werdyktu');
    expect((await _saved()).items.first.toleranceMm, isNull);
  });

  testWidgets(
      'podpowiedź tolerancji z poprzedniej pozycji: nowa pozycja ma '
      'puste pole i brak werdyktu, stuknięcie przyjmuje wartość',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'sc-f-spoolNo', 'S-5');
    await _tapKey(tester, 'sc-set-project');
    await _tapKey(tester, 'sc-add-faceToFace');
    await _enter(tester, 'sc-i-0-tol', '3');
    await _tapKey(tester, 'sc-add-faceToFace');
    await _enter(tester, 'sc-i-1-drawing', '800');
    await _enter(tester, 'sc-i-1-measured', '801');
    expect(await _field(tester, 'sc-i-1-tol'), isEmpty);
    expect(await _text(tester, 'sc-i-1-verdict'), 'brak werdyktu');
    expect((await _saved()).items[1].toleranceMm, isNull);
    final hint = await _show(tester, 'sc-i-1-tol-suggest');
    expect(
        find.descendant(
            of: hint,
            matching: find.text('Jak w poz. 1: ±3 mm — stuknij, by przyjąć')),
        findsOneWidget);
    // Pierwsza pozycja nie ma podpowiedzi (nie ma poprzedniej).
    expect(find.byKey(const ValueKey('sc-i-0-tol-suggest')), findsNothing);
    await _tapKey(tester, 'sc-i-1-tol-suggest');
    expect(await _field(tester, 'sc-i-1-tol'), '3');
    expect(await _text(tester, 'sc-i-1-verdict'), 'w tolerancji');
    expect((await _saved()).items[1].toleranceMm, 3);
    expect(find.byKey(const ValueKey('sc-i-1-tol-suggest')), findsNothing);
  });

  testWidgets(
      'błąd pola tolerancji znika po powrocie do zapisanej wartości '
      '(30 → 300 → 30)', (tester) async {
    await _pump(tester);
    await _enter(tester, 'sc-f-spoolNo', 'S-6');
    await _tapKey(tester, 'sc-set-project');
    await _tapKey(tester, 'sc-add-straightness');
    await _enter(tester, 'sc-i-0-tol', '30');
    expect(find.textContaining('Obowiązuje nadal'), findsNothing);
    await _enter(tester, 'sc-i-0-tol', '300');
    expect(find.textContaining('Obowiązuje nadal: ±30 mm'), findsOneWidget);
    await _enter(tester, 'sc-i-0-tol', '30');
    expect(find.textContaining('Obowiązuje nadal'), findsNothing);
    expect((await _saved()).items.single.toleranceMm, 30);
  });

  testWidgets(
      'tolerancja niesymetryczna +0 / −3 z projektu: werdykt wg znaku '
      'odchyłki; jedna wartość — brak werdyktu', (tester) async {
    await _pump(tester);
    await _enter(tester, 'sc-f-spoolNo', 'S-7');
    await _tapKey(tester, 'sc-set-project');
    await _tapKey(tester, 'sc-add-faceToFace');
    await _enter(tester, 'sc-i-0-drawing', '1250');
    await _enter(tester, 'sc-i-0-measured', '1247');
    await _enter(tester, 'sc-i-0-tolMinus', '3');
    expect(await _text(tester, 'sc-i-0-verdict'), 'brak werdyktu');
    expect(
        find.text('• wpisz obie wartości tolerancji: + i −'), findsOneWidget);
    await _enter(tester, 'sc-i-0-tolPlus', '0');
    expect(await _text(tester, 'sc-i-0-verdict'), 'w tolerancji');
    expect(
        find.text('Tolerancja: +0 mm (0″) / −3 mm (≈0,118″)'), findsOneWidget);
    // Dłuższy o 0,5 mm przy „+0” — poza, choć |0,5| < 3.
    await _enter(tester, 'sc-i-0-measured', '1250,5');
    expect(await _text(tester, 'sc-i-0-verdict'), 'POZA TOLERANCJĄ');
    final it = (await _saved()).items.single;
    expect(it.tolPlusMm, 0);
    expect(it.tolMinusMm, 3);
    // Pola + / − tylko przy zestawie „z projektu”.
    await _tapKey(tester, 'sc-set-pfiEs3');
    expect(find.byKey(const ValueKey('sc-i-0-tolPlus')), findsNothing);
  });

  testWidgets(
      'numer spoola już w historii — ostrzeżenie, protokół zapisuje '
      'się mimo to; brak numeru — przypomnienie', (tester) async {
    await const SpoolCheckStore().upsert(const SpoolCheck(
        id: 'old', spoolNo: 'S-01', date: '2026-10-17', dn: 150));
    await _pump(tester);
    await _enter(tester, 'sc-f-dn', '150');
    await _show(tester, 'sc-spoolno-missing');
    await _enter(tester, 'sc-f-spoolNo', 's-01 ');
    expect(find.byKey(const ValueKey('sc-spoolno-missing')), findsNothing);
    await _show(tester, 'sc-spoolno-duplicate');
    final all = await const SpoolCheckStore().load();
    expect(all.map((c) => c.spoolNo.trim().toLowerCase()), ['s-01', 's-01']);
    await _enter(tester, 'sc-f-spoolNo', 'S-02');
    expect(find.byKey(const ValueKey('sc-spoolno-duplicate')), findsNothing);
  });

  testWidgets(
      'EN 13480-4: klasa zał. B i wartości wpisane — podstawa w '
      'werdykcie', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'sc-set-en13480');
    await _show(tester, 'sc-en-info');
    await _enter(tester, 'sc-f-enGrade', '2');
    await _tapKey(tester, 'sc-add-centerToCenter');
    await _enter(tester, 'sc-i-0-drawing', '900');
    await _enter(tester, 'sc-i-0-measured', '901,5');
    expect(await _text(tester, 'sc-i-0-verdict'), 'brak werdyktu');
    await _enter(tester, 'sc-i-0-tol', '1,5');
    expect(await _text(tester, 'sc-i-0-verdict'), 'w tolerancji');
    expect(find.text('Wobec: EN 13480-4 zał. B (wpisane)'), findsOneWidget);
    expect(await _text(tester, 'sc-status-basis'),
        contains('EN 13480-4:2017 zał. B, klasa 2'));
  });

  testWidgets(
      'nachylenie czoła: kalkulator szczelin wpisuje odchyłkę; '
      'granica ES-3 dla średnicy', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'sc-add-faceTilt');
    await _enter(tester, 'sc-i-0-measured', '0,5');
    expect(await _text(tester, 'sc-i-0-verdict'), 'brak werdyktu');
    expect(find.text('• brak średnicy, na której zmierzono'), findsOneWidget);
    await _enter(tester, 'sc-i-0-base', '300');
    await _enter(tester, 'sc-i-0-gapA', '0,9');
    await _enter(tester, 'sc-i-0-gapB', '0,3');
    expect(find.text('Różnica szczelin: 0,6 mm (≈0,024″)'), findsOneWidget);
    await _tapKey(tester, 'sc-i-0-calc-apply');
    expect(await _field(tester, 'sc-i-0-measured'), '0,6');
    expect(await _text(tester, 'sc-i-0-verdict'), 'w tolerancji');
    expect(find.text('Nachylenie: 0,115° = 2 mm/m'), findsOneWidget);
    expect(find.textContaining('Granica ES-3 na tej średnicy: 1,171875 mm'),
        findsOneWidget);
    await _enter(tester, 'sc-i-0-gapA', '1,3');
    await _enter(tester, 'sc-i-0-gapB', '0');
    await _tapKey(tester, 'sc-i-0-calc-apply');
    expect(await _text(tester, 'sc-i-0-verdict'), 'POZA TOLERANCJĄ');
    expect((await _saved()).items.single.measuredMm, 1.3);
  });

  testWidgets('skręt otworów jako kąt na średnicy podziałowej', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'sc-add-boltRotation');
    await _tapKey(tester, 'sc-i-0-mode-angle');
    await _enter(tester, 'sc-i-0-angle', '0,5');
    expect(await _text(tester, 'sc-i-0-verdict'), 'brak werdyktu');
    expect(find.text('• brak średnicy podziałowej'), findsOneWidget);
    await _enter(tester, 'sc-i-0-base', '241,3');
    expect(await _text(tester, 'sc-i-0-verdict'), 'w tolerancji');
    expect(find.textContaining('= 1,053 mm (≈0,041″) po obwodzie'),
        findsOneWidget);
    expect(find.text('Wobec: PFI ES-3, obrót kołnierza'), findsOneWidget);
    await _enter(tester, 'sc-i-0-angle', '0,8');
    expect(await _text(tester, 'sc-i-0-verdict'), 'POZA TOLERANCJĄ');
    final it = (await _saved()).items.single;
    expect(it.rotationByAngle, isTrue);
    expect(it.angleDeg, 0.8);
    expect(it.baseMm, 241.3);
  });

  testWidgets('usunięcie pozycji z cofnięciem na ekranie', (tester) async {
    await _pump(tester);
    await _enter(tester, 'sc-f-spoolNo', 'S-3');
    await _tapKey(tester, 'sc-add-faceToFace');
    await _tapKey(tester, 'sc-add-branchPosition');
    await _enter(tester, 'sc-i-0-label', 'A');
    await _enter(tester, 'sc-i-1-label', 'B');
    await _tapKey(tester, 'sc-i-0-del');
    expect(find.byKey(const ValueKey('sc-i-1-label')), findsNothing);
    expect((await _saved()).items.map((i) => i.label), ['B']);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect((await _saved()).items.map((i) => i.label), ['A', 'B']);
    expect(await _field(tester, 'sc-i-0-label'), 'A');
  });

  testWidgets('udostępnianie tekstu protokołu', (tester) async {
    final spy = await _pump(tester);
    await _enter(tester, 'sc-f-spoolNo', '100-P-1203-S02');
    await _enter(tester, 'sc-f-dn', '150');
    await _tapKey(tester, 'sc-add-faceToFace');
    await _enter(tester, 'sc-i-0-drawing', '1250');
    await _enter(tester, 'sc-i-0-measured', '1251');
    await _tapKey(tester, 'sc-share-text');
    expect(spy.texts, hasLength(1));
    final (text, subject) = spy.texts.single;
    expect(subject, 'Tolerancje spoola — protokół kontroli wymiarów');
    expect(text, contains('Nr spoola: 100-P-1203-S02'));
    expect(text, contains('WERDYKT: Spool w tolerancji — 1/1 poz.'));
    expect(text, contains('PFI ES-3'));
    await _tapKey(tester, 'sc-share-text-btn');
    expect(spy.texts, hasLength(2));
  });

  testWidgets('po angielsku', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Spool record'), findsOneWidget);
    await _enter(tester, 'sc-f-dn', '150');
    await _tapKey(tester, 'sc-add-faceToFace');
    await _enter(tester, 'sc-i-0-drawing', '1250');
    await _enter(tester, 'sc-i-0-measured', '1253,5');
    expect(await _text(tester, 'sc-i-0-verdict'), 'OUT OF TOLERANCE');
    expect(await _text(tester, 'sc-status-text'),
        startsWith('Spool OUT OF TOLERANCE'));
    await _show(tester, 'sc-howto');
    expect(find.text('HOW TO MEASURE — SHOP PRACTICE'), findsOneWidget);
  });

  testWidgets('ściąga „jak mierzyć” i źródła na ekranie', (tester) async {
    await _pump(tester);
    final how = await _show(tester, 'sc-howto');
    expect(
        find.descendant(
            of: how, matching: find.text('JAK MIERZYĆ — PRAKTYKA WARSZTATOWA')),
        findsOneWidget);
    expect(
        find.descendant(
            of: how,
            matching: find.text('Praktyka warsztatowa, nie wymagania normy.')),
        findsOneWidget);
    final src = await _show(tester, 'sc-sources');
    expect(
        find.descendant(
            of: src, matching: find.textContaining('wyd. poprawione III 2004')),
        findsOneWidget);
    expect(
        find.descendant(
            of: src, matching: find.textContaining('ES-03 R24 (2024)')),
        findsOneWidget);
  });

  testWidgets(
      'ekran 360×640, tekst ×1,5: wszystkie rodzaje pozycji bez '
      'przepełnień', (tester) async {
    await _pump(tester, size: const Size(360, 640), textScale: 1.5);
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'sc-unit-inch');
    for (final k in SpoolItemKind.values) {
      await _tapKey(tester, 'sc-add-${k.name}');
      expect(tester.takeException(), isNull, reason: k.name);
    }
    await _tapKey(tester, 'sc-i-4-mode-angle');
    await _enter(tester, 'sc-i-5-gapA', '1/32');
    for (final s in SpoolToleranceSet.values) {
      await _tapKey(tester, 'sc-set-${s.name}');
      expect(tester.takeException(), isNull, reason: s.name);
    }
    // Przewinięcie całego ekranu buduje każdy element.
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sc-share-text-btn')), 400,
        scrollable: _scrollable, maxScrolls: 200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawica)', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'sc-add-boltRotation');
    await _tapKey(tester, 'sc-add-faceTilt');
    final keys = [
      'sc-share-text',
      'sc-date',
      'sc-unit-mm',
      'sc-unit-inch',
      for (final s in SpoolToleranceSet.values) 'sc-set-${s.name}',
      for (final k in SpoolItemKind.values) 'sc-add-${k.name}',
      'sc-i-0-del',
      'sc-i-0-mode-arc',
      'sc-i-0-mode-angle',
      'sc-i-1-calc-apply',
      'sc-share-text-btn',
    ];
    for (final k in keys) {
      final f = await _show(tester, k);
      final size = tester.getSize(f);
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
  });

  for (final (date, expected) in [
    ('1999-12-31', DateTime(2000)),
    ('2101-01-01', DateTime(2100)),
  ]) {
    testWidgets('kalendarz ogranicza datę początkową spoola $date',
        (tester) async {
      await _pump(tester,
          initial: SpoolCheck.blank(id: 'c1', now: _now).copyWith(date: date));
      await _tapKey(tester, 'sc-date');
      expect(tester.takeException(), isNull);
      expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .initialDate, expected);
    });
  }
}
