import '../../../database/passivation_dao.dart';
import '../../../domain/passivation/passivation_record.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../core/skill_guards.dart';
import '../records/passivation_add_skill.dart' show isPassivationAddRequest;

/// Rejestr trawienia/pasywacji: ostatni zabieg (opcjonalnie dla linii)
/// i wyniki prób. Tylko odczyt — nowy wpis robi się w module.
class PassivationStatusSkill extends AssistantSkill {
  PassivationStatusSkill({Future<List<PassivationRecord>> Function()? load})
      : _load = load ?? (() => PassivationDao().listAll());
  final Future<List<PassivationRecord>> Function() _load;

  @override
  String get id => 'passivation.status';
  @override
  String get toolId => 'passivation';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Kiedy była ostatnia pasywacja', 'When was the last passivation'),
        SkillExample('Pasywacja linii L-12', 'Passivation of line L-12'),
        SkillExample('Czy próba po trawieniu wyszła OK', 'Did the test after pickling pass'),
        SkillExample('Ile zabiegów pasywacji w rejestrze', 'How many passivation treatments in the register'),
        SkillExample('Ostatnie trawienie i pasywacja', 'Last pickling and passivation'),
        SkillExample('Pokaż rejestr pasywacji', 'Show the passivation register'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz trawienie i pasywację', routesTo: 'tool.open'),
        SkillRejection('do czego służy trawienie i pasywacja', routesTo: 'tool.explain'),
        SkillRejection('przebarwienie spoiny słomkowe'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kOpenOrAboutStartNoShow.hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['pasywac', 'trawien', 'passivat', 'pickling'])) return null;
    if (isPassivationAddRequest(u.folded)) return null;
    if (u.hasStem(const ['dodaj', 'zapisz', 'nowy', 'nowa', 'add', 'new'])) return null;
    final line = RegExp(r'\b(?:linii|linia|line)\s+([A-Za-z0-9][\w\-/.]*)',
            caseSensitive: false)
        .firstMatch(u.raw)
        ?.group(1);
    return SkillMatch(this, .9,
        slots: {if (line != null) 'line': line}, utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final List<PassivationRecord> all;
    try {
      all = (await _load()).where((r) => r.deletedAt == null).toList();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać rejestru pasywacji.',
          'Could not read the passivation register.'));
    }
    final line = m.slots['line'] as String?;
    final list = [
      for (final r in all)
        if (line == null || r.line.toLowerCase() == line.toLowerCase()) r
    ]..sort((a, b) => b.date.compareTo(a.date));
    if (list.isEmpty) {
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  line == null
                      ? 'Rejestr pasywacji jest pusty.'
                      : 'Brak wpisów dla linii $line.',
                  line == null
                      ? 'The passivation register is empty.'
                      : 'No entries for line $line.')),
          show: ShowInModule(toolId));
    }
    final last = list.first;
    final nok = list.where((r) => r.testResult == PassivationResult.nok).length;
    String kind(bool en) => switch (last.treatment) {
          PassivationTreatment.pickling => en ? 'pickling' : 'trawienie',
          PassivationTreatment.both => en ? 'pickling + passivation' : 'trawienie + pasywacja',
          _ => en ? 'passivation' : 'pasywacja',
        };
    String result(bool en) => switch (last.testResult) {
          PassivationResult.ok => en ? 'test OK' : 'próba OK',
          PassivationResult.nok => en ? 'test FAILED' : 'próba NIE przeszła',
          _ => en ? 'no test result' : 'bez wyniku próby',
        };
    final where = [last.line, last.testPackage, last.area]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final dwell = last.dwellMin == null ? '' : ', ${fmt(last.dwellMin!, ctx.lang)} min';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Ostatnio: ${last.date} — ${kind(false)}${where.isEmpty ? '' : ' ($where)'}${last.agent.isEmpty ? '' : ', ${last.agent}'}$dwell, ${result(false)}. Wpisów: ${list.length}${nok > 0 ? ', nieudanych prób: $nok' : ''}.',
                'Last: ${last.date} — ${kind(true)}${where.isEmpty ? '' : ' ($where)'}${last.agent.isEmpty ? '' : ', ${last.agent}'}$dwell, ${result(true)}. Entries: ${list.length}${nok > 0 ? ', failed tests: $nok' : ''}.')),
        show: ShowInModule(toolId));
  }
}
