// Rejestr przyrządów na ekranie: dodanie, status, „skalibrowane dziś”.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/instrument_dao.dart';
import 'package:cut_list_app/domain/instruments/instrument.dart';
import 'package:cut_list_app/features/instruments/instrument_edit_page.dart';
import 'package:cut_list_app/features/instruments/instrument_register_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import '../../support/test_database.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useTestDatabase();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('przyrząd po terminie na górze; „skalibrowane dziś” go zieleni',
      (tester) async {
    await tester.runAsync(() async {
      final db = await AppDatabase.get();
      await db.delete('instruments');
      final dao = InstrumentDao();
      await dao.save(const Instrument(
          id: 'ok',
          kind: InstrumentKind.thermometer,
          name: 'Termometr stykowy',
          lastCalibration: '2026-09-01',
          createdAt: 0,
          updatedAt: 0));
      await dao.save(const Instrument(
          id: 'late',
          kind: InstrumentKind.pressureGauge,
          name: 'Manometr 0–40 bar',
          lastCalibration: '2025-01-10',
          createdAt: 0,
          updatedAt: 0));
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          home: InstrumentRegisterPage(clock: () => DateTime(2026, 10, 17))),
    ));
    await _settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('1 po terminie'), findsOneWidget);
    final lateY = tester.getTopLeft(find.byKey(const ValueKey('instrument-late'))).dy;
    final okY = tester.getTopLeft(find.byKey(const ValueKey('instrument-ok'))).dy;
    expect(lateY, lessThan(okY));
    expect(find.textContaining('po terminie 280 dni'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('instrument-late')),
        matching: find.byTooltip('Więcej')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skalibrowane dziś'));
    await tester.pumpAndSettle();
    await _settle(tester);
    await tester.pumpAndSettle();

    final rows = (await tester.runAsync(() => InstrumentDao().listAll()))!;
    final late = rows.firstWhere((r) => r.id == 'late');
    expect(late.lastCalibration, '2026-10-17');
    expect(find.text('0 po terminie'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('formularz: nowy przyrząd z rodzajem i datą zwraca rekord',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Instrument? saved;
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  saved = await Navigator.of(context).push<Instrument>(
                      MaterialPageRoute(
                          builder: (_) => const InstrumentEditPage()));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('instrument-kind-TORQUE')));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nazwa / model'), 'Klucz 40–200 Nm');
    await tester.tap(find.byKey(const ValueKey('instrument-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.kind, InstrumentKind.torqueWrench);
    expect(saved!.name, 'Klucz 40–200 Nm');
    expect(saved!.intervalMonths, 12);
  });
}
