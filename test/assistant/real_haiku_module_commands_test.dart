// Polecenia zapisane z PRAWDZIWEGO modelu (Claude Haiku przez backend FWP)
// dla modułów dodanych do rozmowy w październiku 2026 — natywne umiejętności
// muszą je wykonać bez ponownego pytania o dane, które model już przekazał.
// Fixture: test/assistant/fixtures/real_haiku_module_commands_v1.json
// (tool/verify_assistant_real_haiku.mjs, pole `commands`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import '../support/test_database.dart';
import 'support/assistant_test_support.dart';

void main() {
  useTestDatabase();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final fixture = jsonDecode(File(
          'test/assistant/fixtures/real_haiku_module_commands_v1.json')
      .readAsStringSync()) as Map<String, Object?>;
  for (final raw in fixture['cases']! as List) {
    final c = raw as Map<String, Object?>;
    for (final step in (c['steps']! as List).cast<Map<String, Object?>>()) {
      test('${step['skill_id']}: ${step['command']}', () async {
        final h = BrainHarness();
        addTearDown(h.timer.dispose);
        final reply = await h.say(step['command']! as String);
        expect(reply.match?.skill.id, step['skill_id'],
            reason: 'utterance: ${c['utterance']}');
        expect(reply.result, isA<AnswerResult>(),
            reason: 'the model already gave every value — no re-asking');
        expect((reply.result as AnswerResult).show?.toolId, isNotNull);
      });
    }
  }
}
