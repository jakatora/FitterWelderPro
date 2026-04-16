import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/app.dart';

void main() {
  testWidgets('app shows home menu', (WidgetTester tester) async {
    await tester.pumpWidget(const CutListApp());
    await tester.pumpAndSettle();

    expect(find.text('FITTER'), findsOneWidget);
    expect(find.text('WELDER'), findsOneWidget);
  });
}
