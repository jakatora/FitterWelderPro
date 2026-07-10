import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/readout.dart';

void main() {
  Future<void> pumpReadout(WidgetTester tester, Widget child) {
    return tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: child)),
    ));
  }

  testWidgets('pokazuje etykietę wersalikami, wartość i jednostkę',
      (tester) async {
    await pumpReadout(
      tester,
      const Readout(label: 'Takeout LR 45°', value: '64', unit: 'mm · DN100'),
    );

    expect(find.text('TAKEOUT LR 45°'), findsOneWidget);
    expect(find.text('64'), findsOneWidget);
    expect(find.text('MM · DN100'), findsOneWidget);
  });

  testWidgets('cyfry są tabularne — kolumny wyników muszą się wyrównywać',
      (tester) async {
    await pumpReadout(tester, const Readout(label: 'CEV', value: '0.220'));

    final value = tester.widget<Text>(find.text('0.220'));
    final features = value.style!.fontFeatures!.map((f) => f.feature).toList();
    expect(features, contains('tnum'));
    expect(features, contains('zero'));
  });

  testWidgets('tylko wynik główny świeci bursztynem', (tester) async {
    await pumpReadout(tester, const Readout(label: 'Główny', value: '217', hot: true));
    expect(tester.widget<Text>(find.text('217')).style!.color, kArc);

    await pumpReadout(tester, const Readout(label: 'Pomocniczy', value: '152'));
    expect(tester.widget<Text>(find.text('152')).style!.color, kText);
  });

  testWidgets('jednostka jest opcjonalna', (tester) async {
    await pumpReadout(tester, const Readout(label: 'Bez jednostki', value: '1.5'));
    expect(find.text('1.5'), findsOneWidget);
    // Etykieta + wartość, nic więcej.
    expect(find.byType(Text), findsNWidgets(2));
  });
}
