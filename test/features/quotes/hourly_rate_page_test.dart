// Ekran „Ile brać za godzinę?": przeliczanie na żywo i zwrot stawki do
// wyceny.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/quotes/hourly_rate.dart';
import 'package:cut_list_app/features/quotes/hourly_rate_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/quote_settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: home),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('wyższy cel na rękę podnosi stawkę i zapisuje się',
      (tester) async {
    await pump(tester, const HourlyRatePage());
    expect(find.text('Stawka minimalna'.toUpperCase()), findsOneWidget);
    final before = computeHourlyRate(const HourlyRateInput()).recommendedRate;
    await tester.enterText(
        find.widgetWithText(TextField, 'Na rękę miesięcznie'), '12000');
    await tester.pump(const Duration(seconds: 1));
    final after =
        computeHourlyRate(const HourlyRateInput().copyWith(netIncome: 12000))
            .recommendedRate;
    expect(after, greaterThan(before));
    final saved = await const HourlyRateStore().load();
    expect(saved.netIncome, 12000);
  });

  testWidgets('z wyceny: „Użyj” zwraca stawkę zaokrągloną w górę do 50 gr',
      (tester) async {
    double? picked;
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                picked = await Navigator.of(context).push<double>(
                  MaterialPageRoute(
                      builder: (_) => const HourlyRatePage(pickMode: true)),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr-apply')));
    await tester.pumpAndSettle();
    final expected =
        (computeHourlyRate(const HourlyRateInput()).recommendedRate * 2)
                .ceil() /
            2;
    expect(picked, expected);
  });
}
