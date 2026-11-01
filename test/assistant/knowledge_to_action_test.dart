import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSkill;
import 'global_pipe_slope_flow_test.dart' show say;

void main() {
  useGuestAccount();
  useTestDatabase();
  for (final command in [
    'A zmniejsz szczelinę o 1 mm',
    'And rotate the elbow'
  ]) {
    testWidgets('knowledge answer then editing command executes once: $command',
        (tester) async {
      var chats = 0, runs = 0, interpretations = 0;
      final skill = FixtureSkill('fixture.edit', command, (_) async {
        runs++;
        return const AnswerResult(
            AssistantAnswer(text: AssistantText.same('Zmiana wykonana')));
      });
      await mount(tester, skills: [skill], interpret: (_) async {
        interpretations++;
        throw StateError(
            'Exact native command should not require AI interpretation');
      }, chatSender: (_, __) async {
        chats++;
        return ChatMessage(
            role: ChatRole.assistant,
            text: 'Wyjaśnienie TIG.',
            kind: AiReplyKind.live);
      });
      await say(tester, 'Wyjaśnij spawanie TIG');
      expect(chats, 1);
      expect(runs, 0);
      await say(tester, command);
      expect(chats, 1,
          reason: 'command cannot become a second knowledge question');
      expect(runs, 1);
      expect(interpretations, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
