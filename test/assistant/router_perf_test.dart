// Wydajność routera: 500 wypowiedzi przez cały mózg (ocena + odpowiedź)
// w mniej niż 1 s. `match()` jest synchroniczne i bez I/O, więc to liczy
// czysty koszt logiki — na telefonie budżet na turę to ≤ 1,5 s od końca mowy.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/brain.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import 'support/assistant_test_support.dart';

void main() {
  test('500 wypowiedzi < 1 s', () async {
    final catalog = buildSkillCatalog(actions: FakeActionsPort());
    final corpus = <String>[
      for (final s in catalog) ...[
        for (final e in s.examples) ...[e.pl, e.en],
        for (final r in s.rejections) r.text,
      ],
      'qwerty asdf',
      'coś z kolanem chyba',
      'a dla DN50?',
      'a ścianka?',
      'ten en 40',
      'nie wiem co powiedzieć',
    ];
    final utterances = [
      for (var i = 0; i < 500; i++) corpus[i % corpus.length],
    ];
    final brain = AssistantBrain(skills: catalog);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());

    // Rozgrzewka: jednorazowe indeksy (słownik, Pomoc) i kompilacja JIT —
    // w aplikacji mózg żyje całą sesję, więc liczy się koszt tury, nie startu.
    for (final t in corpus.take(20)) {
      await brain.handle(Utterance(t, lang: AppLanguage.pl), ctx);
      brain.cancelPending();
    }

    final sw = Stopwatch()..start();
    for (final t in utterances) {
      await brain.handle(Utterance(t, lang: AppLanguage.pl), ctx);
      brain.cancelPending();
    }
    sw.stop();
    // ignore: avoid_print
    print('router: ${utterances.length} wypowiedzi w ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });
}
