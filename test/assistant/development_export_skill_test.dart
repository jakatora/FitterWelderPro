import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_routes/development_export_skill.dart';
import 'package:cut_list_app/features/cone_layout/cone_layout_page.dart';
import 'package:cut_list_app/domain/fitter/cone_assistant_input.dart';
import 'package:cut_list_app/domain/fitter/eccentric_cone_assistant_input.dart';
import 'package:cut_list_app/domain/fitter/transition_assistant_input.dart';
import 'package:cut_list_app/services/wrap_template_pdf.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'cone_layout_skill_test.dart' as cone;
import 'eccentric_cone_skill_test.dart' as eccentric;
import 'transition_layout_skill_test.dart' as transition;

void main() {
  useTestDatabase();
  test('PDF source guard never invents recipient, format or print settings',
      () {
    final s = DevelopmentExportSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String t) => Utterance(t, lang: AppLanguage.pl);
    final target = u('Eksportuj szablon PDF');
    expect(
        s.acceptsProposal(
            u('Potrzebuję szablonu PDF aktualnego rozwinięcia'), target, ctx),
        true);
    for (final text in [
      'Przetłumacz eksportuj szablon PDF',
      'Nie eksportuj szablonu PDF',
      'Wyślij PDF do Jana',
      'Eksportuj szablon PDF A3',
      'Eksportuj profil PDF',
      'Zmień wysokość i eksportuj szablon PDF',
      'Eksportuj szablon tekstowy'
    ]) {
      expect(s.acceptsProposal(u(text), target, ctx), false, reason: text);
    }
  });
  for (final entry in [
    (cone.command, cone.payload),
    (eccentric.command, eccentric.fields),
    (transition.command, transition.fields)
  ]) {
    testWidgets(
        'native export prepares actual ${entry.$2['shape']} spec with selected A3 and no geometry mutation',
        (t) async {
      final exports = <(FlatTemplateSpec, String, bool)>[];
      await mount(t,
          home: ConeLayoutPage(
              sharePdf: (spec, name, en) async =>
                  exports.add((spec, name, en))),
          interpret: (_) async => throw StateError('Exact export is native'));
      await say(t, entry.$1);
      final b = ToolBridge.instance;
      final handle = b.current!;
      await t.scrollUntilVisible(
          find.byKey(const ValueKey('cone-paper-a3')), 500,
          scrollable: find
              .descendant(
                  of: find.byType(ConeLayoutPage),
                  matching: find.byType(Scrollable))
              .first);
      AssistantPanelController.instance.setExpanded(false);
      await settle(t);
      await Scrollable.ensureVisible(
          t.element(find.byKey(const ValueKey('cone-paper-a3'))),
          alignment: .2);
      await settle(t);
      await t.tap(find.byKey(const ValueKey('cone-paper-a3')));
      await settle(t);
      expect(
          t
              .widget<ChoiceChip>(find.byKey(const ValueKey('cone-paper-a3')))
              .selected,
          true);
      AssistantPanelController.instance.setExpanded(true);
      await settle(t);
      await say(t, 'Przygotuj PDF bieżącego rozwinięcia');
      expect(exports, hasLength(1));
      final (spec, name, en) = exports.single;
      expect(spec.paper, TemplatePaper.a3);
      expect(spec.shapes, isNotEmpty);
      final width = switch (entry.$2['shape']) {
        'concentric' =>
          ConeAssistantInput.fromFields(entry.$2).result.part.pattern().widthMm,
        'eccentric' => EccentricConeAssistantInput.fromFields(entry.$2)
            .result
            .parts
            .first
            .widthMm,
        _ => TransitionAssistantInput.fromFields(entry.$2)
            .result
            .parts
            .first
            .pattern
            .widthMm,
      };
      expect(spec.shapes.first.widthMm, closeTo(width, 1e-9));
      expect(spec.sheetCount, greaterThan(0));
      expect(name, endsWith('.pdf'));
      expect(en, false);
      expect(b.inputFields('cone_layout'), entry.$2);
      expect(b.current, same(handle));
      expect(find.textContaining('Przygotowano PDF.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'invalid, oversized, popup and arbitrary field requests never invoke PDF callback',
      (t) async {
    var calls = 0;
    await mount(t,
        home: ConeLayoutPage(sharePdf: (_, name, en) async {
          calls++;
        }),
        interpret: (_) async => throw StateError('Exact export is native'));
    await say(t, cone.command);
    final b = ToolBridge.instance,
        h = ToolBridge.instance.current! as ModuleActionHandle;
    expect(
        (await h.performAction('export_pdf', field: 'email')).completed, false);
    expect((await h.performAction('send')).completed, false);
    final context = t.element(find.byType(ConeLayoutPage));
    final dialog = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Hold')));
    await t.pumpAndSettle();
    expect((await h.performAction('export_pdf')).completed, false);
    Navigator.of(context).pop();
    await dialog;
    await settle(t);
    expect(
        await b.current!.apply({
          ...cone.payload,
          'large_dia_mm': 1000,
          'small_dia_mm': 900,
          'height_mm': 2000
        }),
        isEmpty);
    await settle(t);
    expect((await h.performAction('export_pdf')).completed, false);
    await b.current!.apply(cone.payload);
    await settle(t);
    await t.scrollUntilVisible(find.byKey(const ValueKey('cone-D')), -500,
        scrollable: find
            .descendant(
                of: find.byType(ConeLayoutPage),
                matching: find.byType(Scrollable))
            .first);
    await t.enterText(find.byKey(const ValueKey('cone-D')), '0');
    await settle(t);
    expect((await h.performAction('export_pdf')).completed, false);
    expect(calls, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('callback failure does not claim PDF prepared and can retry',
      (t) async {
    var fail = true, calls = 0;
    await mount(t,
        home: ConeLayoutPage(sharePdf: (_, name, en) async {
          calls++;
          if (fail) throw StateError('fixture export failure');
        }),
        interpret: (_) async => throw StateError('Exact export is native'));
    await say(t, cone.command);
    await say(t, 'Eksportuj szablon PDF');
    expect(calls, 1);
    expect(find.textContaining('Przygotowano PDF.'), findsNothing);
    expect(find.textContaining('Nie udało się przygotować szablonu PDF.'),
        findsOneWidget);
    fail = false;
    await say(t, 'Eksportuj szablon PDF');
    expect(calls, 2);
    expect(find.textContaining('Przygotowano PDF.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'concurrent export is not duplicated and changed form stops completion',
      (t) async {
    final pending = Completer<void>();
    var calls = 0;
    await mount(t,
        home: ConeLayoutPage(sharePdf: (_, name, en) {
          calls++;
          return pending.future;
        }),
        interpret: (_) async => throw StateError('Exact export is native'));
    await say(t, cone.command);
    final b = ToolBridge.instance;
    final first = b.performModuleAction('cone_layout', 'export_pdf');
    await t.pump();
    expect(calls, 1);
    expect((await b.performModuleAction('cone_layout', 'export_pdf')).completed,
        false);
    await b.current!.apply({...cone.payload, 'height_mm': 600});
    await settle(t);
    pending.complete();
    await settle(t);
    expect((await first).completed, false);
    expect(calls, 1);
    expect(b.inputFields('cone_layout')!['height_mm'], 600);
    expect(t.takeException(), isNull);
  });
  testWidgets('mocked speech prepares template through the native callback',
      (t) async {
    final speech = FixtureSpeech();
    var calls = 0;
    await mount(t,
        home: ConeLayoutPage(sharePdf: (_, name, en) async {
          calls++;
        }),
        speech: speech,
        interpret: (_) async =>
            throw StateError('Exact export voice is native'));
    await say(t, cone.command);
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit('Wydrukuj bieżące rozwinięcie');
    await settle(t);
    expect(calls, 1);
    expect(find.textContaining('Przygotowano PDF.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'AI natural PDF request reaches native export without invented delivery',
      (t) async {
    var calls = 0, exports = 0;
    await mount(t, home: ConeLayoutPage(sharePdf: (_, name, en) async {
      exports++;
    }), interpret: (_) async {
      calls++;
      return const AiCommandPlan('execute',
          [AiCommandStep('development.export', 'Eksportuj szablon PDF')], '');
    });
    await say(t, cone.command);
    await say(t, 'Potrzebuję szablonu PDF aktualnego rozwinięcia');
    expect(calls, 1);
    expect(exports, 1);
    expect(find.textContaining('Przygotowano PDF.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
