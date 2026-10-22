import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/core/account_navigation_skill.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/account_screen.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'ai_pending_task_switch_test.dart' show newDrawing, pendingPlan;

const profileRequest = 'Przejdźmy teraz do mojego profilu zawodowego';
const profilePlan = AiCommandPlan(
    'execute', [AiCommandStep('account.open', 'Otwórz ustawienia konta')], '');
const registrationRequest = 'Potrzebuję formularza do założenia konta';
const registrationPlan = AiCommandPlan(
    'execute', [AiCommandStep('account.open', 'Utwórz konto')], '');
void main() {
  useTestDatabase();
  useGuestAccount();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  test(
      'source guard keeps registration separate from account/profile and rejects mutations',
      () {
    final skill = AccountNavigationSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    for (final request in [
      profileRequest,
      'Could you please open my professional profile',
      'Chce uzupelnic moj profil zawodowy'
    ]) {
      expect(
          skill.acceptsProposal(u(request), u('Otworz ustawienia konta'), ctx),
          true);
      expect(skill.acceptsProposal(u(request), u('Utworz konto'), ctx), false);
    }
    expect(
        skill.acceptsProposal(u(registrationRequest), u('Utworz konto'), ctx),
        true);
    expect(
        skill.acceptsProposal(
            u(registrationRequest), u('Otworz ustawienia konta'), ctx),
        false);
    for (final request in [
      'Usun moje konto',
      'Nie zakladaj mi konta',
      'Przetlumacz create an account',
      'Ustaw mi uprawnienia administratora',
      'Zmien haslo konta na test123',
      'Chce uzupelnic profil zawodowy stempel ABC',
      'Open steel profiles',
      'Ile wazy profil stalowy'
    ]) {
      expect(skill.acceptsProposal(u(request), u('Utworz konto'), ctx), false,
          reason: request);
      expect(
          skill.acceptsProposal(u(request), u('Otworz ustawienia konta'), ctx),
          false,
          reason: request);
    }
  });
  for (final registering in [false, true]) {
    testWidgets(
        'natural phone request opens the correct credential form without signing in or creating an account registration=$registering',
        (t) async {
      final speech = FixtureSpeech();
      var calls = 0;
      await mount(t, speech: speech, interpret: (request) async {
        calls++;
        final caps = request['capabilities'] as List;
        expect(caps, hasLength(1));
        expect((caps.single as Map)['id'], 'account.open');
        return registering ? registrationPlan : profilePlan;
      });
      final revision = AccountService.instance.sessionRevision;
      await t.tap(find.byKey(const Key('assistant-mic')));
      await settle(t);
      speech.emit(registering ? registrationRequest : profileRequest);
      await settle(t);
      expect(calls, 1);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(
          find.widgetWithText(
              FilledButton, registering ? 'Załóż konto' : 'Zaloguj się'),
          findsOneWidget);
      expect(AccountService.instance.account, isNull);
      expect(AccountService.instance.sessionRevision, revision);
      expect(appRoutes.assistantAvailable, false);
      expect(ToolBridge.instance.inputFields('account'), isNull);
    });
  }
  for (final fail in [false, true]) {
    testWidgets(
        'wrong account destination or outage preserves pending ISO question and queued steps outage=$fail',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (request) async {
        if (++calls == 1) return pendingPlan;
        expect((request['capabilities'] as List), hasLength(1));
        expect((request['context'] as Map)['pending_reply'], isNull);
        if (fail) throw const AssistantAiUnavailable(503);
        return registrationPlan;
      });
      await say(t, 'Narysuj rura metr w prawo kolano DN50 w gore rura metr');
      final c = IsoNotebookController.active!;
      for (var i = 0; i < 12 && c.isBusy; i++) {
        await settle(t);
      }
      await say(t, newDrawing);
      expect(find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
      final revision = c.revision;
      await say(t, profileRequest);
      expect(calls, 2);
      expect(find.byType(AccountScreen), findsNothing);
      expect(c.revision, revision);
      expect(find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
      await say(t, 'Dorysuj');
      for (var i = 0; i < 12 && c.isBusy; i++) {
        await settle(t);
      }
      await settle(t);
      expect(c.summary!.pipeCount, 4);
      expect(calls, 2);
    });
  }
  testWidgets(
      'valid account switch cancels the old queued drawing and hides assistant on the form',
      (t) async {
    var calls = 0;
    await mount(t,
        interpret: (_) async => ++calls == 1 ? pendingPlan : profilePlan);
    await say(t, 'Narysuj rura metr w prawo kolano DN50 w gore rura metr');
    final c = IsoNotebookController.active!;
    for (var i = 0; i < 12 && c.isBusy; i++) {
      await settle(t);
    }
    await say(t, newDrawing);
    final revision = c.revision;
    await say(t, profileRequest);
    expect(calls, 2);
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(c.revision, revision);
    expect(c.summary!.pipeCount, 2);
    expect(appRoutes.assistantAvailable, false);
  });
  testWidgets(
      'signed-in user sees actual saved professional profile without a profile update request',
      (t) async {
    final previous = AccountService.instance;
    var accountCalls = 0;
    final client = MockClient((request) async {
      accountCalls++;
      expectSync(request.url.path.endsWith('/login'), true);
      return http.Response(
          jsonEncode({
            'token': 'fixture-token',
            'account': {
              'id': 'profile-fixture',
              'email': 'profile@example.invalid',
              'role': 'user',
              'displayName': 'Test Spawacz',
              'profession': 'Spawacz',
              'qualifications': 'TIG 141',
              'stamp': 'FWP-TEST',
              'experienceYears': 8,
              'processes': ['TIG'],
            }
          }),
          200);
    });
    final account = AccountService.forTesting(client);
    AccountService.instance = account;
    addTearDown(() {
      AccountService.instance = previous;
      account.dispose();
      client.close();
    });
    var done = false;
    Object? error;
    final login =
        account.signIn('profile@example.invalid', 'fixture-password').then((_) {
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    });
    for (var i = 0; i < 60 && !done; i++) {
      await t.pump(const Duration(milliseconds: 1));
    }
    expect(done, true);
    if (error != null) throw error!;
    await login;
    final revision = account.sessionRevision;
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return profilePlan;
    });
    await say(t, profileRequest);
    expect(calls, 1);
    expect(accountCalls, 1);
    expect(find.byType(AccountScreen), findsOneWidget);
    final texts = t
        .widgetList<TextField>(find.byType(TextField))
        .map((w) => w.controller?.text)
        .toList();
    expect(texts, containsAll(['Spawacz', 'TIG 141', 'FWP-TEST']));
    expect(account.account?['id'], 'profile-fixture');
    expect(account.sessionRevision, revision);
    expect(appRoutes.assistantAvailable, false);
    expect(ToolBridge.instance.inputFields('account'), isNull);
  });
}
