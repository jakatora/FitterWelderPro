// Elektrody zasadowe: limity z tabeli AWS D1.1 / producenta, granice czasu,
// stany, piecyk-przechowalnik (reset po 4 h), ponowne suszenie, zapis JSON
// i plan przypomnień — bez platformy, zegar podawany wprost.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/reminder_plan.dart';
import 'package:cut_list_app/domain/welding/electrode_exposure.dart';

final DateTime t0 = DateTime(2026, 10, 17, 7, 0);
DateTime at(int h, [int m = 0, int s = 0]) => DateTime(2026, 10, 17, h, m, s);

ElectrodeBatch batch(
  ElectrodeClass c, {
  String id = 'b1',
  DateTime? out,
  ElectrodeSource source = ElectrodeSource.oven,
  int? limitMinutes,
  int? maxRedries,
}) =>
    ElectrodeBatch.takenOut(
      id: id,
      electrode: c,
      at: out ?? t0,
      source: source,
      diameterMm: 3.2,
      quantity: '40 szt.',
      location: 'hala B',
      limitMinutes: limitMinutes,
      maxRedries: maxRedries,
    );

void main() {
  group('tabela limitów', () {
    test('limit domyślny dla każdej klasy (AWS D1.1 Tab. 7.1 / producent)', () {
      const expected = <ElectrodeClass, int>{
        ElectrodeClass.e7018: 240,
        ElectrodeClass.e7018dash1: 240,
        ElectrodeClass.e7018R: 540,
        ElectrodeClass.e7018M: 540,
        ElectrodeClass.e7018X: 240,
        ElectrodeClass.e8018X: 120,
        ElectrodeClass.e9018X: 60,
        ElectrodeClass.e10018X: 30,
        ElectrodeClass.e11018X: 30,
        ElectrodeClass.enIso2560B: 240,
        ElectrodeClass.enIso18275E55: 60,
        ElectrodeClass.enIso18275E62: 30,
      };
      expect(expected.keys.toSet(), ElectrodeClass.values.toSet(),
          reason: 'każda klasa ma oczekiwany limit');
      for (final c in ElectrodeClass.values) {
        expect(defaultLimitMinutes(c, ElectrodeSource.oven), expected[c],
            reason: c.name);
        expect(batch(c).limitMinutes, expected[c], reason: c.name);
      }
    });

    test('opakowanie próżniowe: EN wg producenta, AWS dalej tabela D1.1', () {
      const expected = <ElectrodeClass, int>{
        ElectrodeClass.e7018: 240,
        ElectrodeClass.e7018dash1: 240,
        ElectrodeClass.e7018R: 540,
        ElectrodeClass.e7018M: 540,
        ElectrodeClass.e7018X: 240,
        ElectrodeClass.e8018X: 120,
        ElectrodeClass.e9018X: 60,
        ElectrodeClass.e10018X: 30,
        ElectrodeClass.e11018X: 30,
        // SAHARA ReadyPack 8 h, Kobelco ok. 8 h.
        ElectrodeClass.enIso2560B: 480,
        // Ostrożnie 4 h (Kobelco: niektóre produkty 4 h).
        ElectrodeClass.enIso18275E55: 240,
        ElectrodeClass.enIso18275E62: 240,
      };
      for (final c in ElectrodeClass.values) {
        final v = defaultLimitMinutes(c, ElectrodeSource.hermeticPack);
        expect(v, expected[c], reason: c.name);
        expect(v, greaterThanOrEqualTo(c.limitMinutes), reason: c.name);
      }
    });

    test('limit suszeń: AWS D1.1 raz, EN wg producenta 2', () {
      expect(defaultMaxRedries(ElectrodeClass.e7018), 1);
      expect(defaultMaxRedries(ElectrodeClass.e7018R), 1);
      expect(defaultMaxRedries(ElectrodeClass.e9018X), 1);
      expect(defaultMaxRedries(ElectrodeClass.enIso2560B), 2);
      expect(defaultMaxRedries(ElectrodeClass.enIso18275E62), 2);
      expect(ElectrodeClass.enIso2560B.family.perManufacturer, isTrue);
      expect(ElectrodeClass.e7018.family.perManufacturer, isFalse);
    });

    test('wyprzedzenie ostrzeżenia: 30 / 15 / 10 min', () {
      expect(warnLeadMinutes(540), 30);
      expect(warnLeadMinutes(240), 30);
      expect(warnLeadMinutes(120), 30);
      expect(warnLeadMinutes(60), 15);
      expect(warnLeadMinutes(30), 10);
    });

    test('limit edytowalny — ostrzejszy WPS', () {
      final b = batch(ElectrodeClass.e7018, limitMinutes: 120);
      expect(b.limitMinutes, 120);
      expect(b.deadline, at(9));
    });
  });

  group('granice czasu i stany', () {
    test('E7018 4 h: OK → kończy się (30 min) → przekroczony po 11:00', () {
      final b = batch(ElectrodeClass.e7018);
      expect(b.deadline, at(11));
      expect(b.stateAt(at(7)), ExposureState.ok);
      expect(b.stateAt(at(10, 29, 59)), ExposureState.ok);
      expect(b.stateAt(at(10, 30)), ExposureState.endingSoon);
      expect(b.stateAt(at(11)), ExposureState.endingSoon,
          reason: 'równo w limicie — jeszcze nie przekroczony');
      expect(b.remainingAt(at(11)), Duration.zero);
      expect(b.stateAt(at(11, 0, 1)), ExposureState.exceeded);
      expect(b.remainingAt(at(11, 25)), const Duration(minutes: -25));
      expect(b.usedFraction(at(9)), closeTo(0.5, 1e-9));
      expect(b.usedFraction(at(13)), 1.0);
    });

    test('E11018-X 30 min: ostrzeżenie 10 min przed końcem', () {
      final b = batch(ElectrodeClass.e11018X);
      expect(b.stateAt(at(7, 19)), ExposureState.ok);
      expect(b.stateAt(at(7, 20)), ExposureState.endingSoon);
      expect(b.stateAt(at(7, 30, 1)), ExposureState.exceeded);
    });

    test('E7018 H4R 9 h: koniec o 16:00', () {
      final b = batch(ElectrodeClass.e7018R);
      expect(b.deadline, at(16));
      expect(b.stateAt(at(15, 29)), ExposureState.ok);
      expect(b.stateAt(at(15, 30)), ExposureState.endingSoon);
    });

    test('zegar przed godziną wyjęcia nie daje ujemnego czasu', () {
      final b = batch(ElectrodeClass.e7018);
      expect(b.exposureAt(at(6)), Duration.zero);
    });
  });

  group('piecyk-przechowalnik', () {
    test('powrót zatrzymuje licznik', () {
      final b = batch(ElectrodeClass.e7018).returnToOven(at(9));
      expect(b.stateAt(at(12)), ExposureState.inOven);
      expect(b.exposureAt(at(12)), const Duration(hours: 2));
      expect(b.deadline, isNull);
      expect(b.events.last.kind, BatchEventKind.returnedToOven);
      expect(b.events.last.exposure, const Duration(hours: 2));
      expect(() => b.returnToOven(at(10)), throwsStateError);
    });

    test('wyjęte po < 4 h — licznik liczy dalej od zebranego czasu', () {
      final b = batch(ElectrodeClass.e7018)
          .returnToOven(at(9))
          .takeOutAgain(at(12, 59));
      expect(b.events.last.reset, isFalse);
      expect(b.priorExposure, const Duration(hours: 2));
      // Zostały 2 h: 12:59 + 2 h.
      expect(b.deadline, at(14, 59));
      expect(b.exposureAt(at(13, 59)), const Duration(hours: 3));
    });

    test('wyjęte po równo 4 h — limit od nowa', () {
      final b =
          batch(ElectrodeClass.e7018).returnToOven(at(9)).takeOutAgain(at(13));
      expect(b.events.last.reset, isTrue);
      expect(b.priorExposure, Duration.zero);
      expect(b.deadline, at(17));
      expect(b.resetRemainingAt(at(14)), isNull);
    });

    test('pozostały czas do zerowania w piecyku', () {
      final b = batch(ElectrodeClass.e7018).returnToOven(at(9));
      expect(b.resetRemainingAt(at(10)), const Duration(hours: 3));
      expect(b.resetRemainingAt(at(13, 30)), Duration.zero);
    });

    test('po przekroczeniu piecyk nie pomaga — tylko suszenie', () {
      final b = batch(ElectrodeClass.e7018).returnToOven(at(11, 30));
      expect(b.stateAt(at(12)), ExposureState.exceeded);
      expect(b.resetRemainingAt(at(16)), isNull);
      final again = b.takeOutAgain(at(16));
      expect(again.events.last.reset, isFalse);
      expect(again.stateAt(at(16)), ExposureState.exceeded);
    });
  });

  group('ponowne suszenie', () {
    test('suszenie zeruje licznik i liczy suszenia; AWS max 1', () {
      final b = batch(ElectrodeClass.e7018);
      expect(b.stateAt(at(11, 30)), ExposureState.exceeded);
      expect(b.redryLimitReached, isFalse);
      final r1 = b.redried(at(11, 30));
      expect(r1.redryCount, 1);
      expect(r1.stateAt(at(11, 30)), ExposureState.ok);
      expect(r1.deadline, at(15, 30));
      expect(r1.events.last.kind, BatchEventKind.redried);
      expect(r1.events.last.value, 1);
      expect(r1.events.last.exposure, const Duration(hours: 4, minutes: 30));
      expect(r1.redryLimitReached, isTrue);
      expect(r1.redryLimitExceeded, isFalse);
      final r2 = r1.redried(at(16));
      expect(r2.redryCount, 2);
      expect(r2.redryLimitExceeded, isTrue);
    });

    test('EN: domyślnie 2 suszenia, trzecie ponad limit', () {
      var b = batch(ElectrodeClass.enIso2560B);
      b = b.redried(at(12));
      expect(b.redryLimitReached, isFalse);
      b = b.redried(at(13));
      expect(b.redryCount, 2);
      expect(b.redryLimitReached, isTrue);
      expect(b.redryLimitExceeded, isFalse);
      expect(b.redried(at(16)).redryLimitExceeded, isTrue);
    });

    test('limit suszeń edytowalny na partii', () {
      final b = batch(ElectrodeClass.e7018, maxRedries: 3).redried(at(12));
      expect(b.maxRedries, 3);
      expect(b.redryLimitReached, isFalse);
      expect(b.withMaxRedries(1).redryLimitReached, isTrue);
    });

    test('suszenie z piecyka też zaczyna nowy start', () {
      final b = batch(ElectrodeClass.e7018).returnToOven(at(9)).redried(at(10));
      expect(b.isInOven, isFalse);
      expect(b.deadline, at(14));
    });
  });

  group('zamknięcie i limit', () {
    test('zużyte / złom — licznik staje, drugie zamknięcie rzuca', () {
      final used =
          batch(ElectrodeClass.e7018).close(at(10), BatchClosure.consumed);
      expect(used.stateAt(at(20)), ExposureState.consumed);
      expect(used.exposureAt(at(20)), const Duration(hours: 3));
      expect(used.closedAt, at(10));
      expect(() => used.close(at(11), BatchClosure.scrapped), throwsStateError);
      final scrap =
          batch(ElectrodeClass.e7018).close(at(12), BatchClosure.scrapped);
      expect(scrap.stateAt(at(12)), ExposureState.scrapped);
      expect(scrap.events.last.kind, BatchEventKind.scrapped);
    });

    test('zmiana limitu zapisuje wpis i zmienia stan', () {
      final b = batch(ElectrodeClass.e7018).withLimit(120, at(8));
      expect(b.limitMinutes, 120);
      expect(b.events.last.kind, BatchEventKind.limitChanged);
      expect(b.events.last.value, 120);
      expect(b.stateAt(at(9, 1)), ExposureState.exceeded);
      expect(identical(b.withLimit(120, at(8)), b), isTrue);
    });
  });

  group('zapis JSON', () {
    test('pełny cykl zapis → odczyt bez strat', () {
      final b =
          batch(ElectrodeClass.e8018X, source: ElectrodeSource.hermeticPack)
              .returnToOven(at(8))
              .takeOutAgain(at(12, 30))
              .withLimit(90, at(12, 31))
              .redried(at(15))
              .close(at(16), BatchClosure.consumed);
      final c = batch(ElectrodeClass.enIso2560B, id: 'b2');
      final decoded = decodeBatches(encodeBatches([b, c]));
      expect(decoded, hasLength(2));
      expect(decoded[0].toJson(), b.toJson());
      expect(decoded[1].toJson(), c.toJson());
      expect(decoded[0].events, b.events);
      expect(decoded[0].stateAt(at(18)), ExposureState.consumed);
    });

    test('uszkodzony JSON — pusta lista, bez wyjątku', () {
      for (final raw in [
        null,
        '',
        '{',
        'null',
        '"tekst"',
        '[1, 2]',
        '{"batches": 5}',
        '{"batches": [{"id": "x"}]}',
      ]) {
        expect(decodeBatches(raw), isEmpty, reason: '$raw');
      }
    });

    test('jeden uszkodzony wpis nie kasuje reszty', () {
      final good = batch(ElectrodeClass.e7018).toJson();
      final raw = jsonEncode({
        'v': 1,
        'batches': [
          good,
          {'id': 'zły'},
          {...good, 'id': 'b9', 'cls': 'e6010'},
          {...good, 'id': 'b8', 'ev': 'nie lista'},
          'tekst',
        ],
      });
      // b8: zła historia → partia zostaje (bez wpisów), reszta śmieci
      // pominięta; odczyt zgłasza stratę (magazyn zachowa kopię).
      final r = decodeBatchesDetailed(raw);
      expect(r.batches.map((b) => b.id), ['b1', 'b8']);
      expect(r.batches[1].events, isEmpty);
      expect(r.lossy, isTrue);
    });
  });

  group('lista, dziennik, przypomnienia', () {
    test('kolejność aktywnych: przekroczone, kończy się, OK, piecyk', () {
      final now = at(10, 45);
      final exceeded = batch(ElectrodeClass.e8018X, id: 'x'); // 2 h
      final soon = batch(ElectrodeClass.e7018, id: 's'); // 15 min
      final ok = batch(ElectrodeClass.e7018R, id: 'o');
      final oven = batch(ElectrodeClass.e7018, id: 'p').returnToOven(at(8));
      final closed = batch(ElectrodeClass.e7018, id: 'c')
          .close(at(8), BatchClosure.consumed);
      expect(
          sortActive([oven, ok, closed, soon, exceeded], now).map((b) => b.id),
          ['x', 's', 'o', 'p']);
    });

    test('dziennik: dziś / 7 dni / wszystko', () {
      final now = at(12);
      final today = batch(ElectrodeClass.e7018, id: 'dzis')
          .close(at(9), BatchClosure.consumed);
      final threeDays = batch(ElectrodeClass.e7018,
              id: '3dni', out: DateTime(2026, 10, 14, 7))
          .close(DateTime(2026, 10, 14, 9), BatchClosure.scrapped);
      final old =
          batch(ElectrodeClass.e7018, id: 'stara', out: DateTime(2026, 9, 1, 7))
              .close(DateTime(2026, 9, 1, 9), BatchClosure.consumed);
      final activeOld = batch(ElectrodeClass.e7018,
          id: 'aktywna', out: DateTime(2026, 10, 1, 7));
      final all = [old, threeDays, today, activeOld];
      expect(batchesForLog(all, LogRange.today, now).map((b) => b.id),
          ['dzis', 'aktywna']);
      expect(batchesForLog(all, LogRange.week, now).map((b) => b.id),
          ['dzis', '3dni', 'aktywna']);
      expect(batchesForLog(all, LogRange.all, now), hasLength(4));
    });

    test('plan przypomnień: X min przed i w chwili końca, tylko przyszłe', () {
      final b = batch(ElectrodeClass.e7018);
      final plan = planElectrodeReminders([b], now: at(8), english: false);
      expect(plan.map((r) => r.fireAt), [at(10, 30), at(11)]);
      expect(plan.map((r) => r.id).toSet(), hasLength(2));
      expect(plan.first.title, 'Elektrody: zostało 30 min');
      expect(plan.last.title, 'Elektrody: koniec czasu na powietrzu');
      expect(plan.first.certificateId, 'b1');
      expect(plan.first.kind, ReminderKind.expiry);

      final later = planElectrodeReminders([b], now: at(10, 45), english: true);
      expect(later.map((r) => r.fireAt), [at(11)]);
      expect(later.single.id, plan.last.id, reason: 'stabilne id');
      expect(later.single.title, 'Electrodes: exposure limit reached');

      expect(
          planElectrodeReminders([b.returnToOven(at(9))],
              now: at(9), english: false),
          isEmpty);
      expect(
          planElectrodeReminders([b.close(at(9), BatchClosure.consumed)],
              now: at(9), english: false),
          isEmpty);
      expect(
          planElectrodeReminders([b], now: at(11, 1), english: false), isEmpty);
    });

    test('różne partie — różne identyfikatory', () {
      final plan = planElectrodeReminders([
        batch(ElectrodeClass.e7018, id: 'a'),
        batch(ElectrodeClass.e7018, id: 'b'),
      ], now: at(8), english: false);
      expect(plan.map((r) => r.id).toSet(), hasLength(4));
    });
  });

  test('formatowanie: 24 h, czas trwania, średnica', () {
    expect(formatHm(DateTime(2026, 10, 17, 7, 5)), '07:05');
    expect(formatHm(DateTime(2026, 10, 17, 23, 59)), '23:59');
    expect(formatSpan(const Duration(minutes: 45)), '45 min');
    expect(formatSpan(const Duration(hours: 3, minutes: 5)), '3 h 05 min');
    expect(formatSpan(const Duration(minutes: -25)), '25 min');
    expect(formatDiameter(3.2, en: false), '3,2');
    expect(formatDiameter(4, en: true), '4.0');
    expect(
        batch(ElectrodeClass.e7018).label(en: false), 'E7018 · Ø3,2 · 40 szt.');
  });

  // ── Regresje z przeglądu kodu (A1–A6) ─────────────────────────────────

  group('przekroczona partia nie wraca do życia (A1)', () {
    test('podniesienie limitu przekroczonej partii rzuca; obniżenie wolno', () {
      // E8018-X: 2 h → przekroczona o 09:30.
      final b = batch(ElectrodeClass.e8018X);
      expect(b.stateAt(at(9, 30)), ExposureState.exceeded);
      expect(b.canRaiseLimitAt(at(9, 30)), isFalse);
      expect(() => b.withLimit(168 * 60, at(9, 30)), throwsStateError);
      expect(() => b.withLimit(121, at(9, 30)), throwsStateError);
      final lower = b.withLimit(60, at(9, 30));
      expect(lower.limitMinutes, 60);
      expect(lower.events.last.exceeded, isTrue);
      expect(lower.stateAt(at(9, 30)), ExposureState.exceeded);
    });

    test('obejście przez piecyk: przekroczona, 4 h w piecyku — bez resetu', () {
      final b = batch(ElectrodeClass.e8018X).returnToOven(at(9, 30));
      expect(b.canRaiseLimitAt(at(10)), isFalse,
          reason: 'w piecyku nadal przekroczona');
      expect(() => b.withLimit(168 * 60, at(10)), throwsStateError);
      final out = b.takeOutAgain(at(13, 30));
      expect(out.events.last.reset, isFalse);
      expect(out.stateAt(at(13, 30)), ExposureState.exceeded);
    });

    test('nieprzekroczoną partię wolno przestawić w górę', () {
      final b = batch(ElectrodeClass.e8018X);
      expect(b.canRaiseLimitAt(at(8)), isTrue);
      final up = b.withLimit(240, at(8));
      expect(up.limitMinutes, 240);
      expect(up.events.last.exceeded, isFalse);
      expect(up.stateAt(at(10)), ExposureState.ok);
      // Wpis „przekroczona” przechodzi przez JSON.
      final low = batch(ElectrodeClass.e8018X).withLimit(60, at(9, 30));
      expect(decodeBatches(encodeBatches([low])).single.events.last.exceeded,
          isTrue);
    });
  });

  group('godzina z zegara (A2)', () {
    test('godzina po „teraz” to wczoraj — kalendarzowo, także w dobie 25 h',
        () {
      // 25.10.2026 — w Polsce koniec czasu letniego (doba 25 h). 23:45
      // z wczoraj nie może zamienić się w dzisiejszą 00:45.
      expect(resolvePickedTime(DateTime(2026, 10, 25, 23, 30), 23, 45),
          DateTime(2026, 10, 24, 23, 45));
      // 29.03.2026 — doba 23 h.
      expect(resolvePickedTime(DateTime(2026, 3, 29, 1, 30), 23, 15),
          DateTime(2026, 3, 28, 23, 15));
      // Przełom miesiąca i roku.
      expect(resolvePickedTime(DateTime(2027, 1, 1, 0, 10), 22, 0),
          DateTime(2026, 12, 31, 22));
    });

    test('godzina wcześniejsza albo równa „teraz” to dziś', () {
      expect(resolvePickedTime(at(10), 7, 0), at(7));
      expect(resolvePickedTime(at(10), 10, 0), at(10));
    });
  });

  group('cofnięcie jednej partii (A3)', () {
    test('restoreBatch przywraca tylko tę partię, zmiany innych zostają', () {
      final a = batch(ElectrodeClass.e7018, id: 'a');
      final b = batch(ElectrodeClass.e7018, id: 'b');
      final aScrapped = a.close(at(9), BatchClosure.scrapped);
      final bOven = b.returnToOven(at(9, 5));
      final restored = restoreBatch([aScrapped, bOven], a);
      expect(restored.map((x) => x.id), ['a', 'b']);
      expect(restored[0].isClosed, isFalse);
      expect(restored[1].isInOven, isTrue, reason: 'zmiana B zostaje');
    });

    test('usunięta partia wraca na koniec listy', () {
      final a = batch(ElectrodeClass.e7018, id: 'a');
      final b = batch(ElectrodeClass.e7018, id: 'b');
      expect(restoreBatch([b], a).map((x) => x.id), ['b', 'a']);
    });
  });

  group('odczyt ze stratą (A4)', () {
    test('nieznany rodzaj zdarzenia — pomijane tylko zdarzenie', () {
      final good = batch(ElectrodeClass.e7018).returnToOven(at(9)).toJson();
      final events = [...(good['ev']! as List)];
      events.insert(
          1, {'k': 'wymyslonyRodzaj', 'at': at(8).millisecondsSinceEpoch});
      events.add({'k': 'consumed'}); // bez godziny
      final raw = jsonEncode({
        'v': 1,
        'batches': [
          {...good, 'ev': events}
        ],
      });
      final r = decodeBatchesDetailed(raw);
      expect(r.lossy, isTrue);
      expect(r.batches.single.events.map((e) => e.kind),
          [BatchEventKind.takenOut, BatchEventKind.returnedToOven]);
      expect(r.batches.single.isInOven, isTrue);
    });

    test('poprawny zapis — bez straty; uszkodzony — ze stratą', () {
      final ok = encodeBatches([batch(ElectrodeClass.e7018)]);
      expect(decodeBatchesDetailed(ok).lossy, isFalse);
      expect(decodeBatchesDetailed(null).lossy, isFalse);
      expect(decodeBatchesDetailed('{"v":1,"batches":[]}').lossy, isFalse);
      for (final raw in ['{', 'null', '5', '{"batches": 5}', '[1]']) {
        expect(decodeBatchesDetailed(raw).lossy, isTrue, reason: raw);
      }
    });
  });

  group('spójność zapisu (A5)', () {
    Map<String, Object?> base() => batch(ElectrodeClass.e7018).toJson();

    test('otwarta bez start i piecyka — licznik biegnie od ostatniego wpisu',
        () {
      final j = base()..remove('start');
      var lossy = false;
      final b = ElectrodeBatch.fromJson(j, onLoss: () => lossy = true);
      expect(lossy, isTrue);
      expect(b.isExposed, isTrue);
      expect(b.exposureStart, at(7));
      expect(b.deadline, at(11));
      expect(b.stateAt(at(11, 1)), ExposureState.exceeded);
    });

    test(
        'start i piecyk naraz — biegnie; ujemny prior → 0; zamknięta czyszczona',
        () {
      final both = ElectrodeBatch.fromJson({
        ...base(),
        'oven': at(8).millisecondsSinceEpoch,
        'prior': -3600,
      });
      expect(both.isInOven, isFalse);
      expect(both.isExposed, isTrue);
      expect(both.priorExposure, Duration.zero);

      final closed = ElectrodeBatch.fromJson({...base(), 'how': 'consumed'});
      expect(closed.isClosed, isTrue);
      expect(closed.exposureStart, isNull);
      expect(closed.closedAt, at(7));
      expect(closed.stateAt(at(12)), ExposureState.consumed);
    });
  });

  group('przypomnienie w połowie krótkiego limitu (A6)', () {
    test('wyprzedzenia: ≤ 60 min z połową, dłuższe bez', () {
      expect(reminderLeadsFor(30), [15, 10, 0]);
      expect(reminderLeadsFor(60), [30, 15, 0]);
      expect(reminderLeadsFor(20), [10, 0]);
      expect(reminderLeadsFor(120), [30, 0]);
      expect(reminderLeadsFor(240), [30, 0]);
    });

    test('E11018-X 30 min: 07:15 połowa, 07:20, 07:30; E9018-X 1 h', () {
      final short = planElectrodeReminders(
          [batch(ElectrodeClass.e11018X, id: 's')],
          now: at(7), english: false);
      expect(short.map((r) => r.fireAt), [at(7, 15), at(7, 20), at(7, 30)]);
      expect(short.first.title, 'Elektrody: połowa limitu — zostało 15 min');
      expect(short.map((r) => r.id).toSet(), hasLength(3));
      final hour = planElectrodeReminders(
          [batch(ElectrodeClass.e9018X, id: 'h')],
          now: at(7), english: true);
      expect(hour.map((r) => r.fireAt), [at(7, 30), at(7, 45), at(8)]);
      expect(hour.first.title, 'Electrodes: half the limit used — 30 min left');
    });
  });
}
