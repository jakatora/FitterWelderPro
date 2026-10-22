import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_tables/steel_list_share_skill.dart';
import 'package:cut_list_app/domain/steel_weight/steel_order_text.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_page.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'steel_list_summary_test.dart' show order, ReadGate;
import 'steel_add_skill_test.dart' show RecordDisk;

const command = 'Udostepnij zapisana liste stali';
void main() {
  useTestDatabase();
  useGuestAccount();
  Future<T> finish<T>(WidgetTester t, Future<T> operation) async {
    var done = false;
    late T value;
    Object? error;
    operation.then((v) {
      value = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    });
    for (var i = 0; i < 50 && !done; i++) {
      await t.pump(const Duration(milliseconds: 1));
    }
    expect(done, true);
    if (error != null) throw error!;
    return value;
  }

  Future<void> start(WidgetTester t, SteelShareText callback,
      {bool empty = false,
      FixtureSpeech? speech,
      Future<AiCommandPlan> Function()? interpret}) async {
    SteelWeightPage page() => SteelWeightPage(shareText: callback);
    await mount(t,
        home: page(),
        speech: speech,
        interpret: (_) async => interpret == null
            ? throw StateError('Literal sharing is native')
            : interpret());
    if (!empty) await const SteelOrderStore().save(order);
    Navigator.of(t.element(find.byType(SteelWeightPage)))
        .pushReplacement(MaterialPageRoute<void>(builder: (_) => page()));
    await settle(t);
  }

  test('AI cannot add recipients, filters, formats, prices or delivery claims',
      () {
    final s = SteelListShareSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(activeToolId: 'steel_weight'));
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    expect(
        s.acceptsProposal(
            u('Mozesz przygotowac moja liste materialowa do wyslania'),
            u(command),
            ctx),
        true);
    expect(
        s.acceptsProposal(
            u('Could you share my material list please'), u(command), ctx),
        true);
    for (final text in [
      'Nie udostepniaj zapisanej listy stali',
      'How can I share my steel list',
      'Udostepnij liste stali klientowi Janowi',
      'Share only IPE from my material list',
      'Share my material list as PDF',
      'Share material list with price five per kg',
      'Share material list without prices',
      'Delete my material list',
      'Przetlumacz share saved steel list'
    ]) {
      expect(s.acceptsProposal(u(text), u(command), ctx), false, reason: text);
    }
  });
  testWidgets(
      'actual chat shares durable list once without claiming delivery or changing preferences',
      (t) async {
    final sent = <(String, String)>[];
    await start(t, (text, subject) async {
      sent.add((text, subject));
    });
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    await say(t, command);
    expect(sent, hasLength(1));
    expect(sent.single.$1, steelOrderText(order, date: DateTime.now()));
    expect(sent.single.$2, 'Lista materiałowa — stal');
    expect(find.textContaining('Odbiorcę wybierasz'), findsWidgets);
    expect(find.textContaining('Wysłano'), findsNothing);
    await prefs.reload();
    expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, before);
    // An explicit later request reads the newer durable data, not the old UI.
    final latest = order.copyWith(wastePct: 20);
    await const SteelOrderStore().save(latest);
    final result = await finish(t,
        ToolBridge.instance.performModuleAction('steel_weight', 'share_list'));
    expect(result.completed, true);
    expect(sent.last.$1, steelOrderText(latest, date: DateTime.now()));
  });
  testWidgets(
      'natural phone request invokes AI then actual system-share callback',
      (t) async {
    var calls = 0, shares = 0;
    final speech = FixtureSpeech();
    await start(
        t,
        (text, subject) async {
          shares++;
        },
        speech: speech,
        interpret: () async {
          calls++;
          return const AiCommandPlan(
              'execute', [AiCommandStep('steel.list.share', command)], '');
        });
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit('Mozesz przygotowac moja liste materialowa do wyslania');
    await settle(t);
    expect(calls, 1);
    expect(shares, 1);
    expect(find.textContaining('Odbiorcę wybierasz'), findsWidgets);
  });
  testWidgets('empty list and platform error do not report successful sharing',
      (t) async {
    var shares = 0;
    await start(t, (text, subject) async {
      shares++;
      throw StateError('platform failed');
    }, empty: true);
    final empty = await finish(t,
        ToolBridge.instance.performModuleAction('steel_weight', 'share_list'));
    expect(empty.completed, false);
    expect(empty.message.pl, contains('pusta'));
    expect(shares, 0);
    await const SteelOrderStore().save(order);
    final failed = await finish(t,
        ToolBridge.instance.performModuleAction('steel_weight', 'share_list'));
    expect(failed.completed, false);
    expect(shares, 1);
    // Busy state is released even when the platform rejects the request.
    final retry = await finish(t,
        ToolBridge.instance.performModuleAction('steel_weight', 'share_list'));
    expect(retry.completed, false);
    expect(shares, 2);
  });
  testWidgets('overlapping calls cannot open two native share dialogs',
      (t) async {
    var shares = 0;
    final entered = Completer<void>(), release = Completer<void>();
    await start(t, (text, subject) async {
      shares++;
      entered.complete();
      await release.future;
    });
    final first =
        ToolBridge.instance.performModuleAction('steel_weight', 'share_list');
    await finish(t, entered.future);
    final second = await ToolBridge.instance
        .performModuleAction('steel_weight', 'share_list');
    expect(second.completed, false);
    expect(shares, 1);
    release.complete();
    expect((await finish(t, first)).completed, true);
  });
  for (final revoke in [false, true]) {
    testWidgets(
        'sharing does not open after ${revoke ? 'revocation' : 'route change'} during disk read',
        (t) async {
      var shares = 0;
      await start(t, (text, subject) async {
        shares++;
      });
      final prefs = await SharedPreferences.getInstance();
      final gate = ReadGate(
          {for (final k in prefs.getKeys()) 'flutter.$k': prefs.get(k)!});
      SharedPreferencesStorePlatform.instance = gate;
      gate.hold = true;
      final pending =
          ToolBridge.instance.performModuleAction('steel_weight', 'share_list');
      await finish(t, gate.entered.future);
      if (revoke) {
        await finish(t, AccountService.instance.invalidateSession());
      } else {
        Navigator.of(t.element(find.byType(SteelWeightPage))).push(
            MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other route'))));
        await t.pump();
      }
      gate.hold = false;
      gate.release.complete();
      expect((await finish(t, pending)).completed, false);
      expect(shares, 0);
      await settle(t);
    });
  }
  testWidgets('failed manual write cannot leak an unsaved list through sharing',
      (t) async {
    var shares = 0;
    await start(t, (text, subject) async {
      shares++;
    });
    final prefs = await SharedPreferences.getInstance();
    final disk = RecordDisk(
        {for (final k in prefs.getKeys()) 'flutter.$k': prefs.get(k)!})
      ..reject = true;
    SharedPreferencesStorePlatform.instance = disk;
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    final add = find.byKey(const Key('sw-add'));
    final scroll = find
        .descendant(
            of: find.byKey(const Key('sw-profile-list')),
            matching: find.byType(Scrollable))
        .first;
    await t.scrollUntilVisible(add, 300, scrollable: scroll);
    await t.ensureVisible(add);
    await settle(t);
    await t.tap(add);
    await settle(t);
    final failed = await finish(t,
        ToolBridge.instance.performModuleAction('steel_weight', 'share_list'));
    expect(failed.completed, false);
    expect(shares, 0);
    disk.reject = false;
  });
  testWidgets(
      'ordered add then share waits for confirmation and exports the committed item',
      (t) async {
    final sent = <String>[];
    var calls = 0;
    const add = 'Dodaj biezaca pozycje stali do listy';
    await start(t, (text, subject) async {
      sent.add(text);
    }, interpret: () async {
      calls++;
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('steel.item.add', add),
            AiCommandStep('steel.list.share', command),
          ],
          '');
    });
    await say(t, '$add i $command');
    expect(calls, 1);
    expect(sent, isEmpty);
    final save = find.byKey(const Key('assistant-local-save'));
    expect(save, findsOneWidget);
    await t.ensureVisible(save);
    await t.tap(save);
    await settle(t);
    expect(sent, hasLength(1));
    final saved = await const SteelOrderStore().load();
    expect(saved.items, hasLength(3));
    expect(saved.items.last.recordId, isNotNull);
    expect(sent.single, steelOrderText(saved, date: DateTime.now()));
  });
  testWidgets(
      'normal session transition waits until the native share callback finishes',
      (t) async {
    final entered = Completer<void>(), release = Completer<void>();
    await start(t, (text, subject) async {
      entered.complete();
      await release.future;
    });
    final revision = AccountService.instance.sessionRevision;
    final pending =
        ToolBridge.instance.performModuleAction('steel_weight', 'share_list');
    await finish(t, entered.future);
    var switched = false;
    final change = AccountService.instance.forgetSession().then((_) {
      switched = true;
    });
    await t.pump(const Duration(milliseconds: 5));
    expect(switched, false);
    expect(AccountService.instance.sessionRevision, revision);
    release.complete();
    expect((await finish(t, pending)).completed, true);
    await finish(t, change);
    expect(switched, true);
    expect(AccountService.instance.sessionRevision, greaterThan(revision));
    await settle(t);
  });
  testWidgets('cancelled add cancels the queued share as well', (t) async {
    var shares = 0;
    const add = 'Dodaj biezaca pozycje stali do listy';
    await start(t, (text, subject) async {
      shares++;
    },
        interpret: () async => const AiCommandPlan(
            'execute',
            [
              AiCommandStep('steel.item.add', add),
              AiCommandStep('steel.list.share', command)
            ],
            ''));
    await say(t, '$add i $command');
    final cancel = find.byKey(const Key('assistant-local-cancel'));
    expect(cancel, findsOneWidget);
    await t.ensureVisible(cancel);
    await t.tap(cancel);
    await settle(t);
    expect(shares, 0);
    expect((await const SteelOrderStore().load()).items, hasLength(2));
  });
  testWidgets(
      'popup and corrupt persisted payload never reach the native share callback',
      (t) async {
    var shares = 0;
    await start(t, (text, subject) async {
      shares++;
    });
    final context = t.element(find.byType(SteelWeightPage));
    showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Dialog')));
    await settle(t);
    expect(
        (await ToolBridge.instance
                .performModuleAction('steel_weight', 'share_list'))
            .completed,
        false);
    Navigator.of(context).pop();
    await settle(t);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SteelOrderStore.key, '{bad');
    expect(
        (await finish(
                t,
                ToolBridge.instance
                    .performModuleAction('steel_weight', 'share_list')))
            .completed,
        false);
    expect(shares, 0);
    expect(prefs.getString(SteelOrderStore.key), '{bad');
  });
}
