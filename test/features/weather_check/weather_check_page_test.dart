// Ekran „Warunki do spawania”: wpisane wartości zmieniają werdykt, brak
// temperatury powierzchni → widoczne założenie, ujemne temperatury
// z przecinkiem, km/h i Beaufort, ustawienia progów i przywrócenie
// domyślnych, zapis do historii, udostępnianie (wstrzyknięte), wersja EN,
// wąski ekran 320×640 z tekstem ×1,3, cele dotyku ≥ 48 dp.
//
// Liczby (te same co w test/domain/welding/weather_conditions_test.dart):
//   15 °C / 50 % → punkt rosy 4,66 °C;  -5 °C / 80 % → szron -7,02 °C.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/welding/weather_conditions.dart';
import 'package:cut_list_app/features/weather_check/weather_check_page.dart';
import 'package:cut_list_app/features/weather_check/weather_check_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/readout.dart';

class _ShareSpy {
  final List<(String, String)> texts = [];
  final List<(WeatherCheckRecord, bool)> pdfs = [];

  Future<void> text(String t, String subject) async => texts.add((t, subject));
  Future<void> pdf(WeatherCheckRecord r, bool en) async => pdfs.add((r, en));
}

final DateTime _clock = DateTime(2026, 10, 17, 7, 5);

/// Magazyn, którego zapis progów zawsze się nie udaje (W5).
class _FailingThresholdsStore extends WeatherCheckStore {
  const _FailingThresholdsStore();

