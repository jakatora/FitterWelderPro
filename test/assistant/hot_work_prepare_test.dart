import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/records/hot_work_prepare_skill.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/features/hot_work/hot_work_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  final now = DateTime(2026, 10, 21, 12);
  const store = HotWorkStore();
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
    final skill = HotWorkPrepareSkill(newId: () => 'draft');
    final ctx = context();
    final m = SkillMatch(skill, 1, slots: {
      'location': 'Hala A',
      'description': 'Spawanie podpory',
      'permitNo': 'P-12',
      'contractor': 'Jan',
      'securedBy': 'Anna',
      'fireWatch': 'Piotr',
      'issuer': 'Ewa',
      'checked': ['all'],
      'na': ['all'],
      'measurements': [0],
      'dgwLimitPct': 100,
      'measurementMaxAgeMin': 999,
      'date': '2099-01-01',
      'notes': 'ready',
    });
    final result = await skill.run(m, ctx) as ConfirmResult;
    expect(result.touchOnly, isTrue);
    expect(skill.safetyCritical, isTrue);
    expect(skill.readOnly, isFalse);
    expect(await store.load(), isEmpty);
    final undo = await result.perform();
    final draft = (await store.load()).single;
    final expected = HotWorkPermit.blank(id: 'draft', now: now).copyWith(
        location: 'Hala A',
        description: 'Spawanie podpory',
        permitNo: 'P-12',
        contractor: 'Jan',
        securedBy: 'Anna',
        fireWatch: 'Piotr',
        issuer: 'Ewa');
    expect(draft.toJson(), expected.toJson());
    expect(draft.assess(now: now).readyToStart, isFalse);
    expect(result.show?.fields, {'permit_id': 'draft'});
    await undo!();
    expect(await store.load(), isEmpty);
    expect(AssistantHistoryStore.instance.entries.single.undone, isTrue);
  });

  test(
      'real brain asks missing fields sequentially and preserves labelled data',
      () async {
    final h = BrainHarness();
    final start = await h.say('Przygotuj protokół prac gorących');
    expect(start.match?.skill.id, 'hot_work.prepare');
    expect((start.result as AskResult).slot, 'location');
    expect(((await h.say('Hala B')).result as AskResult).slot, 'description');
    final summary = (await h.say('Spawanie wspornika')).result as ConfirmResult;
    expect(summary.summary.lines.map((l) => l.value),
        containsAll(['Hala B', 'Spawanie wspornika']));
    expect(await store.load(), isEmpty);
  });

  test(
      'undo refuses later edits, leaving measurements and unrelated permits intact',
      () async {
    final skill = HotWorkPrepareSkill(newId: () => 'draft');
    final ctx = context();
    final summary = await skill.run(
        SkillMatch(skill, 1, slots: {'location': 'A', 'description': 'B'}),
        ctx) as ConfirmResult;
    final undo = await summary.perform();
    final saved = (await store.load()).single;
    final edited = saved.copyWith(
        description: 'Ręczna poprawka',
        updatedAt: 999,
        measurements: [const HotWorkMeasurement(time: '12:00', dgwPct: 3)]);
    await store.upsert(edited);
    await store.upsert(
        HotWorkPermit.blank(id: 'other', now: now).copyWith(location: 'Inny'));
    await expectLater(undo!(), throwsStateError);
    expect((await store.load()).map((p) => p.id).toSet(), {'draft', 'other'});
    expect((await store.load()).singleWhere((p) => p.id == 'draft').description,
        'Ręczna poprawka');
    expect(
        (await store.load())
            .singleWhere((p) => p.id == 'draft')
            .measurements
            .single
            .dgwPct,
        3);
    expect(AssistantHistoryStore.instance.entries.single.undone, isFalse);
  });

  test('repeated confirmation never overwrites an existing record', () async {
    final skill = HotWorkPrepareSkill(newId: () => 'draft');
    final result = await skill.run(
        SkillMatch(skill, 1, slots: {'location': 'A', 'description': 'B'}),
        context()) as ConfirmResult;
    await result.perform();
    await expectLater(result.perform(), throwsStateError);
    expect(await store.load(), hasLength(1));
  });

  test(
      'conflicting labels and overlong data do not save or silently pick a value',
      () async {
    final skill = HotWorkPrepareSkill();
    final ctx = context();
    final u = Utterance(
        'Przygotuj protokół prac gorących, miejsce: A; miejsce: B; opis: Cięcie',
        lang: AppLanguage.pl);
    expect(await skill.run(skill.match(u, ctx)!, ctx), isA<FailedResult>());
    expect(
        await skill.run(
            SkillMatch(skill, 1,
                slots: {'location': 'A' * 1001, 'description': 'B'}),
            ctx),
        isA<FailedResult>());
    expect(await store.load(), isEmpty);
  });

  test('full or damaged history refuses creation without replacing old data',
      () async {
    final full = jsonEncode(hotWorkPermitsToJson([
      for (var i = 0; i < HotWorkStore.maxEntries; i++)
        HotWorkPermit.blank(id: 'old-$i', now: now)
            .copyWith(location: 'Existing'),
    ]));
    for (final raw in [full, '{broken']) {
      SharedPreferences.setMockInitialValues({HotWorkStore.key: raw});
      final skill = HotWorkPrepareSkill(newId: () => 'new');
      final result = await skill.run(
          SkillMatch(skill, 1, slots: {'location': 'A', 'description': 'B'}),
          context()) as ConfirmResult;
      await expectLater(result.perform(), throwsA(anything));
      expect(
          (await SharedPreferences.getInstance()).getString(HotWorkStore.key),
          raw);
      expect(AssistantHistoryStore.instance.entries, isEmpty);
    }
  });

  test('a summary from the previous day requires a fresh draft', () async {
    var current = now;
    final ctx = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(),
        now: () => current);
    final skill = HotWorkPrepareSkill();
    final result = await skill.run(
        SkillMatch(skill, 1, slots: {'location': 'A', 'description': 'B'}),
        ctx) as ConfirmResult;
    current = now.add(const Duration(days: 1));
    await expectLater(result.perform(), throwsStateError);
    expect(
        (await SharedPreferences.getInstance()).containsKey(HotWorkStore.key),
        isFalse);
  });
}
