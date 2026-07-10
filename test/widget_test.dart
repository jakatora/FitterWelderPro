import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/app.dart';

import 'test_prefs.dart';

void main() {
  setUpAll(() {
    // HomeScreen instantiates the project DAO which talks to sqflite; in a
    // unit-test environment we need the FFI factory.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Brama startowa robi teraz DWA odczyty asynchroniczne (profil + zgoda),
  /// a po akceptacji jeszcze zapis. Kilka klatek to za mało.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// sqflite ustawia 10-sekundowy Timer ostrzegający o zablokowanej bazie.
  /// Przy równoległych izolatach potrafi wisieć po końcu testu, a binding
  /// traktuje wiszący Timer jak błąd. Dajemy mu wygasnąć.
  Future<void> drainTimers(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
  }

  /// Domyślne płótno testu (800×600) jest niższe niż telefon. Po dodaniu zgody
  /// przycisk w onboardingu wypadał poza ekran i nie dawał się kliknąć.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows the FITTER tile on home for an onboarded user',
      (tester) async {
    useTallSurface(tester);
    seedOnboardedUser();
    await tester.pumpWidget(const CutListApp());
    await settle(tester);

    // FITTER is identical in both PL and EN locales so the test is robust to
    // whichever language the device defaults to.
    expect(find.text('FITTER'), findsOneWidget);
    await drainTimers(tester);
  });

  testWidgets('pierwsze uruchomienie wymaga imienia I akceptacji zasad',
      (tester) async {
    useTallSurface(tester);
    seedFreshInstall();
    await tester.pumpWidget(const CutListApp());
    await settle(tester);

    expect(find.text('FITTER'), findsNothing);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Marek');
    await tester.enterText(fields.at(1), 'Kowalczyk');
    await settle(tester);

    // Samo imię nie wystarczy — bez zgody przycisk jest wyłączony.
    final cta = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(cta.onPressed, isNull,
        reason: 'Nie wolno wpuścić nikogo, kto nie zaakceptował zasad');

    await tester.tap(find.byType(Checkbox));
    await settle(tester);
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('FITTER'), findsOneWidget);
    await drainTimers(tester);
  });

  testWidgets('użytkownik sprzed regulaminu musi go zaakceptować',
      (tester) async {
    useTallSurface(tester);
    seedProfileWithoutConsent();
    await tester.pumpWidget(const CutListApp());
    await settle(tester);

    // Ma profil, więc onboardingu nie widzi — ale do narzędzi jeszcze nie wchodzi.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('FITTER'), findsNothing);
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await settle(tester);
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('FITTER'), findsOneWidget);
    await drainTimers(tester);
  });
}
