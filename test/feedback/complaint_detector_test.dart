// Detektor sygnałów feedbacku w wypowiedzi (PL + EN).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/feedback/complaint_detector.dart';
import 'package:cut_list_app/feedback/feedback_signal.dart';

void _expectAll(List<String> phrases, FeedbackKind? kind,
    {required bool lastTurnFailed}) {
  for (final p in phrases) {
    expect(classifyFeedback(p, lastTurnFailed: lastTurnFailed), kind,
        reason: '„$p” (lastTurnFailed: $lastTurnFailed)');
  }
}

void main() {
  test('explicit: „zgłoś problem / błąd”, „report a problem”', () {
    _expectAll(const [
      'zgłoś problem: kalkulator spadku źle liczy',
      'Zgłoś błąd',
      'ZGLOS BLAD',
      'zgłoś problem z tym modułem',
      'chcę zgłosić błąd w zeszycie ISO',
      'zgłaszam problem z mikrofonem',
      'zgłoszenie błędu',
      'zgłoś usterkę',
      'zgłoś to twórcy',
      'chciałbym coś zgłosić',
      'report a problem',
      'Report a bug',
      'I want to report an issue with the calculator',
      'send feedback',
    ], FeedbackKind.explicit, lastTurnFailed: false);
  });

  test('complaint z odniesieniem do aplikacji — bez nieudanej tury', () {
    _expectAll(const [
      'ta apka nie działa',
      'ta aplikacja jest beznadziejna',
      'ten kalkulator źle liczy',
      'ten moduł jest bez sensu',
      'ten ekran mnie wkurza',
      'w tym module nie da się nic zrobić',
      'asystent nic nie rozumie',
      'ten program jest głupi',
      'to nie działa',
      'kurde, to jest bez sensu',
      'to mnie wkurza',
      'no to w ogóle nie działa',
      'tutaj nic nie działa',
      'this app is broken',
      'this is stupid',
      "it doesn't work",
      "it's useless",
      'the app keeps crashing',
      'the calculator gives wrong results',
      'this calculator makes no sense',
    ], FeedbackKind.complaint, lastTurnFailed: false);
  });

  test('complaint zwrócony do asystenta (2. osoba)', () {
    _expectAll(const [
      'nie rozumiesz mnie',
      'nic nie umiesz',
      'jesteś głupi',
      "you don't understand",
      "you're useless",
    ], FeedbackKind.complaint, lastTurnFailed: false);
  });

  test(
      '„spawarka nie działa” bez nieudanej tury → null, po nieudanej → complaint',
      () {
    const phrases = [
      'spawarka nie działa',
      'nie działa',
      'bez sensu',
      'przecinarka źle liczy',
      'my welder is broken',
      'ta spoina jest do bani',
    ];
    _expectAll(phrases, null, lastTurnFailed: false);
    _expectAll(phrases, FeedbackKind.complaint, lastTurnFailed: true);
  });

  test('cantFind: „gdzie jest…”, „nie mogę znaleźć…”, „jak znaleźć…”', () {
    for (final failed in [false, true]) {
      _expectAll(const [
        'gdzie jest kalkulator spadku',
        'Gdzie są moje uprawnienia?',
        'gdzie znajdę tabelę elektrod',
        'nie mogę znaleźć przelicznika cali',
        'nie mogę nigdzie znaleźć zeszytu',
        'jak znaleźć zeszyt ISO',
        'w tej apce nie da się nic znaleźć',
        'where is the pipe weight calculator',
        "where's the ISO notebook",
        "I can't find the settings",
        'how do I find the takeoff table',
      ], FeedbackKind.cantFind, lastTurnFailed: failed);
    }
  });

  test('zwykłe polecenia i pytania → null', () {
    for (final failed in [false, true]) {
      _expectAll(const [
        '',
        '   ',
        'ile waży rura dn50',
        'narysuj kolano 90',
        'dodaj zawór kulowy dn50',
        'jak liczyć spadek rurociągu',
        'nie rozumiem jak liczyć spadek',
        'to jest spoina pachwinowa',
        'zgłoszenie do egzaminu spawacza',
        'what is the weight of a dn50 pipe',
        'how much does a 2 inch pipe weigh',
      ], null, lastTurnFailed: failed);
    }
  });

  test('pierwszeństwo: explicit > cantFind > complaint', () {
    expect(
        classifyFeedback('zgłoś problem, nie mogę znaleźć kalkulatora',
            lastTurnFailed: false),
        FeedbackKind.explicit);
    expect(
        classifyFeedback('gdzie jest ten kalkulator, ta apka nie działa',
            lastTurnFailed: false),
        FeedbackKind.cantFind);
  });
}
