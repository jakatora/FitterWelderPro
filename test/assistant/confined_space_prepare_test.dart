import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/records/confined_space_prepare_skill.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';
import 'package:cut_list_app/features/confined_space/confined_space_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_gas.dart';
import 'support/assistant_test_support.dart';

void main() {
  final now = DateTime(2026, 10, 21, 12);
  final store = ConfinedSpaceStore(clock: () => now);
  Future<List<ConfinedSpaceRecord>> records() async =>
      (await store.load()).records;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AssistantHistoryStore.instance.resetForTest();
  });
  AssistantContext context() => AssistantContext(
      lang: AppLanguage.pl,
      modules: const FixedModuleContext(),
      now: () => now);

  test('confirmed draft changes only whitelisted organisational fields',
      () async {
    final skill = ConfinedSpacePrepareSkill(newId: () => 'draft');
    final ctx = context();
    final m = SkillMatch(skill, 1, slots: {
      'location': 'Hala A',
      'description': 'Spawanie podpory',
      'permitNo': 'P-12',
      'entrants': 'Jan',
      'attendant': 'Anna',
      'supervisor': 'Piotr',
      'issuer': 'Ewa',
      'rescue': 'Straż zakładowa',
      'requiredGases': [],
      'processes': [],
      'checked': ['all'],
      'na': ['all'],
      'measurements': [0],
      'limits': const CsLimits({}),
      'maxAgeMin': 999,
      'date': '2099-01-01',
      'notes': 'ready',
    });
    final result = await skill.run(m, ctx) as ConfirmResult;
    expect(result.touchOnly, isTrue);
    expect(skill.safetyCritical, isTrue);
    expect(skill.readOnly, isFalse);
    expect(await records(), isEmpty);
    final undo = await result.perform();
    final draft = (await records()).single;
    final expected = ConfinedSpaceRecord.blank(id: 'draft', now: now).copyWith(
        location: 'Hala A',
        description: 'Spawanie podpory',
        permitNo: 'P-12',
        entrants: 'Jan',
        attendant: 'Anna',
        supervisor: 'Piotr',
        issuer: 'Ewa',
        rescue: 'Straż zakładowa');
    expect(draft.toJson(), expected.toJson());
    expect(draft.assess(now: now).readyToEnter, isFalse);
    expect(result.show?.fields, {'record_id': 'draft'});
    await undo!();
    expect(await records(), isEmpty);
    expect(AssistantHistoryStore.instance.entries.single.undone, isTrue);
  });

  test(
      'real brain asks missing fields sequentially and preserves labelled data',
      () async {
    final h = BrainHarness();
    final start = await h.say('Przygotuj protokół przestrzeni zamkniętej');
    expect(start.match?.skill.id, 'confined_space.prepare');
    expect((start.result as AskResult).slot, 'location');
    expect(((await h.say('Hala B')).result as AskResult).slot, 'description');
    final summary = (await h.say('Spawanie wspornika')).result as ConfirmResult;
    expect(summary.summary.lines.map((l) => l.value),
        containsAll(['Hala B', 'Spawanie wspornika']));
    expect(await records(), isEmpty);
  });

  test(
      'undo refuses later edits, leaving measurements and unrelated permits intact',
      () async {
    final skill = ConfinedSpacePrepareSkill(newId: () => 'draft');
    final ctx = context();
    final summary = await skill.run(
        SkillMatch(skill, 1, slots: {'location': 'A', 'description': 'B'}),
        ctx) as ConfirmResult;
    final undo = await summary.perform();
    final saved = (await records()).single;
    final edited = saved.copyWith(
        description: 'Ręczna poprawka',
        updatedAt: 999,
        measurements: [
          CsMeasurement(
              id: 'manual',
              time: '12:00',
              at: now.millisecondsSinceEpoch,
              values: const {CsGas.o2: CsQty(20.9, CsUnit.pctVol)})
        ]);
    await store.upsert(edited);
    await store.upsert(ConfinedSpaceRecord.blank(id: 'other', now: now)
        .copyWith(location: 'Inny'));
    await expectLater(undo!(), throwsStateError);
    expect((await records()).map((p) => p.id).toSet(), {'draft', 'other'});
    expect((await records()).singleWhere((p) => p.id == 'draft').description,
        'Ręczna poprawka');
    expect(
        (await records())
            .singleWhere((p) => p.id == 'draft')
            .measurements
            .single
            .values[CsGas.o2]!
            .value,
        20.9);
    expect(AssistantHistoryStore.instance.entries.single.undone, isFalse);
  });

  test('repeated confirmation never overwrites an existing record', () async {
    final skill = ConfinedSpacePrepareSkill(newId: () => 'draft');
    final result = await skill.run(
        SkillMatch(skill, 1, slots: {'location': 'A', 'description': 'B'}),
        context()) as ConfirmResult;
    await result.perform();
    await expectLater(result.perform(), throwsStateError);
    expect(await records(), hasLength(1));
  });

  test(
      'conflicting labels and overlong data do not save or silently pick a value',
      () async {
    final skill = ConfinedSpacePrepareSkill();
    final ctx = context();
    final u = Utterance(
        'Przygotuj protokół przestrzeni zamkniętej, miejsce: A; miejsce: B; opis: Cięcie',
        lang: AppLanguage.pl);
    expect(await skill.run(skill.match(u, ctx)!, ctx), isA<FailedResult>());
    expect(
        await skill.run(
            SkillMatch(skill, 1,
                slots: {'location': 'A' * 1001, 'description': 'B'}),
            ctx),
        isA<FailedResult>());
    expect(await records(), isEmpty);
  });

  test('full or damaged history refuses creation without replacing old data',
      () async {
    final full = jsonEncode(confinedSpaceRecordsToJson([
      for (var i = 0; i < ConfinedSpaceStore.maxEntries; i++)
        ConfinedSpaceRecord.blank(id: 'old-$i', now: now)
            .copyWith(location: 'Existing'),
    ]));
    for (final raw in [full, '{broken']) {
      SharedPreferences.setMockInitialValues({ConfinedSpaceStore.key: raw});
      final skill = ConfinedSpacePrepareSkill(newId: () => 'new');
      final result = await skill.run(
          SkillMatch(skill, 1, slots: {'location': 'A', 'description': 'B'}),
          context()) as ConfirmResult;
      await expectLater(result.perform(), throwsA(anything));
      expect(
          (await SharedPreferences.getInstance())
              .getString(ConfinedSpaceStore.key),
          raw);
      expect(AssistantHistoryStore.instance.entries, isEmpty);
    }
  });

  test(
      'labelled PL/EN roles are parsed explicitly without inferred assignments',
      () async {
    for (final lang in AppLanguage.values) {
      final skill =
          ConfinedSpacePrepareSkill(newId: () => 'roles-${lang.name}');
      final ctx = AssistantContext(
          lang: lang, modules: const FixedModuleContext(), now: () => now);
      final en = lang == AppLanguage.en;
      final u = Utterance(
          en
              ? 'Prepare confined space form, location: Tank A; description: Cleaning; permit number: CS-2; entrants: Jan and Ewa; attendant: Anna; supervisor: Piotr; issuer: Ola; rescue: Rescue team'
              : 'Przygotuj protokół przestrzeni zamkniętej, miejsce: Zbiornik A; opis prac: Czyszczenie; numer pozwolenia: CS-2; wchodzący: Jan i Ewa; asekurujący: Anna; nadzór: Piotr; wystawiający: Ola; ratownictwo: Zespół R',
          lang: lang,
          byVoice: true);
      final result =
          await skill.run(skill.match(u, ctx)!, ctx) as ConfirmResult;
      expect(result.touchOnly, isTrue);
      await result.perform();
      final saved =
          (await records()).singleWhere((r) => r.id == 'roles-${lang.name}');
      expect(saved.entrants, en ? 'Jan and Ewa' : 'Jan i Ewa');
      expect(saved.attendant, 'Anna');
      expect(saved.supervisor, 'Piotr');
      expect(saved.issuer, 'Ola');
      expect(saved.rescue, en ? 'Rescue team' : 'Zespół R');
      expect(saved.permitNo, 'CS-2');
      expect(saved.checked, isEmpty);
      expect(saved.measurements, isEmpty);
    }
  });

  test('a summary from the previous day requires a fresh draft', () async {
    var current = now;
    final ctx = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(),
        now: () => current);
    final skill = ConfinedSpacePrepareSkill();
    final result = await skill.run(
        SkillMatch(skill, 1, slots: {'location': 'A', 'description': 'B'}),
        ctx) as ConfirmResult;
    current = now.add(const Duration(days: 1));
    await expectLater(result.perform(), throwsStateError);
    expect(
        (await SharedPreferences.getInstance())
            .containsKey(ConfinedSpaceStore.key),
        isFalse);
  });
}
