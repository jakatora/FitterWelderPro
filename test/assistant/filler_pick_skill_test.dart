import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/filler/filler_catalog.dart';
import 'package:cut_list_app/domain/filler/filler_reference.dart';
import 'package:cut_list_app/features/filler/filler_selector_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('one grade asks other side then process without silently copying',
      () async {
    final h = BrainHarness();
    expect(((await h.say('spoiwo do 316L')).result as AskResult).slot, 'b');
    expect(((await h.say('S355')).result as AskResult).slot, 'process');
    final a = (await h.say('TIG')).result as AnswerResult;
    expect(a.show!.fields, {
      'material_a': 'ss316L',
      'material_b': 'carbonSteel',
      'process': 'tig'
    });
    expect(a.answer.text.pl, contains('309L'));
    expect(a.answer.text.pl, contains('WPS'));
  });
  test('same material is explicit and all process choices work', () async {
    for (final p in FillerProcess.values) {
      final h = BrainHarness();
      await h.say('spoiwo do 316L');
      final q = (await h.say('ten sam')).result as AskResult;
      expect(q.slot, 'process');
      final a = (await h.say(p == FillerProcess.fcaw ? '136' : p.name3)).result
          as AnswerResult;
      expect(a.show!.fields['material_b'], 'ss316L');
      expect(
          a.answer.text.en,
          fillerReference(BaseMaterial.ss316L, BaseMaterial.ss316L, p,
              en: true));
    }
  });
  test('all material choices are selectable without label ambiguity', () async {
    for (final m in BaseMaterial.values) {
      final h = BrainHarness();
      final q = (await h.say('dobierz spoiwo')).result as AskResult;
      expect(q.slot, 'a');
      await h.say(m.name);
      await h.say('ten sam');
      final a = (await h.say('TIG')).result as AnswerResult;
      expect(a.show!.fields['material_a'], m.name);
      expect(a.show!.fields['material_b'], m.name);
    }
  });
  test('specialist and incompatible pairs retain source verdict', () async {
    for (final q in ['spoiwo P91 i S355 MMA', 'spoiwo 5083 i 316L TIG']) {
      final a = (await BrainHarness().say(q)).result as AnswerResult;
      expect(a.answer.text.pl, isNot(contains('ER316L')));
      expect(a.show, isNotNull);
    }
  });
  test('missing process variant and 114 report a real catalogue gap', () async {
    for (final q in [
      'spoiwo 5083 ten sam MMA',
      'spoiwo 304L i 321 136',
      'spoiwo 316L ten sam 114'
    ]) {
      expect(
          ((await BrainHarness().say(q)).result as FailedResult)
              .reportMissingCapability,
          isTrue);
    }
  });
  test('multiple processes ask rather than selecting the first', () async {
    final h = BrainHarness();
    expect(
        ((await h.say('spoiwo 316L ten sam TIG MMA')).result as AskResult).slot,
        'process');
    final a = (await h.say('MMA')).result as AnswerResult;
    expect(a.show!.fields['process'], 'mma');
  });
  test('spoken grade and process follow the same dialogue', () async {
    final h = BrainHarness();
    await h.say('spoiwo do trzysta szesnaście L', byVoice: true);
    await h.say('ten sam', byVoice: true);
    final a = (await h.say('sto czterdzieści jeden', byVoice: true)).result
        as AnswerResult;
    expect(a.show!.fields,
        {'material_a': 'ss316L', 'material_b': 'ss316L', 'process': 'tig'});
  });
  test('current is not a process code and conflicting same is clarified',
      () async {
    final h = BrainHarness();
    expect(
        ((await h.say('spoiwo 316L ten sam 141 A')).result as AskResult).slot,
        'process');
    final h2 = BrainHarness();
    expect(
        ((await h2.say('spoiwo 304L i 316L ten sam TIG')).result as AskResult)
            .slot,
        'b');
    final a = (await h2.say('316L')).result as AnswerResult;
    expect(a.show!.fields['material_a'], 'ss304L');
    expect(a.show!.fields['material_b'], 'ss316L');
  });
  test('unsupported grade or process entered in a follow-up reports the gap',
      () async {
    for (final grade in ['316Ti', '904L', 'S355J2', 'tytan']) {
      final h = BrainHarness();
      await h.say('spoiwo do 316L TIG');
      expect(
          ((await h.say(grade)).result as FailedResult).reportMissingCapability,
          isTrue);
    }
    final h = BrainHarness();
    await h.say('spoiwo 316L ten sam');
    expect(
        ((await h.say('114')).result as FailedResult).reportMissingCapability,
        isTrue);
  });
  test('material order and explicitly repeated same grade are preserved',
      () async {
    final a = (await BrainHarness().say('spoiwo 316L i 304L TIG')).result
        as AnswerResult;
    expect(a.show!.fields['material_a'], 'ss316L');
    expect(a.show!.fields['material_b'], 'ss304L');
    final b = (await BrainHarness().say('spoiwo 316L z 316L TIG')).result
        as AnswerResult;
    expect(b.show!.fields['material_b'], 'ss316L');
  });
  test('mixed spoken and typed grades preserve the requested side order',
      () async {
    final a = (await BrainHarness()
            .say('spoiwo trzysta szesnaście L i 304L TIG', byVoice: true))
        .result as AnswerResult;
    expect(a.show!.fields['material_a'], 'ss316L');
    expect(a.show!.fields['material_b'], 'ss304L');
  });
  test('grade-like numbers with extra digits do not match a known grade',
      () async {
    expect(
        ((await BrainHarness().say('spoiwo 3161 TIG')).result as AskResult)
            .slot,
        'a');
  });
  testWidgets(
      'handle fills real selection and rejects partial or extra fields atomically',
      (t) async {
    ToolBridge.reset();
    t.view.physicalSize = const Size(1000, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(),
        child: const MaterialApp(home: FillerSelectorPage())));
    await t.pumpAndSettle();
    final handle = ToolBridge.instance.current!;
    await t.tap(find.text('Rozcieńczenie'));
    await t.pumpAndSettle();
    final dilution = find.byKey(const ValueKey('dilution-share-a'));
    await t.ensureVisible(dilution);
    await t.enterText(dilution, '37');
    await t.pumpAndSettle();
    expect(
        await handle.apply(
            {'material_a': 'ss304L', 'material_b': 'ss316L', 'process': 'mma'}),
        isEmpty);
    await t.pumpAndSettle();
    expect(find.textContaining('316L'), findsWidgets);
    final chip = find.byKey(const ValueKey('filler-process-mma'));
    expect(t.widget<ChoiceChip>(chip).selected, isTrue);
    final before = find.textContaining('316L').evaluate().length;
    expect(
        await handle.apply({
          'material_a': 'carbonSteel',
          'material_b': 'carbonSteel',
          'process': 'tig',
          'confirmed': true
        }),
        isNotEmpty);
    await t.pumpAndSettle();
    expect(t.widget<ChoiceChip>(chip).selected, isTrue);
    expect(find.textContaining('316L').evaluate().length, before);
    await t.tap(find.text('Rozcieńczenie'));
    await t.pumpAndSettle();
    final editable =
        find.descendant(of: dilution, matching: find.byType(EditableText));
    expect(t.widget<EditableText>(editable).controller.text, '37');
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    ToolBridge.reset();
  });
}
