import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/electrodes_status_skill.dart';
import 'package:cut_list_app/domain/welding/electrode_exposure.dart';
import 'package:cut_list_app/features/electrode_exposure/electrode_batch_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import 'support/assistant_test_support.dart';

final now = DateTime(2026, 10, 19, 12);
ElectrodeBatch batch(String id,
        {int ago = 10, int limit = 240, String location = ''}) =>
    ElectrodeBatch.takenOut(
        id: id,
        electrode: ElectrodeClass.e7018,
        at: now.subtract(Duration(minutes: ago)),
        limitMinutes: limit,
        location: location);

Future<AnswerResult> ask(String text,
    {AppLanguage lang = AppLanguage.pl}) async {
  final h = BrainHarness(lang: lang, electrodes: readLocalElectrodeBatches);
  final r = await h.say(text);
  expect(r.match?.skill.id, 'electrodes.status');
  return r.result as AnswerResult;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('real preference data uses recorded limits, paused oven and urgency',
      () async {
    final oven = batch('oven', ago: 60, location: 'Piecyk')
        .returnToOven(now.subtract(const Duration(minutes: 40)));
    await const ElectrodeBatchStore().save([
      batch('ok', ago: 10, limit: 17),
      oven,
      batch('exceeded', ago: 300),
      batch('consumed').close(now, BatchClosure.consumed),
    ]);
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(kElectrodeBatchesPrefsKey);
    final result = await ask('ile jeszcze mogą leżeć elektrody?');
    expect(result.answer.lines, hasLength(3));
    expect(
        result.answer.lines.first.value, contains('przekroczony o 1 h 00 min'));
    expect(result.answer.lines[1].value, contains('pozostało 7 min'));
    expect(result.answer.lines[1].value, contains('Zapisany limit: 17 min'));
    expect(result.answer.lines.last.value,
        contains('licznik wstrzymany; pozostało 3 h 40 min'));
    expect(result.answer.text.pl, contains('2026-10-19 12:00'));
    expect(result.show?.fields, isEmpty);
    expect(prefs.getString(kElectrodeBatchesPrefsKey), before);
    expect(prefs.containsKey(kElectrodeBatchesCorruptPrefsKey), isFalse);
  });

  test('exact ID or location includes closed batches and retains accents',
      () async {
    await const ElectrodeBatchStore().save([
      batch('one', location: 'Łódź-2').close(now, BatchClosure.consumed),
      batch('two', location: 'Lodz-2').close(now, BatchClosure.scrapped),
    ]);
    final byPlace = await ask('stan partii elektrod Łódź-2?');
    expect(byPlace.answer.lines, hasLength(1));
    expect(byPlace.answer.lines.single.value,
        startsWith('Zużyte — partia zamknięta'));
    final byId = await ask('Electrode batch status two', lang: AppLanguage.en);
    expect(
        byId.answer.lines.single.value, startsWith('Scrapped — closed batch'));
    expect((await ask('status moich elektrod')).answer.lines, isEmpty);
    expect((await ask('stan partii elektrod missing')).answer.text.pl,
        contains('Nie znalazłem'));
  });

  test('exceeded batch stays exceeded in oven; excessive re-drying is visible',
      () async {
    final exceeded = batch('old', ago: 300)
        .returnToOven(now.subtract(const Duration(minutes: 10)));
    final redried = batch('redried')
        .redried(now.subtract(const Duration(minutes: 5)))
        .redried(now.subtract(const Duration(minutes: 1)));
    await const ElectrodeBatchStore().save([exceeded, redried]);
    final result = await ask('sprawdź stan moich elektrod');
    expect(result.answer.lines.first.value, contains('przekroczony o 50 min'));
    expect(result.answer.lines.first.value, isNot(contains('wstrzymany')));
    expect(result.answer.lines.last.value,
        contains('Suszenia: 2/1 — przekroczony limit suszeń'));
  });

  test('future timestamps are not treated as a new full exposure allowance',
      () async {
    await const ElectrodeBatchStore().save([batch('future', ago: -60)]);
    final result = await ask('status moich elektrod');
    expect(result.answer.lines.single.value,
        'Data z przyszłości — nie mogę ocenić');
  });

  test('sub-minute remaining time and exceedance are not rounded to zero',
      () async {
    await const ElectrodeBatchStore().save([
      ElectrodeBatch.takenOut(
          id: 'ending',
          electrode: ElectrodeClass.e7018,
          at: now.subtract(const Duration(hours: 3, minutes: 59, seconds: 1))),
      ElectrodeBatch.takenOut(
          id: 'over',
          electrode: ElectrodeClass.e7018,
          at: now.subtract(const Duration(hours: 4, seconds: 1))),
    ]);
    final result = await ask('status moich elektrod');
    expect(result.answer.lines.first.value,
        contains('przekroczony o mniej niż 1 min'));
    expect(
        result.answer.lines.last.value, contains('pozostało mniej niż 1 min'));
  });

  test('lossy, malformed and wrong-type preferences never become an empty log',
      () async {
    for (final raw in [
      '{bad-json',
      123,
      jsonEncode([
        {'id': 'lost'}
      ]),
      jsonEncode([batch('invalid-limit').toJson()..['lim'] = 0]),
      jsonEncode([batch('invalid-redry').toJson()..['maxR'] = -1]),
      jsonEncode([batch('fractional-count').toJson()..['r'] = -0.5]),
      jsonEncode([batch('fractional-time').toJson()..['prior'] = 0.5]),
    ]) {
      SharedPreferences.setMockInitialValues({kElectrodeBatchesPrefsKey: raw});
      final h = BrainHarness(electrodes: readLocalElectrodeBatches);
      final r = (await h.say('status moich elektrod')).result as FailedResult;
      expect(r.message.pl, contains('niepełny lub niespójny'));
      expect(r.reportMissingCapability, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(kElectrodeBatchesPrefsKey), raw);
      expect(prefs.containsKey(kElectrodeBatchesCorruptPrefsKey), isFalse);
    }
  });

  test('empty state differs from load errors and production reader reloads',
      () async {
    expect((await ask('status moich elektrod')).answer.text.pl,
        contains('Brak aktywnych'));
    await const ElectrodeBatchStore().save([batch('new')]);
    expect((await ask('status moich elektrod')).answer.lines, hasLength(1));
    await const ElectrodeBatchStore().save([]);
    expect((await ask('status moich elektrod')).answer.lines, isEmpty);
    final h =
        BrainHarness(electrodes: () async => throw StateError('secret-path'));
    final r = (await h.say('status moich elektrod')).result as FailedResult;
    expect(r.message.pl, isNot(contains('secret-path')));
    expect(r.reportMissingCapability, isFalse);
  });

  test('voice personal queries do not enter table reference or perform writes',
      () async {
    var reads = 0;
    final h = BrainHarness(electrodes: () async {
      reads++;
      return BatchDecodeResult([batch('voice')], lossy: false);
    });
    final quoted = await h.say('wyjaśnij polecenie "status moich elektrod"',
        byVoice: true);
    expect(quoted.match?.skill.id, isNot('electrodes.status'));
    expect(reads, 0);
    final personal =
        await h.say('ile jeszcze mogą leżeć elektrody?', byVoice: true);
    expect(personal.match?.skill.id, 'electrodes.status');
    expect(reads, 1);
    expect(h.actions.savedParams, isEmpty);
    expect(h.actions.savedJournal, isEmpty);
    final reference =
        await h.say('ile czasu na powietrzu E7018 bez R z piecyka');
    expect(reference.match?.skill.id, 'electrodes.exposure');
    expect(reads, 1);
  });
}
