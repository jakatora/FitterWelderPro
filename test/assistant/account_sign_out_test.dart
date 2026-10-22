import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/core/account_sign_out_skill.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'ai_pending_task_switch_test.dart' show newDrawing, pendingPlan;

const natural = 'Chciałbym się teraz wylogować';
const logoutPlan = AiCommandPlan(
    'execute', [AiCommandStep('account.sign_out', 'Wyloguj mnie')], '');
Future<void> finish(WidgetTester t, Future<void> operation) async {
  var done = false;
  Object? error;
  final observed = operation.then((_) => done = true, onError: (Object e) {
    error = e;
    done = true;
  });
  for (var i = 0; i < 80 && !done; i++) {
    await t.pump(const Duration(milliseconds: 1));
  }
  expect(done, true);
  if (error != null) throw error!;
  await observed;
}

Finder actScroll() => find
    .descendant(
        of: find.byType(AiChatScreen).last,
        matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down))
    .first;
Future<void> tapControl(WidgetTester t, String key,
    {bool settleAfter = true}) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(f, -100, scrollable: actScroll());
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  if (settleAfter) await settle(t);
}

Future<void> confirm(WidgetTester t) => tapControl(t, 'assistant-local-save');

void main() {
  useTestDatabase();
  late AccountService account;
  late MockClient client;
  late List<http.Request> requests;
  var logoutStatus = 200;
  Completer<http.Response>? deferred;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    requests = [];
    logoutStatus = 200;
    deferred = null;
    final previous = AccountService.instance;
    client = MockClient((r) async {
      requests.add(r);
      if (r.url.path.endsWith('/logout')) {
        if (deferred != null) return deferred!.future;
        return http.Response(
            logoutStatus == 200
                ? '{}'
                : jsonEncode({
                    'error': {'message': 'Fixture unavailable'}
                  }),
            logoutStatus,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      expectSync(r.url.path.endsWith('/login'), true);
      final email = (jsonDecode(r.body) as Map)['email'] as String;
      return http.Response(
          jsonEncode({
            'token': 'fixture-token-$email',
            'account': {
              'id': email,
              'email': email,
              'displayName': 'Fixture Account',
              'role': 'user'
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    account = AccountService.forTesting(client);
    AccountService.instance = account;
    addTearDown(() {
      AccountService.instance = previous;
      account.dispose();
      client.close();
    });
  });
  int logoutCalls() =>
      requests.where((r) => r.url.path.endsWith('/logout')).length;
  Future<void> login(WidgetTester t, [String email = 'a@example.invalid']) =>
      finish(t, account.signIn(email, 'fixture-password'));
  test('only an explicit own sign-out source can authorize the native proposal',
      () {
    final skill = AccountSignOutSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String s) => Utterance(s, lang: AppLanguage.pl);
    for (final source in [
      'Wyloguj mnie',
      natural,
      'Could you please sign me out',
      'I would like to log out'
    ]) {
      expect(skill.acceptsProposal(u(source), u('Wyloguj mnie'), ctx), true);
      expect(skill.aiTaskSwitchCommands(u(source), ctx), hasLength(1));
    }
    for (final source in [
      'Nie wylogowuj mnie',
      'Jak się wylogować',
      'Usuń konto',
      'Wyloguj innego użytkownika',
      'Przetłumacz sign me out',
      'Wyloguj mnie i usuń konto'
    ]) {
      expect(skill.acceptsProposal(u(source), u('Wyloguj mnie'), ctx), false,
          reason: source);
    }
  });
  testWidgets(
      'guest sign-out remains local and never claims a new completed logout',
      (t) async {
    await mount(t, interpret: (_) async => throw StateError('No AI expected'));
    await say(t, 'Wyloguj mnie');
    expect(logoutCalls(), 0);
    expect(find.textContaining('Nie ma aktywnej sesji'), findsWidgets);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
  });
  for (final voice in [false, true]) {
    testWidgets(
        'native sign-out needs confirmation, ends only its session and clears private chat voice=$voice',
        (t) async {
      await login(t);
      final revision = account.sessionRevision;
      var aiCalls = 0;
      final speech = FixtureSpeech();
      await mount(t,
          speech: speech,
          interpret: (r) async {
            aiCalls++;
            if (aiCalls == 1) return const AiCommandPlan('answer', [], '');
            expectSync(jsonEncode(r), isNot(contains('FixturePrivate')));
            expectSync(
                jsonEncode(r), isNot(contains('Fixture private answer')));
            return const AiCommandPlan('clarify', [], 'Doprecyzuj.');
          },
          chatSender: (_, __) async => ChatMessage(
              role: ChatRole.assistant,
              text: 'Fixture private answer',
              kind: AiReplyKind.live));
      await say(t, 'Pomóż mi z prywatnym tematem FixturePrivate');
      expect(find.text('Fixture private answer'), findsOneWidget);
      if (voice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit('Wyloguj mnie');
        await settle(t);
      } else {
        await say(t, 'Wyloguj mnie');
      }
      expect(logoutCalls(), 0);
      expect(account.account, isNotNull);
      expect(find.text('Wyloguj'), findsOneWidget);
      expect(find.text('Zapisz'), findsNothing);
      if (voice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit('Tak wyloguj');
        await settle(t);
      } else {
        await confirm(t);
      }
      expect(logoutCalls(), 1);
      expect(account.account, isNull);
      expect(account.sessionRevision, revision + 1);
      expect(account.localOwnerId, isNull);
      expect(find.textContaining('Wylogowano.'), findsWidgets);
      expect(find.text('Zapisano.'), findsNothing);
      expect(aiCalls, 1);
      await say(t, 'Pomóż mi zacząć nową rozmowę');
      expect(aiCalls, 2);
      final headers = await account.headers();
      expect(headers, isEmpty);
    });
  }
  for (final voice in [false, true]) {
    testWidgets(
        'cancel own sign-out keeps current session without a logout request voice=$voice',
        (t) async {
      await login(t);
      final revision = account.sessionRevision;
      await mount(t,
          interpret: (_) async => throw StateError('No AI expected'));
      await say(t, 'Wyloguj mnie');
      if (voice) {
        await say(t, 'nie');
      } else {
        await tapControl(t, 'assistant-local-cancel');
      }
      expect(logoutCalls(), 0);
      expect(account.account!['id'], 'a@example.invalid');
      expect(account.sessionRevision, revision);
      expect(find.text('Anulowano wylogowanie.'), findsOneWidget);
    });
  }
  testWidgets(
      'source-backed natural request uses one bounded AI capability before native confirmation',
      (t) async {
    await login(t);
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      final caps = r['capabilities'] as List;
      expectSync(caps, hasLength(1));
      expectSync((caps.single as Map)['id'], 'account.sign_out');
      expectSync((caps.single as Map)['read_only'], false);
      File('build/assistant-account-signout-wire.json')
          .writeAsStringSync(jsonEncode(r));
      return logoutPlan;
    });
    await say(t, natural);
    expect(calls, 1);
    expect(logoutCalls(), 0);
    expect(find.text('Wyloguj'), findsOneWidget);
    await say(t, 'tak');
    expect(logoutCalls(), 1);
    expect(calls, 1);
    expect(account.account, isNull);
  });
  testWidgets(
      'logout failure stays retryable and does not claim saved or signed out',
      (t) async {
    await login(t);
    logoutStatus = 500;
    final revision = account.sessionRevision;
    await mount(t, interpret: (_) async => throw StateError('No AI expected'));
    await say(t, 'Wyloguj mnie');
    await confirm(t);
    expect(logoutCalls(), 1);
    expect(account.sessionRevision, revision);
    expect(account.account, isNotNull);
    await t.scrollUntilVisible(
        find.textContaining('Nie udało się potwierdzić wylogowania'), 100,
        scrollable: actScroll());
    expect(find.textContaining('Nie udało się potwierdzić wylogowania'),
        findsWidgets);
    expect(find.text('Zapisano.'), findsNothing);
    logoutStatus = 200;
    await confirm(t);
    expect(logoutCalls(), 2);
    expect(account.account, isNull);
    expect(find.textContaining('Wylogowano.'), findsWidgets);
  });
  testWidgets(
      'voice cancellation after an uncertain failure cancels retries without claiming server logout was undone',
      (t) async {
    await login(t);
    logoutStatus = 500;
    await mount(t, interpret: (_) async => throw StateError('No AI expected'));
    await say(t, 'Wyloguj mnie');
    await confirm(t);
    await say(t, 'nie');
    expect(logoutCalls(), 1);
    expect(find.textContaining('Anulowano dalsze próby wylogowania'),
        findsWidgets);
    expect(find.text('Anulowano wylogowanie.'), findsNothing);
  });
  testWidgets(
      'account data preparation failure stops before logout HTTP and can be retried',
      (t) async {
    await login(t);
    var prepares = 0, releases = 0;
    var fail = true;
    Future<VoidCallback> prepare() async {
      prepares++;
      if (fail) throw AccountException('Fixture unsaved');
      return () => releases++;
    }

    account.addSessionPreparer(prepare);
    addTearDown(() => account.removeSessionPreparer(prepare));
    await mount(t, interpret: (_) async => throw StateError('No AI expected'));
    await say(t, 'Wyloguj mnie');
    await confirm(t);
    expect(prepares, 1);
    expect(logoutCalls(), 0);
    expect(account.account, isNotNull);
    fail = false;
    await confirm(t);
    expect(prepares, 2);
    expect(releases, 1);
    expect(logoutCalls(), 1);
    expect(account.account, isNull);
  });
  testWidgets('stale native confirmation cannot log out a replacement account',
      (t) async {
    await login(t);
    final skill = AccountSignOutSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final u = Utterance('Wyloguj mnie', lang: AppLanguage.pl);
    final pending = await skill.run(skill.match(u, ctx)!, ctx)
        as AccountSignOutConfirmation;
    await login(t, 'b@example.invalid');
    await expectLater(pending.perform(), throwsA(isA<AccountException>()));
    expect(logoutCalls(), 0);
    expect(account.account!['id'], 'b@example.invalid');
    expect(pending.completedForCurrentGuest, false);
  });
  testWidgets(
      'sign-out interrupts a real pending ISO task and drops its queued remainder',
      (t) async {
    await t
        .runAsync(() async => (await AppDatabase.get()).delete('iso_drawings'));
    await login(t);
    var calls = 0;
    await mount(t, interpret: (request) async {
      if (++calls == 1) return pendingPlan;
      expect(
          (request['capabilities'] as List).single['id'], 'account.sign_out');
      expect((request['context'] as Map)['pending_reply'], isNull);
      return logoutPlan;
    });
    await say(t, 'Narysuj rura metr w prawo kolano DN50 w gore rura metr');
    final drawing = IsoNotebookController.active!;
    for (var i = 0; i < 12 && drawing.isBusy; i++) {
      await settle(t);
    }
    await say(t, newDrawing);
    expect(find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
    expect(drawing.summary!.pipeCount, 2);
    await say(t, natural);
    expect(calls, 2);
    expect(find.textContaining('Na arkuszu jest już rysunek'), findsNothing);
    expect(drawing.summary!.pipeCount, 2);
    await confirm(t);
    expect(logoutCalls(), 1);
    expect(account.account, isNull);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    expect(find.textContaining('Wylogowano.'), findsWidgets);
    await login(t);
    await settle(t);
    await say(t, 'Otwórz rysunek ISO');
    await settle(t);
    expect(IsoNotebookController.active!.summary!.pipeCount, 2);
    expect(calls, 2);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'late logout response cannot clear a newer signed-in session or publish its success',
      (t) async {
    await login(t);
    deferred = Completer<http.Response>();
    await mount(t, interpret: (_) async => throw StateError('No AI expected'));
    await say(t, 'Wyloguj mnie');
    await tapControl(t, 'assistant-local-save', settleAfter: false);
    for (var i = 0; i < 40 && logoutCalls() == 0; i++) {
      await t.pump(const Duration(milliseconds: 1));
    }
    expect(logoutCalls(), 1);
    await login(t, 'b@example.invalid');
    deferred!.complete(http.Response('{}', 200));
    await settle(t);
    expect(account.account!['id'], 'b@example.invalid');
    expect((await account.headers())['Authorization'],
        'Bearer fixture-token-b@example.invalid');
    expect(find.textContaining('Wylogowano.'), findsNothing);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
  });
}
