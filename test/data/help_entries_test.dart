// Pomoc w aplikacji (lib/data/help_entries.dart): wpisy do modułów z ostatniej
// fali (t8/5, prace pożarowe, elektrody, PCC-1, pogoda, stożki, słownik,
// spoina pachwinowa, twardość, akord, import do wyceny) i poprawione stare
// wpisy. Sprawdza: obie wersje językowe, unikalne id, właściwą kategorię,
// te same liczby po polsku i po angielsku (we wszystkich wpisach) oraz to, że
// wyszukiwarka (i tryb offline asystenta, który z niej korzysta) trafia
// w nowe wpisy.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/help_entries.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/help_search.dart';

/// Nowe wpisy → kategoria, w której mają być.
const Map<String, String> _newEntries = {
  't85-cooling-time': 'pwht-preheat',
  't85-hit-window': 'pwht-preheat',
  'weather-wind-rain-frost': 'weather-electrodes',
  'weather-cold-dew-point': 'weather-electrodes',
  'electrode-exposure-limit': 'weather-electrodes',
  'electrode-oven-redry': 'weather-electrodes',
  'hot-work-prep': 'safety',
  'hot-work-lel-watch': 'safety',
  'flange-pcc1-alignment': 'flanges-bolting',
  'flange-face-damage': 'flanges-bolting',
  'flange-thread-protrusion': 'flanges-bolting',
  'cone-development': 'cutting-bevel',
  'transition-square-round': 'cutting-bevel',
  'glossary-site-languages': 'codes',
  'fillet-weld-capacity': 'calculations',
  'fillet-throat-leg': 'calculations',
  'hardness-sour-limit': 'materials',
  'hardness-wpqr-b313': 'materials',
  'hardness-conversion': 'materials',
  'quote-import-welds': 'quotes-costs',
  'quote-import-skipped': 'quotes-costs',
  'piecework-di-rate': 'quotes-costs',
  'piecework-rejects-split': 'quotes-costs',
};

/// Stare wpisy poprawione pod nowe moduły.
const List<String> _fixedEntries = [
  'tig-cracks-cool',
  'heat-input-formula',
  'hot-work-35-ft',
  'torque-pattern',
  'nace-mr0175',
];

HelpEntry _entry(String id) => kHelpCategories
    .expand((c) => c.entries)
    .firstWhere((e) => e.id == id, orElse: () => throw StateError(id));

/// Liczby z tekstu jako wartości: przecinek dziesiętny = kropka („2,2” == „2.2”,
/// „0,80” == „0.8”). Znak minus i jednostki pomijane.
Set<double> _numbers(String text) => RegExp(r'\d+(?:[.,]\d+)?')
    .allMatches(text)
    .map((m) => double.parse(m.group(0)!.replaceAll(',', '.')))
    .toSet();

