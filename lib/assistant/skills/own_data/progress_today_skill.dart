import '../../../domain/progress/progress_filter.dart';
import '../../../domain/progress/progress_report.dart' show progressNum;
import '../../../domain/progress/weld_progress.dart';
import '../../../domain/weld_journal/weld_dates.dart';
import '../../../i18n/app_language.dart';
import '../../core/skill.dart';
import 'journal_last_skill.dart';

final _todayQuery = RegExp(
  r'^(?:(?:prosze|powiedz|powiedz mi|please|tell me)\s+)*'
  r'(?:ile (?:cali srednic|di|spoin) (?:zrobilem |wykonalem )?(?:dzis|dzisiaj)|'
  r'(?:pokaz )?(?:moj )?dzisiejszy postep|(?:moj )?postep (?:dzis|dzisiaj)|'
  r'how many (?:diameter inches|dia inches|di|welds) (?:did i (?:do|weld) )?today|'
  r'(?:show )?(?:my )?(?:progress today|today s progress))'
  r'(?:\s+(?:w projekcie|in (?:the )?project) .+)?$',
);
final _rawProject = RegExp(
    r'\s+(?:w\s+projekcie|in\s+(?:the\s+)?project)\s+(.+?)\s*\??$',
    caseSensitive: false);
final _hasProject = RegExp(r'\s+(?:w projekcie|in (?:the )?project) .+$');

class ProgressTodaySkill extends AssistantSkill {
  ProgressTodaySkill({JournalReader? load})
      : _load = load ?? readCurrentJournal;
  final JournalReader _load;

  @override
  String get id => 'progress.today';
  @override
  String get toolId => 'work_progress';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile cali-średnic zrobiłem dzisiaj?',
            'How many diameter inches did I do today?'),
        SkillExample('Ile DI dzisiaj?', 'How many DI today?'),
        SkillExample(
            'Ile spoin zrobiłem dziś?', 'How many welds did I weld today?'),
        SkillExample('Pokaż mój dzisiejszy postęp', 'Show my progress today'),
        SkillExample('Mój postęp dzisiaj', 'My progress today'),
        SkillExample('Ile DI dzisiaj w projekcie Alfa?',
            'How many DI today in project Alfa?'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz postęp robót', routesTo: 'tool.open'),
        SkillRejection('dodaj spoinę 12', alsoNot: ['legacy.journal']),
        SkillRejection('ile DI wczoraj'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!_todayQuery.hasMatch(u.folded)) return null;
    final project = _rawProject.firstMatch(u.raw)?.group(1)?.trim();
    return SkillMatch(this, .94,
        slots: {
          'project': project ?? '',
          'invalidProject': _hasProject.hasMatch(u.folded) && project == null,
        },
        utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    if (m.slots['invalidProject'] == true) {
      return const FailedResult(AssistantText(
          'Podaj nazwę po słowach „w projekcie”, aby wybrać właściwe wpisy.',
          'Give the name after "in project" to select the correct entries.'));
    }
    JournalSnapshot snapshot;
    try {
      snapshot = await _load();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać postępu z dziennika. Spróbuj ponownie.',
          'Could not read progress from the journal. Please try again.'));
    }
    final stamp = snapshot.stamp?.trim().toUpperCase() ?? '';
    if (stamp.isEmpty) {
      return const AnswerResult(AssistantAnswer(
          text: AssistantText(
              'Ustaw stempel spawacza w profilu, aby policzyć Twój postęp.',
              'Set your welder stamp in your profile to calculate your progress.')));
    }
    final now = ctx.now();
    final en = ctx.lang == AppLanguage.en;
    final project = m.slots['project'] as String? ?? '';
    final scope = snapshot.entries
        .where((e) =>
            !e.isDeleted && e.stamps.any((s) => s.toUpperCase() == stamp))
        .toList();
    final filter =
        ProgressFilter(project: project, period: ProgressPeriod.today);
    final today = filter.apply(scope, now);
    final summary = summarizeProgress(today);
    final own = summary.welders
        .where((w) => w.stamp.toUpperCase() == stamp)
        .firstOrNull;
    final undated = filter
        .scopeOf(scope)
        .where((e) => !isIsoWeldDate(e.date.trim()))
        .length;
    final di = own?.diShare ?? 0;
    final approximate = own?.diApprox ?? false;
    final shared = own?.sharedWelds ?? 0;
    return AnswerResult(
        AssistantAnswer(
          text: AssistantText(
              'Twój postęp ($stamp) na ${isoDate(now)}${project.isEmpty ? ', wszystkie projekty' : ', projekt „$project”'}. Liczę wykonane wpisy, także oczekujące na odbiór lub odrzucone.',
              'Your progress ($stamp) on ${isoDate(now)}${project.isEmpty ? ', all projects' : ', project "$project"'}. Completed entries count, including pending or rejected welds.'),
          lines: [
            AnswerLine(const AssistantText('Twój udział DI', 'Your DI share'),
                '${approximate ? '≈ ' : ''}${progressNum(di, en: en)} DI'),
            AnswerLine(
                const AssistantText(
                    'Spoiny z Twoim stemplem', 'Welds bearing your stamp'),
                '${own?.welds ?? 0}'),
            if (shared > 0)
              AnswerLine(const AssistantText('Spoiny wspólne', 'Shared welds'),
                  '$shared · ${en ? 'DI divided equally between welders' : 'DI dzielone po równo między spawaczy'}'),
            if (summary.noOdWelds > 0)
              AnswerLine(
                  const AssistantText('Dzisiejsze spoiny bez OD — bez DI',
                      'Today’s welds without OD — DI unavailable'),
                  '${summary.noOdWelds}'),
            if (approximate)
              AnswerLine(
                  const AssistantText('Przybliżenie DI', 'Approximate DI'),
                  en ? 'OD / 25.4 mm' : 'OD / 25,4 mm'),
            if (undated > 0)
              AnswerLine(
                  const AssistantText(
                      'Niepoprawna lub niepełna data w zakresie — pominięte',
                      'Invalid/incomplete dates in selection — excluded'),
                  '$undated'),
          ],
          source: const AssistantText(
              'Lokalny dziennik spoin · reguły modułu Postęp robót',
              'Local weld journal · Work progress module rules'),
        ),
        show: project.isEmpty || filter.scopeOf(scope).isNotEmpty
            ? ShowInModule(
                'work_progress', {'project': project, 'period': 'today'})
            : null);
  }
}
