import 'package:cut_list_app/services/ai_chat_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/professional_profile_edit.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/core/professional_profile_edit_skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/account_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/ai_professional_context.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'account_sign_out_test.dart' show finish, confirm, tapControl;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const command = 'Ustaw w moim profilu doświadczenie na 8 lat';
const natural = 'Mam 8 lat doświadczenia, wpisz to w moim profilu';
const plan = AiCommandPlan(
    'execute', [AiCommandStep('account.professional.edit', command)], '');
const fixture = <String, dynamic>{
  'id': 'A',
  'email': 'private@example.invalid',
  'role': 'user',
  'displayName': 'Private name',
  'profession': 'Spawacz',
  'experienceYears': 4,
  'processes': ['141'],
  'qualifications': 'Private qualifications',
  'stamp': 'Private stamp',
  'publicProfile': false
};
void main() {
  useTestDatabase();
  late AccountService account;
  late Map<String, dynamic> stored;
  late List<http.Request> writes;
  var status = 200, wrongAck = false;
  setUp(() {
    stored = {...fixture};
    writes = [];
    status = 200;
    wrongAck = false;
    AiProfessionalContext.instance.resetForTest();
    FlutterSecureStorage.setMockInitialValues({});
    final previous = AccountService.instance;
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/login')) {
        if ((jsonDecode(r.body) as Map)['email'] == 'other@example.invalid') {
          stored = {...fixture, 'id': 'B', 'email': 'other@example.invalid'};
        }
        return http.Response(
            jsonEncode({'token': 'fixture-token', 'account': stored}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (r.method == 'GET' && r.url.path.endsWith('/me')) {
        return http.Response(jsonEncode({'account': stored}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      expectSync(r.url.path.endsWith('/profile/assistant'), true);
      writes.add(r);
      final body = jsonDecode(r.body) as Map;
      expectSync(body.keys.toSet(), {'field', 'value', 'expected'});
      if (status != 200) return http.Response('{}', status);
      bool same(Object? a, Object? b) => a is List && b is List
          ? jsonEncode(a.cast<String>().toList()..sort()) ==
              jsonEncode(b.cast<String>().toList()..sort())
          : a == b;
      if (!same(stored[body['field']], body['expected']) &&
          !same(stored[body['field']], body['value'])) {
        return http.Response('{}', 409);
      }
      if (!wrongAck) {
        stored = {...stored, body['field'] as String: body['value']};
      }
      return http.Response(jsonEncode({'account': stored}), 200,
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
  Future<void> login(WidgetTester t) =>
      finish(t, account.signIn('private@example.invalid', 'fixture-password'));
  Finder professionField() => find.byWidgetPredicate((w) =>
      w is TextField &&
      w.decoration?.labelText == 'Zawód (np. spawacz, monter)');
  test('only literal source-backed profession or experience may be proposed',
      () {
    final s = ProfessionalProfileEditSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String s) => Utterance(s, lang: AppLanguage.pl);
    expect(s.acceptsProposal(u(natural), u(command), ctx), true);
    expect(
        s.acceptsProposal(u('Put my profession in my profile as pipe fitter'),
            u('Set my profile profession to pipe fitter'), ctx),
        true);
    for (final source in [
      'Mam 12 lat doświadczenia, wpisz to w moim profilu',
      'Ustaw rolę administratora',
      'Włącz publiczny profil',
      'Jak zmienić doświadczenie',
      'Nie ustawiaj doświadczenia na 8 lat',
      'Ustaw w moim profilu zawód na hasło abc123456'
    ]) {
      expect(s.acceptsProposal(u(source), u(command), ctx), false,
          reason: source);
    }
    expect(
        s.acceptsProposal(
            u(natural), u('Ustaw w moim profilu zawód na Monter'), ctx),
        false);
  });
  for (final voice in [false, true]) {
    testWidgets(
        'natural profile edit opens a credential-free form and writes only after confirmation voice=$voice',
        (t) async {
      await login(t);
      var calls = 0;
      final speech = FixtureSpeech();
      await mount(t, speech: speech, interpret: (r) async {
        calls++;
        expect((r['capabilities'] as List).single['id'],
            'account.professional.edit');
        expect(jsonEncode(r), isNot(contains('Private stamp')));
        File('build/assistant-professional-profile-wire.json')
            .writeAsStringSync(jsonEncode(r));
        return plan;
      });
      if (voice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit(natural);
        await settle(t);
      } else {
        await say(t, natural);
      }
      expect(calls, 1);
      expect(writes, isEmpty);
      expect(appRoutes.assistantAvailable, true);
      expect(ToolBridge.instance.activeToolId, 'professional_profile');
      expect(ToolBridge.instance.inputFields('professional_profile'), isNull);
      expect(find.byWidgetPredicate((w) => w is TextField && w.obscureText),
          findsNothing);
      expect(find.text('E-mail'), findsNothing);
      expect(find.text('Usuń konto'), findsNothing);
      expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
      stored = {...stored, 'stamp': 'Concurrent other-device stamp'};
      if (voice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit('Tak');
        await settle(t);
      } else {
        await confirm(t);
      }
      expect(writes, hasLength(1));
      File('build/assistant-professional-profile-write.json')
          .writeAsStringSync(writes.single.body);
      expect(jsonDecode(writes.single.body),
          {'field': 'experienceYears', 'value': 8, 'expected': 4});
      expect(account.account!['experienceYears'], 8);
      expect(account.account!['stamp'], 'Concurrent other-device stamp');
      expect(account.account!['role'], 'user');
      expect(account.account!['publicProfile'], false);
      expect(find.text('Zapisano.'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'canonical profession remains local and cancellation performs no write',
      (t) async {
    await login(t);
    await mount(t, interpret: (_) async => throw StateError('Local command'));
    await say(t, 'Ustaw w moim profilu zawód na Monter rurociągów');
    expect(writes, isEmpty);
    await tapControl(t, 'assistant-local-cancel');
    expect(writes, isEmpty);
    expect(account.account!['profession'], 'Spawacz');
  });
  for (final failure in ['http', 'ack', 'conflict']) {
    testWidgets(
        'profile save never claims success before confirmed server result failure=$failure',
        (t) async {
      await login(t);
      await mount(t, interpret: (_) async => plan);
      await say(t, natural);
      if (failure == 'http') status = 500;
      if (failure == 'ack') wrongAck = true;
      if (failure == 'conflict') stored = {...stored, 'experienceYears': 12};
      await confirm(t);
      expect(writes, hasLength(1));
      expect(find.text('Zapisano.'), findsNothing);
      expect(account.account!['experienceYears'], 4);
      expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('manual edit after the summary invalidates its prepared save',
      (t) async {
    await login(t);
    await mount(t, interpret: (_) async => plan);
    await say(t, natural);
    await t.enterText(professionField(), 'Manual draft');
    await t.pump();
    await confirm(t);
    expect(writes, isEmpty);
    expect(t.widget<TextField>(professionField()).controller!.text,
        'Manual draft');
    expect(find.text('Zapisano.'), findsNothing);
  });
  testWidgets(
      'profile draft stays native and is never silently included in a prepared change',
      (t) async {
    await login(t);
    await mount(t,
        home: const AccountScreen(professionalOnly: true),
        interpret: (_) async => plan);
    await t.enterText(professionField(), 'Manual draft');
    await t.pump();
    final handle =
        ToolBridge.instance.current! as ProfessionalProfileEditorHandle;
    final result = handle.prepareProfessionalProfileEdit(
        const ProfessionalProfilePatch.experience(8));
    expect(result, isA<AnswerResult>());
    expect((result as AnswerResult).actionCompleted, false);
    expect(writes, isEmpty);
    expect(account.account!['profession'], 'Spawacz');
    expect(ToolBridge.instance.inputFields('professional_profile'), isNull);
    await expectLater(account.signOut(), throwsA(isA<AccountException>()));
    expect(account.account!['id'], 'A');
    expect(t.widget<TextField>(professionField()).controller!.text,
        'Manual draft');
  });
  testWidgets(
      'confirmed profession is persisted and invalidates only enabled AI profile captures',
      (t) async {
    await login(t);
    await mount(t, interpret: (_) async => throw StateError('Local command'));
    final disabled = await AiProfessionalContext.instance.capture();
    await say(t, 'Ustaw w moim profilu zawód na Monter rurociągów');
    await confirm(t);
    expect(account.account!['profession'], 'Monter rurociągów');
    expect(jsonDecode(writes.single.body), {
      'field': 'profession',
      'value': 'Monter rurociągów',
      'expected': 'Spawacz'
    });
    expect(disabled.requireCurrent, returnsNormally);
    await AiProfessionalContext.instance.setEnabled(true);
    final enabled = await AiProfessionalContext.instance.capture();
    await say(t, command);
    await confirm(t);
    expect(enabled.requireCurrent, throwsA(isA<AccountException>()));
    expect(account.account!['experienceYears'], 8);
  });
  testWidgets(
      'a prepared profile confirmation cannot cross a later account switch',
      (t) async {
    await login(t);
    await mount(t,
        home: const AccountScreen(professionalOnly: true),
        interpret: (_) async => plan);
    final handle =
        ToolBridge.instance.current! as ProfessionalProfileEditorHandle;
    final prepared = handle.prepareProfessionalProfileEdit(
        const ProfessionalProfilePatch.experience(8)) as ConfirmResult;
    await finish(
        t, account.signIn('other@example.invalid', 'fixture-password'));
    await settle(t);
    await expectLater(prepared.perform(), throwsA(isA<AccountException>()));
    expect(account.account!['id'], 'B');
    expect(writes, isEmpty);
  });
  testWidgets(
      'server conflict can be reloaded and a newly reviewed change uses its latest value',
      (t) async {
    await login(t);
    await mount(t, interpret: (_) async => plan);
    await say(t, natural);
    stored = {...stored, 'experienceYears': 12};
    await confirm(t);
    expect(account.account!['experienceYears'], 4);
    await say(t, 'anuluj');
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    final reload = find.byKey(const Key('professional-profile-reload'));
    await t.scrollUntilVisible(reload, 200,
        scrollable: find
            .descendant(
                of: find.byType(AccountScreen).last,
                matching: find.byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down))
            .first);
    await t.ensureVisible(reload);
    await t.tap(reload);
    await settle(t);
    expect(account.account!['experienceYears'], 12);
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    await say(t, natural);
    await confirm(t);
    expect(writes, hasLength(2));
    expect(jsonDecode(writes.last.body)['expected'], 12);
    expect(account.account!['experienceYears'], 8);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'help with my profile opens the professional form with the global conversation available',
      (t) async {
    await login(t);
    await mount(t,
        interpret: (_) async => const AiCommandPlan(
            'execute',
            [
              AiCommandStep(
                  'account.open', 'Edytuj profil zawodowy z asystentem')
            ],
            ''));
    await say(t, 'Pomóż mi uzupełnić mój profil zawodowy');
    expect(ToolBridge.instance.activeToolId, 'professional_profile');
    expect(appRoutes.assistantAvailable, true);
    expect(find.byWidgetPredicate((w) => w is TextField && w.obscureText),
        findsNothing);
    expect(writes, isEmpty);
    expect(t.takeException(), isNull);
  });
  test('new fields preserve the field, literal content and process operation',
      () {
    final skill = ProfessionalProfileEditSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String s) => Utterance(s, lang: AppLanguage.pl);
    for (final pair in [
      ('Dodaj TIG do mojego profilu', 'Dodaj w moim profilu procesy 141'),
      ('Usuń 111 z mojego profilu', 'Usuń w moim profilu procesy 111'),
      (
        'Wpisz w moim profilu procesy TIG i MMA',
        'Ustaw w moim profilu procesy na 111 i 141'
      ),
      (
        'Wpisz w moim profilu stempel "AB.7?"',
        'Set my profile stamp to "AB.7?"'
      ),
      (
        'Wpisz w moim profilu kwalifikacje "Szkolenie TIG, grupa A."',
        'Ustaw w moim profilu kwalifikacje na "Szkolenie TIG, grupa A."'
      ),
      (
        'Ustaw w moim profilu procesy na MAG135',
        'Set my profile processes to 135'
      ),
    ]) {
      expect(skill.acceptsProposal(u(pair.$1), u(pair.$2), ctx), true,
          reason: pair.$1);
      expect(skill.aiTaskSwitchCommands(u(pair.$1), ctx), hasLength(1));
    }
    for (final pair in [
      ('Dodaj TIG do mojego profilu', 'Ustaw w moim profilu procesy na 141'),
      ('Usuń 111 z mojego profilu', 'Wyczyść w moim profilu procesy'),
      ('Dodaj MAG do mojego profilu', 'Dodaj w moim profilu procesy 135'),
      (
        'Ustaw w moim profilu procesy na TIG 135',
        'Ustaw w moim profilu procesy na 135 i 141'
      ),
      ('Wpisz w moim profilu stempel "AB.7?"', 'Set my profile stamp to "AB7"'),
      (
        'Wpisz w moim profilu kwalifikacje "Szkolenie TIG"',
        'Set my profile qualifications to "Certified TIG welder"'
      ),
      ('Nie wyczyść w moim profilu stempel', 'Clear my profile stamp'),
    ]) {
      expect(skill.acceptsProposal(u(pair.$1), u(pair.$2), ctx), false,
          reason: pair.$1);
    }
    final values = ['141'];
    final patch = ProfessionalProfilePatch.processes(values,
        operation: ProfileProcessEdit.add);
    values.add('111');
    expect(patch.fields['processes'], ['141']);
    expect(
        patch.resolve({
          'processes': ['135']
        }),
        {
          'processes': ['135', '141']
        });
  });
  for (final row in <(String, String, String, String, Object)>[
    (
      'add',
      'Dodaj TIG do mojego profilu',
      'Dodaj w moim profilu procesy 141',
      'processes',
      ['111', '135', '141']
    ),
    (
      'remove',
      'Usuń 111 z mojego profilu',
      'Usuń w moim profilu procesy 111',
      'processes',
      ['135']
    ),
    (
      'replace',
      'Wpisz w moim profilu procesy TIG i MMA',
      'Ustaw w moim profilu procesy na 111 i 141',
      'processes',
      ['111', '141']
    ),
    (
      'qualifications',
      'Wpisz w moim profilu kwalifikacje "Szkolenie TIG, grupa A."',
      'Ustaw w moim profilu kwalifikacje na "Szkolenie TIG, grupa A."',
      'qualifications',
      'Szkolenie TIG, grupa A.'
    ),
    (
      'stamp',
      'Wpisz w moim profilu stempel "AB.7?"',
      'Ustaw w moim profilu stempel na "AB.7?"',
      'stamp',
      'AB.7?'
    ),
  ]) {
    testWidgets(
        'confirmed professional field update uses native values and a narrow write: ${row.$1}',
        (t) async {
      stored = {
        ...stored,
        'processes': ['135', '111']
      };
      await login(t);
      var calls = 0;
      final speech = FixtureSpeech();
      await mount(t, speech: speech, interpret: (request) async {
        if (++calls > 1) {
          final context = jsonEncode(request['context']);
          expect(context, isNot(contains('135')));
          expect(context, isNot(contains('Private qualifications')));
          expect(context, isNot(contains('Private stamp')));
          return const AiCommandPlan('clarify', [], 'Doprecyzuj pytanie.');
        }
        final cap = (request['capabilities'] as List).single as Map;
        expect(cap['professional_profile_fields'], [
          'profession',
          'experienceYears',
          'processes',
          'qualifications',
          'stamp'
        ]);
        File('build/assistant-professional-${row.$1}-wire.json')
            .writeAsStringSync(jsonEncode(request));
        return AiCommandPlan('execute',
            [AiCommandStep('account.professional.edit', row.$3)], '');
      });
      final byVoice = row.$1 == 'add' || row.$1 == 'stamp';
      if (byVoice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit(row.$2);
        await settle(t);
      } else {
        await say(t, row.$2);
      }
      expect(calls, 1);
      expect(writes, isEmpty);
      expect(ToolBridge.instance.inputFields('professional_profile'), isNull);
      if (byVoice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit('Tak');
        await settle(t);
      } else {
        await confirm(t);
      }
      expect(writes, hasLength(1));
      final body = jsonDecode(writes.single.body) as Map;
      expect(body['field'], row.$4);
      expect(body['value'], row.$5);
      expect(account.account![row.$4], row.$5);
      expect(account.account!['profession'], 'Spawacz');
      expect(account.account!['role'], 'user');
      expect(account.account!['publicProfile'], false);
      File('build/assistant-professional-${row.$1}-write.json')
          .writeAsStringSync(writes.single.body);
      expect(find.text('Zapisano.'), findsWidgets);
      if (row.$1 == 'add') {
        await say(t, 'Pomóż mi z innym pytaniem');
        expect(calls, 2);
      }
      expect(t.takeException(), isNull);
    });
  }
  for (final pair in <(String, String, Object)>[
    ('zawód', 'profession', ''),
    ('kwalifikacje', 'qualifications', ''),
    ('stempel', 'stamp', ''),
    ('procesy', 'processes', <String>[]),
  ]) {
    testWidgets(
        'clearing only the explicitly selected professional field needs confirmation: ${pair.$1}',
        (t) async {
      await login(t);
      await mount(t,
          interpret: (_) async => throw StateError('Exact clear stays local'));
      await say(t, 'Wyczyść w moim profilu ${pair.$1}');
      expect(writes, isEmpty);
      await confirm(t);
      expect(writes, hasLength(1));
      expect(account.account![pair.$2], pair.$3);
      File('build/assistant-professional-clear-${pair.$2}-write.json')
          .writeAsStringSync(writes.single.body);
      expect(account.account!['role'], 'user');
      expect(account.account!['publicProfile'], false);
      expect(t.takeException(), isNull);
    });
  }
  for (final fail in ['ack', 'conflict']) {
    testWidgets(
        'a process write cannot claim success after a mismatched ack or concurrent set edit: $fail',
        (t) async {
      stored = {
        ...stored,
        'processes': ['111', '135']
      };
      await login(t);
      await mount(t,
          interpret: (_) async => const AiCommandPlan(
              'execute',
              [
                AiCommandStep('account.professional.edit',
                    'Dodaj w moim profilu procesy 141')
              ],
              ''));
      await say(t, 'Dodaj TIG do mojego profilu');
      if (fail == 'ack') {
        wrongAck = true;
      } else {
        stored = {
          ...stored,
          'processes': ['135', '141']
        };
      }
      await confirm(t);
      expect(writes, hasLength(1));
      expect(find.text('Zapisano.'), findsNothing);
      expect(account.account!['processes'], ['111', '135']);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'a short MAG code reply completes the original AI-normalized add without repeating the request',
      (t) async {
    await login(t);
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      File('build/assistant-professional-mag-wire.json')
          .writeAsStringSync(jsonEncode(r));
      return AiCommandPlan(
          'execute',
          [
            AiCommandStep(
                'account.professional.edit',
                calls == 1
                    ? 'Dodaj w moim profilu procesy MAG'
                    : 'Dodaj w moim profilu procesy 135')
          ],
          '');
    });
    await say(t, 'Dodaj MAG do mojego profilu');
    expect(writes, isEmpty);
    await say(t, '135');
    expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
    expect(writes, isEmpty);
    await confirm(t);
    expect(account.account!['processes'], ['135', '141']);
    expect(writes, hasLength(1));
    File('build/assistant-professional-mag-write.json')
        .writeAsStringSync(writes.single.body);
    expect(calls, 1);
    expect(t.takeException(), isNull);
  });
  test(
      'MAG questions bind operation and explicit codes; model cannot guess the missing choice',
      () {
    final skill = ProfessionalProfileEditSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    final source = u('Dodaj TIG i MAG do mojego profilu');
    const canonical = 'Dodaj w moim profilu procesy 141 i MAG';
    expect(skill.aiTaskSwitchCommands(source, ctx), [canonical]);
    expect(skill.acceptsProposal(source, u(canonical), ctx), true);
    expect(
        skill.acceptsProposal(u('Remove MAG from my professional profile'),
            u('Remove profile processes MAG'), ctx),
        true);
    for (final command in [
      'Dodaj w moim profilu procesy 141 i 135',
      'Dodaj w moim profilu procesy MAG',
      'Ustaw w moim profilu procesy na 141 i MAG',
      'Usuń w moim profilu procesy 141 i MAG',
      'Dodaj w moim profilu procesy 111 i MAG',
    ]) {
      expect(skill.acceptsProposal(source, u(command), ctx), false,
          reason: command);
    }
    for (final text in [
      'Dodaj MAG 141 do mojego profilu',
      'Dodaj TIG 135 i MAG do mojego profilu',
      'Dodaj MAG albo TIG do mojego profilu',
      'Nie dodawaj MAG do mojego profilu',
      'Jak dodać MAG do mojego profilu'
    ]) {
      expect(skill.aiTaskSwitchCommands(u(text), ctx), isEmpty, reason: text);
    }
    expect(skill.fillProposalSlot('profile_mag_code', u('135'), u('136'), ctx),
        isNull);
    expect(
        skill.fillProposalSlot('profile_mag_code', u('135'), u('MAG 135'), ctx),
        {'profile_mag_code': '135'});
    for (final text in [
      '141',
      '135 i 136',
      'nie 135',
      'Otwórz 135',
      'Anuluj',
      'tak'
    ]) {
      expect(skill.fillSlot('profile_mag_code', u(text), ctx), isNull,
          reason: text);
    }
  });
  for (final voice in [false, true]) {
    for (final row in <(String, String, String, List<String>)>[
      (
        'Dodaj TIG i MAG do mojego profilu',
        'Dodaj w moim profilu procesy 141 i MAG',
        '136',
        ['111', '135', '136', '141']
      ),
      (
        'Usuń MAG i TIG z mojego profilu',
        'Usuń w moim profilu procesy 141 i MAG',
        '135',
        ['111']
      ),
      (
        'Wpisz w moim profilu procesy MMA i MAG',
        'Ustaw w moim profilu procesy na 111 i MAG',
        '138',
        ['111', '138']
      ),
    ]) {
      testWidgets(
          'MAG dialogue retains process operation and explicit codes voice=$voice ${row.$1}',
          (t) async {
        stored = {
          ...stored,
          'processes': ['111', '135', '141']
        };
        await login(t);
        var calls = 0;
        final speech = FixtureSpeech();
        await mount(t, speech: speech, interpret: (r) async {
          calls++;
          expect(
              (r['capabilities'] as List)
                  .single['professional_process_questions'],
              true);
          expect(jsonEncode(r), isNot(contains('Private qualifications')));
          return AiCommandPlan('execute',
              [AiCommandStep('account.professional.edit', row.$2)], '');
        });
        Future<void> send(String text) async {
          if (!voice) {
            await say(t, text);
            return;
          }
          await t.tap(find.byKey(const Key('assistant-mic')));
          await settle(t);
          speech.emit(text);
          await settle(t);
        }

        await send(row.$1);
        expect(find.textContaining('Który proces MAG'), findsWidgets);
        expect(writes, isEmpty);
        await send(row.$3);
        expect(writes, isEmpty);
        expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
        if (voice) {
          await send('Tak');
        } else {
          await confirm(t);
        }
        expect(calls, 1);
        expect(writes, hasLength(1));
        expect(account.account!['processes'], row.$4);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'MAG native question refuses a reply after the account session changes',
      (t) async {
    await login(t);
    final skill = ProfessionalProfileEditSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final match = skill.match(
        Utterance('Dodaj w moim profilu procesy MAG', lang: AppLanguage.pl),
        ctx)!;
    final question = await skill.run(match, ctx) as AskResult;
    await finish(
        t, account.signIn('other@example.invalid', 'fixture-password'));
    final result = await skill.run(
        question.partial.copyWith(
            slots: {...question.partial.slots, 'profile_mag_code': '135'}),
        ctx);
    expect(result, isA<AnswerResult>());
    expect((result as AnswerResult).actionCompleted, false);
    expect(result.answer.text.pl, contains('Sesja'));
    expect(writes, isEmpty);
  });
  testWidgets(
      'a model-invented MAG choice cannot consume an invalid user reply',
      (t) async {
    await login(t);
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      if (calls == 1) {
        return const AiCommandPlan(
            'execute',
            [
              AiCommandStep('account.professional.edit',
                  'Dodaj w moim profilu procesy MAG')
            ],
            '');
      }
      expect((r['context'] as Map)['pending_reply'], {
        'skill_id': 'account.professional.edit',
        'slot': 'profile_mag_code',
        'choices': ['135', '136', '138']
      });
      return const AiCommandPlan(
          'reply', [AiCommandStep('account.professional.edit', '135')], '');
    });
    await say(t, 'Dodaj MAG do mojego profilu');
    await say(t, '141');
    expect(writes, isEmpty);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    expect(find.textContaining('Który proces MAG'), findsWidgets);
    await say(t, '136');
    await confirm(t);
    expect(calls, 2);
    expect(writes, hasLength(1));
    expect(account.account!['processes'], ['136', '141']);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'knowledge question during MAG dialogue preserves the choice and final confirmation',
      (t) async {
    await login(t);
    var calls = 0, answers = 0;
    await mount(t, interpret: (r) async {
      calls++;
      if (calls == 1) {
        return const AiCommandPlan(
            'execute',
            [
              AiCommandStep('account.professional.edit',
                  'Dodaj w moim profilu procesy MAG')
            ],
            '');
      }
      expect((r['context'] as Map)['pending_reply'], isNotNull);
      expect(jsonEncode(r), isNot(contains('Private stamp')));
      return const AiCommandPlan('answer', [], '');
    }, chatSender: (_, __) async {
      answers++;
      return ChatMessage(
          role: ChatRole.assistant,
          text: 'Fixture explanation of process codes',
          kind: AiReplyKind.live);
    });
    await say(t, 'Dodaj MAG do mojego profilu');
    await say(t, 'Co oznaczają te kody procesów?');
    expect(find.textContaining('Fixture explanation'), findsWidgets);
    expect(find.textContaining('Który proces MAG'), findsWidgets);
    expect(writes, isEmpty);
    await say(t, '135');
    await confirm(t);
    expect(calls, 2);
    expect(answers, 1);
    expect(writes, hasLength(1));
    expect(account.account!['processes'], ['135', '141']);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'cancelling a MAG question does not let a later bare code save it',
      (t) async {
    await login(t);
    var calls = 0;
    await mount(t, interpret: (_) async {
      if (++calls == 1) {
        return const AiCommandPlan(
            'execute',
            [
              AiCommandStep('account.professional.edit',
                  'Dodaj w moim profilu procesy MAG')
            ],
            '');
      }
      return const AiCommandPlan(
          'clarify', [], 'Którego polecenia dotyczy ta liczba?');
    });
    await say(t, 'Dodaj MAG do mojego profilu');
    await say(t, 'Anuluj');
    await say(t, '135');
    expect(writes, isEmpty);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    expect(account.account!['processes'], ['141']);
    expect(t.takeException(), isNull);
  });
}
