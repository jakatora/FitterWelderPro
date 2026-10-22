import 'support/assistant_test_support.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:cut_list_app/assistant/ai_clarification.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  final skills =
      buildSkillCatalog(actions: FakeActionsPort(), iso: FakeIsoDrawingPort());
  final context = AssistantContext(
      lang: AppLanguage.pl, modules: const FixedModuleContext());
  Map<String, Object?> request(AiClarification c,
          {String? question = 'Which variant?', AskResult? pending}) =>
      assistantAiRequest(
          text: 'the second one',
          context: context,
          skills: skills,
          pendingQuestion: question,
          pendingReply: pending,
          clarification: c);
  test(
      'clarification requires a question and cannot replace a native pending slot',
      () {
    final c = AiClarification(
        question: 'Which variant?', userTurns: ['Prepare this variant']);
    expect(() => request(c, question: null), throwsFormatException);
    expect(() => request(c, question: ' '), throwsFormatException);
    final pending = AskResult('value', const AssistantText.same('Value?'),
        partial: SkillMatch(skills.first, .99));
    expect(() => request(c, pending: pending), throwsFormatException);
  });
  test(
      'labelled credentials in earlier user turns are never sent to the provider',
      () async {
    final c =
        AiClarification(question: '?', userTurns: ['password=secret12345']);
    expect(() => request(c), throwsFormatException);
    final raw = assistantAiRequest(
        text: 'second',
        context: context,
        skills: skills,
        pendingQuestion: 'Which?');
    (raw['context'] as Map)['clarification'] = {
      'user_turns': ['password=secret12345']
    };
    var identities = 0, calls = 0;
    final transport = MockClient((_) async {
      calls++;
      throw StateError('unexpected HTTP');
    });
    final client = AssistantAiClient(
        client: transport,
        identity: () async {
          identities++;
          return {};
        });
    await expectLater(
        client.interpret(raw),
        throwsA(isA<AssistantAiUnavailable>()
            .having((e) => e.code, 'code', 'AI_SENSITIVE_INPUT')));
    expect(identities, 0);
    expect(calls, 0);
    client.close();
  });
  for (final lang in AppLanguage.values) {
    test('full $lang catalog plus long clarification fits real wire contract',
        () {
      final turns = List.generate(31, (i) => 'User turn $i: ${'x' * 180}');
      final c = AiClarification(question: 'Which variant?', userTurns: turns);
      final body = assistantAiRequest(
          text: 'the second one',
          context:
              AssistantContext(lang: lang, modules: const FixedModuleContext()),
          skills: skills,
          pendingQuestion: c.question,
          clarification: c,
          history: List.generate(
              6,
              (i) => {
                    'role': i.isEven ? 'user' : 'assistant',
                    'text': 'recent $i'
                  }));
      expect((body['capabilities'] as List).length, greaterThanOrEqualTo(80));
      expect((body['context'] as Map)['clarification'], {'user_turns': turns});
      expect(utf8.encode(jsonEncode(body)).length, lessThan(64000));
      File('build/assistant-clarification-wire-${lang.name}.json')
          .writeAsStringSync(jsonEncode(body));
    });
  }
}
