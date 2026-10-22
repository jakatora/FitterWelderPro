import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/records/steel_add_skill.dart';
import 'package:cut_list_app/domain/steel_weight/steel_sections.dart';
import 'package:cut_list_app/domain/steel_weight/steel_weight.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_page.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import '../support/test_account.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const original = SteelOrder(items: [
  SteelItem(
      shape: SteelShape.ipe,
      section: 'IPE 100',
      lengthMm: 1000,
      count: 2,
      unitPrice: 6.25,
      priceUnit: PriceUnit.perM)
], pricePerKg: 4.5, wastePct: 10);
const addCommand = 'Dodaj biezaca pozycje stali do listy';

class RecordDisk extends InMemorySharedPreferencesStore {
  RecordDisk(super.data) : super.withData();
  bool reject = false, failAfterWrite = false, acknowledgeWithoutWrite = false;
  int writes = 0;
  String? holdKey;
  late final entered = Completer<void>();
  late final release = Completer<void>();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.contains('steel_weight_order')) {
      writes++;
      if (holdKey != null && key.endsWith(holdKey!)) {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
      if (reject) return false;
      if (acknowledgeWithoutWrite) return true;
      final result = await super.setValue(valueType, key, value);
      return failAfterWrite ? false : result;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  useTestDatabase();
  useGuestAccount();
  Future<void> pumpUntil(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await t.pump(const Duration(milliseconds: 1));
    }
    expect(done(), true,
        reason: 'Operation did not complete during bounded widget pumps');
  }

  Future<void> finish(WidgetTester t, Future<void> operation) async {
    var done = false;
    Object? error;
    StackTrace? stack;
    operation.then((_) => done = true, onError: (Object e, StackTrace st) {
      error = e;
      stack = st;
      done = true;
    });
    await pumpUntil(t, () => done);
    if (error != null) Error.throwWithStackTrace(error!, stack!);
  }

  Future<AccountService> signedIn(WidgetTester t) async {
    final previous = AccountService.instance;
    FlutterSecureStorage.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/login')) {
        final id =
            (jsonDecode(request.body)['email'] as String).split('@').first;
        return http.Response(
            jsonEncode({
              'token': 'fixture-$id',
              'account': {'id': id, 'role': 'user'}
            }),
            200);
      }
      return http.Response('{}', 200);
    });
    final account = AccountService.forTesting(client);
    AccountService.instance = account;
    addTearDown(() {
      AccountService.instance = previous;
      account.dispose();
      client.close();
    });
    await finish(t, account.signIn('A@example.invalid', 'fixture-password'));
    return account;
  }

  Future<void> start(WidgetTester t) async {
    await mount(t,
        home: const SteelWeightPage(),
        interpret: (_) async => throw StateError('Exact add is native'));
    await const SteelOrderStore().save(original);
    final context = t.element(find.byType(SteelWeightPage));
    Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SteelWeightPage()));
    await settle(t);
  }

  Future<RecordDisk> disk() async {
    final prefs = await SharedPreferences.getInstance();
    final result = RecordDisk(
        {for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!});
    SharedPreferencesStorePlatform.instance = result;
    return result;
  }

  Future<void> save(WidgetTester t) async {
    final button = find.byKey(const Key('assistant-local-save'));
    await t.ensureVisible(button);
    await t.tap(button);
    await settle(t);
  }

  test('add guard never rewrites amount, recipient, price or another record',
      () {
    final s = SteelAddSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String t) => Utterance(t, lang: AppLanguage.pl);
    expect(
        s.acceptsProposal(u('Wrzuc te pozycje na liste'), u(addCommand), ctx),
        true);
    for (final text in [
      'Dodaj 5 sztuk do listy',
      'Zapisz liste klientowi',
      'Nie dodawaj biezacej pozycji stali do listy',
      'Przetlumacz add current steel item to the list',
      'Dodaj biezaca pozycje stali do listy cena 5 zl',
      'Usun biezaca pozycje stali z listy'
    ]) {
      expect(s.acceptsProposal(u(text), u(addCommand), ctx), false,
          reason: text);
    }
  });
  test(
      'AI prose stays scoped to the current item, not questions or extra values',
      () {
    final skill = SteelAddSkill();
    final here = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(activeToolId: 'steel_weight'));
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    for (final text in [
      'Mozesz dorzucic ten element do mojej listy materialowej',
      'Could you put this as another line in my material list'
    ]) {
      expect(skill.match(u(text), here), isNull);
      expect(skill.acceptsProposal(u(text), u(addCommand), here), true);
    }
    for (final text in [
      'Czy moge dodac ten element do listy',
      'How can I add this to the list',
      'Could you add 5 of these to my material list',
      'Please put five of this item in my material list',
      'Please add ten of this item to the material list',
      'Put this as a second item in the material list',
      'Put this aluminium item in the material list',
      'Could you not put this in my list',
      'Put this current profile in the client list',
      'Put this in my list and change the price',
      'Keep this out of my list',
      'Save current steel item as a new material list',
      'Put old profile to my list',
      'Explain the command put this in my list'
    ]) {
      expect(skill.acceptsProposal(u(text), u(addCommand), here), false,
          reason: text);
    }
  });
  testWidgets('free prose invokes AI then native current-item confirmation',
      (t) async {
    var calls = 0;
    await mount(t, home: const SteelWeightPage(), interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute', [AiCommandStep('steel.item.add', addCommand)], '');
    });
    await say(t, 'Could you put this as another line in my material list');
    expect(calls, 1);
    expect((await const SteelOrderStore().load()).items, isEmpty);
    expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
    await save(t);
    expect(
        (await const SteelOrderStore().load()).items.single.section, 'HEB 200');
    expect(calls, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'actual confirmation persists current item and Undo removes only its ID',
      (t) async {
    await start(t);
    await say(t, addCommand);
    expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
    expect((await const SteelOrderStore().load()).items, hasLength(1));
    await save(t);
    final saved = await const SteelOrderStore().load();
    expect(saved.items, hasLength(2));
    expect(saved.items.last.recordId, isNotNull);
    expect(saved.items.last.section, 'HEB 200');
    expect(saved.items.last.lengthMm, 6000);
    expect(saved.pricePerKg, 4.5);
    expect(saved.wastePct, 10);
    expect(saved.items.last.unitPrice, isNull);
    expect(saved.items.last.priceUnit, PriceUnit.perKg);
    expect(
        summarizeOrder(saved).netGrosze,
        summarizeOrder(original).netGrosze! +
            itemCostGrosze(saved.items.last, saved.pricePerKg)!);
    expect(saved.items.first.toJson(), original.items.single.toJson());
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    final add = find.byKey(const ValueKey('sw-add'));
    await t.scrollUntilVisible(add, 500,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('sw-profile-list')),
                matching: find.byType(Scrollable))
            .first);
    await t.ensureVisible(add);
    await settle(t);
    await t.tap(add);
    await settle(t);
    expect((await const SteelOrderStore().load()).items, hasLength(3));
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    final undo = find.byKey(const Key('assistant-local-undo'));
    await t.ensureVisible(undo);
    await t.tap(undo);
    await settle(t);
    final undone = await const SteelOrderStore().load();
    expect(undone.items, hasLength(2));
    expect(
        undone.items.any((item) => item.recordId == saved.items.last.recordId),
        false);
    expect(undone.items.last.section, 'HEB 200');
    expect(undone.items.last.recordId, isNull);
    expect(undone.pricePerKg, 4.5);
    expect(undone.wastePct, 10);
    expect(t.takeException(), isNull);
  });
  for (final mode in ['reject', 'persist-but-fail', 'ack-without-write']) {
    testWidgets(
        'unconfirmed disk $mode never claims saved; retry adds exactly one ID',
        (t) async {
      await start(t);
      final controlled = await disk();
      controlled.reject = mode == 'reject';
      controlled.failAfterWrite = mode == 'persist-but-fail';
      controlled.acknowledgeWithoutWrite = mode == 'ack-without-write';
      await say(t, addCommand);
      await save(t);
      expect(find.text('Zapisano.'), findsNothing);
      expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
      expect((await const SteelOrderStore().load()).items,
          hasLength(mode == 'persist-but-fail' ? 2 : 1));
      controlled.reject = false;
      controlled.failAfterWrite = false;
      controlled.acknowledgeWithoutWrite = false;
      await save(t);
      final saved = await const SteelOrderStore().load();
      expect(saved.items, hasLength(2));
      expect(saved.items.last.recordId, isNotNull);
      expect(saved.items.first.toJson(), original.items.single.toJson());
      expect(find.text('Zapisano.'), findsOneWidget);
      if (mode == 'persist-but-fail') expect(controlled.writes, 1);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'native preparation rejects changed draft and duplicate invocation is idempotent',
      (t) async {
    await start(t);
    final b = ToolBridge.instance;
    final prepared = b.prepareModuleRecord('steel_weight', 'add_draft')!;
    final first = prepared.perform(), second = prepared.perform();
    final results = await Future.wait([first, second]);
    await settle(t);
    expect((await const SteelOrderStore().load()).items, hasLength(2));
    await results.first!();
    await settle(t);
    expect((await const SteelOrderStore().load()).items, hasLength(1));
    final stale = b.prepareModuleRecord('steel_weight', 'add_draft')!;
    final fields = {...b.inputFields('steel_weight')!, 'quantity': 7};
    await b.current!.apply(fields);
    await settle(t);
    await expectLater(Future.sync(stale.perform), throwsStateError);
    expect((await const SteelOrderStore().load()).items, hasLength(1));
    expect(t.takeException(), isNull);
  });
  test('stable native identity survives serialization and manual item edits',
      () {
    final item = original.items.single.copyWith(recordId: 'fixture-native-id');
    expect(SteelItem.fromJson(item.toJson())!.recordId, 'fixture-native-id');
    expect(item.copyWith(count: 3, unitPrice: 6).recordId, 'fixture-native-id');
    expect(item.totalKg, original.items.single.totalKg);
    expect(original.items.single.toJson().containsKey('recordId'), false);
  });
  testWidgets(
      'uncertain persisted save cancellation never claims nothing was saved',
      (t) async {
    await start(t);
    final controlled = await disk();
    controlled.failAfterWrite = true;
    await say(t, addCommand);
    await save(t);
    expect((await const SteelOrderStore().load()).items, hasLength(2));
    final cancel = find.byKey(const Key('assistant-local-cancel'));
    await t.ensureVisible(cancel);
    await t.tap(cancel);
    await settle(t);
    expect(find.text('Anulowano. Nic nie zapisano.'), findsNothing);
    expect(find.textContaining('Anulowano dalsze próby'), findsOneWidget);
    expect(controlled.writes, 1);
    controlled.failAfterWrite = false;
  });
  testWidgets(
      'voice cancellation after a persisted but unacknowledged save preserves the record',
      (t) async {
    await start(t);
    final controlled = await disk();
    controlled.failAfterWrite = true;
    await say(t, addCommand);
    await save(t);
    expect((await const SteelOrderStore().load()).items, hasLength(2));
    await say(t, 'Nie');
    expect(find.text('Anulowano. Nic nie zapisano.'), findsNothing);
    expect(find.textContaining('Anulowano dalsze próby'), findsOneWidget);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    expect(controlled.writes, 1);
    expect((await const SteelOrderStore().load()).items, hasLength(2));
    controlled.failAfterWrite = false;
  });
  testWidgets(
      'speech can edit quantity and prepare add, then confirm without another AI call',
      (t) async {
    final speech = FixtureSpeech();
    var calls = 0;
    await mount(t, home: const SteelWeightPage(), speech: speech,
        interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('steel.draft.edit', 'Ustaw ilosc stali na 5'),
            AiCommandStep('steel.item.add', addCommand)
          ],
          '');
    });
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech
        .emit('Potrzebuje piec takich i dodaj biezaca pozycje stali do listy');
    await settle(t);
    expect(calls, 1);
    expect(ToolBridge.instance.inputFields('steel_weight')!['quantity'], 5);
    expect((await const SteelOrderStore().load()).items, isEmpty);
    expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit('Tak');
    await settle(t);
    expect(calls, 1);
    final item = (await const SteelOrderStore().load()).items.single;
    expect(item.count, 5);
    expect(item.recordId, isNotNull);
    expect(ToolBridge.instance.inputFields('steel_weight')!.keys,
        isNot(contains('recordId')));
    expect(t.takeException(), isNull);
  });
  testWidgets('Undo refuses a manually edited record instead of deleting it',
      (t) async {
    await start(t);
    final prepared =
        ToolBridge.instance.prepareModuleRecord('steel_weight', 'add_draft')!;
    final undo = await prepared.perform();
    await settle(t);
    final stored = await const SteelOrderStore().load();
    final edited = stored.copyWith(
        items: [stored.items.first, stored.items.last.copyWith(count: 3)]);
    await const SteelOrderStore().save(edited);
    await expectLater(undo!(), throwsStateError);
    await settle(t);
    expect((await const SteelOrderStore().load()).toJson(), edited.toJson());
    expect(t.takeException(), isNull);
  });
  testWidgets('pending preparation cannot commit through a popup', (t) async {
    await start(t);
    final prepared =
        ToolBridge.instance.prepareModuleRecord('steel_weight', 'add_draft')!;
    final context = t.element(find.byType(SteelWeightPage));
    final shown = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Hold')));
    await t.pumpAndSettle();
    expect(ToolBridge.instance.prepareModuleRecord('steel_weight', 'add_draft'),
        isNull);
    await expectLater(Future.sync(prepared.perform), throwsStateError);
    Navigator.of(context).pop();
    await shown;
    await settle(t);
    expect((await const SteelOrderStore().load()).items, hasLength(1));
  });
  testWidgets('prepared callback and Undo cannot cross an account switch',
      (t) async {
    final account = await signedIn(t);
    await start(t);
    final stale =
        ToolBridge.instance.prepareModuleRecord('steel_weight', 'add_draft')!;
    final saved =
        ToolBridge.instance.prepareModuleRecord('steel_weight', 'add_draft')!;
    final undo = await saved.perform();
    await settle(t);
    await finish(t, account.signIn('B@example.invalid', 'fixture-password'));
    await settle(t);
    await expectLater(
        Future.sync(stale.perform), throwsA(isA<AccountException>()));
    await expectLater(undo!(), throwsA(isA<AccountException>()));
    await settle(t);
    expect((await const SteelOrderStore().load()).items, isEmpty);
    await finish(t, account.signIn('A@example.invalid', 'fixture-password'));
    await settle(t);
    expect((await const SteelOrderStore().load()).items, hasLength(2));
    expect(t.takeException(), isNull);
  });
  for (final forced in [false, true]) {
    testWidgets(
        'in-flight native add remains owned by A during account change: forced=$forced',
        (t) async {
      final account = await signedIn(t);
      await start(t);
      final controlled = await disk();
      controlled.holdKey = SteelOrderStore.keyForScope('account:A');
      await say(t, addCommand);
      final button = find.byKey(const Key('assistant-local-save'));
      await t.ensureVisible(button);
      await t.tap(button);
      await pumpUntil(t, () => controlled.entered.isCompleted);
      if (forced) {
        await finish(t, account.invalidateSession());
        await settle(t);
        await finish(
            t, account.signIn('B@example.invalid', 'fixture-password'));
        await settle(t);
        expect(account.account!['id'], 'B');
        expect((await const SteelOrderStore().load()).items, isEmpty);
        controlled.release.complete();
        await settle(t);
        expect(find.text('Zapisano.'), findsNothing);
      } else {
        var done = false;
        Object? error;
        final switching =
            account.signIn('B@example.invalid', 'fixture-password');
        switching.then((_) => done = true, onError: (Object e) {
          error = e;
          done = true;
        });
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 1));
        }
        expect(done, false);
        expect(account.account!['id'], 'A');
        controlled.release.complete();
        await pumpUntil(t, () => done);
        expect(error, isNull);
        await switching;
        await settle(t);
      }
      expect(account.account!['id'], 'B');
      expect((await const SteelOrderStore().load()).items, isEmpty);
      await finish(t, account.signIn('A@example.invalid', 'fixture-password'));
      await settle(t);
      final stored = await const SteelOrderStore().load();
      expect(stored.items, hasLength(2));
      expect(stored.items.last.recordId, isNotNull);
      expect(stored.pricePerKg, 4.5);
      expect(stored.wastePct, 10);
      expect(t.takeException(), isNull);
    });
  }
}
