// „Brudna mowa": polecenia tak, jak zapisuje je rozpoznawanie mowy w hałasie,
// z żargonem budowy. Każdy przypadek ma oczekiwany wynik ALBO pytanie —
// zasada: nigdy cichy zły wynik. `absent` = pola, których parser NIE może
// wypełnić (bo byłyby zgadnięte albo złe); `outcome` = co zobaczy spawacz:
// podsumowanie (`ready`), pytanie o pole (`needs:<pole>`), odmowa, tryb
// „Odpowiedz" (`answer`), odczyt moich parametrów (`query`), wpis do
// dziennika (`journal`), otwarcie narzędzia (`open`).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/assistant_intents.dart';
import 'package:cut_list_app/assistant/assistant_parser.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart';

class _Dirty {
  final String text;
  final String intent;
  final Map<String, Object?> fields;
  final Set<String> absent;
  final String outcome;
  const _Dirty(this.text, this.intent, this.outcome,
      [this.fields = const {}, this.absent = const {}]);
}

const _save = kIntentSaveWeldParameter;
const _journal = kIntentAddWeldJournalEntry;
const _query = kIntentQueryMyParams;
const _answer = kIntentAnswerQuestion;
const _open = kIntentOpenTool;

const _tail = 'nierdzewka ścianka 3 mm 90 A';

