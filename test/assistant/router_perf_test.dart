// Wydajność routera: 500 wypowiedzi przez cały mózg (ocena + odpowiedź)
// w mniej niż 1,5 s. `match()` jest synchroniczne i bez I/O, więc to liczy
// czysty koszt logiki — na telefonie budżet na turę to ≤ 1,5 s od końca mowy.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/brain.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import 'support/assistant_test_support.dart';

void main() {
  test('500 wypowiedzi < 1,5 s', () async {
    final harness = BrainHarness();
    addTearDown(harness.timer.dispose);
    // Reuse the isolated session catalog, including its in-memory readers.
    // Rebuilding defaults would measure failed platform/database I/O rather
    // than the pure routing/answer logic this test budgets.
    final catalog = harness.brain.skills;
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
      // Spread across the full catalog, including later knowledge groups.
      for (var i = 0; i < 500; i++)
        corpus[(i * corpus.length ~/ 500) % corpus.length],
    ];
    final brain = AssistantBrain(skills: catalog);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());

    // Rozgrzewka: jednorazowe indeksy (słownik, Pomoc) i kompilacja JIT —
    // w aplikacji mózg żyje całą sesję, więc liczy się koszt tury, nie startu.
    for (final t in corpus) {
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
    print(
        'router: ${utterances.length} wypowiedzi w ${sw.elapsedMilliseconds} ms');
    // 2026-10-23: katalog urósł o ~35 umiejętności (moduły w rozmowie) —
    // ok. 1,8 ms na wypowiedź na stacji, więc 1 s dla 500 przestało mieć
    // zapas pod obciążeniem. 1,5 s (3 ms na turę) to nadal ~500× poniżej
    // budżetu tury na telefonie i łapie regres algorytmiczny.
    expect(sw.elapsed, lessThan(const Duration(milliseconds: 1500)));
  });
}
