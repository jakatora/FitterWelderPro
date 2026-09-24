// Regression net for the dot-less keypad on the project setup screen
// (`lib/screens/new_project_screen.dart`).
//
// Every numeric field there is parsed with
// `double.tryParse(text.replaceAll(',', '.'))`, i.e. the code expects a
// decimal separator. The fields, however, asked for `TextInputType.number`.
// On iOS that keypad has NO '.' and NO ',' key at all, so a fitter entering
// Ø76.2 can only type "762". The project is then created with a diameter an
// order of magnitude off and every cut derived from it is wrong.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/new_project_screen.dart';

/// NewProjectScreen calls `context.tr`, which needs AppLanguageScope in the
/// tree — mirror the app's main() setup. English so the labels are stable.
Widget _wrap(Widget child) {
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.en),
    child: MaterialApp(home: child),
  );
}

/// Address fields by their label rather than by index: the index shifts as
/// soon as somebody reorders the form, and a silently-shifted assertion is
/// worse than no assertion on a screen that feeds the saw.
Finder _fieldWithLabel(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
      description: 'TextField labelled "$label"',
    );

void main() {
  // Every millimetre field on the screen; all of them go through
  // double.tryParse, so all of them need a decimal separator.
  const mmFieldLabels = <String>[
    'Pipe diameter (mm)',
    'Wall thickness (mm)',
    'Stock length (mm)',
    'Kerf (mm per cut)',
    'Gap (mm per weld)',
  ];

  testWidgets('every millimetre field offers a decimal keypad',
      (tester) async {
    await tester.pumpWidget(_wrap(const NewProjectScreen()));
    await tester.pumpAndSettle();

    for (final label in mmFieldLabels) {
      final finder = _fieldWithLabel(label);
      expect(finder, findsOneWidget, reason: 'field "$label" not found');

      final field = tester.widget<TextField>(finder);
      expect(
        field.keyboardType.decimal,
        isTrue,
        reason: '"$label" is parsed with double.tryParse, so the soft '
            'keyboard must expose a decimal separator. TextInputType.number '
            'does not on iOS — 76.2 can only be typed as 762.',
      );
    }
  });

  testWidgets('millimetre fields keep the separator and drop letters',
      (tester) async {
    await tester.pumpWidget(_wrap(const NewProjectScreen()));
    await tester.pumpAndSettle();

    // enterText runs the value through the field's inputFormatters, so this
    // asserts the filter keeps '.' / ',' (the whole point of the fix) while
    // refusing characters the parser would choke on.
    final diameter = _fieldWithLabel('Pipe diameter (mm)');
    await tester.enterText(diameter, '76.2');
    expect(
      tester.widget<TextField>(diameter).controller?.text,
      '76.2',
      reason: 'the decimal point must survive the input filter',
    );

    final wall = _fieldWithLabel('Wall thickness (mm)');
    await tester.enterText(wall, '2,77');
    expect(
      tester.widget<TextField>(wall).controller?.text,
      '2,77',
      reason: 'the comma a Polish decimal pad types must survive the filter',
    );

    // A paste with letters in it is refused as a whole — the field keeps
    // its value. Cutting the letters out instead ('2a,7x7' → '2,77') would
    // hand the parser a number nobody typed; with '1e5' it becomes '15'.
    await tester.enterText(wall, '2a,7x7');
    expect(
      tester.widget<TextField>(wall).controller?.text,
      '2,77',
      reason: 'letters must never reach the parser, and must never be '
          'silently cut out of a value either',
    );
  });
}
