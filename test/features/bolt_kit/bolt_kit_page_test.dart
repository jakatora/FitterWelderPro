// Śruby do kołnierzy na ekranie: długość z tabeli B16.5 po wyborze DN ×
// Class, tryb z wymiarów, lista połączeń → zamówienie z zapasem, zapis,
// udostępnianie przez wstrzykniętą funkcję, „Moment śrub”, EN, wąski ekran
// i cele dotyku.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/bolting/bolt_kit.dart';
import 'package:cut_list_app/features/bolt_kit/bolt_kit_page.dart';
import 'package:cut_list_app/features/bolt_kit/bolt_kit_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/bolt_torque_screen.dart';
import 'package:cut_list_app/services/bolt_kit_export.dart';
import 'package:cut_list_app/theme/app_theme.dart';

Future<void> _noShare(BoltKitOrder o, BoltKitShareFormat f, bool en) async {}

/// Magazyn, którego pierwszy odczyt rzuca (chwilowy błąd platformy).
class _FlakyStore extends BoltKitStore {
  _FlakyStore();

  var reads = 0;

  @override
  Future<Object?> readRaw() async {
    if (reads++ == 0) throw StateError('kanał platformy niedostępny');
    return super.readRaw();
  }
}

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.pl,
  Size size = const Size(800, 6000),
  double textScale = 1.0,
  Map<String, Object> prefs = const {},
  BoltKitShareFn share = _noShare,
  BoltKitTorqueFn? openTorque,
  BoltKitStore store = const BoltKitStore(),
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: BoltKitPage(share: share, openTorque: openTorque, store: store),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(_key(key), text);
  await tester.pump();
}

/// Wybór z listy rozwijanej: [key] pola, [item] tekst pozycji.
Future<void> _pick(WidgetTester tester, String key, String item) async {
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

/// SnackBar trzyma licznik czasu — test kończy się po jego wygaśnięciu.
Future<void> _drainSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String key) {
  final w = tester.widget(_key(key));
  if (w is IconButton) return w.onPressed != null;
  return (w as ButtonStyleButton).onPressed != null;
}

/// Wpisanie do pola niżej na liście (wąski ekran — pole jeszcze nie
/// zbudowane): najpierw przewinięcie do niego.
Future<void> _enterBelow(WidgetTester tester, String key, String text) async {
  await tester.scrollUntilVisible(_key(key), 150,
      scrollable: find
          .descendant(
              of: _key('bk-length-list'), matching: find.byType(Scrollable))
          .first);
  await _enter(tester, key, text);
}

Finder _in(String key, String text) =>
    find.descendant(of: _key(key), matching: find.text(text));

String _saved(List<BoltKitJoint> joints, {int spare = 0}) =>
    encodeBoltKit(BoltKitState(joints: joints, sparePercent: spare));

const _a = BoltKitJoint(
  id: 'a',
  dn: 150,
  cls: 300,
  facing: FlangeFacing.rf,
  material: BoltMaterial.b7,
  count: 4,
);
const _b = BoltKitJoint(
  id: 'b',
  dn: 80,
  cls: 600,
  facing: FlangeFacing.rtj,
  material: BoltMaterial.b7m,
  count: 2,
);
const _c = BoltKitJoint(
  id: 'c',
  dn: 300,
  cls: 1500,
  facing: FlangeFacing.rtj,
  material: BoltMaterial.l7,
  count: 12,
);

