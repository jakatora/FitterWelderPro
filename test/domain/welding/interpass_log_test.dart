// Temperatura podgrzania i międzyściegowa: ocena pomiaru na granicy, przed
// pierwszym ściegiem vs między ściegami, brak limitu z WPS, kredka (tylko
// próg), pomiar wsteczny i zmiana nocna, °C↔°F bez zmiany danych i bez
// artefaktów przeliczenia, minimalny odstęp sąsiednich ściegów, pominięte
// uszkodzone pomiary, pusta min. międzyściegowa, werdykt spoiny, JSON
// i uszkodzony JSON — bez platformy, zegar podawany wprost.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/domain/welding/interpass_text.dart';

DateTime at(int h, [int m = 0, int s = 0]) => DateTime(2026, 10, 17, h, m, s);
int ms(int h, [int m = 0, int s = 0]) => at(h, m, s).millisecondsSinceEpoch;

InterpassReading rd(int pass, double c,
        {int? when,
        InterpassBound bound = InterpassBound.exact,
        InterpassMethod method = InterpassMethod.contact,
        InterpassUnit unit = InterpassUnit.c,
        int? recorded}) =>
    InterpassReading(
      pass: pass,
      temp: unit == InterpassUnit.c
          ? InterpassTemp.c(c)
          : InterpassTemp.entered(c, unit),
      bound: bound,
      method: bound == InterpassBound.exact ? method : InterpassMethod.crayon,
      at: when ?? ms(7, pass),
      recordedAt: recorded ?? when ?? ms(7, pass),
    );

final p91 = InterpassLimits.celsius(
    preheatMinC: 200, interpassMaxC: 300, interpassMinC: 200);
final cmn = InterpassLimits.celsius(preheatMinC: 100, interpassMaxC: 250);

InterpassWeld weld(List<InterpassReading> readings,
        {InterpassLimits? limits, int? passCount}) =>
    InterpassWeld(
      id: 'w1',
      weldNo: 'S-12',
      limits: limits ?? cmn,
      passCount: passCount,
      readings: readings,
      createdAt: ms(7),
      updatedAt: ms(7),
    );

Map<String, Object?> _reading(int pass, num c, int when,
        {String bound = 'exact'}) =>
    {
      'pass': pass,
      'temp': {'v': c, 'u': 'c'},
      'bound': bound,
      'method': 'contact',
      'at': when,
    };

