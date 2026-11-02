import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';

void main() {
  for (final language in AppLanguage.values) {
    for (final query in ['DN50', 'dn 50', ' DN 50 ', 'Dn100']) {
      test('catalogued size $query reaches its exact row: $language', () {
        final hits = searchTools(query, language);
        expect(hits, hasLength(1));
        expect(hits.single.tool.id, 'dn_mm');
        expect(hits.single.fields, {'dn': query.contains('100') ? 100 : 50});
        expect(() => hits.single.fields['dn'] = 999, throwsUnsupportedError);
      });
    }
    for (final query in ['DN9999', 'DN0', 'DN-50', 'DN50.5', 'DN50 extra']) {
      test(
          'unsupported or non-size $query does not prefill a guessed size: $language',
          () {
        expect(searchTools(query, language).every((h) => h.fields.isEmpty),
            isTrue);
      });
    }
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
