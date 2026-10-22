// Zgłoszenie problemu przez asystenta: niezależnie od tego, co napisał model,
// użytkownik dostaje prawdziwą informację, co stało się ze zgłoszeniem
// (wysłane do twórcy albo zapisane na telefonie, gdy brak zgody na wysyłkę),
// a zgłoszenie ląduje w kolejce jako jawne — nie jako „niezrozumiane”.

import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_signal.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say;

void main() {
  useTestDatabase();
  const refusal = 'Nie mogę zgłaszać błędów z tego poziomu asystenta.';

  testWidgets('problem report without upload consent is kept on the phone',
      (t) async {
    await mount(t,
        interpret: (_) async => const AiCommandPlan('unsupported', [], refusal));
    await say(t, 'nie działa mi zapis wyceny, zgłoś to');
    expect(find.textContaining('Zapisałem zgłoszenie na tym telefonie'),
        findsOneWidget);
    expect(find.textContaining(refusal), findsNothing,
        reason: 'the model must not claim a report is impossible');
    final signals = await t.runAsync(() => FeedbackStore.instance.list());
    expect(signals, hasLength(1));
    expect(signals!.single.kind, FeedbackKind.explicit);
  });

  testWidgets(
      'explicit report naming a module is confirmed as sent without AI or the module',
      (t) async {
    var aiCalls = 0;
    await mount(t, interpret: (_) async {
      aiCalls++;
      return const AiCommandPlan('unsupported', [], refusal);
    });
    await t.runAsync(() => FeedbackConsent.instance.grant());
    await say(t, 'zgłoś problem: kalkulator spadku źle liczy');
    expect(find.textContaining('Zapisałem zgłoszenie dla twórcy aplikacji'),
        findsOneWidget);
    expect(find.textContaining('Podaj jedną dodatnią wartość'), findsNothing,
        reason: 'a report is not a slope calculation');
    expect(aiCalls, 0, reason: 'an explicit report needs no paid AI call');
    final signals = await t.runAsync(() => FeedbackStore.instance.list());
    expect(signals!.single.kind, FeedbackKind.explicit);
  });

  testWidgets('a complaint the model cannot act on is logged as a complaint',
      (t) async {
    var aiCalls = 0;
    await mount(t, interpret: (_) async {
      aiCalls++;
      return const AiCommandPlan('unsupported', [], refusal);
    });
    await say(t, 'ta aplikacja jest bez sensu, nic nie daje');
    expect(aiCalls, 1, reason: 'a complaint still goes through the model');
    expect(find.textContaining('Zapisałem zgłoszenie na tym telefonie'),
        findsOneWidget);
    final signals = await t.runAsync(() => FeedbackStore.instance.list());
    expect(signals!.single.kind, FeedbackKind.complaint);
  });

  testWidgets('an ordinary unsupported request keeps the model reply',
      (t) async {
    await mount(t,
        interpret: (_) async => const AiCommandPlan(
            'unsupported', [], 'Nie zamawiam jedzenia — to aplikacja spawalnicza.'));
    await say(t, 'zamów mi pizzę z dostawą');
    expect(find.textContaining('Nie zamawiam jedzenia'), findsOneWidget);
    expect(find.textContaining('Zapisałem zgłoszenie'), findsNothing);
    final signals = await t.runAsync(() => FeedbackStore.instance.list());
    expect(signals!.single.kind, FeedbackKind.notUnderstood);
  });
}