void main() {
  testWidgets('wybór DN × Class → długość szpilki z tabeli B16.5',
      (tester) async {
    await _pump(tester);
    // Domyślnie DN100 Class 150 RF.
    expect(_text(tester, 'bk-asme-length'), '5/8" × 3-1/2"');
    expect(_text(tester, 'bk-asme-mm'), 'długość 88,9 mm');
    expect(_text(tester, 'bk-asme-count'),
        'Szpilki: 8 szt. · nakrętki heavy hex: 16 szt. · gwint 5/8"-11 UNC');

    await _pick(tester, 'bk-class', 'Class 300');
    expect(_text(tester, 'bk-asme-length'), '3/4" × 4-1/2"');

    await _pick(tester, 'bk-dn', 'DN150 (6")');
    expect(_text(tester, 'bk-asme-length'), '3/4" × 4-3/4"');
    expect(_text(tester, 'bk-asme-mm'), 'długość 120,65 mm');
    expect(_text(tester, 'bk-asme-count'), startsWith('Szpilki: 12 szt.'));
    expect(_key('bk-asme-ring'), findsNothing);

    await _tap(tester, 'bk-facing-rtj');
    expect(_text(tester, 'bk-asme-length'), '3/4" × 5-1/2"');
    expect(_text(tester, 'bk-asme-ring'), 'Pierścień R45');
  });

  testWidgets('Class 150 DN15 RTJ — komunikat zamiast wyniku, bez dodawania',
      (tester) async {
    await _pump(tester);
    await _pick(tester, 'bk-dn', 'DN15 (1/2")');
    expect(_text(tester, 'bk-asme-length'), '1/2" × 2-1/4"');
    await _tap(tester, 'bk-facing-rtj');
    expect(_key('bk-asme-problem'), findsOneWidget);
    expect(_key('bk-asme-length'), findsNothing);
    expect(find.textContaining('nie przewiduje RTJ'), findsOneWidget);
    expect(_enabled(tester, 'bk-add'), isFalse);
  });

  testWidgets('rozbieżne źródła — dłuższa długość i notatka', (tester) async {
    await _pump(tester);
    await _pick(tester, 'bk-class', 'Class 600');
    await _pick(tester, 'bk-dn', 'DN200 (8")');
    expect(_key('bk-asme-source-note'), findsNothing);
    await _tap(tester, 'bk-facing-rtj');
    expect(_text(tester, 'bk-asme-length'), '1-1/8" × 7-3/4"');
    expect(_key('bk-asme-source-note'), findsOneWidget);
  });

  testWidgets('tryb z wymiarów: 93,5 mm → 95 mm; puste pole — brak wyniku',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'bk-mode-dims');
    expect(_key('bk-dims-missing'), findsOneWidget);
    expect(_key('bk-dims-result'), findsNothing);

    await _enter(tester, 'bk-f1', '24');
    await _enter(tester, 'bk-f2', '24');
    await _enter(tester, 'bk-gasket-t', '4,5');
    await _enter(tester, 'bk-nut', '18');
    expect(_key('bk-dims-result'), findsNothing);
    expect(find.textContaining('wystawanie gwintu'), findsOneWidget);

    await _enter(tester, 'bk-protrusion', '2,5');
    expect(_text(tester, 'bk-dims-order'), '95 mm');
    expect(_text(tester, 'bk-dims-required'),
        'Obliczona: 93,5 mm → w górę co 5 mm');
    expect(
        _text(tester, 'bk-dims-breakdown'), '24 + 24 + 4,5 + 2 × 18 + 2 × 2,5');

    await _tap(tester, 'bk-series-quarterInch');
    expect(_text(tester, 'bk-dims-order'), '3-3/4" (95,25 mm)');
    await _tap(tester, 'bk-series-mm10');
    expect(_text(tester, 'bk-dims-order'), '100 mm');

    // Podkładki 2 × 3 mm: 99,5 → 100 mm; bez grubości — brak wyniku.
    await _tap(tester, 'bk-washers-2');
    expect(_key('bk-dims-result'), findsNothing);
    expect(find.textContaining('grubość podkładki'), findsOneWidget);
    await _enter(tester, 'bk-washer-t', '3');
    expect(_text(tester, 'bk-dims-required'),
        'Obliczona: 99,5 mm → w górę co 10 mm');
    expect(_text(tester, 'bk-dims-order'), '100 mm');

    // Wyczyszczone albo nieczytelne pole — znowu brak wyniku.
    await _enter(tester, 'bk-nut', '');
    expect(_key('bk-dims-result'), findsNothing);
    await _enter(tester, 'bk-nut', '1,2,3');
    expect(_key('bk-dims-result'), findsNothing);
    expect(find.text('Wpisz liczbę'), findsOneWidget);
    await _enter(tester, 'bk-nut', '0');
    expect(find.text('Wpisz wartość > 0, najwyżej 150 mm'), findsOneWidget);
  });

  testWidgets('lista połączeń → zamówienie z zapasem i zapis', (tester) async {
    await _pump(tester);
    await _pick(tester, 'bk-class', 'Class 300');
    await _pick(tester, 'bk-dn', 'DN150 (6")');
    await _enter(tester, 'bk-count', '4');
    await _tap(tester, 'bk-add');
    expect(
        find.text('Dodano: 4 × DN150 (6") · Class 300 · RF'), findsOneWidget);
    await _drainSnackBars(tester);
    expect(find.text('Komplet (4)'), findsOneWidget);

    await _tap(tester, 'bk-tab-kit');
    expect(_in('bk-order-stud-0', '3/4" × 4-3/4" (120,65 mm) A193 B7'),
        findsOneWidget);
    expect(_in('bk-order-stud-0', '48 szt.'), findsOneWidget);
    expect(_in('bk-order-nut-0', '96 szt.'), findsOneWidget);
    expect(_in('bk-order-gasket-0', 'spiralna (ASME B16.20), NPS 6 Class 300'),
        findsOneWidget);
    expect(_in('bk-order-gasket-0', '4 szt.'), findsOneWidget);

    await _tap(tester, 'bk-spare-10');
    expect(_in('bk-order-stud-0', '48 szt. + zapas 10 % = 53 szt.'),
        findsOneWidget);
    expect(_in('bk-order-nut-0', '96 szt. + zapas 10 % = 106 szt.'),
        findsOneWidget);
    expect(_in('bk-order-gasket-0', '4 szt. + zapas 10 % = 5 szt.'),
        findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final d = decodeBoltKitReport(prefs.getString(BoltKitStore.key));
    expect(d.intact, isTrue);
    expect(d.state.sparePercent, 10);
    expect(d.state.joints.single.count, 4);
    expect(d.state.joints.single.dn, 150);
  });

  testWidgets(
      'to samo połączenie drugi raz — scala; +/− i usuwanie z cofnięciem',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'bk-add');
    await _drainSnackBars(tester);
    await _tap(tester, 'bk-add');
    await _drainSnackBars(tester);
    expect(find.text('Komplet (2)'), findsOneWidget);

    await _tap(tester, 'bk-tab-kit');
    final id = decodeBoltKitReport(
            (await SharedPreferences.getInstance()).getString(BoltKitStore.key))
        .state
        .joints
        .single
        .id;
    expect(_text(tester, 'bk-j-count-$id'), '2 ×');
    await _tap(tester, 'bk-j-plus-$id');
    expect(_text(tester, 'bk-j-count-$id'), '3 ×');
    expect(_in('bk-order-stud-0', '24 szt.'), findsOneWidget);
    await _tap(tester, 'bk-j-minus-$id');
    await _tap(tester, 'bk-j-minus-$id');
    expect(_text(tester, 'bk-j-count-$id'), '1 ×');
    expect(_enabled(tester, 'bk-j-minus-$id'), isFalse);

    await _tap(tester, 'bk-j-del-$id');
    expect(_key('bk-kit-empty'), findsOneWidget);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'bk-j-count-$id'), '1 ×');
    await _drainSnackBars(tester);
  });

  testWidgets('udostępnianie przez wstrzykniętą funkcję (tekst i PDF)',
      (tester) async {
    final calls = <(BoltKitShareFormat, bool, int)>[];
    await _pump(tester,
        prefs: {
          BoltKitStore.key: _saved([_a, _b], spare: 5)
        },
        share: (o, f, en) async => calls.add((f, en, o.totalStuds)));
    expect(find.text('Komplet (6)'), findsOneWidget);
    await _tap(tester, 'bk-tab-kit');
    await _tap(tester, 'bk-share-text');
    await _tap(tester, 'bk-share-pdf');
    // 4 × 12 + 2 × 8 = 64 szpilki.
    expect(calls, [
      (BoltKitShareFormat.text, false, 64),
      (BoltKitShareFormat.pdf, false, 64),
    ]);
  });

  testWidgets('nieudane udostępnianie — komunikat, ekran działa',
      (tester) async {
    await _pump(tester,
        prefs: {
          BoltKitStore.key: _saved([_a])
        },
        share: (o, f, en) async => throw StateError('brak'));
    await _tap(tester, 'bk-tab-kit');
    await _tap(tester, 'bk-share-pdf');
    expect(find.text('Nie udało się udostępnić zamówienia.'), findsOneWidget);
    expect(_enabled(tester, 'bk-share-pdf'), isTrue);
    await _drainSnackBars(tester);
  });

  testWidgets('uszkodzony zapis — komunikat i pusta lista, ekran działa',
      (tester) async {
    await _pump(tester, prefs: {BoltKitStore.key: '{"v":1,"joints":[{'});
    expect(tester.takeException(), isNull);
    expect(find.text('Komplet (0)'), findsOneWidget);
    await _tap(tester, 'bk-tab-kit');
    expect(_key('bk-damaged'), findsOneWidget);
    expect(_key('bk-kit-empty'), findsOneWidget);
  });

  testWidgets(
      'chwilowy błąd odczytu — komunikat, pierwszy zapis zachowuje starą '
      'listę w kopii', (tester) async {
    final original = _saved([_a, _b], spare: 5);
    await _pump(tester,
        prefs: {BoltKitStore.key: original}, store: _FlakyStore());
    expect(find.text('Komplet (0)'), findsOneWidget);
    await _tap(tester, 'bk-tab-kit');
    expect(_key('bk-damaged'), findsOneWidget);
    expect(find.textContaining('Nie udało się odczytać zapisanej listy'),
        findsOneWidget);

    await _tap(tester, 'bk-tab-length');
    await _tap(tester, 'bk-add');
    await _drainSnackBars(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BoltKitStore.corruptKey), original);
    final saved = decodeBoltKitReport(prefs.getString(BoltKitStore.key));
    expect(saved.state.joints.single.dn, 100);

    // Drugi zapis — normalny, kopia bez zmian, bez komunikatu o blokadzie.
    await _tap(tester, 'bk-tab-kit');
    final id = saved.state.joints.single.id;
    await _tap(tester, 'bk-j-plus-$id');
    expect(find.textContaining('zapis wstrzymany'), findsNothing);
    expect(prefs.getString(BoltKitStore.corruptKey), original);
    expect(
        decodeBoltKitReport(prefs.getString(BoltKitStore.key))
            .state
            .joints
            .single
            .count,
        2);
  });

  testWidgets('błąd odczytu i zajęta kopia — zapis wstrzymany z komunikatem',
      (tester) async {
    final original = _saved([_a]);
    await _pump(tester,
        prefs: {
          BoltKitStore.key: original,
          BoltKitStore.corruptKey: 'starsza kopia',
        },
        store: _FlakyStore());
    await _tap(tester, 'bk-add');
    expect(find.textContaining('zapis wstrzymany'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BoltKitStore.key), original);
    await _drainSnackBars(tester);
  });

  testWidgets('„Moment śrub” otwiera istniejący kalkulator z podpowiedzią',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'bk-torque');
    expect(find.byType(BoltTorqueScreen), findsOneWidget);
    expect(find.text('W „Moment śrub” ustaw: DN100 (4") · Class 150 · B7.'),
        findsOneWidget);
    await _drainSnackBars(tester);
  });

  testWidgets('„Moment śrub” z listy — funkcja dostaje to połączenie',
      (tester) async {
    BoltKitJoint? got;
    await _pump(tester,
        prefs: {
          BoltKitStore.key: _saved([_a, _b])
        },
        openTorque: (context, j) => got = j);
    await _tap(tester, 'bk-tab-kit');
    await _tap(tester, 'bk-j-torque-b');
    expect(got?.id, 'b');
    expect(got?.cls, 600);
  });

  testWidgets('EN: teksty i kropka dziesiętna', (tester) async {
    await _pump(tester, lang: AppLanguage.en);
    expect(find.text('Flange bolting'), findsOneWidget);
    expect(_text(tester, 'bk-asme-mm'), 'length 88.9 mm');
    expect(_text(tester, 'bk-asme-count'),
        '8 studs · 16 heavy hex nuts · thread 5/8"-11 UNC');
    await _tap(tester, 'bk-mode-dims');
    await _enter(tester, 'bk-f1', '24');
    await _enter(tester, 'bk-f2', '24');
    await _enter(tester, 'bk-gasket-t', '4.5');
    await _enter(tester, 'bk-nut', '18');
    await _enter(tester, 'bk-protrusion', '2.5');
    expect(_text(tester, 'bk-dims-required'),
        'Calculated: 93.5 mm → up to every 5 mm');
  });

  for (final lang in AppLanguage.values) {
    testWidgets('wąski ekran 320×640, tekst ×1,3 — bez wyjątków (${lang.name})',
        (tester) async {
      await _pump(tester,
          lang: lang,
          size: const Size(320, 640),
          textScale: 1.3,
          prefs: {
            BoltKitStore.key: _saved([_a, _b, _c], spare: 20)
          });
      expect(tester.takeException(), isNull);
      await _tap(tester, 'bk-facing-rtj');
      for (var i = 0; i < 12; i++) {
        await tester.drag(_key('bk-length-list'), const Offset(0, -300));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.drag(_key('bk-length-list'), const Offset(0, 6000));
      await tester.pumpAndSettle();
      await _tap(tester, 'bk-mode-dims');
      await _enterBelow(tester, 'bk-f1', '124,5');
      await _enterBelow(tester, 'bk-f2', '124,5');
      await _enterBelow(tester, 'bk-gasket-t', '4,5');
      await _enterBelow(tester, 'bk-nut', '51');
      await _enterBelow(tester, 'bk-protrusion', '6');
      await tester.scrollUntilVisible(_key('bk-dims-result'), 150,
          scrollable: find
              .descendant(
                  of: _key('bk-length-list'), matching: find.byType(Scrollable))
              .first);
      // 124,5 + 124,5 + 4,5 + 2 × 51 + 2 × 6 = 367,5 → 370 mm.
      expect(_text(tester, 'bk-dims-order'), '370 mm');
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 12; i++) {
        await tester.drag(_key('bk-length-list'), const Offset(0, -300));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await _tap(tester, 'bk-tab-kit');
      for (var i = 0; i < 12; i++) {
        await tester.drag(_key('bk-kit-list'), const Offset(0, -300));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(_key('bk-share-pdf'), findsOneWidget);
    });
  }

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester, prefs: {
      BoltKitStore.key: _saved([_a])
    });
    void big(String k) {
      final s = tester.getSize(_key(k));
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(s.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }

    void segment(String k) {
      final button = find.ancestor(
          of: _key(k),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
      expect(tester.getSize(button.first).height,
          greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }

    for (final k in [
      'bk-dn',
      'bk-class',
      'bk-material',
      'bk-gasket',
      'bk-count',
      'bk-add',
      'bk-torque'
    ]) {
      big(k);
    }
    for (final k in [
      'bk-mode-asme',
      'bk-mode-dims',
      'bk-facing-rf',
      'bk-facing-rtj'
    ]) {
      segment(k);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await _tap(tester, 'bk-mode-dims');
    for (final k in [
      'bk-f1',
      'bk-washers-0',
      'bk-washers-4',
      'bk-series-mm5',
      'bk-series-quarterInch'
    ]) {
      big(k);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await _tap(tester, 'bk-tab-kit');
    for (final k in [
      'bk-j-minus-a',
      'bk-j-plus-a',
      'bk-j-torque-a',
      'bk-j-del-a',
      'bk-spare-0',
      'bk-spare-20',
      'bk-share-text',
      'bk-share-pdf'
    ]) {
      big(k);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });
}
