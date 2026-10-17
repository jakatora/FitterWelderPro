// Słownik spawalniczy na ekranie: szukanie w pięciu językach (bez
// diakrytyków), po numerze ISO, filtr kategorii, język docelowy i ulubione
// zapamiętane, kopiowanie, tryb „pokaż rozmówcy”, wersja EN, wąski ekran.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/data/welding_glossary.dart';
import 'package:cut_list_app/domain/glossary/glossary.dart';
import 'package:cut_list_app/features/glossary/glossary_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

GlossaryTerm _t(String id) => kWeldingGlossary.firstWhere((t) => t.id == id);

Finder _key(String k) => find.byKey(ValueKey(k));
Finder _card(String id) => _key('glossary-term-$id');

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.pl,
  Size size = const Size(1080, 2400),
  double dpr = 1,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
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
      home: const GlossaryPage(),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(_key('glossary-search'), query);
  await tester.pumpAndSettle();
}

/// Identyfikatory kart w kolejności na ekranie (zbudowane przez builder).
List<String> _ids(WidgetTester tester) {
  final cards = tester.widgetList(find.byWidgetPredicate((w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('glossary-term-')));
  return [
    for (final c in cards)
      (c.key! as ValueKey<String>).value.substring('glossary-term-'.length)
  ];
}

/// Dotknięcie nagłówka karty przy jego górnej krawędzi — w czcionce testowej
/// (każdy znak = kwadrat) długi zwrot daje kartę wyższą niż ekran.
Future<void> _tapToggle(WidgetTester tester, String id) async {
  final toggle = _key('glossary-toggle-$id');
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getTopLeft(toggle) + const Offset(24, 12));
  await tester.pumpAndSettle();
}

String _targetText(WidgetTester tester, String id) =>
    tester.widget<Text>(_key('glossary-target-text-$id')).data!;

