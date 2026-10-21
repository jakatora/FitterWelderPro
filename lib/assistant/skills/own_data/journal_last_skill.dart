import '../../../database/weld_journal_dao.dart';
import '../../../domain/weld_journal/weld_dates.dart';
import '../../../domain/weld_journal/weld_entry.dart';
import '../../../i18n/app_language.dart';
import '../../../services/welder_identity.dart';
import '../../core/skill.dart';

class JournalSnapshot {
  const JournalSnapshot({required this.stamp, this.entries = const []});
  final String? stamp;
  final List<WeldEntry> entries;
}

typedef JournalReader = Future<JournalSnapshot> Function();

Future<JournalSnapshot> readLocalJournal({required String? ownerStamp}) async {
  final stamp = ownerStamp?.trim().toUpperCase() ?? '';
  if (stamp.isEmpty) return const JournalSnapshot(stamp: null);
  final entries = await WeldJournalDao().listAll();
  return JournalSnapshot(stamp: stamp, entries: [
    for (final e in entries)
      if (!e.isDeleted && e.stamps.any((s) => s.toUpperCase() == stamp)) e,
  ]);
}

Future<JournalSnapshot> _readCurrent() async => readLocalJournal(
    ownerStamp: (await WelderIdentityService.instance.get())?.stamp);

final _lastQuery = RegExp(
  r'^(?:(?:prosze|powiedz|powiedz mi|please|tell me)\s+)*'
  r'(?:(?:(?:jaka byla|pokaz|podaj)\s+)?(?:moja |moje )?ostatnia '
  r'(?:spoina|spoine)(?: w dzienniku)?|kiedy spawalem ostatnio|'
  r'(?:(?:show|show me|what was)\s+)?(?:my |the )?(?:last|latest) weld|'
  r'when did i last weld)'
  r'(?:\s+(?:w projekcie|z projektu|in (?:the )?project|from (?:the )?project) .+)?$',
);
final _projectSuffix = RegExp(
  r'\s+(?:w\s+projekcie|z\s+projektu|in\s+(?:the\s+)?project|from\s+(?:the\s+)?project)\s+(.+?)\s*\??$',
  caseSensitive: false,
);
final _mentionsProject = RegExp(
    r'\s+(?:w projekcie|z projektu|in (?:the )?project|from (?:the )?project) .+$');

class JournalLastSkill extends AssistantSkill {
  JournalLastSkill({JournalReader? load}) : _load = load ?? _readCurrent;
  final JournalReader _load;

  @override
  String get id => 'journal.last';
  @override
  String get toolId => 'weld_journal';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Jaka była moja ostatnia spoina?', 'What was my last weld?'),
        SkillExample('Pokaż moją ostatnią spoinę', 'Show my latest weld'),
        SkillExample('Ostatnia spoina w dzienniku', 'My last weld'),
        SkillExample('Kiedy spawałem ostatnio?', 'When did I last weld?'),
        SkillExample(
            'Ostatnia spoina w projekcie Alfa', 'Last weld in project Alfa'),
        SkillExample('Podaj moją ostatnią spoinę z projektu Łódź-2',
            'Show my last weld from project Łódź-2'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz dziennik spoin', routesTo: 'tool.open'),
        SkillRejection('dodaj spoinę 12', alsoNot: ['legacy.journal']),
        SkillRejection('jak wykonać ostatnią spoinę'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!_lastQuery.hasMatch(u.folded)) return null;
    final project = _projectSuffix.firstMatch(u.raw)?.group(1)?.trim();
    return SkillMatch(this, .94,
        slots: {
          'project': project ?? '',
          'invalidProject':
              _mentionsProject.hasMatch(u.folded) && project == null,
        },
        utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    if (m.slots['invalidProject'] == true) {
      return const FailedResult(AssistantText(
        'Podaj nazwę po słowach „w projekcie”, aby wybrać właściwe wpisy.',
        'Give the name after "in project" to select the correct entries.',
      ));
    }
    JournalSnapshot snapshot;
    try {
      snapshot = await _load();
    } catch (_) {
      return const FailedResult(AssistantText(
        'Nie udało się odczytać dziennika spoin. Spróbuj ponownie.',
        'Could not read the weld journal. Please try again.',
      ));
    }
    final en = ctx.lang == AppLanguage.en;
    final stamp = snapshot.stamp?.trim().toUpperCase() ?? '';
    final project = (m.slots['project'] as String? ?? '').trim().toLowerCase();
    final asOf = ctx.now();
    final today = isoDate(asOf);
    var missingDate = 0, futureDate = 0;
    final dated = <(WeldEntry, String)>[];
    for (final e in snapshot.entries) {
      if (stamp.isEmpty ||
          e.isDeleted ||
          !e.stamps.any((s) => s.toUpperCase() == stamp) ||
          (project.isNotEmpty &&
              e.projectName.trim().toLowerCase() != project)) {
        continue;
      }
      final date = normalizeWeldDate(e.date, today: asOf);
      if (date == null || date.isEmpty) {
        missingDate++;
      } else if (date.compareTo(today) > 0) {
        futureDate++;
      } else {
        dated.add((e, date));
      }
    }
    dated.sort((a, b) {
      final order = b.$2.compareTo(a.$2);
      return order != 0 ? order : a.$1.id.compareTo(b.$1.id);
    });
    final latest = dated.isEmpty ? '' : dated.first.$2;
    final selected = dated.where((e) => e.$2 == latest).toList();
    return AnswerResult(
      AssistantAnswer(
        text: stamp.isEmpty
            ? const AssistantText(
                'Ustaw stempel spawacza w profilu, aby rozpoznać Twoje wpisy w dzienniku.',
                'Set your welder stamp in your profile to identify your journal entries.')
            : selected.isEmpty
                ? const AssistantText(
                    'Nie znalazłem Twojej spoiny z poprawną datą wykonania do dzisiejszego dnia w tym zakresie.',
                    'No weld of yours with a valid date up to today was found in this selection.')
                : AssistantText(
                    'Najnowsza zapisana data wykonania Twoich spoin: $latest. ${selected.length > 1 ? 'Jest kilka wpisów z tego dnia; bez godzin nie mogę wskazać kolejności.' : 'Według daty wykonania, nie kolejności dodawania wpisów.'}',
                    'Latest recorded date of your welds: $latest. ${selected.length > 1 ? 'Several entries share this date; without times I cannot determine their order.' : 'Based on weld date, not entry creation order.'}'),
        lines: [
          for (final pair in selected)
            AnswerLine(
              AssistantText.same(
                  '${pair.$1.weldNo.isEmpty ? '—' : pair.$1.weldNo} · ${pair.$1.projectName.isEmpty ? '—' : pair.$1.projectName}'),
              '${pair.$2} · ${pair.$1.method.isEmpty ? '—' : pair.$1.method} · ${en ? 'Recorded status' : 'Zapisany status'}: ${pair.$1.status.isEmpty ? '—' : pair.$1.status}',
            ),
          if (missingDate > 0)
            AnswerLine(
                const AssistantText('Bez poprawnej daty — pominięte',
                    'Missing/invalid date — excluded'),
                '$missingDate'),
          if (futureDate > 0)
            AnswerLine(
                const AssistantText(
                    'Data z przyszłości — pominięte', 'Future date — excluded'),
                '$futureDate'),
        ],
        source:
            const AssistantText('Lokalny dziennik spoin', 'Local weld journal'),
      ),
      show: const ShowInModule('weld_journal'),
    );
  }
}
