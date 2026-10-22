import '../support/test_account.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/records/interpass_reading_skill.dart';
import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/features/interpass/interpass_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

class SelectedWeld extends FixedModuleContext implements RecordModuleContext {
  const SelectedWeld(this.id) : super(activeToolId: 'interpass');
  final String id;
  @override
  String? selectedRecordId(String toolId) => toolId == 'interpass' ? id : null;
}

void main() {
  useGuestAccount();
  final now = DateTime(2026, 10, 21, 12);
  const store = InterpassStore();
  InterpassWeld weld(
          {String id = 'w1',
          String name = 'W-12',
          String description = 'Linia A'}) =>
      InterpassWeld.blank(id: id, now: now).copyWith(
          weldNo: name,
          description: description,
          wpsRef: 'WPS-1',
          passCount: 3,
          limits: const InterpassLimits(
              preheatMin: InterpassTemp.c(100),
              interpassMax: InterpassTemp.c(150)));
  AssistantContext ctx({ModuleContext modules = const FixedModuleContext()}) =>
      AssistantContext(lang: AppLanguage.pl, modules: modules, now: () => now);
  Future<InterpassWeld> saved(String id) async =>
      (await store.load()).welds.singleWhere((w) => w.id == id);
  Future<SkillResult> command(String text, {AssistantContext? context}) async {
    final c = context ?? ctx();
    final skill = InterpassReadingSkill(newId: () => 'operation');
    return skill.run(
        skill.match(Utterance(text, lang: AppLanguage.pl, byVoice: true), c)!,
        c);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AssistantHistoryStore.instance.resetForTest();
  });
  const complete =
      'Zapisz pomiar temperatury 120 C przed ściegiem 2 termometr kontaktowy teraz spoina W-12';
  test('preview, confirmed reading and undo preserve every original field',
      () async {
    final before = weld();
    await store.upsert(before);
    final result = await command(complete) as ConfirmResult;
    expect(result.touchOnly, false);
    expect((await saved('w1')).readings, isEmpty);
    expect(result.show!.fields, {'weld_id': 'w1'});
    final undo = await result.perform();
    final after = await saved('w1');
    expect(after.readings.single.pass, 2);
    expect(after.readings.single.tempC, 120);
    expect(after.readings.single.method, InterpassMethod.contact);
    expect(after.toJson()..remove('readings'),
        before.toJson()..remove('readings'));
    expect(AssistantHistoryStore.instance.entries.single.byVoice, true);
    await undo!();
    expect((await saved('w1')).toJson(), before.toJson());
    expect(AssistantHistoryStore.instance.entries.single.undone, true);
  });
  test('dialogue asks all missing facts without writing', () async {
    await store.upsert(weld());
    final h = BrainHarness();
    h.clock = now;
    expect(((await h.say('Dodaj pomiar temperatury')).result as AskResult).slot,
        'temperature');
    expect(((await h.say('120 C')).result as AskResult).slot, 'pass');
    expect(
        ((await h.say('przed ściegiem 2')).result as AskResult).slot, 'method');
    expect(((await h.say('pirometr')).result as AskResult).slot, 'at');
    expect(((await h.say('teraz')).result as AskResult).slot, 'weld');
    expect((await h.say('W-12')).result, isA<ConfirmResult>());
    expect((await saved('w1')).readings, isEmpty);
  });
  test(
      'active editor identifies the actual record instead of the latest record',
      () async {
    await store.upsert(weld());
    await store.upsert(weld(id: 'other', name: 'Other'));
    final result = await command(complete.replaceAll(' spoina W-12', ''),
        context: ctx(modules: const SelectedWeld('w1'))) as ConfirmResult;
    await result.perform();
    expect((await saved('w1')).readings, hasLength(1));
    expect((await saved('other')).readings, isEmpty);
  });
  test('selected weld is captured at the beginning of a multi-turn command',
      () async {
    await store.upsert(weld());
    await store.upsert(weld(id: 'other', name: 'Other'));
    final skill = InterpassReadingSkill();
    final start = skill.match(
        Utterance('Dodaj pomiar temperatury',
            lang: AppLanguage.pl, byVoice: true),
        ctx(modules: const SelectedWeld('w1')))!;
    final result = await skill.run(
        start.copyWith(slots: {
          ...start.slots,
          'temperature': 120,
          'unit': 'c',
          'pass': 2,
          'method': 'contact',
          'at': now.millisecondsSinceEpoch
        }),
        ctx(modules: const SelectedWeld('other'))) as ConfirmResult;
    await result.perform();
    expect((await saved('w1')).readings, hasLength(1));
    expect((await saved('other')).readings, isEmpty);
    expect(AssistantHistoryStore.instance.entries.single.byVoice, true);
  });
  test(
      'spoken numbers, below-zero temperature and fractional passes use explicit units',
      () async {
    await store.upsert(weld());
    final result = await command(
            'Dodaj pomiar minus dwadzieścia stopni Celsjusza przed ściegiem dwa pirometr teraz spoina W-12')
        as ConfirmResult;
    await result.perform();
    expect((await saved('w1')).readings.single.tempC, -20);
    expect(await command(complete.replaceFirst('ściegiem 2', 'ściegiem 3/4')),
        isA<AskResult>());
  });
  test('contradictory crayon outcomes ask instead of choosing', () async {
    await store.upsert(weld());
    final result = await command(
            'Dodaj pomiar 150 C przed ściegiem 2 kredka stopiła się i nie stopiła się teraz spoina W-12')
        as AskResult;
    expect(result.slot, 'bound');
    expect((await saved('w1')).readings, isEmpty);
  });
  test(
      'labelled note is preserved without interpreting its numbers as commands',
      () async {
    await store.upsert(weld());
    final result = await command(
            '$complete uwaga: Poprzednio 250 C, pass 9, WPS-2 — sprawdzić czujnik')
        as ConfirmResult;
    await result.perform();
    final reading = (await saved('w1')).readings.single;
    expect(reading.pass, 2);
    expect(reading.tempC, 120);
    expect(reading.note, 'Poprzednio 250 C, pass 9, WPS-2 — sprawdzić czujnik');
  });
  test('duplicate weld numbers require an explicit choice', () async {
    await store.upsert(weld());
    await store.upsert(weld(id: 'w2', description: 'Linia B'));
    final result = await command(complete) as AskResult;
    expect(result.slot, 'record_id');
    expect(result.choices, hasLength(2));
    final h = BrainHarness();
    h.clock = now;
    await h.say(complete);
    final confirm = (await h.say('wybierz w2')).result as ConfirmResult;
    await confirm.perform();
    expect((await saved('w1')).readings, isEmpty);
    expect((await saved('w2')).readings, hasLength(1));
  });
  test('later manual edits prevent commit and prevent undo', () async {
    await store.upsert(weld());
    final confirm = await command(complete) as ConfirmResult;
    await store.update('w1', (w) => w.copyWith(wpsRef: 'WPS-2'));
    await expectLater(confirm.perform(), throwsStateError);
    expect((await saved('w1')).wpsRef, 'WPS-2');
    final newer = await command(complete) as ConfirmResult;
    final undo = await newer.perform();
    await store.update('w1', (w) => w.copyWith(description: 'Ręczna poprawka'));
    await expectLater(undo!(), throwsStateError);
    expect((await saved('w1')).readings, hasLength(1));
  });
  test('two parallel confirmations produce a single reading', () async {
    await store.upsert(weld());
    final a = await command(complete) as ConfirmResult;
    final b = await command(complete) as ConfirmResult;
    var failures = 0;
    Future<void> perform(ConfirmResult c) async {
      try {
        await c.perform();
      } catch (_) {
        failures++;
      }
    }

    await Future.wait([perform(a), perform(b)]);
    expect(failures, 1);
    expect((await saved('w1')).readings, hasLength(1));
  });
  test(
      'crayon asks outcome, keeps threshold and does not invent exact temperature',
      () async {
    await store.upsert(weld());
    final h = BrainHarness();
    h.clock = now;
    expect(
        ((await h.say(
                    'Dodaj pomiar 150 C przed ściegiem 2 kredka teraz spoina W-12'))
                .result as AskResult)
            .slot,
        'bound');
    final confirm = (await h.say('nie stopiła się')).result as ConfirmResult;
    await confirm.perform();
    expect((await saved('w1')).readings.single.bound, InterpassBound.below);
    expect((await saved('w1')).readings.single.temp.value, 150);
  });
  test('Fahrenheit and backdated timestamp are retained', () async {
    await store.upsert(weld());
    final confirm = await command(complete
        .replaceFirst('120 C', '250 F')
        .replaceFirst('teraz', '2026-10-21 10:30')) as ConfirmResult;
    await confirm.perform();
    final reading = (await saved('w1')).readings.single;
    expect(reading.temp.unit, InterpassUnit.f);
    expect(reading.temp.value, 250);
    expect(reading.tempC, closeTo(121.1111, .001));
    expect(reading.backdated, true);
  });
  for (final replacement in [
    '120 C przed ściegiem -1',
    '120 C przed ściegiem 1.5',
    '120 C przed ściegiem 4',
    '1200 C przed ściegiem 2',
    '120 130 C przed ściegiem 2',
    '120 C i 130 C przed ściegiem 2'
  ]) {
    test('rejects ambiguous or invalid measurement $replacement', () async {
      await store.upsert(weld());
      final text = complete.replaceFirst('120 C przed ściegiem 2', replacement);
      expect(await command(text), isNot(isA<ConfirmResult>()));
      expect((await saved('w1')).readings, isEmpty);
    });
  }
  test('corrupt log and later damage prevent all assistant writes', () async {
    await store.upsert(weld());
    final confirm = await command(complete) as ConfirmResult;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(InterpassStore.key, 'broken');
    await expectLater(confirm.perform(), throwsStateError);
    expect(prefs.getString(InterpassStore.key), 'broken');
    expect(await command(complete), isA<FailedResult>());
  });
  test('missing weld and future or invalid calendar time do not save',
      () async {
    expect(await command(complete), isA<FailedResult>());
    await store.upsert(weld());
    for (final time in ['2026-10-22 12:00', '2026-02-30 12:00']) {
      expect(await command(complete.replaceFirst('teraz', time)),
          isA<AskResult>());
    }
  });
  test('CAS never changes other welds or accepts a different record id',
      () async {
    final before = weld();
    await store.upsert(before);
    final other = weld(id: 'other', name: 'Other');
    await store.upsert(other);
    expect(await store.replaceIfUnchanged(before, other), false);
    final confirm = await command(complete) as ConfirmResult;
    await confirm.perform();
    expect(jsonEncode((await saved('other')).toJson()),
        jsonEncode(other.toJson()));
  });
  test('a pass reply does not merge two separate numeric tokens', () {
    final skill = InterpassReadingSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    expect(skill.fillSlot('pass', Utterance('2 4', lang: AppLanguage.pl), ctx),
        isNull);
    expect(skill.fillSlot('pass', Utterance('2,0', lang: AppLanguage.pl), ctx),
        {'pass': 2.0});
  });
}
