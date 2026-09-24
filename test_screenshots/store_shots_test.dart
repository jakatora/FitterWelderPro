// Zrzuty ekranu do App Store / Google Play — renderowane z PRAWDZIWYCH ekranów
// aplikacji, nie z makiet. Rozmiar 1242×2688 (iPhone 6.5"), czyli dokładnie ten,
// który przyjmuje App Store Connect.
//
// Uruchomienie (zapisuje pliki do test_screenshots/shots/):
//
//     flutter test test_screenshots --update-goldens
//
// Katalog celowo leży POZA test/, żeby zwykłe `flutter test` nie próbowało
// porównywać zrzutów i nie wywracało zestawu.
//
// Font Roboto ładujemy ręcznie — bez tego środowisko testowe rysuje tekst
// jako czarne prostokąty i zrzuty są bezużyteczne.
//
// Analizator nie uznaje katalogu poza test/ za testowy, więc nie wie, że
// SharedPreferences.setMockInitialValues jest tu użyte zgodnie z przeznaczeniem.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/user_profile.dart';

// iPhone 6.5" — 1242×2688 px przy skali 3.0 => 414×896 pt.
const Size kPhysical = Size(1242, 2688);
const double kDpr = 3.0;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // 1) Wszystkie rodziny z FontManifest — bez tego MaterialIcons rysują się
    //    jako puste kwadraty.
    final manifest = json.decode(
      await rootBundle.loadString('FontManifest.json'),
    ) as List<dynamic>;
    for (final entry in manifest) {
      final family = (entry as Map<String, dynamic>)['family'] as String;
      final loader = FontLoader(family);
      for (final f in entry['fonts'] as List<dynamic>) {
        loader.addFont(rootBundle.load((f as Map<String, dynamic>)['asset'] as String));
      }
      await loader.load();
    }

    // 2) Roboto jest w projekcie zwykłym assetem, nie rodziną fontów, więc
    //    rejestrujemy go ręcznie — pod nazwą rodziny i pod pustą nazwą, której
    //    silnik używa, gdy TextStyle.fontFamily jest null (paski tytułowe).
    for (final family in const ['Roboto', '']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
      await loader.load();
    }
  });

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = kPhysical;
    tester.view.devicePixelRatio = kDpr;
    addTearDown(tester.view.reset);

    // Brama startowa sprawdza profil ORAZ akceptację zasad — bez zgody
    // zrzuty pokazywałyby ekran regulaminu zamiast aplikacji.
    SharedPreferences.setMockInitialValues({
      'user_profile_v1': jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
      'legal_consent_v1': jsonEncode({
        'version': kLegalVersion,
        'acceptedAt': '2026-07-09T12:00:00.000',
      }),
    });
    UserProfileService.instance.resetForTest();
    LegalConsent.instance.resetForTest();

    await tester.pumpWidget(const CutListApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Domknij timery SnackBara (błąd bazy przy równoległych izolatach),
  /// inaczej binding zgłasza "A Timer is still pending".
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
  }

  Future<void> shoot(WidgetTester tester, String name) {
    return expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  testWidgets('01 — ekran główny', (tester) async {
    await boot(tester);
    await settle(tester);
    await shoot(tester, '01_home');
    await drain(tester);
  });

  testWidgets('02 — menu Fitter', (tester) async {
    await boot(tester);
    await tester.tap(find.byIcon(Icons.handyman_outlined));
    await settle(tester);
    await shoot(tester, '02_fitter_menu');
    await drain(tester);
  });

  testWidgets('03 — wymiary kolan, DN100', (tester) async {
    await boot(tester);
    await tester.tap(find.byIcon(Icons.handyman_outlined));
    await settle(tester);
    // Na prawdziwej wysokości telefonu kafel jest pod zgięciem, a siatka
    // buduje tylko widoczne elementy — trzeba przewinąć, jak użytkownik.
    final elbows = find.byIcon(Icons.table_rows_outlined);
    await tester.scrollUntilVisible(elbows, 320,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(elbows);
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '100');
    await settle(tester);
    await shoot(tester, '03_elbow_takeout_dn100');
    await drain(tester);
  });

  testWidgets('04 — menu Spawacz', (tester) async {
    await boot(tester);
    await tester.tap(find.byIcon(Icons.waves_outlined));
    await settle(tester);
    await shoot(tester, '04_welder_menu');
    await drain(tester);
  });

  testWidgets('05 — podgrzewanie i CEV', (tester) async {
    await boot(tester);
    await tester.tap(find.byIcon(Icons.waves_outlined));
    await settle(tester);
    // „Heat input i CE" → zakładka „Preheat / CE" (dawna zakładka
    // „Temperatura" w kalkulatorach spawacza została usunięta jako duplikat).
    final heatInput = find.byIcon(Icons.local_fire_department_outlined);
    await tester.ensureVisible(heatInput);
    await settle(tester);
    await tester.tap(heatInput);
    await settle(tester);
    await tester.tap(find.byType(Tab).at(1));
    await settle(tester);

    Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label);
    await tester.enterText(field('Grubość'), '10');
    await settle(tester);
    await tester.enterText(field('C'), '0.18');
    await settle(tester);
    await tester.enterText(field('Mn'), '1.20');
    await settle(tester);
    // Bez kursora i klawiatury; skład chemiczny na górze, wynik CE pod nim.
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await tester.ensureVisible(find.text('SKŁAD CHEMICZNY (% WT)'));
    await settle(tester);

    await shoot(tester, '05_preheat_cev');
    await drain(tester);
  });
}
