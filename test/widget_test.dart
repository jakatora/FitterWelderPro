import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_database.dart';

import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/models/project.dart';

import 'test_prefs.dart';

void main() {
  useTestDatabase();

  /// Brama startowa robi teraz DWA odczyty asynchroniczne (profil + zgoda),
  /// a po akceptacji jeszcze zapis. Kilka klatek to za mało.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 150));
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
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'home finishes loading and shows a project saved in the real database',
      (tester) async {
    useTallSurface(tester);
    seedOnboardedUser();
    final dao = ProjectDao();
    await tester.runAsync(() => dao.insert(Project(
          id: 'home-persisted',
          name: 'Projekt zapisany na budowie',
          materialGroup: 'SS',
          diameterMm: 60.3,
          wallThicknessMm: 2,
          currentDiameterMm: 60.3,
          stockLengthMm: 6000,
          sawKerfMm: 1,
          gapMm: 0,
          createdAt: 1,
          updatedAt: 1,
        )));
    try {
      await tester.pumpWidget(const CutListApp());
      await settle(tester);
      expect(find.text('Projekt zapisany na budowie'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => dao.deleteById('home-persisted'));
    }
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
  });
}
