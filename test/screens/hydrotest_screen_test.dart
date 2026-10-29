// Ekran próby ciśnieniowej — presety norm, korekta ST/S, puste pola pomiarowe.
//
// Liczby (ręcznie; wzory i źródła w test/domain/pressure_test/):
//   B31.3 §345.4.2: Pt = 1,5 · 10 · 1,2 = 18,00 bar (stary ekran: 1,5 · 10 = 15,00)
//   B31.1 §137.4.5: Pt = 1,5 · 10 = 15,00 bar
//   EN 13480-5 / PED: Pt = max(1,25 · 10 · 1,0; 1,43 · 10) = 14,30 bar
//   ASME VIII-1 UG-99(b): Pt = 1,3 · 10 · 1,0 = 13,00 bar
//   B31.3 §345.5.4 pneumatyczna: Pt = 1,1 · 10 = 11,00 bar
//   §345.2.1(a): OD 60,3 × 3,91, Pt = 1,5 · 100 = 150 bar = 15 MPa →
//     σ = 15 · 60,3 / (2 · 3,91) = 115,7 MPa > Re 100 MPa;
//     P(σ = Re) = 2 · 3,91 · 100 / 60,3 = 12,97 MPa = 129,7 bar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_database.dart';

import 'package:cut_list_app/database/hydrotest_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/hydrotest_screen.dart';
import 'package:cut_list_app/services/hydrotest_export.dart';

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(home: child),
    );

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(const HydrotestScreen()));
  for (var i = 0; i < 3; i++) {
    await flushTestDatabase(tester);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
      description: 'TextField labelled $label',
    );

