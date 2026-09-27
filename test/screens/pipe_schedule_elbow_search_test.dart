// Ekrany „Grubości ścianek / Sch” i „Wymiary kolan”:
//  • wyszukiwanie `2"` / `2 cale` (podpowiedź w polu tak radzi, przed
//    poprawką: pusta lista / „Brak wyników”);
//  • przy SS kolumny ASME B36.19M: DN300 40S = 9,53 (B36.10M Sch 40 = 10,31),
//    80S = 12,70 (Sch 80 = 17,48) — projectmaterials.com, Wikipedia NPS;
//  • ID = OD − 2t: DN50 Sch 40 → 60,3 − 7,82 = 52,48.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/elbow_takeout_screen.dart';
import 'package:cut_list_app/screens/pipe_schedule_screen.dart';

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

Future<void> _big(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Sch', () {
    testWidgets('2" znajduje DN50', (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(const PipeScheduleScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2"');
      await tester.pumpAndSettle();
      expect(find.text('DN50'), findsOneWidget);
      expect(find.textContaining('Brak wyników'), findsNothing);
      await tester.enterText(find.byType(TextField), '2 cale');
      await tester.pumpAndSettle();
      expect(find.text('DN50'), findsOneWidget);
      expect(find.text('DN15'), findsNothing);
    });

    testWidgets('SS pokazuje B36.19M: DN300 40S 9.53, 80S 12.70, bez 10.31',
        (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(const PipeScheduleScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SS — B36.19M'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DN300');
      await tester.pumpAndSettle();
      for (final h in ['5S', '10S', '40S', '80S']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(find.text('9.53'), findsOneWidget);
      expect(find.text('12.70'), findsOneWidget);
      expect(find.text('10.31'), findsNothing);
      expect(find.text('17.48'), findsNothing);
    });

    testWidgets('CS pokazuje B36.10M: DN300 Sch 40 = 10.31', (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(const PipeScheduleScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DN300');
      await tester.pumpAndSettle();
      expect(find.text('10.31'), findsOneWidget);
      expect(find.text('40S'), findsNothing);
    });

    testWidgets('ID: DN50 Sch 40 → 52.48', (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(const PipeScheduleScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ID mm'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2"');
      await tester.pumpAndSettle();
      // STD i Sch 40 to ta sama ścianka 3,91 → dwa razy 52.48.
      expect(find.text('52.48'), findsNWidgets(2));
      expect(find.textContaining('ID = OD − 2t'), findsOneWidget);
    });
  });

  group('Wymiary kolan', () {
    testWidgets('2" → DN50 (LR 76)', (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(const ElbowTakeoutScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2"');
      await tester.pumpAndSettle();
      expect(find.text('DN50  · 2"', findRichText: true), findsOneWidget);
      expect(find.text('76'), findsOneWidget);
    });

    testWidgets('1 1/2" → DN40; brak wyników ma komunikat', (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(const ElbowTakeoutScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1 1/2"');
      await tester.pumpAndSettle();
      expect(find.text('57'), findsOneWidget); // LR90 DN40
      await tester.enterText(find.byType(TextField), '7"');
      await tester.pumpAndSettle();
      expect(find.textContaining('Brak wyników'), findsOneWidget);
    });
  });
}
