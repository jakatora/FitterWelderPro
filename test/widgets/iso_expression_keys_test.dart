// The operator key bar under an ISO-dimension field (segment builder, scan
// review): what each key inserts, where it inserts it, and which characters
// the ISO field lets through — always checked against the real parser.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/iso_parser.dart';
import 'package:cut_list_app/widgets/iso_expression_keys.dart';

TextEditingController _ctrl(String text, {int? cursor, int? extent}) {
  final c = TextEditingController(text: text);
  if (cursor != null) {
    c.selection = TextSelection(
      baseOffset: cursor,
      extentOffset: extent ?? cursor,
    );
  }
  return c;
}

void main() {
  group('insertAtCursor', () {
    test('inserts at the cursor and moves it past the insert', () {
      final c = _ctrl('3000525', cursor: 4);
      expect(insertAtCursor(c, '+'), '3000+525');
      expect(c.selection, const TextSelection.collapsed(offset: 5));
    });

    test('replaces a selection', () {
      final c = _ctrl('3000*525', cursor: 4, extent: 5);
      expect(insertAtCursor(c, '×'), '3000×525');
    });

    test('a reversed selection is handled like a forward one', () {
      final c = _ctrl('3000*525', cursor: 5, extent: 4);
      expect(insertAtCursor(c, '+'), '3000+525');
    });

    test('a field that never had a cursor gets the key appended', () {
      final c = TextEditingController(text: '3000');
      expect(c.selection.isValid, isFalse);
      expect(insertAtCursor(c, '+'), '3000+');
    });
  });

  group('backspaceAtCursor', () {
    test('deletes the character before the cursor', () {
      final c = _ctrl('3000+525', cursor: 5);
      expect(backspaceAtCursor(c), '3000525');
      expect(c.selection, const TextSelection.collapsed(offset: 4));
    });

    test('deletes a selection', () {
      final c = _ctrl('3000+525-80', cursor: 8, extent: 11);
      expect(backspaceAtCursor(c), '3000+525');
    });

    test('at the start of the text it does nothing', () {
      final c = _ctrl('3000', cursor: 0);
      expect(backspaceAtCursor(c), '3000');
    });

    test('without a cursor it deletes from the end', () {
      final c = TextEditingController(text: '3000+');
      expect(backspaceAtCursor(c), '3000');
      expect(backspaceAtCursor(TextEditingController()), '');
    });

    test('removes a whole non-ASCII character (×, ½), never half of it', () {
      expect(backspaceAtCursor(_ctrl('5×', cursor: 2)), '5');
      expect(backspaceAtCursor(_ctrl('4½', cursor: 2)), '4');
    });
  });

  group('keys insert exactly what the ISO parser reads', () {
    test('every key but backspace inserts a parser character', () {
      final inserts = [
        for (final k in kIsoExpressionKeys)
          if (!k.isBackspace) k.insert!
      ];
      expect(inserts, ['+', '-', '×', '(', ')', '"']);
    });

    test('expressions built from the keys evaluate as on the drawing', () {
      expect(parseIsoExpression('3000+525-80'), 3445);
      expect(parseIsoExpression('(1500+200)×2'), 3400);
      expect(parseIsoExpression('5×200+150'), 1150);
      expect(parseIsoExpression('76"'), closeTo(1930.4, 1e-9));
      expect(parseIsoExpression('1020,5+20'), 1040.5);
    });
  });

  group('isoExpressionInputFormatters', () {
    final f = isoExpressionInputFormatters().single;
    String edit(String from, String to) => f
        .formatEditUpdate(
          TextEditingValue(text: from),
          TextEditingValue(
            text: to,
            selection: TextSelection.collapsed(offset: to.length),
          ),
        )
        .text;

    test('lets through everything the parser understands', () {
      for (final ok in [
        '3000+525-80',
        '5*200',
        '5x200',
        '5×200',
        '5·200',
        '(1500+200)*2',
        '1020,5 + 20',
        '76"',
        "76''",
        '76 in',
        '3000 mm',
        '4½"',
        '4 1/2"',
        '1\'234',
        '3000\u2212500',
        '3000\u2013500',
      ]) {
        expect(edit('', ok), ok, reason: ok);
      }
    });

    test('refuses a paste with anything else instead of trimming it', () {
      // Trimming '3000;525' would leave the wrong but valid '3000525'.
      expect(edit('', '3000;525'), '');
      expect(edit('3000', '3000=3525'), '3000');
      expect(edit('', '3000\n525'), '');
    });
  });

  group('IsoExpressionKeyBar', () {
    Widget host(TextEditingController ctrl, List<String> changes,
            {double width = 320}) =>
        AppLanguageScope(
          controller: AppLanguageController(AppLanguage.pl),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(controller: ctrl),
                    IsoExpressionKeyBar(
                      controller: ctrl,
                      onChanged: changes.add,
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );

    Future<void> tap(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(ValueKey('iso-key-$label')));
      await tester.pump();
    }

    testWidgets('taps edit the text and report every change',
        (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      final changes = <String>[];
      await tester.pumpWidget(host(ctrl, changes));

      await tester.enterText(find.byType(TextField), '3000');
      await tap(tester, '+');
      await tester.enterText(find.byType(TextField), '${ctrl.text}525');
      await tap(tester, '\u2212');
      await tester.enterText(find.byType(TextField), '${ctrl.text}80');

      expect(ctrl.text, '3000+525-80');
      expect(changes, ['3000+', '3000+525-']);

      await tap(tester, '⌫');
      expect(ctrl.text, '3000+525-8');
      expect(changes.last, '3000+525-8');
    });

    testWidgets('keys are at least 48 dp even on a narrow screen',
        (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(host(ctrl, [], width: 240));
      for (final k in kIsoExpressionKeys) {
        final size = tester.getSize(find.byKey(ValueKey('iso-key-${k.label}')));
        expect(size.width, greaterThanOrEqualTo(48), reason: k.label);
        expect(size.height, greaterThanOrEqualTo(48), reason: k.label);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out inside an AlertDialog (intrinsic width)',
        (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.en),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      content: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(controller: ctrl),
                        IsoExpressionKeyBar(controller: ctrl),
                      ]),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('iso-key-(')));
      await tester.pump();
      expect(ctrl.text, '(');
    });

    testWidgets('keys carry spoken labels for screen readers', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(ctrl, []));
      expect(find.bySemanticsLabel('minus'), findsOneWidget);
      expect(find.bySemanticsLabel('usuń znak'), findsOneWidget);
      handle.dispose();
    });
  });
}
