// Fallbacki mózgu: „co umiesz" (także dla bieżącego modułu), otwórz
// narzędzie, wyjaśnij narzędzie, wiedza z Pomocy i słownika, „nie
// rozumiem" z propozycjami narzędzi.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';

import '../../support/assistant_test_support.dart';

void main() {
  group('co umiesz', () {
    test('ogólnie: przykłady umiejętności i chipy', () async {
      final r = await BrainHarness().say('co umiesz?');
      expect(r.match!.skill.id, 'assistant.capabilities');
      final a = r.result as AnswerResult;
      final values = a.answer.lines.map((l) => l.value).toList();
      expect(values, contains('Jaka jest średnica rury DN40?'));
      expect(values, contains('Otwórz heat input'));
      expect(a.followUps, isNotEmpty);
    });
    test('EN', () async {
      final r = await BrainHarness(lang: AppLanguage.en).say('what can you do');
      expect(r.match!.skill.id, 'assistant.capabilities');
      expect((r.result as AnswerResult).answer.lines.map((l) => l.value),
          contains('What is the OD of DN40?'));
    });
    test('w module: co tu zrobię', () async {
      final r = await BrainHarness(activeToolId: 'dn_mm', onHome: false)
          .say('co tu zrobię?');
      final a = r.result as AnswerResult;
      expect(a.answer.text.pl, startsWith('„DN ↔ mm”'));
      expect(a.answer.lines.map((l) => l.value),
          contains('Jaka jest średnica rury DN40?'));
    });
    test('w module poziomu A: uczciwie, że liczenie głosem jeszcze nie działa',
        () async {
      final r = await BrainHarness(activeToolId: 'bolt_torque', onHome: false)
          .say('co mogę tu zrobić');
      expect(textOf(r.result), contains('jeszcze nie'));
    });
  });

  group('otwórz', () {
    test('„otwórz heat input" → pokaż moduł', () async {
      final r = await BrainHarness().say('otwórz heat input');
      expect(r.match!.skill.id, 'tool.open');
      final a = r.result as AnswerResult;
      expect(a.answer.text.pl, 'Otwieram „Heat input i CE”.');
      expect(a.show!.toolId, 'heat_input');
    });
    test('generyczne słowa nie przeszkadzają', () async {
      final r = await BrainHarness().say('otwórz proszę kalkulator heat input');
      expect((r.result as AnswerResult).show!.toolId, 'heat_input');
    });
    test('EN: open the DN table', () async {
      final r =
          await BrainHarness(lang: AppLanguage.en).say('open the DN table');
      expect((r.result as AnswerResult).show!.toolId, 'dn_mm');
    });
    test('„gdzie jest dziennik spoin" też otwiera', () async {
      final r = await BrainHarness().say('gdzie jest dziennik spoin');
      expect((r.result as AnswerResult).show!.toolId, 'weld_journal');
    });
    test('samo „otwórz" → pytanie, odpowiedź nazwą → otwarcie', () async {
      final h = BrainHarness();
      final r = await h.say('otwórz');
      expect((r.result as AskResult).slot, 'tool');
      final r2 = await h.say('rolling offset');
      expect((r2.result as AnswerResult).show!.toolId, 'rolling_offset');
    });
    test('każde narzędzie z rejestru otwiera się z tytułu PL i EN', () async {
      for (final t in availableTools) {
        final rPl = await BrainHarness().say('otwórz ${t.titlePl}');
        final rEn =
            await BrainHarness(lang: AppLanguage.en).say('open ${t.titleEn}');
        for (final r in [rPl, rEn]) {
          final res = r.result;
          final ids = switch (res) {
            AnswerResult(:final show) => [show?.toolId],
            AskResult(:final choices) => [
                for (final c in choices) c.utterance,
              ],
            _ => const <String?>[],
          };
          expect(
              ids.any((id) =>
                  id == t.id ||
                  (id != null &&
                      (id.contains(t.titlePl) || id.contains(t.titleEn)))),
              isTrue,
              reason: '${t.id}: ${textOf(res)}');
        }
      }
    });
  });

  group('wyjaśnij', () {
    test('„do czego służy rolling offset"', () async {
      final r = await BrainHarness().say('do czego służy rolling offset');
      expect(r.match!.skill.id, 'tool.explain');
      final a = r.result as AnswerResult;
      expect(a.answer.text.pl, startsWith('„Rolling offset”'));
      expect(a.show, isNull);
      expect(a.followUps.first.utterance, 'otwórz Rolling offset');
    });
    test('„co to jest heat input" → wyjaśnienie z przykładem głosowym',
        () async {
      final r = await BrainHarness().say('co to jest heat input');
      expect(r.match!.skill.id, 'tool.explain');
    });
    test('EN: what is the wall thickness tool for', () async {
      final r = await BrainHarness(lang: AppLanguage.en)
          .say('what is wall thickness for');
      expect(r.match!.skill.id, 'tool.explain');
      expect((r.result as AnswerResult).answer.text.en,
          contains('What is the wall of DN40 schedule 40?'));
    });
  });

  group('wiedza', () {
    test('Pomoc: „dlaczego pojawia się porowatość"', () async {
      final r = await BrainHarness().say('dlaczego pojawia się porowatość');
      expect(r.match!.skill.id, 'knowledge');
      final a = r.result as AnswerResult;
      expect(a.answer.text.pl, startsWith('Dlaczego pojawia się porowatość?'));
      expect(a.answer.source!.pl, startsWith('Pomoc'));
    });
    test('słownik: „jak jest podtopienie po niemiecku"', () async {
      final r = await BrainHarness().say('jak jest podtopienie po niemiecku');
      expect(r.match!.skill.id, 'knowledge');
      final a = r.result as AnswerResult;
      expect(a.answer.text.pl, contains('DE:'));
      expect(a.answer.source!.pl, contains('Słownik'));
    });
    test('EN: what is undercut in German', () async {
      final r = await BrainHarness(lang: AppLanguage.en)
          .say('what is undercut in German');
      expect(r.match!.skill.id, 'knowledge');
      expect(textOf(r.result, AppLanguage.en), contains('DE:'));
    });
    test('pojedyncze słowo z Pomocy nie wystarcza', () async {
      final r = await BrainHarness().say('dodaj spoinę 12');
      expect(r.match?.skill.id, isNot('knowledge'));
    });
  });

  group('nie rozumiem', () {
    test('bełkot → NotUnderstood, sygnał i propozycje', () async {
      final r = await BrainHarness().say('qwerty asdf zxcv');
      expect(r.notUnderstood, isTrue);
      final n = r.result as NotUnderstood;
      expect(n.suggestions, isNotEmpty);
      expect(n.suggestions.length, lessThanOrEqualTo(3));
    });
    test('propozycje z wyszukiwarki narzędzi', () async {
      final r = await BrainHarness().say('coś z kolanem chyba');
      final n = r.result as NotUnderstood;
      expect(n.suggestions.first.utterance, startsWith('otwórz '));
      expect(n.suggestions.length, 3);
    });
  });
}
