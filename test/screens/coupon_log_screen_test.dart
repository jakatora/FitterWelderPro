// Log kuponów próbnych: dało się tylko dodać i usunąć kupon. Teraz:
// edycja istniejącego wpisu (bez dublowania), parametry programu, odczyt O₂
// i poziom przebarwień AWS D18.2, eksport CSV/PDF.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/coupon_log_screen.dart';

import '../support/test_database.dart';

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

Future<void> _settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(const CouponLogScreen()));
  await _settle(tester);
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
    description: 'TextField "$label"');

void main() {
  useTestDatabase();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> clear(WidgetTester tester) => tester.runAsync(() async {
        final db = await AppDatabase.get();
        await db.delete('weld_coupons');
      });

  testWidgets('dotknięcie kuponu otwiera edycję; zapis zmienia ten sam wpis',
      (tester) async {
    await clear(tester);
    await tester.runAsync(() => CouponDao().insert(const CouponEntry(
          id: 'c1',
          date: '2026-09-20',
          welder: 'JK-12',
          machine: 'M-3',
          size: '2"×1.65',
          result: 'OK',
          notes: '',
        )));
    await _pumpScreen(tester);

    await tester.tap(find.textContaining('M-3'));
    await tester.pumpAndSettle();
    expect(find.text('Edytuj kupon'), findsOneWidget);
    expect(tester.widget<TextField>(_field('Maszyna / głowica')).controller!.text,
        'M-3');

    await tester.enterText(_field('Nr programu'), '12');
    await tester.enterText(_field('Odczyt O₂ (ppm)'), '18,5');
    await tester.ensureVisible(find.text('NOK'));
    await tester.tap(find.text('NOK'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('heat-tint-2')));
    await tester.tap(find.byKey(const ValueKey('heat-tint-2')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await tester.pump();
    await _settle(tester);
    await tester.pumpAndSettle();

    final all = (await tester.runAsync(() => CouponDao().listAll()))!;
    expect(all, hasLength(1), reason: 'edycja nie może dublować kuponu');
    final c = all.single;
    expect(c.id, 'c1');
    expect(c.result, 'NOK');
    expect(c.programNo, '12');
    expect(c.o2Ppm, 18.5);
    expect(c.heatTint, 2);
  });

  testWidgets('nowy kupon z poziomem przebarwień i O₂', (tester) async {
    await clear(tester);
    await _pumpScreen(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Nowy kupon próbny'), findsOneWidget);
    await tester.enterText(_field('Maszyna / głowica'), 'Orbitalna M-7');
    await tester.enterText(_field('Odczyt O₂ (ppm)'), '40');
    await tester.pump();
    // Podpowiedź poziomu z O₂ (AWS D18.2: 50 ppm ≈ próbka 3).
    expect(find.textContaining('≈ poziom 3'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('heat-tint-3')));
    await tester.tap(find.byKey(const ValueKey('heat-tint-3')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await tester.pump();
    await _settle(tester);
    await tester.pumpAndSettle();

    final c = (await tester.runAsync(() => CouponDao().listAll()))!.single;
    expect(c.machine, 'Orbitalna M-7');
    expect(c.o2Ppm, 40);
    expect(c.heatTint, 3);
    expect(find.textContaining('Orbitalna M-7'), findsOneWidget);
  });

  testWidgets('eksport CSV i PDF są na pasku', (tester) async {
    await clear(tester);
    await _pumpScreen(tester);
    expect(find.byTooltip('Eksport CSV (Excel)'), findsOneWidget);
    expect(find.byTooltip('Eksport PDF'), findsOneWidget);
  });
}
