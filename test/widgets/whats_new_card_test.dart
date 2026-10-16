// Karta „Nowe w aplikacji”: pokazuje nowe narzędzia, zamknięta nie wraca.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';
import 'package:cut_list_app/widgets/whats_new_card.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: Scaffold(body: WhatsNewCard())),
    ));
    await tester.pumpAndSettle();
  }

  test('każdy identyfikator nowości istnieje w rejestrze narzędzi', () {
    for (final id in kWhatsNewToolIds) {
      expect(toolById(id), isNotNull, reason: id);
    }
  });

  testWidgets('pokazuje nowe narzędzia; po zamknięciu znika na stałe',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester);
    expect(find.text('NOWE W APLIKACJI'), findsOneWidget);
    expect(find.byKey(const ValueKey('whats-new-weld_quotes')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('whats-new-close')));
    await tester.pumpAndSettle();
    expect(find.text('NOWE W APLIKACJI'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kWhatsNewSeenKey), isTrue);

    // Ponowne wejście na ekran — karta nie wraca.
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    expect(find.text('NOWE W APLIKACJI'), findsNothing);
  });
}