void main() {
  group('ocena pomiaru', () {
    test('na granicy: równość z limitem = OK, 0,01 °C dalej — poza', () {
      expect(interpassCheck(rd(1, 100), cmn), InterpassCheck.ok);
      expect(interpassCheck(rd(1, 99.99), cmn), InterpassCheck.low);
      expect(interpassCheck(rd(2, 250), cmn), InterpassCheck.ok);
      expect(interpassCheck(rd(2, 250.01), cmn), InterpassCheck.high);
      // Min. międzyściegowa (P91 — wg WPS) też włącznie.
      expect(interpassCheck(rd(3, 200), p91), InterpassCheck.ok);
      expect(interpassCheck(rd(3, 199.99), p91), InterpassCheck.low);
      expect(interpassCheck(rd(3, 300), p91), InterpassCheck.ok);
    });

    test('przed pierwszym ściegiem — vs min. podgrzania; między — vs maks.',
        () {
      // 280 °C przed ściegiem 1: podgrzanie spełnione, maks. go nie dotyczy.
      expect(interpassCheck(rd(1, 280), cmn), InterpassCheck.ok);
      // 280 °C przed ściegiem 2: powyżej maks. międzyściegowej.
      expect(interpassCheck(rd(2, 280), cmn), InterpassCheck.high);
      // 80 °C przed ściegiem 1: za zimno; przed ściegiem 2 (bez min.
      // międzyściegowej) — w limicie maks.
      expect(interpassCheck(rd(1, 80), cmn), InterpassCheck.low);
      expect(interpassCheck(rd(2, 80), cmn), InterpassCheck.ok);
      expect(interpassPhaseOf(1), InterpassPhase.preheat);
      expect(interpassPhaseOf(2), InterpassPhase.interpass);
    });

    test('brak limitu z WPS — neutralnie, ani OK, ani błąd', () {
      const none = InterpassLimits();
      expect(interpassCheck(rd(1, 150), none), InterpassCheck.noLimit);
      expect(interpassCheck(rd(2, 150), none), InterpassCheck.noLimit);
      // Tylko maks.: ścieg 1 bez limitu podgrzania.
      final onlyMax = InterpassLimits.celsius(interpassMaxC: 250);
      expect(interpassCheck(rd(1, 150), onlyMax), InterpassCheck.noLimit);
      // Tylko min. międzyściegowa: spełniona nie wystarcza (brak maks.),
      // niespełniona — błąd.
      final onlyMin = InterpassLimits.celsius(interpassMinC: 150);
      expect(interpassCheck(rd(2, 160), onlyMin), InterpassCheck.noLimit);
      expect(interpassCheck(rd(2, 140), onlyMin), InterpassCheck.low);
      expect(interpassCheckLabel(InterpassCheck.noLimit, en: false),
          'brak limitu z WPS');
    });

    test('kredka mówi tylko „powyżej / poniżej progu”', () {
      InterpassReading c(int pass, double r, bool melted) => rd(pass, r,
          bound: melted ? InterpassBound.atLeast : InterpassBound.below);
      // Podgrzanie 100: kredka 100 stopiona → OK; niestopiona → za zimno.
      expect(interpassCheck(c(1, 100, true), cmn), InterpassCheck.ok);
      expect(interpassCheck(c(1, 100, false), cmn), InterpassCheck.low);
      // Kredka 80 stopiona (T ≥ 80) nie potwierdza min. 100.
      expect(interpassCheck(c(1, 80, true), cmn), InterpassCheck.unconfirmed);
      // Kredka 150 niestopiona (T < 150) nie rozstrzyga min. 100.
      expect(interpassCheck(c(1, 150, false), cmn), InterpassCheck.unconfirmed);
      // Maks. 250: kredka 250 niestopiona → OK; stopiona → nie rozstrzyga;
      // kredka 270 stopiona → za gorąco.
      expect(interpassCheck(c(2, 250, false), cmn), InterpassCheck.ok);
      expect(interpassCheck(c(2, 250, true), cmn), InterpassCheck.unconfirmed);
      expect(interpassCheck(c(2, 270, true), cmn), InterpassCheck.high);
      expect(interpassCheck(c(2, 300, false), cmn), InterpassCheck.unconfirmed);
    });

    test(
        'kredka stopiona przy progu = maks.: „nie rozstrzyga — użyj termometru”',
        () {
      final w = weld([
        rd(1, 120, when: ms(8, 0)),
        rd(2, 250, bound: InterpassBound.atLeast, when: ms(8, 30)),
      ], passCount: 2);
      final a = w.assess();
      expect(a.status, InterpassWeldStatus.unconfirmed);
      expect(interpassCheckLabel(a.checkOf(w.readingsChrono[1]), en: false),
          'nie rozstrzyga — użyj termometru');
      expect(interpassStatusText(a, en: false),
          'Kredka nie rozstrzyga limitu dla ściegu 2 — użyj termometru.');
      expect(interpassCheckLabel(InterpassCheck.unconfirmed, en: true),
          'not conclusive — use a thermometer');
    });
  });

  group('czas pomiaru', () {
    test('sama godzina = najbliższe wystąpienie do +5 min, także w nocy', () {
      final now = DateTime(2026, 10, 18, 0, 12);
      expect(interpassReadingAt('23:50', now), DateTime(2026, 10, 17, 23, 50));
      expect(interpassReadingAt('00:05', now), DateTime(2026, 10, 18, 0, 5));
      // 5 min zapasu na różnicę zegarów.
      expect(interpassReadingAt('00:16', now), DateTime(2026, 10, 18, 0, 16));
      expect(interpassReadingAt('00:18', now), DateTime(2026, 10, 17, 0, 18));
      expect(interpassReadingAt('25:00', now), now);
      expect(interpassReadingAt('zła', now), now);
    });

    test('00:03 wpisane o 23:58 = jutro 00:03 (+5 min), nie doba wstecz', () {
      final now = DateTime(2026, 10, 17, 23, 58);
      final t = interpassReadingAt('00:03', now);
      expect(t, DateTime(2026, 10, 18, 0, 3));
      expect(interpassAtInFuture(t, now), isFalse);
      // 00:04 to już ponad 5 min — wczoraj rano (dzisiaj 00:04).
      expect(interpassReadingAt('00:04', now), DateTime(2026, 10, 17, 0, 4));
      // Przez koniec miesiąca.
      expect(interpassReadingAt('00:01', DateTime(2026, 10, 31, 23, 59)),
          DateTime(2026, 11, 1, 0, 1));
    });

    test('data + godzina = dokładnie ta chwila; przyszłość wykrywana', () {
      final now = DateTime(2026, 10, 17, 9, 0);
      expect(interpassResolveAt(now: now), now);
      expect(interpassResolveAt(hhmm: '08:30', now: now), at(8, 30));
      expect(
          interpassResolveAt(
              date: DateTime(2026, 10, 16), hhmm: '22:15', now: now),
          DateTime(2026, 10, 16, 22, 15));
      expect(interpassResolveAt(date: DateTime(2026, 10, 16), now: now),
          DateTime(2026, 10, 16, 9, 0));
      final later = interpassResolveAt(
          date: DateTime(2026, 10, 17), hhmm: '10:00', now: now);
      expect(interpassAtInFuture(later, now), isTrue);
      expect(interpassAtInFuture(at(9, 4), now), isFalse);
    });

    test('pomiar wsteczny nie zmienia oceny ściegu — decyduje czas', () {
      // Przed ściegiem 2: 10:00 — 280 °C (za gorąco). Później dopisany
      // pomiar z 09:50 — 230 °C: wcześniejszy w czasie, więc nie zdejmuje
      // przekroczenia.
      final w = weld([
        rd(1, 120, when: ms(9, 30)),
        rd(2, 280, when: ms(10, 0)),
      ], passCount: 2)
          .addReading(rd(2, 230, when: ms(9, 50), recorded: ms(10, 20)));
      final a = w.assess();
      expect(a.status, InterpassWeldStatus.outOfLimits);
      expect(a.failedPasses, [2]);
      // Lista w kolejności czasu, nie dopisania.
      expect(
          w.readingsChrono.map((r) => r.at), [ms(9, 30), ms(9, 50), ms(10, 0)]);
      expect(w.readingsChrono[1].backdated, isTrue);
      expect(interpassReadingFlags(w.readingsChrono[1], a, en: false),
          contains('zastąpiony późniejszym pomiarem'));
      expect(interpassReadingFlags(w.readingsChrono[1], a, en: false),
          contains('wpisano 2026-10-17 10:20'));

      // Odczekano — ponowny pomiar 10:10: 230 °C decyduje, spoina OK,
      // a pomiar poza limitem zostaje w protokole jako zastąpiony.
      final w2 = w.addReading(rd(2, 230, when: ms(10, 10)));
      final a2 = w2.assess();
      expect(a2.status, InterpassWeldStatus.ok);
      expect(a2.supersededOutOfLimits.single.tempC, 280);
    });

    test('zmiana nocna: kolejność przez północ', () {
      final w = weld([
        rd(2, 200, when: DateTime(2026, 10, 18, 0, 10).millisecondsSinceEpoch),
        rd(1, 120, when: DateTime(2026, 10, 17, 23, 50).millisecondsSinceEpoch),
      ], passCount: 2);
      expect(w.readingsChrono.map((r) => r.pass), [1, 2]);
      expect(w.assess().status, InterpassWeldStatus.ok);
    });

    test(
        'sąsiednie ściegi: odstęp poniżej 1 min — konflikt, 1 min — granica OK',
        () {
      InterpassAssessment two(int a, int b) => weld([
            rd(1, 120, when: a),
            rd(2, 200, when: b),
          ], passCount: 2)
              .assess();
      // 08:00:10 i 08:00:40 — ściegu nie dało się położyć w 30 s.
      final fast = two(ms(8, 0, 10), ms(8, 0, 40));
      expect(fast.status, InterpassWeldStatus.orderConflict);
      expect(fast.orderConflictPasses, [1]);
      expect(interpassStatusText(fast, en: false),
          contains('mniej niż 1 min później'));
      // Ta sama chwila — też konflikt.
      expect(two(ms(8), ms(8)).status, InterpassWeldStatus.orderConflict);
      // 59 s — konflikt; dokładnie 60 s — na granicy, OK.
      expect(two(ms(8, 0, 0), ms(8, 0, 59)).status,
          InterpassWeldStatus.orderConflict);
      expect(two(ms(8, 0, 0), ms(8, 1, 0)).status, InterpassWeldStatus.ok);
      expect(kInterpassMinPassGap, const Duration(minutes: 1));
      // Ponowny pomiar TEGO SAMEGO ściegu może być chwilę później.
      final again = weld([
        rd(1, 120, when: ms(8, 0)),
        rd(2, 280, when: ms(8, 30)),
        rd(2, 240, when: ms(8, 30, 20)),
      ], passCount: 2)
          .assess();
      expect(again.status, InterpassWeldStatus.ok);
    });
  });

  group('jednostki', () {
    test('°F ↔ °C: wartość kanoniczna w °C, wyświetlanie bez zmiany danych',
        () {
      expect(interpassToC(482, InterpassUnit.f), 250);
      expect(interpassToC(212, InterpassUnit.f), 100);
      expect(interpassToC(250, InterpassUnit.f), closeTo(121.111, 0.001));
      const c250 = InterpassTemp.c(250);
      expect(formatInterpassTemp(c250, InterpassUnit.c, en: false), '250 °C');
      expect(formatInterpassTemp(c250, InterpassUnit.f, en: false), '482 °F');
      expect(formatInterpassTempFull(c250, InterpassUnit.f, en: false),
          '482 °F (wpisano 250 °C)');
      expect(formatInterpassNumber(-0.001, en: false), '0');

      // Granica przeliczona z °F: limit 250 °F i pomiar 250 °F → równość.
      final lim = InterpassLimits(
          preheatMin: InterpassTemp.entered(212, InterpassUnit.f),
          interpassMax: InterpassTemp.entered(250, InterpassUnit.f));
      expect(interpassCheck(rd(2, 250, unit: InterpassUnit.f), lim),
          InterpassCheck.ok);
      // Pomiar w °F 249,8 vs limit 121 °C: ta sama temperatura.
      expect(
          interpassCheck(rd(2, 249.8, unit: InterpassUnit.f),
              InterpassLimits.celsius(interpassMaxC: 121)),
          InterpassCheck.ok);

      // Tekst w °C i °F — dane (JSON) i werdykt identyczne.
      final w = weld([rd(1, 120), rd(2, 251)], passCount: 2);
      final json = jsonEncode(w.toJson());
      final c = interpassProtocolText(w, InterpassUnit.c, en: false);
      final f = interpassProtocolText(w, InterpassUnit.f, en: false);
      expect(jsonEncode(w.toJson()), json);
      expect(c, contains('251 °C'));
      expect(f, contains('483,8 °F (wpisano 251 °C)'));
      expect(c, contains('POZA LIMITEM'));
      expect(f, contains('POZA LIMITEM'));
      expect(f, contains('Werdykt liczony w °C'));
    });

    test('400 °F wpisane w °F zostaje 400 °F (pole, tekst, PDF)', () {
      final t400 = InterpassTemp.entered(400, InterpassUnit.f);
      final t375 = InterpassTemp.entered(375, InterpassUnit.f);
      // Pole w °F: dokładnie to, co wpisano (bez 399,99 / 375,01).
      expect(
          formatInterpassTempNumber(t400, InterpassUnit.f, en: false), '400');
      expect(
          formatInterpassTempNumber(t375, InterpassUnit.f, en: false), '375');
      // W °C — przeliczone, z wpisaną wartością obok.
      expect(formatInterpassTempFull(t400, InterpassUnit.c, en: false),
          '204,444 °C (wpisano 400 °F)');

      final w = InterpassWeld(
        id: 'f',
        weldNo: 'S-F',
        limits: InterpassLimits(preheatMin: t375, interpassMax: t400),
        passCount: 1,
        readings: [
          InterpassReading(pass: 1, temp: t400, at: ms(8), recordedAt: ms(8)),
        ],
        createdAt: ms(7),
        updatedAt: ms(8),
      );
      final textF = interpassProtocolText(w, InterpassUnit.f, en: false);
      expect(textF, contains('Min. podgrzanie: ≥ 375 °F'));
      expect(textF, contains('Maks. międzyściegowa: ≤ 400 °F'));
      expect(textF,
          contains('Ścieg 1 · 2026-10-17 08:00 · 400 °F · termometr · OK'));
      expect(textF, isNot(contains('399,99')));
      expect(textF, isNot(contains('375,01')));
      // Tabela pomiarów w PDF — te same wiersze.
      expect(interpassReadingRows(w, InterpassUnit.f, en: false).single[2],
          '400 °F');
      expect(interpassReadingRows(w, InterpassUnit.c, en: false).single[2],
          '204,444 °C (wpisano 400 °F)');
      // Zapis: liczba + jednostka; odczyt bez zmian.
      final back = InterpassWeld.fromJson(jsonDecode(jsonEncode(w.toJson())))!;
      expect(back.limits.preheatMin, t375);
      expect(back.limits.interpassMax, t400);
      expect(back.readings.single.temp, t400);
      expect(back.assess().status, InterpassWeldStatus.ok);
      // Równość z limitem w °F = OK (ta sama liczba → ta sama °C).
      expect(
          interpassCheck(
              back.readings.single, InterpassLimits(preheatMin: t400)),
          InterpassCheck.ok);
      // 399,99 °F przy min. 400 °F — poniżej (rozdzielczość wpisu °F).
      expect(
          interpassCheck(rd(1, 399.99, unit: InterpassUnit.f),
              InterpassLimits(preheatMin: t400)),
          InterpassCheck.low);
    });
  });

  group('werdykt spoiny', () {
    test('zielony tylko gdy każdy ścieg ma pomiar i wszystko w limitach', () {
      final ok = weld([rd(1, 120), rd(2, 200), rd(3, 240)], passCount: 3);
      expect(ok.assess().status, InterpassWeldStatus.ok);
      expect(interpassStatusText(ok.assess(), en: false),
          startsWith('Wszystkie ściegi (3)'));

      // Brak liczby ściegów — nie zielony.
      expect(weld([rd(1, 120), rd(2, 200)]).assess().status,
          InterpassWeldStatus.passCountMissing);
      // Luka: brak pomiaru przed ściegiem 2.
      final gap = weld([rd(1, 120), rd(3, 200)], passCount: 3).assess();
      expect(gap.status, InterpassWeldStatus.missingPasses);
      expect(gap.missingPasses, [2]);
      // Liczba ściegów większa niż pomiary.
      expect(
          weld([rd(1, 120), rd(2, 200)], passCount: 4).assess().missingPasses,
          [3, 4]);
      // Pomiar dla ściegu ponad liczbę ściegów.
      expect(
          weld([rd(1, 120), rd(2, 200), rd(3, 200)], passCount: 2)
              .assess()
              .status,
          InterpassWeldStatus.passCountConflict);
      // Brak pomiarów.
      expect(weld([], passCount: 2).assess().status,
          InterpassWeldStatus.noReadings);
    });

    test('przekroczenie = czerwony, niezależnie od innych braków', () {
      final a = weld([rd(1, 90), rd(3, 200)]).assess();
      expect(a.status, InterpassWeldStatus.outOfLimits);
      expect(a.failedPasses, [1]);
      expect(
          interpassBlockers(a, en: false),
          containsAll([
            'poza limitem: ścieg 1',
            'brak pomiaru przed ściegiem 2',
            'brak liczby ściegów',
          ]));
    });

    test('brak limitu, kredka, kolejność czasu, sprzeczne limity', () {
      expect(
          weld([rd(1, 120), rd(2, 200)],
                  limits: InterpassLimits.celsius(preheatMinC: 100),
                  passCount: 2)
              .assess()
              .status,
          InterpassWeldStatus.noLimit);
      expect(
          weld([
            rd(1, 120),
            rd(2, 250, bound: InterpassBound.atLeast),
          ], passCount: 2)
              .assess()
              .status,
          InterpassWeldStatus.unconfirmed);
      // Ścieg 2 zmierzony po ściegu 3 — sprawdź godziny.
      final order = weld([
        rd(1, 120, when: ms(8, 0)),
        rd(2, 200, when: ms(8, 40)),
        rd(3, 200, when: ms(8, 20)),
      ], passCount: 3)
          .assess();
      expect(order.status, InterpassWeldStatus.orderConflict);
      expect(order.orderConflictPasses, [2]);
      // Min. międzyściegowa wyżej niż maks. — literówka.
      final conflict = weld([rd(1, 210), rd(2, 220)],
              limits: InterpassLimits.celsius(
                  preheatMinC: 200, interpassMaxC: 250, interpassMinC: 260),
              passCount: 2)
          .assess();
      expect(conflict.limits.conflict, isTrue);
      // Pomiar 220 jest poniżej (sprzecznego) min. 260 — czerwony wygrywa.
      expect(conflict.status, InterpassWeldStatus.outOfLimits);
      expect(
          weld([rd(1, 210)],
                  limits: InterpassLimits.celsius(
                      preheatMinC: 300, interpassMaxC: 250),
                  passCount: 1)
              .assess()
              .status,
          InterpassWeldStatus.outOfLimits);
      expect(
          weld([],
                  limits: InterpassLimits.celsius(
                      preheatMinC: 300, interpassMaxC: 250))
              .assess()
              .status,
          InterpassWeldStatus.limitsConflict);
    });

    test(
        'pusta min. międzyściegowa: 60 °C przy podgrzaniu 150 °C — OK z podpowiedzią',
        () {
      final limits =
          InterpassLimits.celsius(preheatMinC: 150, interpassMaxC: 250);
      final w = weld([
        rd(1, 160, when: ms(8, 0)),
        rd(2, 60, when: ms(8, 30)),
      ], limits: limits, passCount: 2);
      final a = w.assess();
      // Zachowanie bez zmian (bez zgody użytkownika): OK…
      expect(a.status, InterpassWeldStatus.ok);
      // …ale z wyraźną podpowiedzią.
      expect(a.belowPreheatUnchecked, [2]);
      expect(interpassMinUnsetNote(a, InterpassUnit.c, en: false),
          startsWith('Ścieg 2: poniżej min. podgrzania 150 °C — NIE oceniany'));
      expect(interpassProtocolText(w, InterpassUnit.c, en: false),
          contains('spadek poniżej podgrzania nie jest kontrolowany'));
      // Bez spadku — podpowiedź ogólna.
      final fine =
          weld([rd(1, 160), rd(2, 200)], limits: limits, passCount: 2).assess();
      expect(interpassMinUnsetNote(fine, InterpassUnit.c, en: false),
          startsWith('Min. międzyściegowa pusta'));
      // „Ustaw = min. podgrzania” → 60 °C jest poniżej minimum.
      final set =
          w.copyWith(limits: limits.copyWith(interpassMin: limits.preheatMin));
      expect(set.assess().status, InterpassWeldStatus.outOfLimits);
      expect(interpassMinUnsetNote(set.assess(), InterpassUnit.c, en: false),
          isNull);
    });

    test('podpowiedź ściegu: ponów po przekroczeniu, inaczej następny', () {
      expect(weld([]).nextPass, 1);
      expect(weld([rd(1, 120)]).nextPass, 2);
      expect(weld([rd(1, 120), rd(2, 280)]).nextPass, 2);
      expect(weld([rd(1, 80)]).nextPass, 1);
      // Po ostatnim ściegu nie podpowiada n+1 ponad liczbę ściegów.
      expect(weld([rd(1, 120), rd(2, 200)], passCount: 2).nextPass, 2);
      expect(weld([rd(1, 120), rd(2, 200)], passCount: 3).nextPass, 3);
    });

    test('„Cofnij” przy tej samej chwili: pomiar wraca na dawne miejsce', () {
      final w = weld([
        rd(1, 120, when: ms(8)),
        rd(2, 280, when: ms(8, 30)),
        rd(2, 240, when: ms(8, 30)),
      ], passCount: 2);
      expect(w.assess().decisive[2]!.tempC, 240);
      final removed = w.readingsChrono[1];
      final restored = w.removeReadingAt(1).restoreReadingAt(removed, 1);
      expect(restored.readingsChrono.map((r) => r.tempC), [120, 280, 240]);
      expect(restored.assess().decisive[2]!.tempC, 240);
      // Dopisanie na koniec zmieniłoby decydujący pomiar.
      expect(
          w.removeReadingAt(1).addReading(removed).assess().decisive[2]!.tempC,
          280);
    });
  });

  group('JSON', () {
    test('zapis i odczyt bez strat', () {
      final w = InterpassWeld(
        id: 'w1',
        weldNo: 'S-12',
        description: 'Linia 100-P-12, P91',
        wpsRef: 'WPS-091 rev B',
        journalWeldId: 'j7',
        limits: p91,
        method: InterpassMethod.crayon,
        passCount: 5,
        readings: [
          rd(2, 250, bound: InterpassBound.below),
          rd(1, 200, bound: InterpassBound.atLeast),
        ],
        createdAt: ms(7),
        updatedAt: ms(8),
      );
      final back =
          interpassLogFromJson(jsonDecode(jsonEncode(interpassLogToJson([w]))));
      expect(back.dropped, 0);
      expect(back.lossy, isFalse);
      final r = back.welds.single;
      expect(jsonEncode(r.toJson()), jsonEncode(w.toJson()));
      expect(r.readings.map((x) => x.pass), [1, 2]);
      expect(r.limits, p91);
      expect(r.method, InterpassMethod.crayon);
      expect(r.passCount, 5);
    });

    test('starszy zapis (v1, temperatury jako °C) czytany bez strat', () {
      final parsed = interpassLogFromJson({
        'v': 1,
        'welds': [
          {
            'id': 'old',
            'preheatMinC': 100,
            'interpassMaxC': 250,
            'passCount': 1,
            'readings': [
              {
                'pass': 1,
                'tempC': 120,
                'bound': 'exact',
                'method': 'contact',
                'at': ms(7)
              },
            ],
          },
        ],
      });
      expect(parsed.lossy, isFalse);
      final w = parsed.welds.single;
      expect(w.limits.preheatMin, const InterpassTemp.c(100));
      expect(w.readings.single.temp, const InterpassTemp.c(120));
      expect(w.assess().status, InterpassWeldStatus.ok);
    });

    test('uszkodzony JSON: całość → FormatException, wpisy → pominięte', () {
      expect(() => interpassLogFromJson('x'), throwsFormatException);
      expect(() => interpassLogFromJson(const {'v': 1}), throwsFormatException);
      expect(() => interpassLogFromJson(const [1, 2]), throwsFormatException);
      final parsed = interpassLogFromJson({
        'v': 1,
        'welds': [
          'śmieci',
          {'weldNo': 'bez id'},
          {
            'id': 'ok',
            'preheatMinC': 'sto',
            'interpassMaxC': 5000,
            'passCount': 2.5,
            'readings': [
              {
                'pass': 1,
                'tempC': 120,
                'bound': 'exact',
                'method': 'contact',
                'at': ms(7)
              },
              {
                'pass': 0,
                'tempC': 120,
                'bound': 'exact',
                'method': 'contact',
                'at': ms(7)
              },
              {
                'pass': 2,
                'tempC': 'gorąco',
                'bound': 'exact',
                'method': 'contact',
                'at': ms(7)
              },
              {
                'pass': 2,
                'tempC': 200,
                'bound': 'nieznany',
                'method': 'contact',
                'at': ms(7)
              },
              {'pass': 2, 'tempC': 200, 'bound': 'exact', 'method': 'contact'},
            ],
          },
        ],
      });
      expect(parsed.dropped, 2);
      // 4 pominięte pomiary + 2 nieczytelne limity + liczba ściegów.
      expect(parsed.damaged, 7);
      expect(parsed.lossy, isTrue);
      final w = parsed.welds.single;
      expect(w.id, 'ok');
      expect(w.limits.isEmpty, isTrue);
      expect(w.passCount, isNull);
      expect(w.readings, hasLength(1));
      expect(w.readings.single.recordedAt, ms(7));
      expect(w.lostReadings, 4);
    });

    test(
        'pominięty uszkodzony pomiar: spoina nie jest zielona do potwierdzenia',
        () {
      // Najpóźniejszy (gorący) pomiar przed ściegiem 2 jest uszkodzony —
      // bez blokady spoina zmieniłaby się z czerwonej w zieloną.
      final raw = {
        'v': 2,
        'welds': [
          {
            'id': 'w',
            'preheatMin': {'v': 100, 'u': 'c'},
            'interpassMax': {'v': 250, 'u': 'c'},
            'passCount': 2,
            'readings': [
              _reading(1, 120, ms(8)),
              _reading(2, 230, ms(8, 20)),
              _reading(2, 290, ms(8, 30), bound: 'zepsute'),
            ],
          },
        ],
      };
      final parsed = interpassLogFromJson(raw);
      expect(parsed.lossy, isTrue);
      final w = parsed.welds.single;
      expect(w.lostReadings, 1);
      final a = w.assess();
      expect(a.status, InterpassWeldStatus.lostReadings);
      expect(a.ok, isFalse);
      expect(interpassStatusText(a, en: false),
          startsWith('Przy odczycie zapisu pominięto uszkodzone pomiary: 1'));

      // Po zapisie licznik zostaje (pomiar już przepadł, blokada nie).
      final saved = InterpassWeld.fromJson(jsonDecode(jsonEncode(w.toJson())))!;
      expect(saved.lostReadings, 1);
      expect(saved.assess().status, InterpassWeldStatus.lostReadings);

      // Potwierdzenie użytkownika zdejmuje blokadę; protokół to pokazuje.
      final confirmed = saved.confirmLostReadings();
      expect(confirmed.assess().status, InterpassWeldStatus.ok);
      expect(confirmed.lostConfirmed, 1);
      expect(interpassProtocolText(confirmed, InterpassUnit.c, en: false),
          contains('Pominięte uszkodzone pomiary: 1 — sprawdzone'));
    });

    test('pusta spoina nie jest do zapisu', () {
      expect(InterpassWeld.blank(id: 'b', now: at(7)).isBlank, isTrue);
      expect(
          InterpassWeld.blank(id: 'b', now: at(7))
              .copyWith(weldNo: 'S-1')
              .isBlank,
          isFalse);
    });
  });
}
