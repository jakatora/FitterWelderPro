// Krok „przedstaw się" przed czatem: cele dotyku dla rękawicy i zgoda
// zaznaczana stuknięciem w cały wiersz.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/legal_screen.dart';
import 'package:cut_list_app/screens/onboarding_name_screen.dart';

import '../test_prefs.dart';

Future<void> _pump(WidgetTester tester, {VoidCallback? onDone}) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  final controller = AppLanguageController(AppLanguage.pl);
  addTearDown(controller.dispose);
  await tester.pumpWidget(AppLanguageScope(
    controller: controller,
    child: MaterialApp(home: OnboardingNameScreen(onDone: onDone ?? () {})),
  ));
  await tester.pump();
}

bool _checked(WidgetTester tester) =>
    tester.widget<Checkbox>(find.byType(Checkbox)).value ?? false;

void main() {
  setUp(seedFreshInstall);

  testWidgets('wiersz zgody ma co najmniej 48 dp wysokości', (tester) async {
    await _pump(tester);
    final row = tester.getSize(find.byKey(const ValueKey('onboarding-consent-row')));
    expect(row.height, greaterThanOrEqualTo(48));
    // Samo pole wyboru też nie jest już ścieśnione do 30×30.
    final box = tester.getSize(find.byType(Checkbox));
    expect(box.width, greaterThanOrEqualTo(40));
  });

  testWidgets('stuknięcie w tekst zgody zaznacza i odznacza', (tester) async {
    await _pump(tester);
    expect(_checked(tester), isFalse);

    final text = find.textContaining('Mam ukończone');
    await tester.tapAt(tester.getTopLeft(text) + const Offset(12, 8));
    await tester.pump();
    expect(_checked(tester), isTrue);

    await tester.tapAt(tester.getTopLeft(text) + const Offset(12, 8));
    await tester.pump();
    expect(_checked(tester), isFalse);

    // Samo pole wyboru działa jak dawniej.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(_checked(tester), isTrue);
  });

  testWidgets('odnośnik do regulaminu w wierszu nadal otwiera dokument',
      (tester) async {
    await _pump(tester);
    await tester.tapOnText(find.textRange.ofSubstring('Regulamin'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LegalScreen), findsOneWidget);
  });

  testWidgets('przyciski PL / EN mają co najmniej 48×48 dp i przełączają',
      (tester) async {
    await _pump(tester);
    for (final k in ['onboarding-lang-pl', 'onboarding-lang-en']) {
      final size = tester.getSize(find.byKey(ValueKey(k)));
      expect(size.width, greaterThanOrEqualTo(48), reason: k);
      expect(size.height, greaterThanOrEqualTo(48), reason: k);
    }
    expect(find.text('Zanim napiszesz na czacie'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-lang-en')));
    await tester.pump();
    expect(find.text('Before you post in chat'), findsOneWidget);
  });

  testWidgets('bez zgody nic nie zapisuje; z imieniem i zgodą woła onDone',
      (tester) async {
    var done = 0;
    await _pump(tester, onDone: () => done++);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Marek');
    await tester.enterText(fields.at(1), 'Kowalczyk');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(done, 1);
  });
}