bool _chipSelected(WidgetTester tester, String key) =>
    tester.widget<ChoiceChip>(_key(key)).selected;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('szukanie po PL: „podtopienie” daje 5011 z tłumaczeniem DE',
      (tester) async {
    await _pump(tester);
    expect(_chipSelected(tester, 'glossary-target-de'), isTrue);
    await _search(tester, 'podtopienie ciagle');
    expect(_ids(tester).first, 'i5011');
    expect(_targetText(tester, 'i5011'), _t('i5011').de);
    expect(find.text(_t('i5011').pl), findsOneWidget);
    expect(find.text('ISO 6520-1: 5011'), findsOneWidget);
  });

  testWidgets('DE z umlautem wpisany bez umlautu (u i ue) oraz ß jako ss',
      (tester) async {
    await _pump(tester);
    await _search(tester, 'uberkopfposition');
    expect(_ids(tester), contains('pos_pe'));
    await _search(tester, 'ueberkopfposition');
    expect(_ids(tester), contains('pos_pe'));
    await _search(tester, 'SCHWEISSBRENNER');
    expect(_ids(tester).first, 'n_torch');
  });

  testWidgets('NO z ø: wpisane z ø, bez ø i jako oe', (tester) async {
    await _pump(tester);
    for (final q in ['Rørledning', 'rorledning', 'roerledning']) {
      await _search(tester, q);
      expect(_ids(tester).first, 'r_pipeline', reason: q);
    }
  });

  testWidgets('po numerze ISO: 5011, 135, 141', (tester) async {
    await _pump(tester);
    await _search(tester, '5011');
    expect(_ids(tester).first, 'i5011');
    await _search(tester, '135');
    expect(_ids(tester).first, 'p135');
    await _search(tester, '141');
    expect(_ids(tester).first, 'p141');
  });

  testWidgets('filtr kategorii zawęża listę i licznik', (tester) async {
    await _pump(tester);
    final imperfections = kWeldingGlossary
        .where((t) => t.category == GlossaryCategory.imperfection)
        .length;
    await tester.tap(_key('glossary-cat-imperfection'));
    await tester.pumpAndSettle();
    expect(find.text('Pozycji: $imperfections'), findsOneWidget);
    for (final id in _ids(tester)) {
      expect(_t(id).category, GlossaryCategory.imperfection, reason: id);
    }
    // Proces 135 nie jest niezgodnością — w tej kategorii go nie ma.
    await _search(tester, '135');
    expect(_key('glossary-empty'), findsOneWidget);
    // „Wszystko” wraca do pełnej listy.
    await tester.ensureVisible(_key('glossary-cat-all'));
    await tester.tap(_key('glossary-cat-all'));
    await tester.pumpAndSettle();
    expect(_ids(tester).first, 'p135');
  });

  testWidgets('zmiana języka docelowego jest zapamiętana', (tester) async {
    await _pump(tester);
    await _search(tester, '5011');
    await tester.tap(_key('glossary-target-no'));
    await tester.pumpAndSettle();
    expect(_targetText(tester, 'i5011'), _t('i5011').no);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(GlossaryPage.targetPrefsKey), 'no');

    // Nowe otwarcie ekranu — dalej NO.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    expect(_chipSelected(tester, 'glossary-target-no'), isTrue);
    expect(_chipSelected(tester, 'glossary-target-de'), isFalse);
    await _search(tester, '5011');
    expect(_targetText(tester, 'i5011'), _t('i5011').no);

    await tester.tap(_key('glossary-target-nl'));
    await tester.pumpAndSettle();
    expect(_targetText(tester, 'i5011'), _t('i5011').nl);
    expect(prefs.getString(GlossaryPage.targetPrefsKey), 'nl');
  });

  testWidgets('ulubione: gwiazdka, zapis i filtr', (tester) async {
    await _pump(tester);
    await _search(tester, '5011');
    await tester.tap(_key('glossary-fav-i5011'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(GlossaryPage.favoritesPrefsKey), ['i5011']);

    await _search(tester, '');
    await tester.tap(_key('glossary-fav-filter'));
    await tester.pumpAndSettle();
    expect(_ids(tester), ['i5011']);
    expect(find.textContaining('Pozycji: 1'), findsOneWidget);

    // Zdjęcie gwiazdki przy włączonym filtrze — pusta lista z podpowiedzią.
    await tester.tap(_key('glossary-fav-i5011'));
    await tester.pumpAndSettle();
    expect(_key('glossary-empty'), findsOneWidget);
    expect(find.textContaining('Dotknij gwiazdki'), findsOneWidget);
    expect(prefs.getStringList(GlossaryPage.favoritesPrefsKey), isEmpty);
  });

  testWidgets('ulubione wczytane z pamięci przy starcie', (tester) async {
    SharedPreferences.setMockInitialValues({
      GlossaryPage.favoritesPrefsKey: ['p135', 'i5011'],
      GlossaryPage.targetPrefsKey: 'en',
    });
    await _pump(tester);
    await tester.tap(_key('glossary-fav-filter'));
    await tester.pumpAndSettle();
    expect(_ids(tester).toSet(), {'p135', 'i5011'});
    expect(_targetText(tester, 'p135'), _t('p135').en);
  });

  testWidgets('kopiowanie tłumaczenia do schowka', (tester) async {
    final copied = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _pump(tester);
    await _search(tester, '5011');
    await tester.tap(_key('glossary-copy-i5011-target'));
    await tester.pump();
    expect(copied, [_t('i5011').de]);
    expect(find.text('Skopiowano: ${_t('i5011').de}'), findsOneWidget);

    // Rozwinięcie: każdy z pięciu języków ma własny przycisk kopiowania.
    await tester.tap(_key('glossary-toggle-i5011'));
    await tester.pumpAndSettle();
    for (final lang in GlossaryLang.values) {
      expect(_key('glossary-copy-i5011-${lang.name}'), findsOneWidget);
    }
    await tester.tap(_key('glossary-copy-i5011-nl'));
    await tester.pump();
    expect(copied.last, _t('i5011').nl);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('rozwinięcie pokazuje 5 języków, definicję i numer ISO',
      (tester) async {
    await _pump(tester);
    await _search(tester, '5011');
    expect(_key('glossary-details-i5011'), findsNothing);
    await tester.tap(_key('glossary-toggle-i5011'));
    await tester.pumpAndSettle();
    final details = _key('glossary-details-i5011');
    expect(details, findsOneWidget);
    final t = _t('i5011');
    for (final lang in GlossaryLang.values) {
      expect(
          find.descendant(of: details, matching: find.text(t.text(lang))),
          findsOneWidget,
          reason: lang.code);
    }
    expect(t.defPl, isNotNull);
    expect(find.text(t.defPl!), findsOneWidget);
    // Drugie dotknięcie zwija.
    await tester.tap(_key('glossary-toggle-i5011'));
    await tester.pumpAndSettle();
    expect(details, findsNothing);
  });

  testWidgets('tryb „pokaż rozmówcy”: duży napis, obrót, zmiana języka',
      (tester) async {
    await _pump(tester);
    await _search(tester, 'zezwolenie na prace pozarowe');
    final id = _ids(tester).first;
    expect(id, 's_hot_work_permit');
    await tester.tap(_key('glossary-toggle-$id'));
    await tester.pumpAndSettle();
    await tester.tap(_key('glossary-show-$id'));
    await tester.pumpAndSettle();

    expect(find.byType(GlossaryShowView), findsOneWidget);
    final big = tester.widget<Text>(_key('glossary-show-text'));
    expect(big.data, _t(id).de);
    expect(big.style!.fontSize, greaterThanOrEqualTo(30));

    RotatedBox box() => tester.widget<RotatedBox>(_key('glossary-show-rotation'));
    expect(box().quarterTurns, 0);
    await tester.tap(_key('glossary-show-rotate'));
    await tester.pump();
    expect(box().quarterTurns, 2);
    await tester.tap(_key('glossary-show-rotate'));
    await tester.pump();
    expect(box().quarterTurns, 0);

    await tester.tap(_key('glossary-show-lang-no'));
    await tester.pump();
    expect(tester.widget<Text>(_key('glossary-show-text')).data, _t(id).no);

    await tester.tap(_key('glossary-show-close'));
    await tester.pumpAndSettle();
    expect(find.byType(GlossaryShowView), findsNothing);
    expect(_card(id), findsOneWidget);
  });

  testWidgets('zwroty na budowę: kategoria i tryb pokazu', (tester) async {
    await _pump(tester);
    await tester.ensureVisible(_key('glossary-cat-phrase'));
    await tester.tap(_key('glossary-cat-phrase'));
    await tester.pumpAndSettle();
    await _search(tester, 'gasnica');
    final id = _ids(tester).first;
    expect(_t(id).category, GlossaryCategory.phrase);
    expect(_targetText(tester, id), _t(id).de);
  });

  testWidgets('wersja EN: tytuł, chipy i wiersz źródłowy po angielsku',
      (tester) async {
    await _pump(tester, lang: AppLanguage.en);
    expect(find.text('Welding dictionary'), findsOneWidget);
    expect(find.text('Imperfections'), findsOneWidget);
    await _search(tester, 'undercut');
    expect(_ids(tester), contains('i5011'));
    expect(find.text(_t('i5011').en), findsOneWidget);
    expect(_targetText(tester, 'i5011'), _t('i5011').de);
    // Angielski jako docelowy — wiersz źródłowy wraca do polskiego.
    await tester.tap(_key('glossary-target-en'));
    await tester.pumpAndSettle();
    expect(find.text(_t('i5011').pl), findsOneWidget);
    await _search(tester, 'zzzz');
    expect(find.textContaining('Nothing found'), findsOneWidget);
  });

  testWidgets('wąski ekran 320×640, tekst ×1,3 — bez wyjątków i przepełnień',
      (tester) async {
    await _pump(tester,
        size: const Size(960, 1920), dpr: 3, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.drag(_key('glossary-list'), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _search(tester, 'potrzebuje');
    final id = _ids(tester).first;
    await _tapToggle(tester, id);
    expect(tester.takeException(), isNull);
    expect(_key('glossary-details-$id'), findsOneWidget);
    await tester.ensureVisible(_key('glossary-show-$id'));
    await tester.pumpAndSettle();
    await tester.tap(_key('glossary-show-$id'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(_key('glossary-show-rotate'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(_key('glossary-show-close'));
    await tester.pumpAndSettle();

    // Najdłuższy tekst w danych — też się mieści.
    final longest = kWeldingGlossary.reduce((a, b) =>
        a.text(GlossaryLang.de).length >= b.text(GlossaryLang.de).length
            ? a
            : b);
    await _search(tester, longest.text(GlossaryLang.de));
    expect(_ids(tester), contains(longest.id));
    if (_key('glossary-details-${longest.id}').evaluate().isEmpty) {
      await _tapToggle(tester, longest.id);
    }
    expect(_key('glossary-details-${longest.id}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawice)', (tester) async {
    await _pump(tester, size: const Size(960, 1920), dpr: 3);
    await _search(tester, '5011');
    final targets = [
      'glossary-fav-filter',
      'glossary-search-clear',
      'glossary-target-de',
      'glossary-target-no',
      'glossary-cat-all',
      'glossary-copy-i5011-target',
      'glossary-fav-i5011',
      'glossary-toggle-i5011',
    ];
    for (final k in targets) {
      final size = tester.getSize(_key(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await tester.tap(_key('glossary-toggle-i5011'));
    await tester.pumpAndSettle();
    for (final k in [
      'glossary-copy-i5011-pl',
      'glossary-copy-i5011-no',
      'glossary-show-i5011',
    ]) {
      expect(tester.getSize(_key(k)).height,
          greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
    await tester.ensureVisible(_key('glossary-show-i5011'));
    await tester.pumpAndSettle();
    await tester.tap(_key('glossary-show-i5011'));
    await tester.pumpAndSettle();
    for (final k in [
      'glossary-show-close',
      'glossary-show-rotate',
      'glossary-show-lang-nl',
    ]) {
      final size = tester.getSize(_key(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
  });
}
