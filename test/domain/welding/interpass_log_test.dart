// Temperatura podgrzania i międzyściegowa: ocena pomiaru na granicy, przed
// pierwszym ściegiem vs między ściegami, brak limitu z WPS, kredka (tylko
// próg), pomiar wsteczny i zmiana nocna, °C↔°F bez zmiany danych, werdykt
// spoiny, JSON i uszkodzony JSON — bez platformy, zegar podawany wprost.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/domain/welding/interpass_text.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 17, h, m);
int ms(int h, [int m = 0]) => at(h, m).millisecondsSinceEpoch;

InterpassReading rd(int pass, double c,
        {int? when,
        InterpassBound bound = InterpassBound.exact,
        InterpassMethod method = InterpassMethod.contact,
        int? recorded}) =>
    InterpassReading(
      pass: pass,
      tempC: c,
      bound: bound,
      method: bound == InterpassBound.exact ? method : InterpassMethod.crayon,
      at: when ?? ms(7, pass),
      recordedAt: recorded ?? when ?? ms(7, pass),
    );

const p91 =
    InterpassLimits(preheatMinC: 200, interpassMaxC: 300, interpassMinC: 200);
const cmn = InterpassLimits(preheatMinC: 100, interpassMaxC: 250);

InterpassWeld weld(List<InterpassReading> readings,
        {InterpassLimits limits = cmn, int? passCount}) =>
    InterpassWeld(
      id: 'w1',
      weldNo: 'S-12',
      limits: limits,
      passCount: passCount,
      readings: readings,
      createdAt: ms(7),
      updatedAt: ms(7),
    );

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
      const onlyMax = InterpassLimits(interpassMaxC: 250);
      expect(interpassCheck(rd(1, 150), onlyMax), InterpassCheck.noLimit);
      // Tylko min. międzyściegowa: spełniona nie wystarcza (brak maks.),
      // niespełniona — błąd.
      const onlyMin = InterpassLimits(interpassMinC: 150);
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
  });

  group('czas pomiaru', () {
    test('sama godzina = najbliższe wcześniejsze wystąpienie, także w nocy',
        () {
      final now = DateTime(2026, 10, 18, 0, 12);
      expect(interpassReadingAt('23:50', now), DateTime(2026, 10, 17, 23, 50));
      expect(interpassReadingAt('00:05', now), DateTime(2026, 10, 18, 0, 5));
      // 5 min zapasu na różnicę zegarów.
      expect(interpassReadingAt('00:16', now), DateTime(2026, 10, 18, 0, 16));
      expect(interpassReadingAt('00:18', now), DateTime(2026, 10, 17, 0, 18));
      expect(interpassReadingAt('25:00', now), now);
      expect(interpassReadingAt('zła', now), now);
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
  });

  group('jednostki', () {
    test('°F ↔ °C: wartość kanoniczna w °C, wyświetlanie bez zmiany danych',
        () {
      expect(interpassToC(482, InterpassUnit.f), 250);
      expect(interpassToC(212, InterpassUnit.f), 100);
      expect(interpassToC(250, InterpassUnit.f), 121.11);
      expect(formatInterpassTemp(250, InterpassUnit.c, en: false), '250 °C');
      expect(formatInterpassTemp(250, InterpassUnit.f, en: false), '482 °F');
      expect(formatInterpassTemp(121.11, InterpassUnit.f, en: true), '250 °F');
      expect(
          formatInterpassTemp(121.11, InterpassUnit.c, en: false), '121,11 °C');
      expect(formatInterpassNumber(-0.001, en: false), '0');

      // Granica przeliczona z °F: limit 250 °F i pomiar 250 °F → równość.
      final lim = InterpassLimits(
          preheatMinC: interpassToC(212, InterpassUnit.f),
          interpassMaxC: interpassToC(250, InterpassUnit.f));
      expect(interpassCheck(rd(2, interpassToC(250, InterpassUnit.f)), lim),
          InterpassCheck.ok);
      // Pomiar w °F 249,8 vs limit 121 °C: ta sama liczba po zaokrągleniu.
      expect(interpassToC(249.8, InterpassUnit.f), 121);
      expect(
          interpassCheck(rd(2, interpassToC(249.8, InterpassUnit.f)),
              const InterpassLimits(interpassMaxC: 121)),
          InterpassCheck.ok);

      // Tekst w °C i °F — dane (JSON) i werdykt identyczne.
      final w = weld([rd(1, 120), rd(2, 251)], passCount: 2);
      final json = jsonEncode(w.toJson());
      final c = interpassProtocolText(w, InterpassUnit.c, en: false);
      final f = interpassProtocolText(w, InterpassUnit.f, en: false);
      expect(jsonEncode(w.toJson()), json);
      expect(c, contains('251 °C'));
      expect(f, contains('483,8 °F'));
      expect(c, contains('POZA LIMITEM'));
      expect(f, contains('POZA LIMITEM'));
      expect(f, contains('Wartości zapisane w °C'));
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
                  limits: const InterpassLimits(preheatMinC: 100), passCount: 2)
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
              limits: const InterpassLimits(
                  preheatMinC: 200, interpassMaxC: 250, interpassMinC: 260),
              passCount: 2)
          .assess();
      expect(conflict.limits.conflict, isTrue);
      // Pomiar 220 jest poniżej (sprzecznego) min. 260 — czerwony wygrywa.
      expect(conflict.status, InterpassWeldStatus.outOfLimits);
      expect(
          weld([rd(1, 210)],
                  limits: const InterpassLimits(
                      preheatMinC: 300, interpassMaxC: 250),
                  passCount: 1)
              .assess()
              .status,
          InterpassWeldStatus.outOfLimits);
      expect(
          weld([],
                  limits: const InterpassLimits(
                      preheatMinC: 300, interpassMaxC: 250))
              .assess()
              .status,
          InterpassWeldStatus.limitsConflict);
    });

    test('podpowiedź ściegu: ponów po przekroczeniu, inaczej następny', () {
      expect(weld([]).nextPass, 1);
      expect(weld([rd(1, 120)]).nextPass, 2);
      expect(weld([rd(1, 120), rd(2, 280)]).nextPass, 2);
      expect(weld([rd(1, 80)]).nextPass, 1);
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
      final r = back.welds.single;
      expect(jsonEncode(r.toJson()), jsonEncode(w.toJson()));
      expect(r.readings.map((x) => x.pass), [1, 2]);
      expect(r.limits, p91);
      expect(r.method, InterpassMethod.crayon);
      expect(r.passCount, 5);
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
      final w = parsed.welds.single;
      expect(w.id, 'ok');
      expect(w.limits.isEmpty, isTrue);
      expect(w.passCount, isNull);
      expect(w.readings, hasLength(1));
      expect(w.readings.single.recordedAt, ms(7));
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
