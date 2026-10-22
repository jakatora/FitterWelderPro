import 'package:cut_list_app/database/local_record_owner.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/records/interpass_reading_skill.dart';
import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/features/interpass/interpass_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import '../support/test_account.dart';

class DelayedInterpassStore extends InterpassStore {
  final loaded = Completer<void>();
  final release = Completer<void>();
  @override
  Future<InterpassLoad> load() async {
    final value = await super.load();
    loaded.complete();
    await release.future;
    return value;
  }
}

void main() {
  useGuestAccount();
  final now = DateTime(2026, 10, 22, 12);
  const store = InterpassStore();
  Future<SkillResult> preview({InterpassStore source = store}) {
    final skill =
        InterpassReadingSkill(store: source, newId: () => 'operation');
    final ctx = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(),
        now: () => now);
    final u = Utterance(
        'Zapisz pomiar temperatury 120 C przed ściegiem 2 termometr kontaktowy teraz spoina W-12',
        lang: AppLanguage.pl);
    return skill.run(skill.match(u, ctx)!, ctx);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AssistantHistoryStore.instance.resetForTest();
    await store.upsert(InterpassWeld.blank(id: 'w1', now: now)
        .copyWith(weldNo: 'W-12', passCount: 3));
  });
  test('storage CAS refuses a captured owner after session transition',
      () async {
    final before = (await store.load()).welds.single;
    final owner = await LocalRecordOwner.capture();
    await seedSignedInAccount();
    await expectLater(
        store.replaceIfUnchanged(before, before.copyWith(description: 'stale'),
            expectedOwner: owner),
        throwsA(isA<AccountException>()));
    expect((await store.load()).welds.single.description, isEmpty);
  });
  test('queued storage CAS rechecks owner when its turn begins', () async {
    final before = (await store.load()).welds.single;
    final owner = await LocalRecordOwner.capture();
    final outcome = Completer<Object>();
    Future<void>? erasure;
    await store.update('w1', (w) {
      store
          .replaceIfUnchanged(
              before, before.copyWith(description: 'stale queued write'),
              expectedOwner: owner)
          .then((value) => outcome.complete(value),
              onError: (Object error) => outcome.complete(error));
      erasure = AccountService.instance.invalidateSession();
      return w;
    });
    await erasure;
    expect(await outcome.future, isA<AccountException>());
    expect((await store.load()).welds.single.description, isEmpty);
  });
  test('preview cannot commit after account changes', () async {
    final result = await preview() as ConfirmResult;
    await seedSignedInAccount();
    await expectLater(result.perform(), throwsA(isA<AccountException>()));
    expect((await store.load()).welds.single.readings, isEmpty);
    expect(AssistantHistoryStore.instance.entries, isEmpty);
  });
  test('committed reading history and undo stay with the preview owner',
      () async {
    await seedSignedInAccount();
    final result = await preview() as ConfirmResult;
    final undo = await result.perform();
    expect(AssistantHistoryStore.instance.entries.single.ownerScope,
        'account:test-account');
    await seedGuestAccount();
    expect(AssistantHistoryStore.instance.entries, isEmpty);
    await expectLater(undo!(), throwsA(isA<AccountException>()));
    expect((await store.load()).welds.single.readings, hasLength(1));
  });
  test('delayed read cannot produce a preview for a different account',
      () async {
    final delayed = DelayedInterpassStore();
    final result = preview(source: delayed);
    await delayed.loaded.future;
    await seedSignedInAccount();
    delayed.release.complete();
    expect(await result, isA<FailedResult>());
    expect((await store.load()).welds.single.readings, isEmpty);
  });
}
