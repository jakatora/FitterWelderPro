import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';

void main() {
  for (final language in AppLanguage.values) {
    for (final query in ['DN', 'dn']) {
      test('$query finds pipe sizing without incidental hardness: $language',
          () {
        final ids = searchTools(query, language).map((h) => h.tool.id).toList();
        expect(ids, contains('dn_mm'));
        expect(ids, isNot(contains('hardness')));
      });
    }
    test('OD finds pipe sizing without incidental supports: $language', () {
      final ids = searchTools('OD', language).map((h) => h.tool.id).toList();
      expect(ids, contains('dn_mm'));
      expect(ids, isNot(contains('pipe_supports')));
    });
    test('AI finds the assistant without matching stainless: $language', () {
      final ids = searchTools('AI', language).map((h) => h.tool.id).toList();
      expect(ids, contains('assistant'));
      expect(ids, isNot(contains('filler_selector')));
    });
  }
}
