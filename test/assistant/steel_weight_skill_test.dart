import '../support/test_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_tables/steel_weight_skill.dart';
import 'package:cut_list_app/domain/steel_weight/steel_weight.dart';
import 'package:cut_list_app/domain/steel_weight/steel_sections.dart';
import 'package:cut_list_app/domain/steel_weight/steel_draft_fields.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_page.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

class MemoryOrderStore extends SteelOrderStore {
  final original = const SteelOrder(items: [
    SteelItem(
        shape: SteelShape.ipe, section: 'IPE 100', lengthMm: 1000, count: 1)
  ], pricePerKg: 4.5);
  int saves = 0;
  @override
  Future<SteelOrder> load() async => original;
  @override
  Future<void> save(SteelOrder order) async {
    saves++;
  }
}

void main() {
  useGuestAccount();
  for (final designation in [
    'IPE200',
    'HEA200',
    'HEB200',
    'HEM200',
    'UPN200',
    'UPE200'
  ]) {
    test('attached standard designation is recognized: $designation', () async {
      final r = (await BrainHarness()
              .say('oblicz masę $designation długość 1 m ilość 1 stal węglowa'))
          .result as AnswerResult;
      expect(r.show!.fields['section'], '${designation.substring(0, 3)} 200');
    });
  }
  for (final product in [
    'kątownika L50×50×5',
    'kątownika L60×40×5',
    'pręta kwadratowego bok 20 mm'
  ]) {
    test('additional product types use existing domain: $product', () async {
      final r = (await BrainHarness()
              .say('masa $product długość 1 m ilość 1 stal węglowa'))
          .result;
      expect(r, isA<AnswerResult>());
    });
  }

  for (final ex in SteelWeightSkill().examples) {
    test('complete example calculates rather than asking: ${ex.pl}', () async {
      expect((await BrainHarness().say(ex.pl)).result, isA<AnswerResult>());
      expect((await BrainHarness(lang: AppLanguage.en).say(ex.en)).result,
          isA<AnswerResult>());
    });
  }
  test('IPE 200 uses tabulated 22.4 kg/m and 12 m total without costs',
      () async {
    final r = (await BrainHarness()
            .say('oblicz masę IPE 200 długość 6 m ilość 2 stal konstrukcyjna'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('22,4 kg/m'));
    expect(r.answer.text.pl, contains('268,8 kg'));
    expect(r.show!.fields.containsKey('price'), isFalse);
    expect(r.answer.source!.pl, contains('EN 10365'));
  });
  test(
      'joint dimensions, length, count and material are collected with no defaults',
      () async {
    final h = BrainHarness();
    expect((await h.say('oblicz wagę IPE')).result, isA<AskResult>());
    expect((await h.say('200')).result, isA<AskResult>());
    expect((await h.say('6 m')).result, isA<AskResult>());
    expect((await h.say('2')).result, isA<AskResult>());
    final r = (await h.say('stal węglowa')).result as AnswerResult;
    expect(r.show!.fields['section'], 'IPE 200');
    expect(r.show!.fields['quantity'], 2);
  });
  test('plate dimensions produce 353.25 kg for one sheet', () async {
    final r = (await BrainHarness().say(SteelWeightSkill().examples[2].pl))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('78,5 kg/m²'));
    expect(r.answer.text.pl, contains('353,25 kg'));
  });
  for (final text in [
    'masa IPE 999 długość 6 m ilość 2 stal konstrukcyjna',
    'masa IPE 200 długość minus 6 m ilość 2 stal konstrukcyjna',
    'masa IPE 200 długość 6 m ilość 1,5 stal konstrukcyjna',
    'masa IPE 200 długość 6 m ilość 2 304L 316L',
    'masa profilu zamkniętego wysokość 10 mm szerokość 10 mm ścianka 8 mm długość 1 m ilość 1 stal węglowa',
  ]) {
    test('invalid steel data never fills calculator: $text', () async {
      expect(
          (await BrainHarness().say(text)).result, isNot(isA<AnswerResult>()));
    });
  }
  test('wire format cannot inject prices or arbitrary profile names', () {
    final f = {
      'shape': 'ipe',
      'section': 'IPE 200',
      'material': 'carbon',
      'length_mm': 6000,
      'quantity': 2
    };
    expect(steelDraftFromFields(f), isNotNull);
    expect(steelDraftFromFields({...f, 'unitPrice': -10}), isNull);
    expect(steelDraftFromFields({...f, 'section': 'IPE 999'}), isNull);
    expect(steelDraftFromFields({...f, 'quantity': 1.5}), isNull);
  });
  testWidgets(
      'only fills calculation draft; existing material list and prices are never saved',
      (tester) async {
    final store = MemoryOrderStore();
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: SteelWeightPage(store: store))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness().say(SteelWeightSkill().examples.first.pl))
        .result as AnswerResult;
    var showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.appliedInPlace);
    expect(find.text('22,40 kg/m'), findsOneWidget);
    expect(find.text('Lista (1)'), findsOneWidget);
    final handle = ToolBridge.instance.current!;
    expect(await handle.apply({...r.show!.fields, 'quantity': double.nan}),
        isNotEmpty);
    expect(await handle.apply({...r.show!.fields, 'price': 10}), isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(store.saves, 0);
    expect(store.original.items.single.section, 'IPE 100');
    expect(store.original.pricePerKg, 4.5);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(store.saves, 0);
  });
}
