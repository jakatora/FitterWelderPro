import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_journal/weld_filter.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/weld_journal/weld_filter_sheet.dart';

void main() {
  testWidgets('filtr dziennika otwiera daty spoza zakresu kalendarza',
      (tester) async {
    final year = DateTime.now().year;
    final old = '${year - 30}-01-01';
    final future = '${year + 3}-01-01';
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWeldFilterSheet(
                context,
                filter: WeldJournalFilter(dateFrom: old, dateTo: future),
                projects: const [],
                welders: const [],
              ),
              child: const Text('Otwórz filtr'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Otwórz filtr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Od: $old'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog))
        .initialDate, DateTime(year - 20));

    Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Do: $future'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog))
        .initialDate, DateTime(year + 2));
  });
}
