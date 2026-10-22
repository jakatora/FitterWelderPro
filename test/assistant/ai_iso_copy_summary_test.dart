import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_copy_summary_skill.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const command = 'Skopiuj zestawienie rysunku ISO';
void main() {
  useTestDatabase();
  useGuestAccount();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  Future<T> finish<T>(WidgetTester t, Future<T> op) async {
    var done = false;
    late T value;
    Object? error;
    op.then((v) {
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

  Future<IsoNotebookController> draw(WidgetTester t,
      {FixtureSpeech? speech,
      Future<AiCommandPlan> Function()? interpret}) async {
    await mount(t,
        speech: speech,
        interpret: (_) async => interpret == null
            ? throw StateError('Literal command is native')
            : interpret());
    await say(t, 'Narysuj rura metr w prawo kolano DN50 w gore rura metr');
    final c = IsoNotebookController.active!;
    for (var i = 0; i < 12 && c.isBusy; i++) {
      await settle(t);
    }
    await settle(t);
    expect(c.isBusy, false);
    return c;
  }

  void clipboard(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, handler);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  test(
      'copy source guard does not turn filters, messages or questions into a clipboard action',
      () {
    final s = IsoCopySummarySkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(activeToolId: 'iso_notebook'));
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    expect(
        s.acceptsProposal(
            u('Wrzuć mi zestawienie tego rysunku do schowka'), u(command), ctx),
        true);
    expect(
        s.acceptsProposal(
            u('Could you copy the summary of this drawing to clipboard'),
            u(command),
            ctx),
        true);
    for (final text in [
      'Nie kopiuj zestawienia rysunku ISO',
      'Przetlumacz copy current ISO drawing summary',
      'Jak skopiowac zestawienie rysunku ISO',
      'Skopiuj tylko rury z zestawienia rysunku',
      'Skopiuj zestawienie poprzedniego rysunku ISO',
      'Wyslij zestawienie rysunku ISO klientowi',
      'Skopiuj zestawienie rysunku ISO jako CSV',
      'Skopiuj zestawienie rysunku ISO bez notatek',
      'Copy the summary of five pipes in this drawing',
      'Copy the first drawing summary'
    ]) {
      expect(s.acceptsProposal(u(text), u(command), ctx), false, reason: text);
    }
  });
  testWidgets(
      'actual chat copies native engine CUT and BOM without editing the drawing',
      (t) async {
    final copied = <String>[];
    clipboard((call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    final c = await draw(t);
    await flushTestDatabase(t);
    final before = await t.runAsync(() => IsoDrawingDao().latest());
    final version = c.revision;
    await say(t, command);
    expect(copied, hasLength(1));
    final text = copied.single;
    expect(text, contains('CUT LIST'));
    expect(text, contains('ZESTAWIENIE MATERIAŁOWE (BOM)'));
    for (final cut in c.debugPipeCutsMm.where((v) => v.isFinite && v >= 0)) {
      expect(text, contains('${cut.toStringAsFixed(1)} mm'));
    }
    expect(
        find.textContaining(
            'Skopiowano zestawienie bieżącego rysunku ISO do schowka.'),
        findsWidgets);
    await flushTestDatabase(t);
    final after = await t.runAsync(() => IsoDrawingDao().latest());
    expect(after!.id, before!.id);
    expect(after.json, before.json);
    expect(c.revision, version);
  });
  testWidgets(
      'free phone request invokes AI and actual native clipboard callback',
      (t) async {
    var calls = 0;
    final copied = <String>[];
    final speech = FixtureSpeech();
    clipboard((call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    await draw(t, speech: speech, interpret: () async {
      calls++;
      return const AiCommandPlan(
          'execute', [AiCommandStep('iso.summary.copy', command)], '');
    });
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit('Wrzuć mi zestawienie tego rysunku do schowka');
    await settle(t);
    expect(calls, 1);
    expect(copied, hasLength(1),
        reason: find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .whereType<String>()
            .join(' | '));
  });
  testWidgets(
      'platform clipboard failure reports failure and permits a real retry',
      (t) async {
    var fail = true, writes = 0;
    clipboard((call) async {
      if (call.method == 'Clipboard.setData') {
        writes++;
        if (fail) throw PlatformException(code: 'blocked');
      }
      return null;
    });
    await draw(t);
    final failed = await finish(
        t,
        ToolBridge.instance
            .performModuleAction('iso_notebook', 'copy_summary'));
    expect(failed.completed, false);
    expect(writes, 1);
    fail = false;
    final retried = await finish(
        t,
        ToolBridge.instance
            .performModuleAction('iso_notebook', 'copy_summary'));
    expect(retried.completed, true);
    expect(writes, 2);
  });
  testWidgets('popup prevents copying another visible drawing', (t) async {
    var writes = 0;
    clipboard((call) async {
      if (call.method == 'Clipboard.setData') writes++;
      return null;
    });
    await draw(t);
    final context = t.element(find.byType(IsoNotebookScreen));
    showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Dialog')));
    await settle(t);
    expect(
        (await ToolBridge.instance
                .performModuleAction('iso_notebook', 'copy_summary'))
            .completed,
        false);
    expect(writes, 0);
  });
  for (final revoke in [false, true]) {
    testWidgets(
        'pending copy rejects overlap and stale ${revoke ? 'session' : 'drawing revision'} completion',
        (t) async {
      final entered = Completer<void>(), release = Completer<void>();
      var writes = 0;
      clipboard((call) async {
        if (call.method == 'Clipboard.setData') {
          writes++;
          if (!entered.isCompleted) entered.complete();
          await release.future;
        }
        return null;
      });
      final c = await draw(t);
      final pending = ToolBridge.instance
          .performModuleAction('iso_notebook', 'copy_summary');
      await finish(t, entered.future);
      final duplicate = await ToolBridge.instance
          .performModuleAction('iso_notebook', 'copy_summary');
      expect(duplicate.completed, false);
      expect(writes, 1);
      if (revoke) {
        await finish(t, AccountService.instance.invalidateSession());
      } else {
        await say(t, 'Zmien szczeline ISO na 3 mm');
        expect(c.rootGapMm, 3);
      }
      release.complete();
      final result = await finish(t, pending);
      expect(result.completed, false);
      await settle(t);
    });
  }
  testWidgets(
      'empty and partially animated drawing cannot be copied as a finished summary',
      (t) async {
    var writes = 0;
    clipboard((call) async {
      if (call.method == 'Clipboard.setData') writes++;
      return null;
    });
    await mount(t, interpret: (_) async => throw StateError('Native only'));
    await say(t, 'Otwórz zeszyt ISO');
    final c = IsoNotebookController.active!;
    expect(
        (await finish(
                t,
                ToolBridge.instance
                    .performModuleAction('iso_notebook', 'copy_summary')))
            .completed,
        false);
    final drawing = c.draw(const [
      IsoPipe(lengthMm: 1000, dir: IsoDir.right),
      IsoTurn(toDir: IsoDir.up),
      IsoPipe(lengthMm: 2000)
    ], stepDelay: const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 20));
    expect(c.isBusy, true);
    expect(
        (await finish(
                t,
                ToolBridge.instance
                    .performModuleAction('iso_notebook', 'copy_summary')))
            .completed,
        false);
    expect(writes, 0);
    for (var i = 0; i < 12 && c.isBusy; i++) {
      await t.pump(const Duration(seconds: 2));
      await settle(t);
    }
    await drawing;
    await settle(t);
    expect(
        (await finish(
                t,
                ToolBridge.instance
                    .performModuleAction('iso_notebook', 'copy_summary')))
            .completed,
        true);
    expect(writes, 1);
  });
  testWidgets(
      'ordered draw then copy waits for complete geometry and native CUT',
      (t) async {
    const drawing = 'Narysuj rura metr w prawo kolano DN50 w gore rura metr';
    final copied = <String>[];
    var calls = 0;
    clipboard((call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    await mount(t, interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('iso.draw', drawing),
            AiCommandStep('iso.summary.copy', command)
          ],
          '');
    });
    await say(t, '$drawing a potem $command');
    for (var i = 0; i < 12 && copied.isEmpty; i++) {
      await settle(t);
    }
    expect(calls, 1);
    expect(copied, hasLength(1));
    final c = IsoNotebookController.active!;
    expect(c.isBusy, false);
    expect(c.summary!.pipeCount, 2);
    for (final cut in c.debugPipeCutsMm.where((v) => v.isFinite && v >= 0)) {
      expect(copied.single, contains('${cut.toStringAsFixed(1)} mm'));
    }
  });
}
