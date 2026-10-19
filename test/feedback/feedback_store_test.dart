// Lokalna kolejka feedbacku: kolejność, limit 300, jawne nie wypadają,
// kopia uszkodzonego zapisu, brak wyścigów.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/feedback/feedback_signal.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';

import 'feedback_test_utils.dart';

FeedbackStore get store => FeedbackStore.instance;

void main() {
  setUp(seedFeedback);

  test('pusta kolejka', () async {
    expect(await store.list(), isEmpty);
    expect(await store.takeBatch(), isEmpty);
    final st = await store.stats();
    expect(st.count, 0);
    expect(st.corrupt, isFalse);
  });

  test('add → list od najstarszego; zapis przeżywa nową instancję prefs',
      () async {
    await fill(0, 3);
    expect((await store.list()).map((e) => e.id), ['sig-0', 'sig-1', 'sig-2']);

    final raw = (await SharedPreferences.getInstance())
        .getString(FeedbackStore.prefsKey)!;
    final decoded = jsonDecode(raw) as Map;
    expect(decoded['v'], 1);
    expect((decoded['items'] as List).length, 3);
  });

  test('to samo id dodane drugi raz nic nie zmienia', () async {
    expect(await store.add(sig(1)), isTrue);
    expect(await store.add(sig(1)), isTrue);
    expect(await store.list(), hasLength(1));
  });

  test('sygnał niezgodny z kontraktem nie wchodzi', () async {
    final bad = FeedbackSignal(
      id: 'x',
      kind: FeedbackKind.complaint,
      text: 'a',
      tool: null,
      skill: null,
      skillsVersion: 1,
      app: '0.4.0+18',
      platform: 'linux',
      lang: 'pl',
      at: DateTime.utc(2026),
      errorType: null,
    );
    expect(await store.add(bad), isFalse);
    expect(await store.list(), isEmpty);
  });

  test('pusty tekst wchodzi tylko dla error', () async {
    expect(
        await store.add(FeedbackSignal.create(
            kind: FeedbackKind.explicit, text: '  ', id: 'pusty')),
        isFalse);
    expect(
        await store.add(FeedbackSignal.create(
            kind: FeedbackKind.error, errorType: 'StateError', id: 'blad')),
        isTrue);
    expect((await store.list()).map((e) => e.id), ['blad']);
  });

  test('add maskuje tekst nawet sygnału zbudowanego konstruktorem', () async {
    FeedbackSignal raw(FeedbackKind kind, String id) => FeedbackSignal(
          id: id,
          kind: kind,
          text: 'dzwoń +48 600 100 200 albo jan@x.pl',
          tool: '  ',
          skill: null,
          skillsVersion: 1,
          app: '0.4.0+18',
          platform: 'android',
          lang: 'pl',
          at: DateTime.utc(2026, 10, 19),
          errorType: null,
        );
    expect(await store.add(raw(FeedbackKind.explicit, 'a')), isTrue);
    expect(await store.add(raw(FeedbackKind.error, 'b')), isTrue);

    final items = await store.list();
    expect(items[0].text, 'dzwoń *** albo ***');
    expect(items[0].tool, isNull);
    expect(items[1].text, '', reason: 'error bez treści');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FeedbackStore.prefsKey), isNot(contains('600')));
    expect(prefs.getString(FeedbackStore.prefsKey), isNot(contains('@')));
  });

  test('takeBatch(20) bierze najstarsze 20 i NIE usuwa', () async {
    await fill(0, 25);
    final batch = await store.takeBatch(20);
    expect(batch.map((e) => e.id), [for (var i = 0; i < 20; i++) 'sig-$i']);
    expect(await store.list(), hasLength(25));
  });

  test('markSent i remove usuwają, liczniki rosną', () async {
    await fill(0, 5);
    expect(await store.markSent(['sig-0', 'sig-1', 'nie-ma']), 2);
    expect(await store.remove('sig-4'), isTrue);
    expect(await store.remove('sig-4'), isFalse);
    expect(await store.markRejected(['sig-2']), 1);
    expect((await store.list()).map((e) => e.id), ['sig-3']);
    final st = await store.stats();
    expect(st.sent, 2);
    expect(st.rejected, 1);
  });

  group('limit 300', () {
    test('przepełnienie: wypada najstarszy automatyczny, licznik dropped',
        () async {
      seedFeedback({
        FeedbackStore.prefsKey:
            queueJson([for (var i = 0; i < 300; i++) sig(i)]),
      });
      expect(await store.add(sig(300)), isTrue);

      final ids = (await store.list()).map((e) => e.id).toList();
      expect(ids, hasLength(FeedbackStore.capacity));
      expect(ids.first, 'sig-1');
      expect(ids.last, 'sig-300');
      expect((await store.stats()).dropped, 1);
    });

    test('jawne zgłoszenia nigdy nie wypadają', () async {
      seedFeedback({
        FeedbackStore.prefsKey: queueJson([
          for (var i = 0; i < 10; i++) sig(i, kind: FeedbackKind.explicit),
          for (var i = 10; i < 300; i++) sig(i),
        ]),
      });
      for (var i = 300; i < 305; i++) {
        expect(await store.add(sig(i, kind: FeedbackKind.explicit)), isTrue);
      }

      final items = await store.list();
      expect(items, hasLength(300));
      final explicitIds =
          items.where((e) => e.isExplicit).map((e) => e.id).toSet();
      expect(explicitIds, {
        for (var i = 0; i < 10; i++) 'sig-$i',
        for (var i = 300; i < 305; i++) 'sig-$i',
      });
      // Wypadły najstarsze automatyczne: sig-10..sig-14.
      expect(items.any((e) => e.id == 'sig-14'), isFalse);
      expect(items.any((e) => e.id == 'sig-15'), isTrue);
      expect((await store.stats()).dropped, 5);
    });

    test('300 jawnych: nowy sygnał nie wchodzi, żaden jawny nie wypada',
        () async {
      seedFeedback({
        FeedbackStore.prefsKey: queueJson([
          for (var i = 0; i < 300; i++) sig(i, kind: FeedbackKind.explicit),
        ]),
      });
      expect(await store.add(sig(900)), isFalse);
      expect(await store.add(sig(901, kind: FeedbackKind.explicit)), isFalse);

      final st = await store.stats();
      expect(st.count, 300);
      expect(st.explicitCount, 300);
      expect(st.dropped, 1, reason: 'odrzucony automatyczny się liczy');
    });
  });

  group('uszkodzony zapis', () {
    test('zły JSON: kopia surowego zapisu, flaga, kolejka działa dalej',
        () async {
      const raw = '{"v":1,"items":[{"id":';
      seedFeedback({FeedbackStore.prefsKey: raw});

      expect(await store.list(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FeedbackStore.corruptKey), raw);
      expect((await store.stats()).corrupt, isTrue);

      expect(await store.add(sig(1)), isTrue);
      expect(await store.list(), hasLength(1));
      expect((await store.stats()).corrupt, isTrue);
    });

    test('jeden zły element: reszta ocalała, kopia całości', () async {
      final good = sig(1).toJson();
      final raw = jsonEncode({
        'v': 1,
        'items': [
          good,
          {...good, 'id': 'sig-2', 'kind': 'praise'},
          {...good, 'id': 'sig-3', 'text': null},
          'śmieć',
        ],
        'dropped': 7,
      });
      seedFeedback({FeedbackStore.prefsKey: raw});

      expect((await store.list()).map((e) => e.id), ['sig-1']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FeedbackStore.corruptKey), raw);
      final st = await store.stats();
      expect(st.corrupt, isTrue);
      expect(st.dropped, 7, reason: 'liczniki z zapisu zostają');
    });

    test(
        'element o dobrej strukturze, ale niezgodny z kontraktem, zostaje '
        '(odsieje go uploader) — to nie jest uszkodzenie', () async {
      final good = sig(1).toJson();
      seedFeedback({
        FeedbackStore.prefsKey: jsonEncode({
          'v': 1,
          'items': [
            good,
            {...good, 'id': 'sig-2', 'platform': 'amiga'},
            {...good, 'id': 'sig-3', 'text': ''},
          ],
        }),
      });
      final items = await store.list();
      expect(items.map((e) => e.id), ['sig-1', 'sig-2', 'sig-3']);
      expect(items.map((e) => e.isValidForUpload), [true, false, false]);
      expect((await store.stats()).corrupt, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(FeedbackStore.corruptKey), isFalse);
    });

    test('kopia powstaje RAZ — druga awaria nie nadpisuje pierwszej', () async {
      seedFeedback({FeedbackStore.prefsKey: 'pierwsza-awaria'});
      await store.list();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(FeedbackStore.prefsKey, 'druga-awaria');

      await store.list();
      expect(prefs.getString(FeedbackStore.corruptKey), 'pierwsza-awaria');
    });

    test('wartość innego typu pod kluczem', () async {
      seedFeedback({FeedbackStore.prefsKey: 42});
      expect(await store.add(sig(1)), isTrue);
      expect(await store.list(), hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FeedbackStore.corruptKey), '42');
    });
  });

  group('bez wyścigów', () {
    test('60 równoległych add → 60 elementów', () async {
      await Future.wait([for (var i = 0; i < 60; i++) store.add(sig(i))]);
      final ids = (await store.list()).map((e) => e.id).toList();
      expect(ids, [for (var i = 0; i < 60; i++) 'sig-$i']);
    });

    test('równoległe add, markSent i remove — wynik jak po kolei', () async {
      await fill(0, 10);
      await Future.wait([
        store.add(sig(10)),
        store.markSent(['sig-0', 'sig-1']),
        store.add(sig(11)),
        store.remove('sig-5'),
        store.add(sig(12)),
        store.markRejected(['sig-9']),
      ]);
      final ids = (await store.list()).map((e) => e.id).toList();
      expect(ids, [
        'sig-2', 'sig-3', 'sig-4', 'sig-6', 'sig-7', 'sig-8', //
        'sig-10', 'sig-11', 'sig-12',
      ]);
      final st = await store.stats();
      expect(st.sent, 2);
      expect(st.rejected, 1);
    });
  });

  test('clear usuwa kolejkę, liczniki i kopię uszkodzonego zapisu', () async {
    seedFeedback({
      FeedbackStore.prefsKey: queueJson([sig(1)], dropped: 3),
      FeedbackStore.corruptKey: 'stary-zapis',
    });
    await store.clear();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(FeedbackStore.prefsKey), isFalse);
    expect(prefs.containsKey(FeedbackStore.corruptKey), isFalse);
    final st = await store.stats();
    expect(st.count, 0);
    expect(st.dropped, 0);
  });
}
