// Zapisy w rejestrach głosem/tekstem: kupon do logu kuponów i wpis
// trawienia/pasywacji. Nic nie trafia do rejestru bez dotknięcia
// „Potwierdź” (touchOnly); „Cofnij” tylko dla niezmienionego wpisu.

import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/records/coupon_add_skill.dart';
import 'package:cut_list_app/assistant/skills/records/passivation_add_skill.dart';
import 'package:cut_list_app/database/coupon_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/passivation_dao.dart';
import 'package:cut_list_app/domain/passivation/passivation_record.dart';
import 'package:cut_list_app/domain/weld_journal/coupon_entry.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_database.dart';
import 'support/assistant_test_support.dart';

void main() {
  useTestDatabase();
  final now = DateTime(2026, 10, 23, 9);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AssistantHistoryStore.instance.resetForTest();
    final db = await AppDatabase.get();
    for (final t in [
      'weld_coupon_history',
      'weld_coupons',
      'passivation_records'
    ]) {
      await db.delete(t);
    }
  });
  AssistantContext context([AppLanguage lang = AppLanguage.pl]) =>
      AssistantContext(
          lang: lang, modules: const FixedModuleContext(), now: () => now);

  group('coupon.add', () {
    test('etykiety → karta potwierdzenia; zapis dopiero po dotknięciu',
        () async {
      final skill =
          CouponAddSkill(stamp: () async => 'XX-9', newId: () => 'c1');
      final m = skill.match(
          Utterance(
              'Dodaj kupon, spawacz: JK-12; maszyna: M-3; wymiar: 2 cale; '
              'tlen: 20 ppm; uwagi: przetop równy',
              lang: AppLanguage.pl),
          context())!;
      final r = await skill.run(m, context()) as ConfirmResult;
      expect(r.touchOnly, isTrue);
      expect(await CouponDao().listAll(), isEmpty);
      final undo = await r.perform();
      final c = (await CouponDao().listAll()).single;
      expect(c.id, 'c1');
      expect(c.date, '2026-10-23');
      expect(c.welder, 'JK-12', reason: 'podany stempel wygrywa z profilem');
      expect(c.machine, 'M-3');
      expect(c.size, '2 cale');
      expect(c.o2Ppm, 20);
      expect(c.result, CouponResult.pending,
          reason: 'bez pola wynik czeka na ocenę — nie OK domyślnie');
      expect(c.notes, 'przetop równy');
      expect(r.show?.toolId, 'coupon_log');
      expect(AssistantHistoryStore.instance.entries.single.kind, 'coupon.add');

      await undo!();
      expect(await CouponDao().listAll(), isEmpty);
      expect((await CouponDao().listAll(includeDeleted: true)).single.isDeleted,
          isTrue,
          reason: 'cofnięcie = miękkie usunięcie z historią, jak w logu');
      expect(AssistantHistoryStore.instance.entries.single.undone, isTrue);
    });

    test('stempel z profilu, wynik słowami, brak stempla → pytanie', () async {
      final withProfile =
          CouponAddSkill(stamp: () async => 'AB-1', newId: () => 'c2');
      final ok = await withProfile.run(
          withProfile.match(
              Utterance('Zapisz kupon, wynik: przeszedł', lang: AppLanguage.pl),
              context())!,
          context()) as ConfirmResult;
      await ok.perform();
      final c = (await CouponDao().listAll()).single;
      expect(c.welder, 'AB-1');
      expect(c.result, CouponResult.ok);

      final noProfile = CouponAddSkill(stamp: () async => null);
      final ask = await noProfile.run(
          noProfile.match(
              Utterance('Dodaj kupon', lang: AppLanguage.pl), context())!,
          context());
      expect((ask as AskResult).slot, 'welder');

      final bad = await withProfile.run(
          withProfile.match(
              Utterance('Dodaj kupon, wynik: chyba', lang: AppLanguage.pl),
              context())!,
          context());
      expect(bad, isA<FailedResult>());
    });

    test('cofnięcie odmawia po edycji kuponu', () async {
      final skill =
          CouponAddSkill(stamp: () async => 'AB-1', newId: () => 'c3');
      final r = await skill.run(
          skill.match(
              Utterance('Dodaj kupon', lang: AppLanguage.pl), context())!,
          context()) as ConfirmResult;
      final undo = await r.perform();
      final c = (await CouponDao().listAll()).single;
      await CouponDao().update(c.copyWith(result: CouponResult.nok));
      await expectLater(undo!(), throwsStateError);
      expect((await CouponDao().listAll()).single.result, CouponResult.nok);
    });

    test('router: zapis kuponu nie miesza się ze stanem logu ani spoiną', () {
      bool add(String s) =>
          isCouponAddRequest(Utterance(s, lang: AppLanguage.pl).folded);
      expect(add('dodaj kupon'), isTrue);
      expect(add('nowy kupon próbny'), isTrue);
      expect(add('log a new coupon, welder: JK-12'), isTrue);
      expect(add('ile kuponów dzisiaj'), isFalse);
      expect(add('stan logu kuponów'), isFalse);
      expect(add('dodaj kupon do spoiny W-12'), isFalse);
    });
  });

  group('passivation.add', () {
    test('wpis z etykiet, zabieg z polecenia, liczby z jednostkami', () async {
      final skill =
          PassivationAddSkill(stamp: () async => 'JK-12', newId: () => 'p1');
      final m = skill.match(
          Utterance(
              'Zapisz trawienie, linia: WFI-101; środek: pasta Avesta; '
              'partia: B-7; czas: 60 min; temperatura: 18,5; '
              'płukanie: 4 µS/cm; test: ferroksyl; wynik: OK',
              lang: AppLanguage.pl),
          context())!;
      final r = await skill.run(m, context()) as ConfirmResult;
      expect(r.touchOnly, isTrue);
      expect(await PassivationDao().listAll(), isEmpty);
      final undo = await r.perform();
      final p = (await PassivationDao().listAll()).single;
      expect(p.treatment, PassivationTreatment.pickling);
      expect(p.line, 'WFI-101');
      expect(p.agent, 'pasta Avesta');
      expect(p.agentBatch, 'B-7');
      expect(p.dwellMin, 60);
      expect(p.tempC, 18.5);
      expect(p.rinseUsCm, 4);
      expect(p.testMethod, 'ferroksyl');
      expect(p.testResult, PassivationResult.ok);
      expect(p.byStamp, 'JK-12');
      expect(p.date, '2026-10-23');
      expect(r.show?.toolId, 'passivation');

      await undo!();
      expect(await PassivationDao().listAll(), isEmpty);
      expect(AssistantHistoryStore.instance.entries.single.undone, isTrue);
    });

    test('bez linii/pakietu/obszaru pyta; błędna liczba nie zapisuje',
        () async {
      final skill = PassivationAddSkill(stamp: () async => null);
      final ask = await skill.run(
          skill.match(
              Utterance('Zapisz pasywację', lang: AppLanguage.pl), context())!,
          context());
      expect((ask as AskResult).slot, 'line');
      final bad = await skill.run(
          skill.match(
              Utterance('Zapisz pasywację, linia: L1; czas: długo',
                  lang: AppLanguage.pl),
              context())!,
          context());
      expect(bad, isA<FailedResult>());
      expect(await PassivationDao().listAll(), isEmpty);
    });

    test('cofnięcie odmawia po edycji wpisu', () async {
      final skill =
          PassivationAddSkill(stamp: () async => null, newId: () => 'p2');
      final r = await skill.run(
          skill.match(
              Utterance('Zapisz pasywację, linia: L2', lang: AppLanguage.pl),
              context())!,
          context()) as ConfirmResult;
      final undo = await r.perform();
      final p = await PassivationDao().byId('p2');
      await PassivationDao().save(PassivationRecord(
          id: p!.id,
          date: p.date,
          line: 'L2',
          notes: 'poprawione',
          createdAt: p.createdAt,
          updatedAt: p.updatedAt));
      await expectLater(undo!(), throwsStateError);
      expect((await PassivationDao().listAll()).single.notes, 'poprawione');
    });

    test(
        'polecenia wygenerowane przez prawdziwego Haiku (2026-10-23) '
        'dają właściwe wpisy', () async {
      Future<ConfirmResult> run(AssistantSkill skill, String command) async =>
          await skill.run(
              skill.match(Utterance(command, lang: AppLanguage.pl), context())!,
              context()) as ConfirmResult;
      final coupon = CouponAddSkill(stamp: () async => 'ZZ-1');
      final c1 =
          await run(coupon, 'Dodaj kupon, tlen: 20 ppm; uwagi: kupon próbny');
      expect(c1.summary.lines.map((l) => l.value),
          containsAll(['ZZ-1', '20 ppm', 'do oceny', 'kupon próbny']));
      final c2 = await run(coupon, 'Dodaj kupon, spawacz: AB-1; wynik: OK');
      expect(c2.summary.lines.map((l) => l.value), containsAll(['AB-1', 'OK']));

      final pas = PassivationAddSkill(stamp: () async => null);
      final p1 = await run(pas,
          'Zapisz pasywację, linia: WFI-101; środek: pasta Avesta; czas: 60 min; test: ferroksyl; wynik: OK');
      expect(
          p1.summary.lines.map((l) => l.value),
          containsAll([
            'Pasywacja',
            'WFI-101',
            'pasta Avesta',
            '60 min',
            'ferroksyl',
            'OK'
          ]));
      final p2 = await run(pas,
          'Zapisz trawienie, obszar: spoiny W-001 do W-040; pakiet: TP-12');
      expect(p2.summary.lines.map((l) => l.value),
          containsAll(['Trawienie', 'spoiny W-001 do W-040', 'TP-12']));
    });

    test('mózg: polecenie trafia w zapis, pytanie w stan rejestru', () async {
      final h = BrainHarness();
      final add = await h.say('Zapisz pasywację, linia: WFI-101');
      expect(add.match?.skill.id, 'passivation.add');
      expect(add.result, isA<ConfirmResult>());
      final coupon = await h.say('Dodaj kupon, spawacz: JK-12');
      expect(coupon.match?.skill.id, 'coupon.add');
      expect(await CouponDao().listAll(), isEmpty,
          reason: 'bez dotknięcia nic nie zapisano');
    });
  });
}
