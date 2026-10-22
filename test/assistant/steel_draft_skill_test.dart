import '../support/test_account.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart'
    show assistantNumber;
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_tables/steel_draft_skill.dart';
import 'package:cut_list_app/assistant/skills/fitter_tables/steel_weight_skill.dart';
import 'package:cut_list_app/domain/steel_weight/steel_draft_fields.dart';
import 'package:cut_list_app/domain/steel_weight/steel_sections.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'steel_weight_skill_test.dart' show MemoryOrderStore;

void main() {
  useGuestAccount();
  useTestDatabase();
  test('AI source guards preserve dimensions, quantity and draft scope', () {
    final edit = SteelDraftEditSkill(), weight = SteelWeightSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String s) => Utterance(s, lang: AppLanguage.pl);
    expect(
        edit.acceptsProposal(
            u('Potrzebuje 5 takich sztuk'), u('Ustaw ilosc na 5'), ctx),
        true);
    expect(
        edit.acceptsProposal(
            u('Niech dlugosc wynosi 3 m'), u('Ustaw dlugosc na 3000 mm'), ctx),
        true);
    for (final source in [
      'Potrzebuje 6 takich sztuk',
      'Zmien cene na 5',
      'Ustaw ilosc na -5',
      'Zapisz 5 sztuk na liscie',
      'Jak ustawic ilosc na 5',
      'Przetlumacz set quantity to 5',
      'Ustaw ilosc na 5 i dlugosc na 3 m'
    ]) {
      expect(edit.acceptsProposal(u(source), u('Ustaw ilosc na 5'), ctx), false,
          reason: source);
    }
    final original = weight.examples.first.pl;
    expect(weight.acceptsProposal(u(original), u(original), ctx), true);
    expect(
        weight.acceptsProposal(
            u(original), u(original.replaceFirst('6 m', '7 m')), ctx),
        false);
    expect(
        weight.acceptsProposal(u('masa IPE 200 dlugosc 6 m'), u(original), ctx),
        false);
  });
  testWidgets(
      'native live draft supports all shapes without saving orders or prices',
      (t) async {
    final store = MemoryOrderStore();
    await mount(t,
        home: SteelWeightPage(store: store),
        interpret: (_) async =>
            throw StateError('Literal draft edit is local'));
    final b = ToolBridge.instance, handle = ToolBridge.instance.current!;
    for (final shape in SteelShape.values) {
      final fields = <String, Object?>{
        'shape': shape.name,
        'material': 'stainless316',
        if (shape.tabulated) 'section': sectionsOf(shape).first.name,
        'a_mm': 100.0,
        'b_mm': 80.0,
        't_mm': 4.0,
        'length_mm': 2000.0,
        'quantity': 2,
      };
      expect(steelDraftFromFields(fields), isNotNull, reason: shape.name);
      expect(await handle.apply(fields), isEmpty, reason: shape.name);
      await settle(t);
      final base = Map<String, Object?>.of(b.inputFields('steel_weight')!);
      expect(base['quantity'], 2);
      await say(t, 'Zmien dlugosc na 3 m');
      expect(b.inputFields('steel_weight'), {...base, 'length_mm': 3000.0},
          reason: shape.name);
      await say(t, 'Ustaw ilosc na 5');
      final updated = {...base, 'length_mm': 3000.0, 'quantity': 5};
      expect(b.inputFields('steel_weight'), updated, reason: shape.name);
      await say(t, 'Ile wazy biezaca pozycja');
      final mass = assistantNumber(
          steelDraftFromFields(updated)!.totalKg, AppLanguage.pl);
      expect(find.textContaining('$mass kg.'), findsWidgets);
      expect(b.current, same(handle));
      expect(b.inputFields('steel_weight'), updated);
    }
    expect(store.saves, 0);
    expect(store.original.pricePerKg, 4.5);
    expect(store.original.items.single.section, 'IPE 100');
    expect(t.takeException(), isNull);
  });
  for (final changed in [false, true]) {
    testWidgets(
        'AI natural quantity uses actual live draft and discards changed snapshot: $changed',
        (t) async {
      final store = MemoryOrderStore();
      final pending = Completer<AiCommandPlan>();
      var calls = 0;
      await mount(t, home: SteelWeightPage(store: store), interpret: (request) {
        calls++;
        expect((request['context'] as Map)['inputs']['material'], 'carbon');
        return pending.future;
      });
      final b = ToolBridge.instance;
      final before = Map<String, Object?>.of(b.inputFields('steel_weight')!);
      await say(t, 'Potrzebuje 5 takich sztuk');
      expect(calls, 1);
      final base = {...before, if (changed) 'material': 'aluminium'};
      if (changed) {
        await b.current!.apply(base);
        await settle(t);
      }
      pending.complete(const AiCommandPlan('execute',
          [AiCommandStep('steel.draft.edit', 'Ustaw ilosc na 5')], ''));
      await settle(t);
      expect(b.inputFields('steel_weight'),
          {...base, if (!changed) 'quantity': 5});
      expect(store.saves, 0);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('saved-list tab and popup cannot be edited as the current draft',
      (t) async {
    final store = MemoryOrderStore();
    await mount(t,
        home: SteelWeightPage(store: store),
        interpret: (_) async => throw StateError('Local action'));
    final b = ToolBridge.instance;
    final base = Map<String, Object?>.of(b.inputFields('steel_weight')!);
    await t.tap(find.byKey(const ValueKey('sw-tab-list')));
    await settle(t);
    expect(b.inputFields('steel_weight'), isEmpty);
    await say(t, 'Ustaw ilosc na 5');
    expect(b.inputFields('steel_weight'), isEmpty);
    await t.tap(find.byKey(const ValueKey('sw-tab-profile')));
    await settle(t);
    expect(b.inputFields('steel_weight'), base);
    final handle = b.current!;
    final context = t.element(find.byType(SteelWeightPage));
    final dialog = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Hold')));
    await t.pumpAndSettle();
    expect(await handle.apply({...base, 'quantity': 5}), isNotEmpty);
    Navigator.of(context).pop();
    await dialog;
    await settle(t);
    expect(b.inputFields('steel_weight'), base);
    expect(store.saves, 0);
  });
  testWidgets(
      'manual inputs remain authoritative; explicit repair changes only the requested field',
      (t) async {
    final store = MemoryOrderStore();
    await mount(t,
        home: SteelWeightPage(store: store),
        interpret: (_) async => throw StateError('Local edit'));
    final b = ToolBridge.instance;
    final field = find.descendant(
        of: find.byKey(const ValueKey('sw-count')),
        matching: find.byType(TextField));
    await t.ensureVisible(field);
    await t.enterText(field, '7');
    await settle(t);
    expect(b.inputFields('steel_weight')!['quantity'], 7);
    await say(t, 'Zmien dlugosc na 3 m');
    expect(b.inputFields('steel_weight')!['quantity'], 7);
    expect(b.inputFields('steel_weight')!['length_mm'], 3000);
    final refreshed = find.descendant(
        of: find.byKey(const ValueKey('sw-count')),
        matching: find.byType(TextField));
    await t.ensureVisible(refreshed);
    await t.enterText(refreshed, '0');
    await settle(t);
    expect(b.inputFields('steel_weight')!['quantity'], 0);
    final invalid = Map<String, Object?>.of(b.inputFields('steel_weight')!);
    await say(t, 'Zmien dlugosc na 4 m');
    expect(b.inputFields('steel_weight'), invalid);
    await say(t, 'Ustaw ilosc na 5');
    expect(b.inputFields('steel_weight'), {...invalid, 'quantity': 5});
    expect(store.saves, 0);
    expect(t.takeException(), isNull);
  });
  test(
      'generic edits never steal another module; invalid quantities and units refuse',
      () {
    final edit = SteelDraftEditSkill();
    final here = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(activeToolId: 'steel_weight'));
    for (final id in [null, 'cone_layout', 'rolling_offset']) {
      final other = AssistantContext(
          lang: AppLanguage.pl, modules: FixedModuleContext(activeToolId: id));
      expect(
          edit.match(
              Utterance('Ustaw dlugosc na 3 m', lang: AppLanguage.pl), other),
          isNull);
    }
    for (final bad in [
      'Ustaw ilosc na 0',
      'Ustaw ilosc na 1,5',
      'Ustaw ilosc na 2147483648',
      'Ustaw dlugosc na -3 m',
      'Ustaw dlugosc na 3',
      'Ustaw dlugosc na 3 m cm',
      'Ustaw dlugosc na 3 m i ilosc na 5'
    ]) {
      expect(edit.match(Utterance(bad, lang: AppLanguage.pl), here), isNull,
          reason: bad);
    }
  });
  testWidgets(
      'spoken natural count reaches native draft and rejects invented AI count',
      (t) async {
    final store = MemoryOrderStore(), speech = FixtureSpeech();
    var calls = 0;
    await mount(t, home: SteelWeightPage(store: store), speech: speech,
        interpret: (_) async {
      calls++;
      return AiCommandPlan(
          'execute',
          [
            AiCommandStep('steel.draft.edit',
                calls == 1 ? 'Ustaw ilosc na 6' : 'Ustaw ilosc na 5')
          ],
          '');
    });
    final b = ToolBridge.instance;
    final base = Map<String, Object?>.of(b.inputFields('steel_weight')!);
    for (final expected in [1, 5]) {
      await t.tap(find.byKey(const Key('assistant-mic')));
      await settle(t);
      speech.emit('Potrzebuje piec takich sztuk');
      await settle(t);
      expect(b.inputFields('steel_weight'), {...base, 'quantity': expected});
    }
    expect(calls, 2);
    expect(store.saves, 0);
    expect(t.takeException(), isNull);
  });
  for (final wrong in [false, true]) {
    testWidgets(
        'AI continuation uses manual current shape, not earlier conversation: wrong=$wrong',
        (t) async {
      final store = MemoryOrderStore();
      var calls = 0;
      await mount(t, home: SteelWeightPage(store: store),
          interpret: (request) async {
        calls++;
        expect((request['context'] as Map)['inputs']['shape'], 'hollow');
        expect((request['context'] as Map)['inputs']['material'], 'aluminium');
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep(
                  wrong ? 'steel.weight' : 'steel.draft.edit',
                  wrong
                      ? SteelWeightSkill().examples.first.pl
                      : 'Zmien dlugosc stali na 3 m')
            ],
            '');
      });
      await say(t, SteelWeightSkill().examples.first.pl);
      final b = ToolBridge.instance;
      final manual = <String, Object?>{
        'shape': 'hollow',
        'a_mm': 100.0,
        'b_mm': 80.0,
        't_mm': 4.0,
        'length_mm': 2500.0,
        'quantity': 7,
        'material': 'aluminium'
      };
      expect(await b.current!.apply(manual), isEmpty);
      await settle(t);
      final before = Map<String, Object?>.of(b.inputFields('steel_weight')!);
      await say(t, 'A dlugosc 3 m');
      expect(calls, 1);
      expect(b.inputFields('steel_weight'),
          {...before, if (!wrong) 'length_mm': 3000.0});
      expect(store.saves, 0);
      expect(t.takeException(), isNull);
    });
  }
}