  @override
  Future<void> saveThresholds(WeatherThresholds t) async =>
      throw StateError('dysk pełny');
}

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  _ShareSpy? spy,
  Size size = const Size(1080, 2400),
  double textScale = 1.0,
  WeatherCheckStore store = const WeatherCheckStore(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = spy ?? _ShareSpy();
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: WeatherCheckPage(
          now: () => _clock, shareText: s.text, sharePdf: s.pdf, store: store),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

/// Przewija widoczną listę (progi albo ekran główny), aż element powstanie
/// — ListView buduje leniwie, na wąskim ekranie dalsze sekcje nie istnieją.
Future<void> _reveal(WidgetTester tester, String key) async {
  final f = _key(key);
  if (f.evaluate().isEmpty) {
    final listKey =
        _key('wx-th-list').evaluate().isNotEmpty ? 'wx-th-list' : 'wx-list';
    final scrollable = find
        .descendant(of: _key(listKey), matching: find.byType(Scrollable))
        .first;
    await tester.drag(scrollable, const Offset(0, 20000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(f, 250, scrollable: scrollable);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await _reveal(tester, key);
  await tester.enterText(_key(key), text);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, key);
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

/// Spokojny dzień: 15 °C, 50 %, 1 m/s, złącze sprawdzone i suche.
Future<void> _calm(WidgetTester tester) async {
  await _enter(tester, 'wx-ambient', '15');
  await _enter(tester, 'wx-rh', '50');
  await _enter(tester, 'wx-wind', '1');
  await _tap(tester, 'wx-surface-state-dry');
}

String _dew(WidgetTester tester) =>
    tester.widget<Readout>(_key('wx-dew')).value;

Finder _verdict(WeatherVerdict v) => _key('wx-verdict-${v.name}');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('wpisanie wartości zmienia werdykt', (tester) async {
    await _pump(tester);
    // Puste pola — prośba o dane zamiast werdyktu.
    expect(_key('wx-problems'), findsOneWidget);
    expect(find.textContaining('Podaj temperaturę powietrza'), findsOneWidget);

    await _calm(tester);
    expect(_key('wx-problems'), findsNothing);
    expect(_verdict(WeatherVerdict.go), findsOneWidget);
    // Ten sam werdykt na pasku na dole ekranu.
    expect(
        find.descendant(
            of: _key('wx-bar'), matching: find.text('Można spawać')),
        findsOneWidget);
    expect(_dew(tester), '4,7');

    // MAG przy 5 m/s bez osłony — nie spawać.
    await _tap(tester, 'wx-process-mag135');
    await _enter(tester, 'wx-wind', '5');
    expect(_verdict(WeatherVerdict.noGo), findsOneWidget);
    expect(_key('wx-stop-${WeatherCode.windGas}'), findsOneWidget);

    // Parawan — zakaz znika, zostaje warunek do odhaczenia.
    await _tap(tester, 'wx-shelter-windbreak');
    expect(_verdict(WeatherVerdict.conditional), findsOneWidget);
    expect(_key('wx-cond-${WeatherCode.windGas}'), findsOneWidget);

    // Deszcz — parawan nie chroni przed opadem.
    await _tap(tester, 'wx-precip-rain');
    expect(_verdict(WeatherVerdict.noGo), findsOneWidget);
    expect(_key('wx-stop-${WeatherCode.precipitation}'), findsOneWidget);

    // Namiot — dwa warunki; odhaczenie liczy się w podtytule.
    await _tap(tester, 'wx-shelter-enclosure');
    expect(_verdict(WeatherVerdict.conditional), findsOneWidget);
    expect(find.text('Odhaczone: 0 z 2'), findsOneWidget);
    await _tap(tester, 'wx-cond-${WeatherCode.precipitation}');
    expect(find.text('Odhaczone: 1 z 2'), findsOneWidget);
    await _tap(tester, 'wx-cond-${WeatherCode.windGas}');
    expect(find.textContaining('Wszystkie warunki odhaczone'), findsOneWidget);

    // Zmiana pomiaru czyści odhaczenia.
    await _enter(tester, 'wx-wind', '6');
    expect(find.text('Odhaczone: 0 z 2'), findsOneWidget);

    // MMA bez opadu przy 6 m/s — można spawać.
    await _tap(tester, 'wx-precip-none');
    await _tap(tester, 'wx-process-mma111');
    expect(_verdict(WeatherVerdict.go), findsOneWidget);
  });

  testWidgets('brak temperatury powierzchni → założenie widoczne',
      (tester) async {
    await _pump(tester);
    await _calm(tester);
    expect(_key('wx-surface-assumed'), findsOneWidget);
    expect(find.textContaining('Założenie: temperatura powierzchni'),
        findsOneWidget);
    expect(find.text('Powierzchnia (założona)'), findsOneWidget);
    expect(_key('wx-rec-${WeatherCode.recMeasureSurface}'), findsOneWidget);

    // Pomiar kontaktowy 6 °C: zapas 6 - 4,66 = 1,34 K < 3 K → warunek.
    await _enter(tester, 'wx-surface', '6');
    expect(_key('wx-surface-assumed'), findsNothing);
    expect(find.text('Powierzchnia (pomiar)'), findsOneWidget);
    expect(_verdict(WeatherVerdict.conditional), findsOneWidget);
    expect(_key('wx-cond-${WeatherCode.condensation}'), findsOneWidget);
    expect(find.descendant(of: _key('wx-margin'), matching: find.text('1,34 K')),
        findsOneWidget);
  });

  testWidgets('ujemne temperatury z przecinkiem: mróz → podgrzać do 21 °C',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'wx-ambient', '-5');
    await _enter(tester, 'wx-rh', '80');
    await _enter(tester, 'wx-wind', '0,5');
    expect(_verdict(WeatherVerdict.conditional), findsOneWidget);
    expect(_dew(tester), '-7,9');
    expect(
        find.descendant(of: _key('wx-frost'), matching: find.text('-7,0 °C')),
        findsOneWidget);
    expect(
        find.descendant(of: _key('wx-required'), matching: find.text('21 °C')),
        findsOneWidget);
    expect(_key('wx-cond-${WeatherCode.materialTemp}'), findsOneWidget);

    // Nierdzewna: minimum 10 °C.
    await _tap(tester, 'wx-material-stainless');
    expect(
        find.descendant(of: _key('wx-required'), matching: find.text('10 °C')),
        findsOneWidget);
  });

  testWidgets('km/h przelicza pole; Beaufort wpisuje górną granicę',
      (tester) async {
    await _pump(tester);
    await _calm(tester);
    await _enter(tester, 'wx-wind', '5');
    await _tap(tester, 'wx-unit-kmh');
    expect(find.widgetWithText(TextField, '18'), findsOneWidget);
    expect(find.textContaining('= 5 m/s'), findsOneWidget);
    await _tap(tester, 'wx-unit-ms');
    expect(find.widgetWithText(TextField, '5'), findsOneWidget);

    await _tap(tester, 'wx-beaufort');
    await _tap(tester, 'wx-bft-3');
    expect(find.widgetWithText(TextField, '5,4'), findsOneWidget);
    expect(find.textContaining('górna granica stopnia'), findsOneWidget);
    // 5,4 m/s = 3° B; TIG bez osłony — nie spawać.
    await _tap(tester, 'wx-process-tig141');
    expect(_verdict(WeatherVerdict.noGo), findsOneWidget);
  });

  testWidgets('ustawienia progów: zmiana, zapis i przywrócenie domyślnych',
      (tester) async {
    await _pump(tester);
    await _calm(tester);
    await _tap(tester, 'wx-process-mag135');
    await _enter(tester, 'wx-wind', '4');
    expect(_verdict(WeatherVerdict.noGo), findsOneWidget);

    await _tap(tester, 'wx-thresholds');
    expect(find.text('Ustawienia progów'), findsOneWidget);
    await _enter(tester, 'wx-th-maxWindGasMs', '5');
    expect(find.textContaining('≈ 18 km/h'), findsOneWidget);
    await _tap(tester, 'wx-th-save');

    expect(_verdict(WeatherVerdict.go), findsOneWidget);
    await _reveal(tester, 'wx-thresholds-custom');
    expect(_key('wx-thresholds-custom'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString(WeatherCheckStore.thresholdsKey)!)
        as Map<String, dynamic>;
    expect(saved['maxWindGasMs'], 5);

    // Błędna wartość blokuje zapis.
    await _tap(tester, 'wx-thresholds');
    // Sam przecinek przechodzi przez filtr pola, ale nie jest liczbą.
    await _enter(tester, 'wx-th-dewMarginK', ',');
    expect(find.text('Wpisz liczbę'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(_key('wx-th-save')).onPressed, isNull);

    await _tap(tester, 'wx-th-restore');
    expect(find.widgetWithText(TextField, '2,2'), findsOneWidget);
    await _tap(tester, 'wx-th-save');
    expect(_verdict(WeatherVerdict.noGo), findsOneWidget);
    await tester.drag(_key('wx-list'), const Offset(0, 20000));
    await tester.pumpAndSettle();
    expect(_key('wx-thresholds-custom'), findsNothing);
    expect(prefs.getString(WeatherCheckStore.thresholdsKey), isNull);
  });

  testWidgets('progi zapisane wcześniej wczytują się przy starcie',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      WeatherCheckStore.thresholdsKey:
          encodeWeatherThresholds(const WeatherThresholds(maxWindGasMs: 5)),
    });
    await _pump(tester);
    await _calm(tester);
    await _tap(tester, 'wx-process-mag135');
    await _enter(tester, 'wx-wind', '4');
    expect(_verdict(WeatherVerdict.go), findsOneWidget);
    await _reveal(tester, 'wx-thresholds-custom');
    expect(_key('wx-thresholds-custom'), findsOneWidget);
  });

  testWidgets('zapis do historii: wpis z miejscem, godziną i odhaczeniem',
      (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _enter(tester, 'wx-ambient', '-5');
    await _enter(tester, 'wx-rh', '80');
    await _enter(tester, 'wx-wind', '0');
    await _tap(tester, 'wx-cond-${WeatherCode.materialTemp}');
    await _enter(tester, 'wx-place', 'Estakada E-3, spoina 12');
    await _tap(tester, 'wx-save');
    expect(find.text('Zapisano w historii.'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final list =
        decodeWeatherHistory(prefs.getString(WeatherCheckStore.historyKey));
    expect(list, hasLength(1));
    final r = list.single;
    expect(r.place, 'Estakada E-3, spoina 12');
    expect(r.takenAt, _clock);
    expect(r.verdict, WeatherVerdict.conditional);
    expect(r.input.ambientC, -5);
    expect(r.checked, {WeatherCode.materialTemp});

    // Historia: wpis widoczny, podgląd, udostępnienie, usunięcie.
    await _tap(tester, 'wx-history');
    expect(find.text('Historia pomiarów'), findsOneWidget);
    expect(
        find.textContaining('2026-10-17 07:05 · Estakada E-3'), findsOneWidget);
    await _tap(tester, 'wx-record-${r.id}');
    await _tap(tester, 'wx-rec-share-text');
    expect(spy.texts.single.$1, contains('Estakada E-3, spoina 12'));
    expect(spy.texts.single.$1, contains('[x]'));
    await _tap(tester, 'wx-rec-delete');
    await _tap(tester, 'wx-rec-delete-confirm');
    expect(find.textContaining('Brak zapisanych pomiarów'), findsOneWidget);
    expect(decodeWeatherHistory(prefs.getString(WeatherCheckStore.historyKey)),
        isEmpty);
  });

  testWidgets('uszkodzona historia w pamięci nie wywraca ekranu',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      WeatherCheckStore.historyKey: '{to nie jest json',
      WeatherCheckStore.thresholdsKey: '[[[',
    });
    await _pump(tester);
    await _calm(tester);
    expect(tester.takeException(), isNull);
    expect(_verdict(WeatherVerdict.go), findsOneWidget);
    await _tap(tester, 'wx-save');
    final prefs = await SharedPreferences.getInstance();
    expect(decodeWeatherHistory(prefs.getString(WeatherCheckStore.historyKey)),
        hasLength(1));
  });

  testWidgets('udostępnianie tekstu i PDF przez wstrzyknięte funkcje',
      (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _calm(tester);
    await _tap(tester, 'wx-precip-snow');
    await _tap(tester, 'wx-share-text');
    expect(spy.texts, hasLength(1));
    final (text, subject) = spy.texts.single;
    expect(subject, 'Warunki do spawania');
    expect(text, contains('Werdykt: NIE SPAWAĆ'));
    expect(text, contains('2026-10-17 07:05'));
    expect(text, contains('Opad: śnieg'));
    expect(text, contains('Punkt rosy: 4,7 °C'));
    expect(text, contains('założenie'));
    expect(text, contains('Podstawa: AWS D1.1'));

    await _tap(tester, 'wx-share-pdf');
    expect(spy.pdfs, hasLength(1));
    final (record, en) = spy.pdfs.single;
    expect(en, isFalse);
    expect(record.verdict, WeatherVerdict.noGo);
    expect(record.input.precipitation, Precipitation.snow);
    expect(record.takenAt, _clock);
  });

  testWidgets('wersja EN', (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, language: AppLanguage.en, spy: spy);
    expect(find.text('Welding conditions'), findsOneWidget);
    expect(find.textContaining('Enter the air temperature'), findsOneWidget);
    await _enter(tester, 'wx-ambient', '15');
    await _enter(tester, 'wx-rh', '50');
    await _enter(tester, 'wx-wind', '1.0');
    await _tap(tester, 'wx-surface-state-dry');
    expect(_key('wx-bar-go'), findsOneWidget);
    expect(find.text('OK to weld'), findsNWidgets(2));
    expect(_dew(tester), '4.7');
    expect(
        find.textContaining('Assumption: surface temperature'), findsOneWidget);
    await _tap(tester, 'wx-process-mag135');
    await _enter(tester, 'wx-wind', '3');
    expect(_key('wx-bar-noGo'), findsOneWidget);
    expect(find.text('Do not weld'), findsNWidgets(2));
    await _tap(tester, 'wx-share-text');
    expect(spy.texts.single.$2, 'Welding conditions');
    expect(spy.texts.single.$1, contains('Verdict: DO NOT WELD'));
  });

  testWidgets('wąski ekran 320×640, tekst ×1,3 — bez przepełnień',
      (tester) async {
    await _pump(tester, size: const Size(320, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);
    await _enter(tester, 'wx-ambient', '-25,5');
    await _enter(tester, 'wx-rh', '95');
    await _enter(tester, 'wx-surface', '-28');
    await _enter(tester, 'wx-wind', '12');
    await _tap(tester, 'wx-precip-snow');
    await _tap(tester, 'wx-process-fcawG136');
    await _tap(tester, 'wx-shelter-enclosure');
    await _enter(tester, 'wx-wps', '75');
    await _tap(tester, 'wx-beaufort');
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 40; i++) {
      await tester.drag(_key('wx-list'), const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'krok $i');
    }
    await tester.pumpAndSettle();
    expect(_key('wx-disclaimer'), findsOneWidget);

    await _tap(tester, 'wx-thresholds');
    for (var i = 0; i < 10; i++) {
      await tester.drag(_key('wx-th-list'), const Offset(0, -400));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('pasek werdyktu na dole: bez danych prośba, „Szczegóły” przewija',
      (tester) async {
    await _pump(tester, size: const Size(360, 720));
    expect(
        find.descendant(
            of: _key('wx-bar'),
            matching: find.text('Uzupełnij pomiar, żeby zobaczyć werdykt')),
        findsOneWidget);
    expect(_key('wx-bar-details'), findsNothing);
    await _calm(tester);
    await _tap(tester, 'wx-precip-rain');
    expect(_key('wx-bar-noGo'), findsOneWidget);
    // Wróć na górę i przewiń „Szczegółami” do wyniku.
    await tester.drag(_key('wx-list'), const Offset(0, 20000));
    await tester.pumpAndSettle();
    // Odczyt punktu rosy poniżej ekranu (720 px) …
    expect(
        tester
            .getTopLeft(
                find.byKey(const ValueKey('wx-dew'), skipOffstage: false))
            .dy,
        greaterThan(720));
    await tester.tap(_key('wx-bar-details'));
    await tester.pumpAndSettle();
    // … a po „Szczegółach” w widocznej części listy.
    expect(tester.getTopLeft(_key('wx-dew')).dy, inInclusiveRange(56, 600));
  });

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester);
    await _calm(tester);
    await _tap(tester, 'wx-precip-rain');
    await _tap(tester, 'wx-shelter-enclosure');
    final keys = [
      'wx-thresholds',
      'wx-history',
      for (final u in WindUnit.values) 'wx-unit-${u.name}',
      for (final p in Precipitation.values) 'wx-precip-${p.name}',
      for (final p in WeatherProcess.values) 'wx-process-${p.name}',
      for (final s in WeatherShelter.values) 'wx-shelter-${s.name}',
      for (final m in WeatherMaterial.values) 'wx-material-${m.name}',
      'wx-cond-${WeatherCode.precipitation}',
      'wx-save',
      'wx-share-text',
      'wx-share-pdf',
      for (final s in SurfaceState.values) 'wx-surface-state-${s.name}',
      'wx-bar-details',
    ];
    for (final k in keys) {
      await _reveal(tester, k);
      final size = tester.getSize(_key(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await _tap(tester, 'wx-beaufort');
    for (final b in kBeaufortScale) {
      expect(tester.getSize(_key('wx-bft-${b.force}')).height,
          greaterThanOrEqualTo(kMinTapTarget),
          reason: 'B${b.force}');
    }
  });

  // ── Poprawki z przeglądu (W1–W7) ───────────────────────────────────────

  testWidgets('W1: 8 km/h MAG → STOP, przełączenie na m/s nie zmienia werdyktu',
      (tester) async {
    await _pump(tester);
    await _calm(tester);
    await _tap(tester, 'wx-process-mag135');
    await _tap(tester, 'wx-unit-kmh');
    await _enter(tester, 'wx-wind', '8');
    // 8 km/h = 2,222 m/s > 2,2 m/s.
    expect(_verdict(WeatherVerdict.noGo), findsOneWidget);
    await _tap(tester, 'wx-unit-ms');
    // Pole pokazuje 2,23 (w górę), werdykt liczony dalej z 2,222 m/s.
    expect(find.widgetWithText(TextField, '2,23'), findsOneWidget);
    expect(_verdict(WeatherVerdict.noGo), findsOneWidget);
    expect(_key('wx-stop-${WeatherCode.windGas}'), findsOneWidget);
    await _tap(tester, 'wx-unit-kmh');
    expect(find.widgetWithText(TextField, '8'), findsOneWidget);
    expect(_verdict(WeatherVerdict.noGo), findsOneWidget);
    // To samo dla wartości z Beauforta: 2° B = 3,3 m/s, w km/h 11,88.
    await _tap(tester, 'wx-beaufort');
    await _tap(tester, 'wx-bft-2');
    expect(find.widgetWithText(TextField, '11,88'), findsOneWidget);
    await _tap(tester, 'wx-unit-ms');
    expect(find.widgetWithText(TextField, '3,3'), findsOneWidget);
    expect(_verdict(WeatherVerdict.noGo), findsOneWidget);
  });

  testWidgets('W2: stan złącza — nie sprawdzono → warunek, mokre → STOP',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'wx-ambient', '15');
    await _enter(tester, 'wx-rh', '50');
    await _enter(tester, 'wx-wind', '1');
    // Domyślnie „nie sprawdzono” — nie ma czystego „Można spawać”.
    expect(_verdict(WeatherVerdict.conditional), findsOneWidget);
    expect(_key('wx-cond-${WeatherCode.surfaceState}'), findsOneWidget);
    await _tap(tester, 'wx-surface-state-wet');
    expect(_verdict(WeatherVerdict.noGo), findsOneWidget);
    expect(_key('wx-stop-${WeatherCode.surfaceState}'), findsOneWidget);
    await _tap(tester, 'wx-surface-state-frozen');
    await _tap(tester, 'wx-shelter-enclosure');
    expect(_verdict(WeatherVerdict.conditional), findsOneWidget);
    expect(find.textContaining('osusz / ogrzej je w namiocie'), findsOneWidget);
    await _tap(tester, 'wx-surface-state-dry');
    expect(_verdict(WeatherVerdict.go), findsOneWidget);
  });

  testWidgets('W3: ekran progów nie zaokrągla nieedytowanych wartości',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      WeatherCheckStore.thresholdsKey: encodeWeatherThresholds(
          const WeatherThresholds(maxWindGasMs: 2.26, dewMarginK: 2.345)),
    });
    await _pump(tester);
    await _tap(tester, 'wx-thresholds');
    expect(find.widgetWithText(TextField, '2,26'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2,345'), findsOneWidget);
    // Edycja jednego pola nie rusza pozostałych.
    await _enter(tester, 'wx-th-minMaterialC', '12');
    await _tap(tester, 'wx-th-save');
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString(WeatherCheckStore.thresholdsKey)!)
        as Map<String, dynamic>;
    expect(saved['maxWindGasMs'], 2.26);
    expect(saved['dewMarginK'], 2.345);
    expect(saved['minMaterialC'], 12);
  });

  testWidgets('W4: uszkodzona historia — komunikat, kopia przed nadpisaniem',
      (tester) async {
    final good = WeatherCheckRecord(
      id: 'ok',
      takenAt: DateTime(2026, 10, 1, 8),
      input: const WeatherInput(ambientC: 10, rhPct: 60, windMs: 1),
      verdict: WeatherVerdict.conditional,
    ).toJson();
    final raw = jsonEncode([
      1,
      {'id': 'zly'},
      good
    ]);
    SharedPreferences.setMockInitialValues({WeatherCheckStore.historyKey: raw});
    await _pump(tester);
    expect(_key('wx-history-damaged'), findsOneWidget);
    expect(
        find.textContaining('2 uszkodzonych wpisów pominięto'), findsOneWidget);
    await _tap(tester, 'wx-history');
    expect(_key('wx-history-skipped'), findsOneWidget);
    expect(find.textContaining('2 wpisów pominięto'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _calm(tester);
    await _tap(tester, 'wx-save');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(WeatherCheckStore.corruptHistoryKey), raw);
    expect(
        decodeWeatherHistory(prefs.getString(WeatherCheckStore.historyKey))
            .map((r) => r.id),
        hasLength(2));
    expect(_key('wx-history-damaged'), findsNothing);

    // Kolejne uszkodzenie nie nadpisuje pierwszej kopii.
    await prefs.setString(WeatherCheckStore.historyKey, '{znowu zły');
    await _tap(tester, 'wx-save');
    expect(prefs.getString(WeatherCheckStore.corruptHistoryKey), raw);
  });

  testWidgets('W4: ostrzeżenie przy zbliżaniu się do limitu historii',
      (tester) async {
    final many = [
      for (var i = 0; i < WeatherCheckStore.warnRecords; i++)
        WeatherCheckRecord(
          id: 'r$i',
          takenAt: DateTime(2026, 1, 1).add(Duration(hours: i)),
          input: const WeatherInput(ambientC: 10, rhPct: 60, windMs: 1),
          verdict: WeatherVerdict.conditional,
        ),
    ];
    SharedPreferences.setMockInitialValues(
        {WeatherCheckStore.historyKey: encodeWeatherHistory(many)});
    await _pump(tester);
    await _calm(tester);
    await _tap(tester, 'wx-save');
    expect(find.textContaining('Historia: 271 z 300'), findsOneWidget);
    await _tap(tester, 'wx-history');
    expect(_key('wx-history-limit'), findsOneWidget);
  });

  testWidgets('W5: uszkodzone progi → baner; błąd zapisu progów → snackbar',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      WeatherCheckStore.thresholdsKey:
          '{"maxWindGasMs": 1.5, "dewMarginK": "x"',
    });
    await _pump(tester, store: const _FailingThresholdsStore());
    expect(_key('wx-thresholds-repaired'), findsOneWidget);
    await _tap(tester, 'wx-thresholds');
    await _enter(tester, 'wx-th-maxWindGasMs', '1,5');
    await _tap(tester, 'wx-th-save');
    expect(find.textContaining('Nie udało się zapisać progów'), findsOneWidget);
    // Zapis się nie udał — baner zostaje.
    expect(_key('wx-thresholds-repaired'), findsOneWidget);
  });

  testWidgets('W6: walidacja krzyżowa progów i ostrzeżenie o łagodnych progach',
      (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _calm(tester);
    await _tap(tester, 'wx-thresholds');
    await _enter(tester, 'wx-th-maxWindAnyMs', '2');
    expect(
        find.text('Nie mniej niż limit dla procesów gazowych'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(_key('wx-th-save')).onPressed, isNull);
    await _enter(tester, 'wx-th-maxWindAnyMs', '10,8');
    await _enter(tester, 'wx-th-coldPreheatC', '-1');
    expect(find.text('Nie niżej niż próg „zimnej” stali'), findsOneWidget);
    await _enter(tester, 'wx-th-coldPreheatC', '21');
    // Łagodniej niż norma: minimum materiału 5 °C.
    await _enter(tester, 'wx-th-minMaterialC', '5');
    expect(find.textContaining('ŁAGODNIEJ niż norma!'), findsOneWidget);
    await _tap(tester, 'wx-th-save');
    expect(_verdict(WeatherVerdict.go), findsOneWidget);
    expect(_key('wx-looser-warning'), findsOneWidget);
    expect(_key('wx-bar-looser'), findsOneWidget);
    await _tap(tester, 'wx-share-text');
    expect(spy.texts.single.$1,
        contains('!!! UWAGA: progi łagodniejsze niż wartości z norm'));
  });

  testWidgets('W7: wpis zapisany starszą wersją reguł oznaczony w historii',
      (tester) async {
    final old = WeatherCheckRecord(
      id: 'old',
      takenAt: DateTime(2026, 10, 1, 8),
      input: const WeatherInput(ambientC: 15, rhPct: 50, windMs: 1),
      verdict: WeatherVerdict.go,
    ).toJson()
      ..remove('rulesVersion');
    SharedPreferences.setMockInitialValues({
      WeatherCheckStore.historyKey: jsonEncode([old])
    });
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _tap(tester, 'wx-history');
    expect(_key('wx-record-mismatch-old'), findsOneWidget);
    await _tap(tester, 'wx-record-old');
    await _tap(tester, 'wx-rec-share-text');
    expect(spy.texts.single.$1,
        contains('Szczegóły odtworzone inną wersją reguł'));
    expect(spy.texts.single.$1, contains('Werdykt: MOŻNA SPAWAĆ'));
  });

  testWidgets('drobne: komunikat wilgotności zgodny z walidacją (0; 100]',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'wx-rh', '0');
    expect(find.textContaining('Wilgotność: większa od 0 i najwyżej 100 %.'),
        findsOneWidget);
  });
}