const _cases = <_Dirty>[
  // ── Żargon prądu i ścianki ────────────────────────────────────────────────
  _Dirty('zapisz nierdzewka dwójka tig bez drutu sześćdziesiąt ampów', _save,
      'ready', {'material': 'SS', 'process': 'TIG', 'filler': false, 'wall_mm': 2.0, 'current_a': 60.0}),
  _Dirty('zapisz tig na setkę nierdzewka ścianka 2 mm bez drutu', _save,
      'ready', {'current_a': 100.0, 'wall_mm': 2.0}),
  _Dirty('zapisz TIG na stówę bez drutu kwasówka 2 mm', _save, 'ready',
      {'current_a': 100.0, 'material': 'SS'}),
  _Dirty('zapisz sześćdziesiąt ampów tig bez drutu nierdzewka ścianka 2 mm',
      _save, 'ready', {'current_a': 60.0, 'wall_mm': 2.0}),
  _Dirty('zapisz sto dziesięć ampów MAG czarna ścianka 5 mm', _save, 'ready',
      {'current_a': 110.0, 'process': 'MIG_MAG', 'material': 'CS', 'filler': true}),
  _Dirty('zapisz TIG bez drutu nierdzewka ścianka 2 mm 60 ampy', _save,
      'ready', {'current_a': 60.0}),
  _Dirty('zapisz TIG z drutem kwasówka ścianka 2,77 90 ampy', _save, 'ready',
      {'wall_mm': 2.77, 'current_a': 90.0, 'material': 'SS'}),
  _Dirty(
      'zapisz eee tig no bez drutu nierdzewka no dwa milimetry i sześćdziesiąt amperów',
      _save,
      'ready',
      {'wall_mm': 2.0, 'current_a': 60.0, 'filler': false}),

  // ── Dwie liczby obok siebie: nigdy 62 A ──────────────────────────────────
  _Dirty('zapisz TIG bez drutu nierdzewka ścianka dwa sześćdziesiąt amper',
      _save, 'ready', {'wall_mm': 2.0, 'current_a': 60.0}),
  _Dirty('zapisz TIG bez drutu nierdzewka ścianka dwa, sześćdziesiąt amper',
      _save, 'ready', {'wall_mm': 2.0, 'current_a': 60.0}),
  // „dwa sześćdziesiąt" bez jednostki: 2 i 60 czy 2,60 mm? → pytanie.
  _Dirty('zapisz TIG bez drutu nierdzewka 60 A ścianka dwa sześćdziesiąt',
      _save, 'needs:wall_mm', {'current_a': 60.0}, {'wall_mm', 'diameter_mm'}),
  _Dirty(
      'zapisz TIG bez drutu nierdzewka ścianka dwa sześćdziesiąt milimetra 60 A',
      _save,
      'needs:wall_mm',
      {'current_a': 60.0},
      {'wall_mm', 'diameter_mm'}),
  _Dirty('save tig stainless wall two sixty amps no filler', _save, 'ready',
      {'wall_mm': 2.0, 'current_a': 60.0, 'filler': false}),

  // ── Cale = NPS (średnica), nigdy ścianka ─────────────────────────────────
  _Dirty('zapisz TIG z drutem nierdzewka ścianka 2 mm 60 A rura 2 cale', _save,
      'ready', {'diameter_mm': 60.3, 'wall_mm': 2.0}),
  _Dirty('zapisz TIG z drutem nierdzewka ścianka 3/4 cala 60 A', _save,
      'needs:wall_mm', {'diameter_mm': 26.7, 'current_a': 60.0}, {'wall_mm'}),
  _Dirty('zapisz TIG z drutem nierdzewka 2 mm 60 A rura 3/4"', _save, 'ready',
      {'diameter_mm': 26.7, 'wall_mm': 2.0}),
  _Dirty('zapisz TIG z drutem nierdzewka ścianka trzy czwarte cala 60 A', _save,
      'needs:wall_mm', {'diameter_mm': 26.7}, {'wall_mm'}),
  _Dirty('zapisz TIG z drutem nierdzewka ścianka 3/4 60 A', _save,
      'needs:wall_mm', {'current_a': 60.0}, {'wall_mm', 'diameter_mm'}),
  _Dirty('zapisz TIG z drutem nierdzewka 2 mm 60 A rura 1 1/4 cala', _save,
      'ready', {'diameter_mm': 42.2, 'wall_mm': 2.0}),
  _Dirty('zapisz TIG z drutem nierdzewka 2 mm 60 A rura pół cala', _save,
      'ready', {'diameter_mm': 21.3, 'wall_mm': 2.0}),
  _Dirty('zapisz TIG bez drutu nierdzewka ścianka 2 mm 60 A rura setka', _save,
      'ready', {'diameter_mm': 114.3}),

  // ── Pozycje literowane przez rozpoznawanie mowy ──────────────────────────
  _Dirty('zapisz TIG z drutem $_tail pozycja pe ef', _save, 'ready',
      {'position': 'PF'}),
  _Dirty('zapisz TIG z drutem $_tail pozycja pe a', _save, 'ready',
      {'position': 'PA', 'current_a': 90.0}),
  _Dirty('zapisz TIG z drutem $_tail pozycja pe ce', _save, 'ready',
      {'position': 'PC'}),
  _Dirty('zapisz TIG z drutem $_tail pe ef', _save, 'ready',
      {'position': 'PF'}),
  _Dirty('zapisz TIG z drutem $_tail pozycja ha el zero czterdzieści pięć',
      _save, 'ready', {'position': 'H-L045', 'current_a': 90.0, 'wall_mm': 3.0}),
  _Dirty('zapisz TIG z drutem $_tail pozycja H-L045', _save, 'ready',
      {'position': 'H-L045'}),
  _Dirty('zapisz TIG z drutem $_tail pozycja 5 G', _save, 'ready',
      {'position': '5G'}),
  _Dirty('zapisz TIG z drutem $_tail pozycja pięć gie', _save, 'ready',
      {'position': '5G'}),
  _Dirty('zapisz TIG z drutem $_tail 6 G R', _save, 'ready',
      {'position': '6GR'}),

  // ── Formowanie ≠ gaz i przepływ na palnik ────────────────────────────────
  _Dirty(
      'zapisz TIG bez drutu nierdzewka ścianka 2 mm 60 A formowanie 5 litrów argon 8 litrów',
      _save,
      'ready',
      {'purge_lpm': 5.0, 'flow_lpm': 8.0, 'gas': 'AR'}),
  _Dirty(
      'zapisz TIG bez drutu nierdzewka ścianka 2 mm 60 A formowanie azotem 5 l',
      _save,
      'ready',
      {'purge_lpm': 5.0},
      {'flow_lpm', 'gas'}),
  _Dirty(
      'zapisz TIG bez drutu nierdzewka ścianka 2 mm 60 A gaz formujący 6 l/min przepływ na palnik 9 l/min',
      _save,
      'ready',
      {'purge_lpm': 6.0, 'flow_lpm': 9.0}),

  // ── Metoda, materiał, drut ───────────────────────────────────────────────
  _Dirty('zapisz tik bez drutu nierdzewka 2 mm 60 A', _save, 'ready',
      {'process': 'TIG'}),
  _Dirty('zapisz argonówka nierdzewka bez drutu ścianka 2 mm 60 A', _save,
      'ready', {'process': 'TIG'}, {'gas'}),
  _Dirty('zapisz mag jedynka czarna ścianka 5 mm 150 ampów', _save, 'ready',
      {'process': 'MIG_MAG', 'electrode_mm': 1.0, 'material': 'CS', 'wall_mm': 5.0}),
  // „Jedynka" przy TIG to nie ścianka 1 mm ani elektroda — pytanie o ściankę.
  _Dirty('zapisz TIG jedynka nierdzewka bez drutu 60 A', _save,
      'needs:wall_mm', {}, {'wall_mm', 'electrode_mm'}),
  _Dirty('zapisz elektroda dwójka czarna ścianka 6 mm 80 A', _save, 'ready',
      {'process': 'MMA', 'electrode_mm': 2.0, 'wall_mm': 6.0, 'filler': true}),
  _Dirty('zapisz elektrodą stal czarna ścianka 8 mm 110 ampów', _save, 'ready',
      {'process': 'MMA', 'material': 'CS', 'current_a': 110.0}),
  _Dirty('zapisz TIG bez drutu czarna nierdzewka ścianka 2 mm 60 A', _save,
      'needs:material', {}, {'material'}),
  _Dirty('zapisz TIG bez drutu nierdzewka ścianka 2 mm prąd sześćset', _save,
      'rejected:outOfRange', {'current_a': 600.0}),

  // ── Pytanie ≠ zapis ──────────────────────────────────────────────────────
  _Dirty('jaki prąd na TIG nierdzewka 2 mm', _answer, 'answer'),
  _Dirty('ile ampów na dwójkę nierdzewka tig', _answer, 'answer'),
  _Dirty('a jaki gaz do duplexu', _answer, 'answer'),
  _Dirty('How much current for 2 mm stainless TIG?', _answer, 'answer'),
  _Dirty('czy możesz zapisać TIG nierdzewka 2 mm 60 A bez drutu', _save,
      'ready', {'current_a': 60.0}),

  // ── Moje parametry (odczyt offline) ──────────────────────────────────────
  _Dirty('jaki prąd mam zapisany na nierdzewkę 2 mm', _query, 'query',
      {'material': 'SS', 'wall_mm': 2.0}, {'current_a'}),
  _Dirty('pokaż moje parametry na czarną MAG', _query, 'query',
      {'material': 'CS', 'process': 'MIG_MAG'}),
  _Dirty('co mam zapisane dla TIG z drutem', _query, 'query',
      {'process': 'TIG', 'filler': true}),
  _Dirty('otwórz moje parametry', _open, 'open'),

  // ── Dziennik spoin ───────────────────────────────────────────────────────
  _Dirty('dopisz spoinę numer 12 do dziennika', _journal, 'needs:project',
      {'weld_no': '12'}),
  _Dirty('dopisz spoinę W-12 projekt Blok 4 WPS 141-01', _journal, 'journal',
      {'weld_no': 'W-12', 'project': 'Blok 4', 'wps': '141-01'}),
  _Dirty('dodaj do dziennika spoinę dwanaście, projekt Orlen', _journal,
      'journal', {'weld_no': '12', 'project': 'Orlen'}),
  _Dirty('dopisz do dziennika', _journal, 'needs:weld_no'),
  _Dirty(
      'Zapisz TIG z drutem stal nierdzewna ścianka 3 mm 90 A spoina doczołowa pozycja 6G',
      _save,
      'ready',
      {'joint': 'BUTT', 'position': '6G'}),
  _Dirty('Save stainless TIG with wire wall 3 mm 90 A fillet weld 2F', _save,
      'ready', {'joint': 'FILLET', 'position': '2F'}),
];