TextField _textField(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label));

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), text);
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabase();

  testWidgets('B31.3: P = 10 bar, ST/S = 1,2 → 18,00 bar (dotąd 15,00)',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'Design pressure (bar)', '10');
    expect(find.text('15.00 bar'), findsOneWidget); // ST/S puste = 1,0

    await _enter(tester, 'ST/S (temperature correction)', '1.2');
    expect(find.text('18.00 bar'), findsOneWidget);
    expect(find.text('15.00 bar'), findsNothing);
    expect(find.textContaining('Pt = 1.5 · 10.00 · 1.20 = 18.00 bar'),
        findsOneWidget);
  });

  testWidgets('ST/S > 6,5 jest obcinane z ostrzeżeniem', (tester) async {
    await _pump(tester);
    await _enter(tester, 'Design pressure (bar)', '10');
    await _enter(tester, 'ST/S (temperature correction)', '8');
    // 1,5 · 10 · 6,5 = 97,5
    expect(find.text('97.50 bar'), findsOneWidget);
    expect(find.textContaining('6.5 used'), findsOneWidget);
  });

  testWidgets('presety mają właściwe normy, a nie stare podpisy',
      (tester) async {
    await _pump(tester);
    expect(find.text('B31.1 steam'), findsNothing);
    expect(find.text('PED gas'), findsNothing);
    await _enter(tester, 'Design pressure (bar)', '10');

    await _tapText(tester, 'ASME B31.1 — hydrostatic');
    expect(find.text('15.00 bar'), findsOneWidget);
    // B31.1 nie stosuje ST/S — pole znika.
    expect(_field('ST/S (temperature correction)'), findsNothing);

    await _tapText(tester, 'EN 13480-5 / PED — hydrostatic');
    expect(find.text('14.30 bar'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);

    await _tapText(tester, 'ASME VIII-1 — vessel, hydrostatic');
    expect(find.text('13.00 bar'), findsOneWidget);
  });

  testWidgets('próba pneumatyczna: 1,1·P i ostrzeżenie o energii gazu',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'Design pressure (bar)', '10');
    expect(find.textContaining('PNEUMATIC TEST'), findsNothing);

    await _tapText(tester, 'ASME B31.3 — pneumatic');
    expect(find.text('11.00 bar'), findsOneWidget);
    expect(find.textContaining('PNEUMATIC TEST'), findsOneWidget);
    expect(find.textContaining('13.30 bar'), findsOneWidget); // 1,33·P
  });

  testWidgets('minimalny czas: B31.3 §345.2.2(a), nie §345.4.2',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'Design pressure (bar)', '10');
    expect(find.text('per ASME B31.3 §345.2.2(a)'), findsOneWidget);
    expect(find.textContaining('§ 345.4.2'), findsNothing);
  });

  testWidgets('§345.2.1(a): ostrzeżenie, gdy σ przy Pt > Re', (tester) async {
    await _pump(tester);
    await _enter(tester, 'OD (mm)', '60,3');
    await _enter(tester, 'Wall t (mm)', '3,91');
    await _enter(tester, 'Design pressure (bar)', '100');
    await _enter(tester, 'Yield at test temp. (MPa) — optional', '100');
    expect(
        find.textContaining('Hoop stress at Pt = 116 MPa > yield 100 MPa'),
        findsOneWidget);
    expect(find.textContaining('reduced to 129.6'), findsOneWidget);

    await _enter(tester, 'Yield at test temp. (MPa) — optional', '240');
    expect(find.textContaining('(48 % of yield)'), findsOneWidget);
  });

  testWidgets('telefon 360 dp: presety, pneumatyczna i arkusz bez overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const HydrotestScreen()));
    for (var i = 0; i < 3; i++) {
      await flushTestDatabase(tester);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await _enter(tester, 'Design pressure (bar)', '10');
    await _tapText(tester, 'ASME B31.3 — pneumatic');
    await _tapText(tester, 'EN 13480-5 / PED — hydrostatic');
    await _enter(tester, 'f_test/f (temperature correction)', '1.2');
    expect(find.text('15.00 bar'), findsOneWidget); // 1,25 · 10 · 1,2
    await _tapText(tester, 'Save test');
    expect(find.text('File the test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'arkusz zapisu: pola pomiarowe puste, obliczenia tylko jako podpowiedź; '
      'rekord nie udaje pomiarów', (tester) async {
    await _pump(tester);
    await _enter(tester, 'Design pressure (bar)', '10');
    await _enter(tester, 'ST/S (temperature correction)', '1.2');
    await _tapText(tester, 'Save test');

    final start = _textField(tester, 'Start pressure (bar)');
    expect(start.controller!.text, isEmpty);
    expect(start.decoration!.hintText, 'calc. 18.00');
    final hold = _textField(tester, 'Hold time (min)');
    expect(hold.controller!.text, isEmpty);
    expect(hold.decoration!.hintText, 'min. 10');
    expect(find.textContaining('ASME B31.3 §345.4.2  ·  ST/S = 1.20'),
        findsOneWidget);

    await _enter(tester, 'System / line *', 'WFI-101');
    await _enter(tester, 'Company', 'Montaż Rur');
    await _enter(tester, 'Test fluid', 'Woda');
    await _enter(tester, 'Relief valve set pressure (bar)', '19,5');
    await _enter(tester, 'Notes', 'Korki 2×.');
    await _tapText(tester, 'PASS');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await flushTestDatabase(tester);
      await tester.pump();
    }

    final rows = await tester.runAsync(() => HydrotestDao().listAll());
    final r = rows!.firstWhere((x) => x.systemName == 'WFI-101');
    expect(r.testPressureBar, closeTo(18.0, 1e-9));
    expect(r.factor, closeTo(1.8, 1e-9)); // Pt / P, nie gołe 1,5
    // Niewpisane pomiary zostają puste — PDF wydrukuje „—”, nie wartość
    // obliczoną.
    expect(r.pressureStartBar, isNull);
    expect(r.holdMinutes, isNull);
    expect(hydrotestMissingNote(r), contains('ciśnienie początkowe'));
    expect(r.notes, 'Korki 2×.'); // uwagi bez żadnych doklejek
    final meta = hydrotestMeta(r)!;
    expect(meta.presetId, 'b31_3_hydro');
    expect(meta.stressRatio, 1.2);
    expect(meta.company, 'Montaż Rur');
    expect(meta.testMedium, 'Woda');
    expect(meta.reliefSetBar, 19.5);
    await tester.pumpAndSettle();
  });

  // B31.3 hydro, P = 10 → Pt = 15,00 bar. Najwyższy punkt 10 m nad
  // manometrem: 15 + 10 · 0,0980665 = 15,98 bar; najniższy 5 m pod
  // manometrem: 15,98 + 0,49 = 16,47 bar.
  testWidgets('słup wody: odczyt manometru i najniższy punkt; arkusz porównuje '
      'ciśnienie początkowe z odczytem', (tester) async {
    await _pump(tester);
    await _enter(tester, 'Design pressure (bar)', '10');
    await _enter(tester, 'Highest point above gauge (m)', '10');
    await _enter(tester, 'Lowest point below gauge (m)', '5');
    expect(find.text('15.98 bar'), findsOneWidget);
    expect(find.textContaining('lowest point: 16.47 bar'), findsOneWidget);

    await _tapText(tester, 'Save test');
    expect(_textField(tester, 'Start pressure (bar)').decoration!.hintText,
        'calc. 15.98');
    // 15,5 bar ≥ Pt, ale < odczytu wymaganego przy tym manometrze.
    await _enter(tester, 'Start pressure (bar)', '15,5');
    expect(find.textContaining('Start pressure below the required 15.98 bar'),
        findsOneWidget);
    await _enter(tester, 'Start pressure (bar)', '16');
    expect(find.textContaining('Start pressure below the required'),
        findsNothing);
  });

  testWidgets('arkusz: PASS przy ciśnieniu < Pt → ostrzeżenie i oznaczenie '
      'na protokole', (tester) async {
    await _pump(tester);
    await _enter(tester, 'Design pressure (bar)', '10'); // Pt 15,00
    await _tapText(tester, 'Save test');
    await _enter(tester, 'System / line *', 'LOW-1');
    await _enter(tester, 'Start pressure (bar)', '12');
    expect(find.textContaining('marked NOT CODE-COMPLIANT'), findsOneWidget);
    await _tapText(tester, 'PASS');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await flushTestDatabase(tester);
      await tester.pump();
    }
    final rows = await tester.runAsync(() => HydrotestDao().listAll());
    final r = rows!.firstWhere((x) => x.systemName == 'LOW-1');
    expect(hydrotestPassNotCompliant(r), isTrue);
    expect(hydrotestStartPressureNote(r), contains('NIE SPEŁNIA'));
    await tester.pumpAndSettle();
  });

  // Pneumatyczna P = 10 → Pt 11,00, maks. 1,33 · P = 13,30 bar.
  // OD 60,3 × 3,91, Re 5 MPa: P(90 % Re) = 2 · 3,91 · 4,5 / 60,3 · 10
  // = 5,84 bar < 13,30 → maks. Pt = 5,84 bar, Pt 11 bar za wysokie.
  testWidgets('pneumatyczna: Re → 90 % Re; arkusz: start > 1,33·P',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'OD (mm)', '60,3');
    await _enter(tester, 'Wall t (mm)', '3,91');
    await _enter(tester, 'Design pressure (bar)', '10');
    await _tapText(tester, 'ASME B31.3 — pneumatic');
    expect(_field('Highest point above gauge (m)'), findsNothing,
        reason: 'słup gazu pomijalny');
    await _enter(tester, 'Yield at test temp. (MPa) — optional', '5');
    expect(find.textContaining('at 90 % of yield = 5.84 bar'), findsOneWidget);
    expect(find.textContaining('exceeds the maximum'), findsOneWidget);
    await _enter(tester, 'Yield at test temp. (MPa) — optional', '240');
    // Re 240: P(90 % Re) = 280,1 bar > 13,30 → maks. Pt = 13,30 bar.
    expect(find.textContaining('at 90 % of yield = 13.30 bar'),
        findsOneWidget);
    expect(find.textContaining('exceeds the maximum'), findsNothing);

    await _tapText(tester, 'Save test');
    await _enter(tester, 'Start pressure (bar)', '14');
    expect(find.textContaining('Start pressure above the max 1.33·P = 13.30'),
        findsOneWidget);
    // §345.5.1: zawór ≤ 11 + min(3,45; 1,1) = 12,10 bar.
    await _enter(tester, 'Relief valve set pressure (bar)', '13');
    expect(find.textContaining('= 12.10 bar (ASME B31.3 §345.5.1)'),
        findsOneWidget);
    await _enter(tester, 'Relief valve set pressure (bar)', '12');
    expect(find.textContaining('§345.5.1).'), findsNothing);
  });

  testWidgets('EN 13480-5: σ/Re i granica „do potwierdzenia w normie”',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'OD (mm)', '60,3');
    await _enter(tester, 'Wall t (mm)', '3,91');
    await _enter(tester, 'Design pressure (bar)', '10');
    await _tapText(tester, 'EN 13480-5 / PED — hydrostatic');
    await _enter(tester, 'Yield at test temp. (MPa) — optional', '240');
    // Pt 14,30 bar → σ = 1,43 · 60,3 / (2 · 3,91) = 11,0 MPa = 5 % Re.
    expect(find.textContaining('(5 % of yield)'), findsOneWidget);
    expect(find.textContaining('to be confirmed in the standard'),
        findsWidgets);
  });

  testWidgets('kalendarz ogranicza datę początkową próby ciśnieniowej',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'Design pressure (bar)', '10');
    await _tapText(tester, 'Save test');
    final year = DateTime.now().year;
    await _enter(tester, 'Test date', '${year - 10}-01-01');
    await tester.ensureVisible(find.byIcon(Icons.calendar_month_outlined));
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog))
        .initialDate, DateTime(year - 5));
  });

  testWidgets('kalendarz ogranicza datę początkową kalibracji manometru',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'Design pressure (bar)', '10');
    await _tapText(tester, 'Save test');
    final year = DateTime.now().year;
    await _enter(tester, 'Calibration due', '${year + 10}-01-01');
    await tester.ensureVisible(find.byIcon(Icons.event_available_outlined));
    await tester.tap(find.byIcon(Icons.event_available_outlined));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog))
        .initialDate, DateTime(year + 5));
  });
}
