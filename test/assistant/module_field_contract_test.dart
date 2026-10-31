// Contract 4.2(e): compare fields emitted by the full brain against actual
// mounted native handles. Modules without field-bearing examples still have
// their actual navigation checked; this is NOT field/action coverage for them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/database/weld_quote_dao.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';
import 'support/assistant_test_support.dart';

Future<void> settleFields(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await flushTestDatabase(t);
    await t.pump(const Duration(milliseconds: 100));
  }
  for (var i = 0;
      i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      i++) {
    await flushTestDatabase(t);
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useTestDatabase();
  final emitted = <String, List<(String, ShowInModule, bool)>>{};
  setUpAll(() async {
    final catalog = buildSkillCatalog(
        actions: FakeActionsPort(), iso: FakeIsoDrawingPort());
    for (final skill
        in catalog.where((s) => s.tier.index >= AssistantTier.b.index)) {
      for (final example in skill.examples) {
        for (final (lang, text) in [
          (AppLanguage.pl, example.pl),
          (AppLanguage.en, example.en)
        ]) {
          seedFreshInstall();
          final h = BrainHarness(lang: lang);
          try {
            var reply = await h.say(text);
            expect(reply.match?.skill.id, skill.id, reason: text);
            // Quote examples intentionally start a dialogue. Complete only
            // its required input slots; never perform the confirmation or
            // alter prices just to inspect its native record-id field.
            final quoteAnswers = {
              'material': lang == AppLanguage.pl
                  ? 'stal nierdzewna'
                  : 'stainless steel',
              'scheme': 'TIG + MMA',
              'site': lang == AppLanguage.pl ? 'w warsztacie' : 'in shop',
            };
            for (var i = 0;
                i < 3 && skill.id == 'quote.new' && reply.result is AskResult;
                i++) {
              final answer = quoteAnswers[(reply.result as AskResult).slot];
              if (answer == null) break;
              reply = await h.say(answer);
              expect(reply.match?.skill.id, skill.id);
            }
            final show = switch (reply.result) {
              AnswerResult(:final show) => show,
              ConfirmResult(:final show) => show,
              _ => null,
            };
            if (show != null && show.fields.isNotEmpty) {
              emitted.putIfAbsent(show.toolId, () => []).add(
                  (text, show, skill.readOnly && reply.result is AnswerResult));
            }
          } finally {
            h.timer.dispose();
          }
        }
      }
    }
    expect(
        emitted.keys,
        containsAll(
            ['dn_mm', 'wall_thickness', 'pipe_weight', 'steel_weight']));
    expect(emitted.keys.every((id) => toolById(id) != null), isTrue);
    expect(emitted.keys, contains('weld_quotes'));
    debugPrint(
        'field contract targets: ${emitted.length}; read-only value application targets: ${emitted.values.where((cases) => cases.any((c) => c.$3)).length}');
    expect(await WeldQuoteDao().listAll(), isEmpty,
        reason: 'field metadata checks must never confirm or create a quote');
  });
  for (final tool in availableTools) {
    testWidgets('native module contract: ${tool.id}', (t) async {
      final examples =
          emitted[tool.id] ?? const <(String, ShowInModule, bool)>[];
      seedOnboardedUser();
      AssistantPanelController.instance.setExpanded(false);
      ToolBridge.reset();
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.5;
      addTearDown(t.view.reset);
      addTearDown(() async {
        AssistantPanelController.instance.setExpanded(false);
        await t.pumpWidget(const SizedBox.shrink());
        await settleFields(t);
      });
      await t.pumpWidget(const CutListApp());
      await settleFields(t);
      final outcome = await showInModule(ShowInModule(tool.id), explicit: true);
      expect(outcome, anyOf(ShowOutcome.opened, ShowOutcome.appliedInPlace));
      await settleFields(t);
      if (tool.id == 'assistant') {
        expect(AssistantPanelController.instance.expanded, isTrue,
            reason: 'the global assistant opens over the current route');
      } else {
        expect(appRoutes.toolId, tool.id,
            reason: 'the requested native screen must actually be visible');
      }
      expect(t.takeException(), isNull);
      if (examples.isEmpty) {
        // Opening a screen must not be silently omitted just because no
        // catalog example injects fields. Never invent field payloads here.
        return;
      }
      for (var i = 0; i < 20; i++) {
        await settleFields(t);
        final handle = ToolBridge.instance.current;
        if (handle?.toolId == tool.id && ToolBridge.instance.isReady(handle!)) {
          break;
        }
      }
      final handle = ToolBridge.instance.current;
      expect(handle?.toolId, tool.id,
          reason: 'actual visible module must own the handle');
      expect(ToolBridge.instance.isReady(handle!), isTrue);
      for (final (text, show, canApply) in examples) {
        expect(show.fields.keys.toSet().difference(handle.supportedFields),
            isEmpty,
            reason: '${tool.id}: $text');
        if (canApply) {
          Set<String>? rejected;
          Object? error;
          final done = handle.apply(show.fields).then((value) {
            rejected = value;
          }, onError: (Object e) {
            error = e;
          });
          for (var frame = 0;
              frame < 20 && rejected == null && error == null;
              frame++) {
            await settleFields(t);
          }
          expect(error, isNull, reason: '${tool.id}: $text');
          expect(rejected, isNotNull,
              reason: '${tool.id}: field application did not finish');
          await done;
          expect(rejected, isEmpty,
              reason: '${tool.id}: $text rejected actual example values');
          if (show.fields.length == 1 && show.fields['action'] == 'formula') {
            // Opening a formula dialog is an explicit UI action, not a field
            // update. Verify the overlay and restoration of the same route.
            expect(appRoutes.top, isA<PopupRoute>());
            expect(find.byType(AlertDialog), findsOneWidget);
            appNavigatorKey.currentState!.pop();
            await settleFields(t);
          }
          expect(ToolBridge.instance.current, same(handle),
              reason: 'a field update must not change the target route');
          expect(t.takeException(), isNull, reason: '${tool.id}: $text');
        }
      }
      if (tool.id == 'weld_quotes') {
        expect(await t.runAsync(() => WeldQuoteDao().listAll()), isEmpty,
            reason:
                'opening the field-contract target must not create or confirm a financial record');
      }
    });
  }
}