String _outcome(AssistantProposal p) {
  if (p.intent == kIntentUnknown) return 'unknown';
  return switch (validateAssistantProposal(p.intent, p.fields)) {
    AssistantReadyToSave() => 'ready',
    AssistantReadyToOpen() => 'open',
    AssistantReadyToAnswer() => 'answer',
    AssistantReadyToQuery() => 'query',
    AssistantReadyToJournal() => 'journal',
    AssistantNeedsField(:final field) => 'needs:$field',
    AssistantRejected(:final reason) => 'rejected:${reason.name}',
  };
}

void main() {
  test('zestaw ma co najmniej 40 brudnych poleceń', () {
    expect(_cases.length, greaterThanOrEqualTo(40));
  });

  for (final c in _cases) {
    test(c.text, () {
      final p = parseAssistantCommand(c.text);
      expect(p.intent, c.intent, reason: 'intencja: $p');
      c.fields.forEach((key, value) {
        expect(p.fields[key], value, reason: '$key w: $p');
      });
      for (final key in c.absent) {
        expect(p.fields.containsKey(key), isFalse,
            reason: '$key nie może być zgadnięte: $p');
      }
      expect(_outcome(p), c.outcome, reason: '$p');
    });
  }

  group('odpowiedź na pytanie o jedno pole — też brudna', () {
    test('„na setkę" na pytanie o prąd = 100 A', () {
      expect(parseFieldAnswer('current_a', 'na setkę'), {'current_a': 100.0});
    });
    test('„dwójka" na pytanie o ściankę = 2 mm', () {
      expect(parseFieldAnswer('wall_mm', 'dwójka')['wall_mm'], 2.0);
    });
    test('„dwa sześćdziesiąt" na pytanie o ściankę → brak (zapyta znowu)', () {
      expect(parseFieldAnswer('wall_mm', 'dwa sześćdziesiąt'), isEmpty);
    });
    test('„20 A" na pytanie o ściankę to nie ścianka 20 mm', () {
      final r = parseFieldAnswer('wall_mm', '20 A');
      expect(r.containsKey('wall_mm'), isFalse);
      expect(r['current_a'], 20.0);
    });
    test('„trzy czwarte cala" na pytanie o ściankę → brak ścianki', () {
      expect(parseFieldAnswer('wall_mm', 'trzy czwarte cala')
          .containsKey('wall_mm'), isFalse);
    });
    test('numer spoiny i projekt', () {
      expect(parseFieldAnswer('weld_no', '12'), {'weld_no': '12'});
      expect(parseFieldAnswer('weld_no', 'dwanaście'), {'weld_no': '12'});
      expect(parseFieldAnswer('weld_no', 'W-7'), {'weld_no': 'W-7'});
      expect(parseFieldAnswer('project', 'projekt Blok 4.'),
          {'project': 'Blok 4'});
      expect(parseFieldAnswer('project', '   '), isEmpty);
    });
  });

  group('liczby słownie: tylko malejące rzędy się łączą', () {
    final cases = <String, double>{
      'sto dwa': 102,
      'dwieście jedenaście': 211,
      'pięćset sześćdziesiąt': 560,
      'sixty five': 65,
      'dwa sześćdziesiąt': 2,
      'dziesięć pięć': 10,
      'sto sto': 100,
    };
    cases.forEach((text, value) {
      test(text, () => expect(parseSpokenNumber(text), value));
    });
  });
}
