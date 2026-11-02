import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
Future<void> enter(WidgetTester t, String label, String text) async {
  final f = field(label);
  await t.ensureVisible(f);
  await t.enterText(f, text);
  await t.pumpAndSettle();
}

Future<void> mount(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(1000, 1800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: FitterToolsScreen(initialTab: 5))));
  await t.pumpAndSettle();
  await enter(t, 'OD (mm)', '60,3');
  await enter(t, 'Gr. ścianki t (mm)', '3,91');
  expect(find.text('5.541 kg/m'), findsOneWidget);
}

void main() {
  testWidgets(
      'piece count without length is explained and correction restores total',
      (t) async {
    await mount(t);
    await enter(t, 'Ilość szt.', '2');
    expect(find.text('11.08 kg'), findsOneWidget);
    await enter(t, 'Długość (mm)', '');
    expect(find.text('Podaj długość jednej sztuki albo usuń ilość sztuk.'),
        findsOneWidget);
    expect(find.text('5.541 kg/m'), findsNothing);
    await enter(t, 'Ilość szt.', '');
    expect(find.text('5.541 kg/m'), findsOneWidget);
    expect(find.text('11.08 kg'), findsNothing);
    await enter(t, 'Długość (mm)', '1000');
    await enter(t, 'Ilość szt.', '2');
    expect(find.text('11.08 kg'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('manual piece count has the same supported maximum as assistant',
      (t) async {
    await mount(t);
    await enter(t, 'Ilość szt.', '2147483648');
    expect(find.text('Ilość: wpisz całkowitą liczbę sztuk od 1 do 2147483647'),
        findsOneWidget);
    expect(find.text('5.541 kg/m'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('finite dimensions whose mass overflows do not render Infinity',
      (t) async {
    await mount(t);
    await enter(t, 'OD (mm)', '1${'0' * 160}');
    await enter(t, 'Gr. ścianki t (mm)', '1${'0' * 159}');
    expect(find.text('Wynik poza zakresem. Sprawdź wymiary, długość i ilość.'),
        findsOneWidget);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