void main() {
  test('id kategorii i wpisów są unikalne w całej pomocy', () {
    final catIds = kHelpCategories.map((c) => c.id).toList();
    expect(catIds.toSet().length, catIds.length);
    final ids = kHelpCategories.expand((c) => c.entries).map((e) => e.id);
    final seen = <String>{};
    for (final id in ids) {
      expect(seen.add(id), isTrue, reason: 'powtórzone id: $id');
    }
  });

  test('każdy nowy wpis jest w istniejącej, właściwej kategorii', () {
    final catIds = kHelpCategories.map((c) => c.id).toSet();
    _newEntries.forEach((id, catId) {
      expect(catIds, contains(catId), reason: '$id → brak kategorii $catId');
      final cat = kHelpCategories.firstWhere((c) => c.id == catId);
      expect(cat.entries.map((e) => e.id), contains(id),
          reason: '$id nie jest w kategorii $catId');
    });
  });

  test('nowa kategoria „Pogoda i elektrody” ma tytuł i opis w obu językach', () {
    final cat = kHelpCategories.firstWhere((c) => c.id == 'weather-electrodes');
    expect(cat.title(AppLanguage.pl), 'Pogoda i elektrody');
    expect(cat.title(AppLanguage.en), 'Weather & electrodes');
    expect(cat.subtitle(AppLanguage.pl), isNot(cat.subtitle(AppLanguage.en)));
  });

  group('nowe i poprawione wpisy', () {
    for (final id in [..._newEntries.keys, ..._fixedEntries]) {
      test('$id: PL i EN, tagi, te same liczby', () {
        final e = _entry(id);
        final qPl = e.question(AppLanguage.pl);
        final qEn = e.question(AppLanguage.en);
        final aPl = e.answer(AppLanguage.pl);
        final aEn = e.answer(AppLanguage.en);
        for (final s in [qPl, qEn, aPl, aEn]) {
          expect(s.trim(), isNotEmpty);
        }
        expect(qPl, isNot(qEn), reason: 'pytanie bez tłumaczenia');
        expect(aPl, isNot(aEn), reason: 'odpowiedź bez tłumaczenia');

        expect(e.tags, isNotEmpty);
        expect(e.tags.toSet().length, e.tags.length, reason: 'powtórzony tag');
        for (final t in e.tags) {
          expect(t, t.toLowerCase(), reason: 'tag „$t” nie jest małymi literami');
        }

        expect(_numbers('$qPl $aPl'), _numbers('$qEn $aEn'),
            reason: 'liczby PL ≠ EN w „$id”');
      });
    }
  });

  test('we wszystkich wpisach pomocy liczby PL == liczby EN', () {
    final bad = <String>[];
    for (final e in kHelpCategories.expand((c) => c.entries)) {
      final pl = _numbers(
          '${e.question(AppLanguage.pl)} ${e.answer(AppLanguage.pl)}');
      final en = _numbers(
          '${e.question(AppLanguage.en)} ${e.answer(AppLanguage.en)}');
      if (pl.length != en.length || !pl.containsAll(en)) {
        bad.add('${e.id}: tylko PL ${pl.difference(en)}, '
            'tylko EN ${en.difference(pl)}');
      }
    }
    expect(bad, isEmpty);
  });

  group('stare wpisy nie przeczą nowym modułom', () {
    test('suszenie elektrod: nie 230 °C (D1.5), tylko 260–430 °C wg D1.1', () {
      final e = _entry('tig-cracks-cool');
      for (final lang in AppLanguage.values) {
        expect(e.answer(lang), isNot(contains('230')));
        expect(e.answer(lang), contains('260–430 °C'));
      }
    });

    test('PCC-1 Legacy: rundy 20–30 / 50–70 / 100 %, runda 5 po ≥ 4 h', () {
      final e = _entry('torque-pattern');
      for (final lang in AppLanguage.values) {
        final a = e.answer(lang);
        expect(a, contains('20–30 %'));
        expect(a, contains('50–70 %'));
        expect(a, contains('4 h'));
        expect(a, isNot(contains('20 min')));
        expect(a, isNot(contains('75%')));
      }
    });

    test('dozór po pracy: NFPA 51B:2019 co najmniej 1 h, nie „30 min” jako reguła',
        () {
      final e = _entry('hot-work-35-ft');
      for (final lang in AppLanguage.values) {
        final a = e.answer(lang);
        expect(a, contains('NFPA 51B:2019'));
        expect(a, contains('1 h'));
        expect(a, isNot(contains('high-risk')));
      }
    });

    test('NACE: 250 HV i 22 HRC to osobne limity, nie przeliczenie', () {
      final e = _entry('nace-mr0175');
      for (final lang in AppLanguage.values) {
        final a = e.answer(lang);
        expect(a, contains('250 HV'));
        expect(a, contains('248 HV'));
        expect(a, isNot(contains('~250 HV10')));
      }
    });
  });

  group('wyszukiwarka trafia w nowe wpisy', () {
    const cases = <(String, AppLanguage, String)>[
      ('czas stygnięcia t8/5', AppLanguage.pl, 't85-cooling-time'),
      ('t8/5 cooling time', AppLanguage.en, 't85-cooling-time'),
      ('DGW dozór', AppLanguage.pl, 'hot-work-lel-watch'),
      ('prace pożarowe zezwolenie', AppLanguage.pl, 'hot-work-prep'),
      ('elektrody E7018 piecyk', AppLanguage.pl, 'electrode-exposure-limit'),
      ('suszenie elektrod', AppLanguage.pl, 'electrode-oven-redry'),
      ('punkt rosy', AppLanguage.pl, 'weather-cold-dew-point'),
      ('wiatr deszcz mróz', AppLanguage.pl, 'weather-wind-rain-frost'),
      ('osiowanie kołnierzy PCC-1', AppLanguage.pl, 'flange-pcc1-alignment'),
      ('rysa przylga', AppLanguage.pl, 'flange-face-damage'),
      ('stożek rozwinięcie', AppLanguage.pl, 'cone-development'),
      ('square to round', AppLanguage.en, 'transition-square-round'),
      ('słownik niemiecki', AppLanguage.pl, 'glossary-site-languages'),
      ('nośność spoiny pachwinowej', AppLanguage.pl, 'fillet-weld-capacity'),
      ('przelicznik twardości HRC', AppLanguage.pl, 'hardness-conversion'),
      ('akord', AppLanguage.pl, 'piecework-di-rate'),
      ('importuj spoiny', AppLanguage.pl, 'quote-import-welds'),
    ];
    for (final (query, lang, id) in cases) {
      test('„$query” → $id', () {
        final top = searchHelp(query, lang, limit: 3).map((r) => r.entry.id);
        expect(top, contains(id));
      });
    }
  });

  test('tryb offline asystenta odpowiada nowym wpisem pomocy', () {
    final prev = AppLanguageController.current;
    addTearDown(() => AppLanguageController.current = prev);
    AppLanguageController.current = AppLanguage.pl;
    final reply = AiChatService.instance
        .offlineReply('Ile elektrody E7018 mogą leżeć poza piecykiem?');
    expect(reply.kind, AiReplyKind.offlineHelp);
    expect(reply.text, contains('E70XX (E7016, E7018) — 4 h'));
    expect(reply.citations.single, 'Pogoda i elektrody');
  });
}
