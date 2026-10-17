// Ekran „Twardość: przelicznik i limity”: pomiar → przeliczenie i werdykt,
// seria z przekroczeniem, pomiar poza tablicą, zmiana presetu, własny limit,
// stal nierdzewna, EN, wąski ekran z dużą czcionką, cele dotyku,
// udostępnianie przez wstrzykniętą funkcję, PDF z polskimi znakami.
//
// Liczby (ISO 18265 tab. A.1): 22 HRC = 245 + 5 · 0,7/0,9 = 248,89 HV
// → „≈ 248,8 HV” (w dół, bo OK); 22,21 HRC = 250,06 HV → „≈ 250,1 HV”
// (w górę, bo przekroczony); 250 HV = 22,2 HRC = 238 HB = 99,5 HRB.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/welding/hardness.dart';
import 'package:cut_list_app/features/hardness/hardness_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/hardness_export.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/readout.dart';

class _ShareSpy {
  final List<(HardnessReport, HardnessShareFormat, bool)> calls = [];

  Future<void> call(HardnessReport r, HardnessShareFormat f, bool en) async =>
      calls.add((r, f, en));
}

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.pl,
  _ShareSpy? spy,
  Size size = const Size(900, 2400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = spy ?? _ShareSpy();
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HardnessPage(share: s.call),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _k(String key) => find.byKey(ValueKey(key));

/// Przewija do widżetu — także takiego, którego leniwa lista jeszcze nie
/// zbudowała (wąski ekran).
Future<void> _show(WidgetTester tester, String key) async {
  if (_k(key).evaluate().isEmpty) {
    final list = find.byType(Scrollable).first;
    try {
      await tester.scrollUntilVisible(_k(key), 300,
          scrollable: list, maxScrolls: 40);
    } catch (_) {
      // Nie ma niżej — szukamy wyżej.
      await tester.scrollUntilVisible(_k(key), -300,
          scrollable: list, maxScrolls: 80);
    }
  }
  await tester.ensureVisible(_k(key));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _show(tester, key);
  await tester.tap(_k(key));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await _show(tester, key);
  await tester.enterText(_k(key), text);
  await tester.pumpAndSettle();
}

/// Pomiar w wierszu [id]: wartość i skala.
Future<void> _reading(
    WidgetTester tester, int id, String value, HardnessScale scale) async {
  await _enter(tester, 'hard-row-$id-value', value);
  await _tap(tester, 'hard-row-$id-scale-${scale.name}');
}

String _detail(WidgetTester tester, int id) => tester
    .widget<Text>(_k('hard-row-$id-detail'))
    .textSpan!
    .toPlainText();

String _location(WidgetTester tester, int id) =>
    tester.widget<TextField>(_k('hard-row-$id-loc')).controller!.text;

Finder _verdict(SeriesVerdict v) => _k('hard-verdict-${v.name}');

Finder _status(int id, ReadingStatus s) => _k('hard-row-$id-status-${s.name}');

Future<void> _pickPreset(WidgetTester tester, String id) async {
  await _tap(tester, 'hard-limit-picker');
  await _tap(tester, 'hard-preset-$id');
}

pw.Font _font(String f) => pw.Font.ttf(
    ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('wpisanie pomiaru: przeliczenie HRC → HV i zielony werdykt',
      (tester) async {
    await _pump(tester);
    // Bez pomiaru — brak werdyktu, nie zielony.
    expect(_verdict(SeriesVerdict.empty), findsOneWidget);
    // Przelicznik startuje od 250 HV.
    expect(find.text('≈ 22,2 HRC'), findsOneWidget);
    expect(find.text('≈ 238,0 HB'), findsOneWidget);
    expect(find.text('≈ 99,5 HRB'), findsOneWidget);
    expect(find.text('≈ 800 MPa'), findsOneWidget);

    await _reading(tester, 0, '22', HardnessScale.hrc);
    expect(_status(0, ReadingStatus.ok), findsOneWidget);
    expect(_detail(tester, 0), contains('22 HRC ≈ 248,8 HV ≤ 250 HV'));
    expect(_verdict(SeriesVerdict.pass), findsOneWidget);
  });

  testWidgets('seria z jednym przekroczeniem → czerwony werdykt',
      (tester) async {
    await _pump(tester);
    await _reading(tester, 0, '240', HardnessScale.hv);
    await _tap(tester, 'hard-add-hazA');
    expect(_location(tester, 1), 'SWC strona A');
    await _reading(tester, 1, '260', HardnessScale.hv);
    await _tap(tester, 'hard-add-base');
    await _reading(tester, 2, '21', HardnessScale.hrc);

    expect(_status(0, ReadingStatus.ok), findsOneWidget);
    expect(_status(1, ReadingStatus.exceeded), findsOneWidget);
    expect(_status(2, ReadingStatus.ok), findsOneWidget);
    expect(_verdict(SeriesVerdict.fail), findsOneWidget);
    expect(_verdict(SeriesVerdict.pass), findsNothing);
    expect(find.textContaining('Przekroczenia: 1 z 3'), findsOneWidget);

    // Usunięcie przekroczonego pomiaru → zielony.
    await _tap(tester, 'hard-row-1-del');
    expect(_verdict(SeriesVerdict.pass), findsOneWidget);
  });

  testWidgets('pomiar poza tablicą → nie zielony', (tester) async {
    await _pump(tester);
    // 15 HRC — tablica HRC zaczyna się od 20,3.
    await _reading(tester, 0, '15', HardnessScale.hrc);
    expect(_status(0, ReadingStatus.outOfRange), findsOneWidget);
    expect(_verdict(SeriesVerdict.incomplete), findsOneWidget);
    expect(_verdict(SeriesVerdict.pass), findsNothing);
    // Wartość HV wpisana przy wybranej skali HRC — błąd wpisu, nie pomiar.
    await _enter(tester, 'hard-row-0-value', '260');
    expect(_status(0, ReadingStatus.invalid), findsOneWidget);
    expect(_detail(tester, 0), contains('260 HRC — poza skalą HRC (max 100)'));
    expect(_verdict(SeriesVerdict.incomplete), findsOneWidget);
    // Pusty dodatkowy pomiar przy dobrym pierwszym też nie daje zieleni.
    await _reading(tester, 0, '240', HardnessScale.hv);
    expect(_verdict(SeriesVerdict.pass), findsOneWidget);
    await _tap(tester, 'hard-add-root');
    expect(_status(1, ReadingStatus.blank), findsOneWidget);
    expect(_verdict(SeriesVerdict.incomplete), findsOneWidget);
  });

  testWidgets('liczba obok werdyktu zaokrąglona w stronę werdyktu',
      (tester) async {
    await _pump(tester);
    await _reading(tester, 0, '250,04', HardnessScale.hv);
    expect(_status(0, ReadingStatus.exceeded), findsOneWidget);
    expect(_detail(tester, 0), contains('250,04 HV > 250 HV'));
    // Max w górę: 250,04 → „250,1”, nie „250,0”.
    expect(tester.widget<Readout>(_k('hard-max')).value, '250,1 HV');
    await _reading(tester, 0, '22.21', HardnessScale.hrc);
    expect(_status(0, ReadingStatus.exceeded), findsOneWidget);
    expect(_detail(tester, 0), contains('≈ 250,1 HV > 250 HV'));
  });

  testWidgets('zmiana presetu limitu zmienia werdykt i jest zapamiętana',
      (tester) async {
    await _pump(tester);
    await _reading(tester, 0, '300', HardnessScale.hv);
    expect(_verdict(SeriesVerdict.fail), findsOneWidget);

    // EN ISO 15614-1:2004+A2:2012, gr. 1–2 bez obróbki: 380 HV10.
    await _pickPreset(tester, 'iso15614_2004_g12_aw');
    expect(find.text('max 380 HV'), findsWidgets);
    expect(_verdict(SeriesVerdict.pass), findsOneWidget);

    // ISO 15156-2 HRC: 300 HV = 29,8 HRC > 22.
    await _pickPreset(tester, 'iso15156_hrc');
    expect(_verdict(SeriesVerdict.fail), findsOneWidget);
    expect(_detail(tester, 0), contains('300 HV ≈ 29,8 HRC > 22 HRC'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(HardnessLimitStore.presetKey), 'iso15156_hrc');
  });

  testWidgets('zapamiętany limit wraca po otwarciu ekranu', (tester) async {
    SharedPreferences.setMockInitialValues(
        {HardnessLimitStore.presetKey: 'b313_p5'});
    await _pump(tester);
    expect(find.text('max 241 HB'), findsOneWidget);
  });

  testWidgets('własny limit przeżywa preset i restart; pusty tekst go nie kasuje',
      (tester) async {
    Future<void> restart() async {
      await tester.pumpWidget(const SizedBox());
      await _pump(tester);
    }

    await _pump(tester);
    await _pickPreset(tester, kHardnessCustomLimitId);
    await _enter(tester, 'hard-limit-value', '300');
    await _tap(tester, 'hard-limit-scale-hb');
    expect(find.text('max 300 HB'), findsOneWidget);
    // Przejście na preset i restart.
    await _pickPreset(tester, 'iso15156_weld');
    await restart();
    expect(find.text('max 250 HV'), findsOneWidget);
    // Własny limit nadal jest — z wartością i skalą.
    await _pickPreset(tester, kHardnessCustomLimitId);
    expect(find.text('max 300 HB'), findsOneWidget);
    expect(
        tester.widget<TextField>(_k('hard-limit-value')).controller!.text,
        '300');
    // Wyczyszczenie pola nie nadpisuje zapisu pustym tekstem.
    await _enter(tester, 'hard-limit-value', '');
    expect(_verdict(SeriesVerdict.invalidLimit), findsOneWidget);
    await restart();
    expect(find.text('max 300 HB'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(HardnessLimitStore.customKey), 'hb|300');
  });

  testWidgets('limit z pierwszej wersji zapisu (jeden klucz) też wraca',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {HardnessLimitStore.legacyKey: 'custom|hb|300'});
    await _pump(tester);
    expect(find.text('max 300 HB'), findsOneWidget);
  });

  testWidgets('EN ISO 15614-1 gr. 4–5 po OC: 330 HV — 2004 przekroczony, 2017 OK',
      (tester) async {
    await _pump(tester);
    await _reading(tester, 0, '330', HardnessScale.hv);
    await _pickPreset(tester, 'iso15614_2004_g45_ht');
    expect(find.text('max 320 HV'), findsWidgets);
    expect(find.textContaining('EN ISO 15614-1:2004+A2:2012'), findsWidgets);
    expect(_verdict(SeriesVerdict.fail), findsOneWidget);
    await _pickPreset(tester, 'iso15614_2017_g45_ht');
    expect(find.textContaining('EN ISO 15614-1:2017'), findsWidgets);
    expect(find.textContaining('Sprawdź w normie z kontraktu'), findsOneWidget);
    expect(_verdict(SeriesVerdict.pass), findsOneWidget);
  });

  testWidgets('nierdzewna + preset dla stali węglowych → BRAK OCENY z powodem',
      (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _reading(tester, 0, '240', HardnessScale.hv);
    expect(_verdict(SeriesVerdict.pass), findsOneWidget);
    await _tap(tester, 'hard-mat-stainless');
    // Domyślny preset NACE dla stali węglowych, ta sama skala HV.
    expect(_status(0, ReadingStatus.limitNotForMaterial), findsOneWidget);
    expect(_verdict(SeriesVerdict.incomplete), findsOneWidget);
    expect(_verdict(SeriesVerdict.pass), findsNothing);
    expect(_k('hard-limit-material-mismatch'), findsOneWidget);
    expect(
        find.textContaining(
            'Powód: Preset dotyczy stali węglowych/niskostopowych'),
        findsOneWidget);
    await _tap(tester, 'hard-share-text');
    final (report, _, _) = spy.calls.single;
    final text = buildHardnessText(report, en: false);
    expect(text, contains('BRAK OCENY'));
    expect(text, contains('Powód: Preset dotyczy stali węglowych/niskostopowych '
        '— wybierz własny limit ze specyfikacji.'));
    expect(text, isNot(contains('ZGODNE')));
    final pdf = await buildHardnessPdf(report,
            font: _font('Roboto-Regular.ttf'),
            boldFont: _font('Roboto-Bold.ttf'),
            en: false,
            generatedAt: DateTime(2026, 10, 17))
        .save();
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    // Własny limit w tej samej skali — ocena działa.
    await _pickPreset(tester, kHardnessCustomLimitId);
    await _enter(tester, 'hard-limit-value', '250');
    expect(_verdict(SeriesVerdict.pass), findsOneWidget);
    expect(_k('hard-limit-material-mismatch'), findsNothing);
  });

  testWidgets('własny limit: pusty albo 0 → brak werdyktu, nigdy zielony',
      (tester) async {
    await _pump(tester);
    await _reading(tester, 0, '240', HardnessScale.hv);
    await _pickPreset(tester, kHardnessCustomLimitId);
    expect(_verdict(SeriesVerdict.invalidLimit), findsOneWidget);
    await _enter(tester, 'hard-limit-value', '0');
    expect(_verdict(SeriesVerdict.invalidLimit), findsOneWidget);
    expect(_status(0, ReadingStatus.noLimit), findsOneWidget);
    await _enter(tester, 'hard-limit-value', '1,2,3');
    expect(_verdict(SeriesVerdict.invalidLimit), findsOneWidget);
    await _enter(tester, 'hard-limit-value', '230');
    expect(_verdict(SeriesVerdict.fail), findsOneWidget);
    // Limit w HB: 240 HV = 228 HB ≤ 230 HB.
    await _tap(tester, 'hard-limit-scale-hb');
    expect(_verdict(SeriesVerdict.pass), findsOneWidget);
    expect(_detail(tester, 0), contains('240 HV ≈ 228,0 HB ≤ 230 HB'));
  });

  testWidgets('stal nierdzewna: bez przeliczeń, inna skala bez oceny',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'hard-mat-stainless');
    expect(_k('hard-stainless-notice'), findsOneWidget);
    expect(_k('hard-conv-out-hrc'), findsNothing);
    // Limit ze specyfikacji (presety NACE/15614-1 są dla stali węglowych).
    await _pickPreset(tester, kHardnessCustomLimitId);
    await _enter(tester, 'hard-limit-value', '250');
    await _reading(tester, 0, '20', HardnessScale.hrc);
    expect(_status(0, ReadingStatus.notConvertible), findsOneWidget);
    expect(_verdict(SeriesVerdict.incomplete), findsOneWidget);
    // Ta sama skala co limit — ocena jest.
    await _reading(tester, 0, '240', HardnessScale.hv);
    expect(_verdict(SeriesVerdict.pass), findsOneWidget);
  });

  testWidgets('wersja EN', (tester) async {
    await _pump(tester, lang: AppLanguage.en);
    expect(find.text('Hardness: converter and limits'), findsOneWidget);
    expect(find.text('≈ 22.2 HRC'), findsOneWidget);
    await _reading(tester, 0, '22', HardnessScale.hrc);
    expect(_detail(tester, 0), contains('22 HRC ≈ 248.8 HV ≤ 250 HV'));
    expect(find.textContaining('PASS — all readings within the limit'),
        findsOneWidget);
    expect(_location(tester, 0), 'Cap');
  });

  testWidgets('wąski ekran 320×640, tekst ×1,3 — bez overflow', (tester) async {
    await _pump(tester, size: const Size(320, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);
    await _reading(tester, 0, '22', HardnessScale.hrc);
    await _tap(tester, 'hard-add-hazB');
    await _reading(tester, 1, '1000', HardnessScale.hv);
    await _tap(tester, 'hard-mat-stainless');
    await _tap(tester, 'hard-mat-carbonLowAlloy');
    await _pickPreset(tester, kHardnessCustomLimitId);
    await _enter(tester, 'hard-limit-value', '0');
    // Cała lista od góry do dołu, krokami — każdy element przechodzi layout.
    await tester.drag(find.byType(ListView).first, const Offset(0, 6000));
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -250));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hard-disclaimer')), findsOneWidget);
    // Lista presetów też się mieści.
    await _tap(tester, 'hard-limit-picker');
    expect(tester.takeException(), isNull);
    await _tap(tester, 'hard-preset-b313_p5');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawica)', (tester) async {
    await _pump(tester);
    final keys = [
      for (final m in HardnessMaterial.values) 'hard-mat-${m.name}',
      for (final s in HardnessScale.values) 'hard-conv-scale-${s.name}',
      for (final s in HardnessScale.values) 'hard-row-0-scale-${s.name}',
      'hard-limit-picker',
      'hard-row-0-del',
      'hard-row-0-value',
      'hard-row-0-loc',
      'hard-conv-value',
      'hard-add-cap',
      'hard-add-other',
      'hard-share-text',
      'hard-share-pdf',
    ];
    for (final k in keys) {
      await tester.ensureVisible(_k(k));
      final size = tester.getSize(_k(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await _tap(tester, 'hard-limit-picker');
    final tile = tester.getSize(_k('hard-preset-iso15156_weld'));
    expect(tile.height, greaterThanOrEqualTo(kMinTapTarget));
  });

  testWidgets('udostępnianie tekstu i PDF przez wstrzykniętą funkcję',
      (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    // Bez pomiarów udostępnianie wyłączone.
    await _tap(tester, 'hard-share-text');
    expect(spy.calls, isEmpty);

    await _reading(tester, 0, '22', HardnessScale.hrc);
    await _tap(tester, 'hard-add-hazA');
    await _reading(tester, 1, '260', HardnessScale.hv);
    await _tap(tester, 'hard-share-text');
    await _tap(tester, 'hard-share-pdf');
    expect(spy.calls.map((c) => c.$2),
        [HardnessShareFormat.text, HardnessShareFormat.pdf]);
    final (report, _, en) = spy.calls.first;
    expect(en, isFalse);
    expect(report.result.verdict, SeriesVerdict.fail);
    final text = buildHardnessText(report, en: false);
    expect(text, contains('NIEZGODNE'));
    expect(text, contains('NACE MR0175/ISO 15156-2:2020, tab. A.1'));
    expect(text, contains('1. Lico: 22 HRC ≈ 248,8 HV ≤ 250 HV — OK'));
    expect(text, contains('2. SWC strona A: 260 HV > 250 HV — Przekroczony'));
    expect(text, contains('Max: 260,0 HV'));
  });

  test('PDF z polskimi znakami (PL i EN) i nazwa pliku', () async {
    final report = HardnessReport(
      material: HardnessMaterial.carbonLowAlloy,
      preset: hardnessPresetById('iso15156_weld'),
      limit: const HardnessLimit(HardnessScale.hv, 250),
      readings: const [
        HardnessReading(
            location: 'Lico — strona północna, spoina W-12',
            value: 22,
            scale: HardnessScale.hrc),
        HardnessReading(
            location: 'SWC', value: 15, scale: HardnessScale.hrc),
        HardnessReading(
            location: 'Materiał rodzimy', value: null, scale: HardnessScale.hv,
            blank: true),
      ],
    );
    for (final en in [false, true]) {
      final doc = buildHardnessPdf(report,
          font: _font('Roboto-Regular.ttf'),
          boldFont: _font('Roboto-Bold.ttf'),
          en: en,
          generatedAt: DateTime(2026, 10, 17, 9, 30));
      final bytes = await doc.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
    expect(hardnessFileName(DateTime(2026, 10, 7), extension: 'pdf'),
        'Twardosc_2026-10-07.pdf');
  });
}
