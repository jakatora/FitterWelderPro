import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../test_prefs.dart';

void main() {
  for (final size in const [
    Size(360, 900),
    Size(432, 900),
    Size(900, 360),
    Size(600, 900)
  ]) {
    for (final scale in [1.0, 1.3]) {
      for (final language in AppLanguage.values) {
        for (final brightness in Brightness.values) {
          testWidgets(
              'elbow-cut result fits $size text$scale ${language.name} ${brightness.name}',
              (t) async {
            seedFreshInstall();
            ToolBridge.reset();
            t.view.physicalSize = size;
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            addTearDown(() async {
              await t.pumpWidget(const SizedBox.shrink());
              await t.pumpAndSettle();
            });
            await t.pumpWidget(AppLanguageScope(
                controller: AppLanguageController(language),
                child: MaterialApp(
                    theme: ThemeData(brightness: brightness),
                    builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: child!),
                    home: const FitterToolsScreen(initialTab: 1))));
            await t.pumpAndSettle();
            final handle = ToolBridge.instance.current!;
            expect(handle.toolId, 'elbow_cut');
            expect(
                await handle.apply({
                  'base_angle_deg': 90.0,
                  'extrados_mm': 180.0,
                  'intrados_mm': 90.0,
                  'target_angle_deg': 45.0
                }),
                isEmpty);
            await t.pumpAndSettle();
            final result = find.textContaining(language == AppLanguage.pl
                ? 'OD wyliczone z pomiaru:'
                : 'OD derived from measurement:');
            final scroll = find
                .descendant(
                    of: find.byType(ListView).first,
                    matching: find.byType(Scrollable))
                .first;
            await t.scrollUntilVisible(result, 180, scrollable: scroll);
            await t.pumpAndSettle();
            expect(result, findsOneWidget);
            expect(find.textContaining('57.3 mm'), findsOneWidget);
            expect(t.getRect(result).right, lessThanOrEqualTo(size.width));
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  }
}
