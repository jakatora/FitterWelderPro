// Wiersz kwoty wyceny: duża kwota na wąskim ekranie z większą czcionką
// nie wychodzi poza wiersz (zgłoszone przy module „Akord”).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/features/quotes/quote_widgets.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  testWidgets('duża kwota, 320 px, tekst ×1,3 — bez przepełnienia',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                MoneyRow(
                  label: 'Razem brutto (z VAT 23 %)',
                  grosze: 123456789012,
                  strong: true,
                  hot: true,
                  hint: 'Kwota do oferty dla klienta',
                ),
                MoneyRow(label: 'Robocizna', grosze: 98765432),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(MoneyRow), findsNWidgets(2));
  });
}
