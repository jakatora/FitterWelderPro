import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

class WireContext implements ModuleContext, FieldModuleContext {
  @override
  String? get activeToolId => 'cone_layout';
  @override
  bool get onHomeOrAssistant => false;
  @override
  Map<String, Object?> inputFields(String id) => const {
        'shape': 'transition',
        'side_a_mm': 600,
        'side_b_mm': 400,
        'diameter_mm': 300,
        'height_mm': 400,
        'thickness_mm': 4,
        'reference': 'outside',
        'offset_x_mm': -50,
        'offset_y_mm': 20,
        'parts': 1,
        'divisions': 16,
        'seam': 'sideB',
      };
}

void main() {
  for (final lang in AppLanguage.values) {
    test('full session wire fixture fits backend UTF8 contract: ${lang.name}',
        () {
      final request = assistantAiRequest(
          text: List.filled(2000, 'ą').join(),
          context: AssistantContext(lang: lang, modules: WireContext()),
          skills: buildSkillCatalog(
              actions: FakeActionsPort(), iso: FakeIsoDrawingPort()),
          history: List.generate(
              6,
              (i) => {
                    'role': i.isEven ? 'user' : 'assistant',
                    'text': List.filled(1000, 'ą').join()
                  }));
      request['use_professional_profile'] = false;
      final encoded = jsonEncode(request), bytes = utf8.encode(encoded).length;
      final caps = (request['capabilities'] as List).cast<Map>();
      expect(bytes, lessThanOrEqualTo(64000));
      expect(caps.length, lessThanOrEqualTo(160));
      expect(
          caps.map((c) => c['id']),
          containsAll([
            'iso.draw',
            'development.export',
            'development.summary',
            'development.height',
            'transition.layout',
            'cone.eccentric'
          ]));
      for (final c in caps) {
        expect(
            (c['examples'] as List).every((e) => (e as String).length <= 300),
            true,
            reason: '${c['id']}');
      }
      final file = File('build/assistant-full-wire-${lang.name}.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(encoded);
      // Public synthetic fixtures only; no account/profile/key data.
      debugPrint(
          'FULL_WIRE lang=${lang.name} capabilities=${caps.length} utf8_bytes=$bytes');
    });
  }
}
