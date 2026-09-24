import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_database.dart';

import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/chat_screen.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/screens/home_screen.dart';
import 'package:cut_list_app/screens/onboarding_name_screen.dart';
import 'package:cut_list_app/services/legal_consent.dart';

import 'test_prefs.dart';

void main() {
  useTestDatabase();

  /// Ekran główny czyta profil, zgodę, bazę i listę ostatnio używanych
  /// narzędzi — kilka klatek to za mało.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Domyślne płótno testu (800×600) jest niższe niż telefon.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows the MONTER tile on home for an onboarded user',
      (tester) async {
    useTallSurface(tester);
    seedOnboardedUser();
    await tester.pumpWidget(const CutListApp());
    await settle(tester);

    // PL: MONTER / SPAWACZ (dawniej nietłumaczone „FITTER" obok „SPAWACZ").
    expect(find.text('MONTER'), findsOneWidget);
    expect(find.text('SPAWACZ'), findsOneWidget);
    expect(find.text('FITTER'), findsNothing);
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

  testWidgets(
      'pierwsze uruchomienie: od razu ekran główny, bez imienia i bez zgody',
      (tester) async {
    useTallSurface(tester);
    seedFreshInstall();
    await tester.pumpWidget(const CutListApp());
    await settle(tester);

    // Kalkulatory działają offline i bez konta — nic nie stoi przed nimi.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingNameScreen), findsNothing);
    expect(find.byType(ConsentScreen), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('MONTER'), findsOneWidget);
    // Bez imienia powitanie jest ogólne.
    expect(find.text('Witaj'), findsOneWidget);
  });

  testWidgets(
      'użytkownik sprzed regulaminu wchodzi do narzędzi; zasady dopiero przy '
      'czacie', (tester) async {
    useTallSurface(tester);
    seedProfileWithoutConsent();
    await tester.pumpWidget(const CutListApp());
    await settle(tester);

    // Ma profil bez zgody — i nadal widzi narzędzia.
    expect(find.text('MONTER'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.byIcon(Icons.forum_outlined)); // CZAT
    await settle(tester);

    // Bramka czatu: sam ekran zasad (imię już jest).
    expect(find.byType(ConsentScreen), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);

    await tester.tap(find.byType(Checkbox));
    await settle(tester);
    await tester.tap(find.byType(FilledButton));
    await settle(tester);

    expect(LegalConsent.instance.isAccepted, isTrue);
    expect(find.byType(ChatScreen), findsOneWidget);

    // Domknij żądania czatu (odpowiedź 400 z atrapy HTTP, limit czasu 8 s).
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox());
  });
}
