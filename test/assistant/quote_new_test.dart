import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/records/quote_new_skill.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_quote_dao.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/domain/quotes/quote_process.dart';
import 'package:cut_list_app/domain/quotes/quote_calculator.dart';
import 'package:cut_list_app/services/quote_settings.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import 'support/assistant_test_support.dart';

void main() {
  useTestDatabase();
  final now = DateTime(2026, 10, 21, 12);
  final dao = WeldQuoteDao(clock: () => now.millisecondsSinceEpoch);
  const store = QuoteSettingsStore();
  const settings = QuoteSettings(
      baseRates: QuoteRates(welderRate: 175.5, fitterRate: 130, marginPct: 17),
      fillerPrices: {
        QuoteMaterial.stainless: {QuoteProcess.tig: 333}
      },
      validityDays: 14);
  AssistantContext ctx() => AssistantContext(
      lang: AppLanguage.pl,
      modules: const FixedModuleContext(),
      now: () => now);
  const complete = 'Utwórz wycenę stal nierdzewna TIG + MMA w warsztacie';
  Future<SkillResult> command(String text, {String id = 'new'}) async {
    final skill = QuoteNewSkill(dao: dao, newId: () => id);
    return skill.run(
        skill.match(
            Utterance(text, lang: AppLanguage.pl, byVoice: true), ctx())!,
        ctx());
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AssistantHistoryStore.instance.resetForTest();
    await (await AppDatabase.get()).delete(WeldQuoteDao.table);
    await store.save(settings);
  });
  test(
      'preview, commit and guarded undo operate on real SQLite and keep a rate snapshot',
      () async {
    final result = await command(
            '$complete tytuł: Kolektor; klient: Firma A; notatka: TIG 250 zł')
        as ConfirmResult;
    expect(await dao.listAll(), isEmpty);
    expect(result.touchOnly, false);
    expect(result.show!.fields, {'quote_id': 'new'});
    await store
        .save(settings.copyWith(baseRates: const QuoteRates(welderRate: 999)));
    final undo = await result.perform();
    final saved = (await dao.byId('new'))!;
    expect(saved.status, QuoteStatus.draft);
    expect(saved.number, 'WYC/2026/001');
    expect(saved.rates.welderRate, 175.5);
    expect(saved.rates.fillerPriceOf(QuoteProcess.tig), 333);
    expect(saved.joints, isEmpty);
    expect(saved.extras, isEmpty);
    expect(saved.title, 'Kolektor');
    expect(saved.client, 'Firma A');
    expect(saved.notes, 'TIG 250 zł');
    expect(saved.validityDays, 14);
    expect(saved.material, QuoteMaterial.stainless);
    expect(saved.scheme.code, 'TIG+MMA');
    expect(saved.site, QuoteSite.shop);
    expect(saved.purge, true);
    expect(computeQuote(saved).netGrosze, 0);
    expect(AssistantHistoryStore.instance.entries.single.byVoice, true);
    await undo!();
    expect(await dao.listAll(), isEmpty);
    expect((await dao.byId('new'))!.isDeleted, true);
    expect(AssistantHistoryStore.instance.entries.single.undone, true);
    final next = await command(complete, id: 'next') as ConfirmResult;
    await next.perform();
    expect((await dao.byId('next'))!.number, 'WYC/2026/002');
  });
  test('process labels and ISO numbers do not become extra processes',
      () async {
    final result =
        await command(complete.replaceFirst('TIG + MMA', 'TIG 141 + MMA 111'))
            as ConfirmResult;
    await result.perform();
    expect((await dao.byId('new'))!.scheme.code, 'TIG+MMA');
    expect(
        await command(complete.replaceFirst('TIG + MMA', 'TIG + 138'),
            id: 'unsupported'),
        isA<AskResult>());
  });
  for (final price in [
    'stawka spawacza 200 zł',
    'VAT 8 procent',
    'welder rate 99 PLN',
    'rabat 10 procent',
    '200 zł'
  ]) {
    test(
        'explicit financial changes are not silently replaced with template rates: $price',
        () async {
      final result = await command('$complete $price') as FailedResult;
      expect(result.reportMissingCapability, true);
      expect(await dao.listAll(), isEmpty);
    });
  }
  test('dialogue asks material, scheme, site without selecting defaults',
      () async {
    final h = BrainHarness();
    h.clock = now;
    expect(
        ((await h.say('Utwórz wycenę')).result as AskResult).slot, 'material');
    expect(((await h.say('aluminium')).result as AskResult).slot, 'scheme');
    expect(((await h.say('MIG')).result as AskResult).slot, 'site');
    expect((await h.say('na obiekcie')).result, isA<ConfirmResult>());
    expect(await dao.listAll(), isEmpty);
  });
  test(
      'concurrent drafts receive distinct numbers and duplicate ID never replaces anything',
      () async {
    final a = await command(complete, id: 'a') as ConfirmResult;
    final b = await command(complete, id: 'b') as ConfirmResult;
    await Future.wait([a.perform(), b.perform()]);
    final quotes = await dao.listAll();
    expect(
        quotes.map((q) => q.number).toSet(), {'WYC/2026/001', 'WYC/2026/002'});
    await expectLater(a.perform(), throwsA(isA<Exception>()));
    expect(await dao.listAll(), hasLength(2));
  });
  test('manual rate edits, sent status and damaged JSON prevent undo',
      () async {
    for (final id in ['price', 'sent', 'damaged']) {
      final confirm = await command(complete, id: id) as ConfirmResult;
      final undo = await confirm.perform();
      final saved = (await dao.byId(id))!;
      if (id == 'price') {
        await dao
            .save(saved.copyWith(rates: saved.rates.copyWith(welderRate: 222)));
      }
      if (id == 'sent') {
        await dao.save(saved.copyWith(status: QuoteStatus.sent));
      }
      if (id == 'damaged') {
        await (await AppDatabase.get()).update(
            WeldQuoteDao.table, {'data_json': 'broken'},
            where: 'id = ?', whereArgs: [id]);
      }
      await expectLater(undo!(), throwsStateError);
      expect((await dao.byId(id))!.isDeleted, false);
    }
  });
  test(
      'unknown slots cannot set prices, mark the offer accepted or add quoted work',
      () async {
    final skill = QuoteNewSkill(dao: dao, newId: () => 'whitelist');
    final match =
        skill.match(Utterance(complete, lang: AppLanguage.pl), ctx())!;
    final result = await skill.run(
        match.copyWith(slots: {
          ...match.slots,
          'rates': const QuoteRates(welderRate: 1),
          'status': 'ACCEPTED',
          'number': 'HACK',
          'joints': ['fake'],
          'extras': ['fake'],
          'deletedAt': 123
        }),
        ctx()) as ConfirmResult;
    await result.perform();
    final saved = (await dao.byId('whitelist'))!;
    expect(saved.status, QuoteStatus.draft);
    expect(saved.rates.welderRate, 175.5);
    expect(saved.number, 'WYC/2026/001');
    expect(saved.joints, isEmpty);
    expect(saved.extras, isEmpty);
    expect(saved.deletedAt, isNull);
    final expected = WeldQuote(
        id: 'whitelist',
        number: 'WYC/2026/001',
        material: QuoteMaterial.stainless,
        scheme:
            const WeldScheme(root: QuoteProcess.tig, fill: QuoteProcess.mma),
        site: QuoteSite.shop,
        purge: true,
        rates: settings.ratesFor(QuoteMaterial.stainless),
        validityDays: 14,
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch);
    expect(saved.toRow(netGrosze: 0, grossGrosze: 0),
        expected.toRow(netGrosze: 0, grossGrosze: 0));
  });
  for (final raw in <Object>[
    'broken',
    7,
    '[]',
    '{"rates":{"welder":"100"}}',
    '{"rates":{"welder":-1}}',
    '{"filler":{"SS":{"TIG":"9"}}}',
    '{"scheme":"UNKNOWN"}',
    '{"validity":1.5}'
  ]) {
    test('invalid template never silently supplies other prices: $raw',
        () async {
      final prefs = await SharedPreferences.getInstance();
      if (raw is String) {
        await prefs.setString(QuoteSettingsStore.key, raw);
      } else {
        await prefs.setInt(QuoteSettingsStore.key, raw as int);
      }
      expect(await command(complete), isA<FailedResult>());
      expect(await dao.listAll(), isEmpty);
    });
  }
  test(
      'valid older partial template keeps known rate and documents module defaults',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        QuoteSettingsStore.key,
        jsonEncode({
          'rates': {'welder': 123}
        }));
    final result = await command(complete) as ConfirmResult;
    await result.perform();
    expect((await dao.byId('new'))!.rates.welderRate, 123);
  });
  for (final commandText in [
    'Utwórz wycenę stal nierdzewna TIG lub MMA w warsztacie',
    'Utwórz wycenę stal nierdzewna i aluminium TIG w warsztacie',
    'Utwórz wycenę stal nierdzewna TIG w warsztacie i na obiekcie'
  ]) {
    test('ambiguous choice asks instead of guessing: $commandText', () async {
      expect(await command(commandText), isA<AskResult>());
      expect(await dao.listAll(), isEmpty);
    });
  }
}
