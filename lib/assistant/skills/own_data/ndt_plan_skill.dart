import '../../../database/weld_journal_dao.dart';
import '../../../domain/ndt/ndt_plan.dart';
import '../../../domain/weld_journal/weld_defaults.dart' show loadLastWeldProject;
import '../../../domain/weld_journal/weld_entry.dart';
import '../../../domain/weld_journal/weld_ndt.dart';
import '../../../features/ndt_plan/ndt_plan_store.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;

final _projectRe = RegExp(
    r'\s+(?:w\s+projekcie|dla\s+projektu|projekt|in\s+(?:the\s+)?project|for\s+project)\s+(.+?)\s*\??$',
    caseSensitive: false);

/// „Ile spoin do badań” — plan NDT z dziennika i reguł zapisanych dla
/// projektu w module (ten sam rachunek co ekran). Tylko odczyt.
class NdtPlanSkill extends AssistantSkill {
  NdtPlanSkill({
    Future<List<WeldEntry>> Function()? loadWelds,
    Future<String> Function()? loadLastProject,
    NdtPlanStore store = const NdtPlanStore(),
  })  : _loadWelds = loadWelds ?? (() => WeldJournalDao().listAll()),
        _loadLastProject = loadLastProject ?? loadLastWeldProject,
        _store = store;
  final Future<List<WeldEntry>> Function() _loadWelds;
  final Future<String> Function() _loadLastProject;
  final NdtPlanStore _store;

  @override
  String get id => 'ndt.plan';
  @override
  String get toolId => 'ndt_plan';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile spoin trzeba zlecić do badań', 'How many welds to order for NDT'),
        SkillExample('Plan badań NDT w projekcie Alfa', 'NDT plan in project Alfa'),
        SkillExample('Ile spoin zlecić do RT', 'How many welds to order for RT'),
        SkillExample('Co zlecić do prześwietlenia', 'Which welds to order for radiography'),
        SkillExample('Czy linia jest gotowa do próby po badaniach',
            'Is the line ready for testing after NDT'),
        SkillExample('Pokaż plan badań', 'Show the NDT plan'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz plan badań NDT', routesTo: 'tool.open'),
        SkillRejection('do czego służy plan badań NDT', routesTo: 'tool.explain'),
        SkillRejection('ile podtopienia dopuszcza ISO 5817 na poziomie C'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    final ndt = u.hasStem(const ['badan', 'ndt', 'przeswietl', 'radiogra']) ||
        u.hasAny(const ['rt', 'ut', 'pt', 'mt', 'vt']);
    if (!ndt) return null;
    if (!u.hasStem(const ['ile', 'zlec', 'plan', 'gotow', 'order', 'ready', 'pokaz', 'show']) &&
        !u.hasAny(const ['how many', 'what to'])) {
      return null;
    }
    // Normy dopuszczalności (ISO 5817…) to inne pytanie niż „ile zlecić”.
    if (u.hasStem(const ['5817', 'podtopien', 'dopuszcz', 'poziom'])) return null;
    final project = _projectRe.firstMatch(u.raw)?.group(1)?.trim();
    return SkillMatch(this, .95,
        slots: {if (project != null && project.isNotEmpty) 'project': project},
        utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final List<WeldEntry> all;
    try {
      all = (await _loadWelds()).where((e) => !e.isDeleted).toList();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać dziennika spoin.',
          'Could not read the weld journal.'));
    }
    final projects = ndtProjects(all);
    if (projects.isEmpty) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'W dzienniku nie ma spoin z projektem — plan badań liczy się per projekt.',
                  'The journal has no welds with a project — the NDT plan is per project.')),
          show: ShowInModule('ndt_plan'));
    }
    String? pick(String? wanted) => wanted == null
        ? null
        : projects
            .where((p) => p.toLowerCase() == wanted.trim().toLowerCase())
            .firstOrNull;
    final asked = m.slots['project'] as String?;
    var project = pick(asked);
    if (asked != null && project == null) {
      return FailedResult(AssistantText(
          'Nie ma projektu „$asked” w dzienniku. Projekty: ${projects.take(5).join(', ')}.',
          'No project "$asked" in the journal. Projects: ${projects.take(5).join(', ')}.'));
    }
    if (project == null) {
      String last = '';
      try {
        last = await _loadLastProject();
      } catch (_) {}
      project = pick(last) ?? projects.first;
    }
    final rules = await _store.load(project);
    if (!rules.saved || rules.set.rules.isEmpty) {
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Projekt „$project” nie ma jeszcze reguł badań — wybierz w module zestaw (np. B31.3 RT 5 % + VT 100 %).',
                  'Project "$project" has no NDT rules yet — pick a set in the module (e.g. B31.3 RT 5 % + VT 100 %).')),
          show: ShowInModule(toolId, {'project': project}));
    }
    final plan = computeNdtPlan(all,
        rules: rules.set.rules, rulesIntact: rules.intact, project: project);
    String counts(Map<NdtMethod, List<NdtOrderItem>> byMethod) => [
          for (final e in byMethod.entries) '${e.key.code} ${e.value.length}'
        ].join(', ');
    final toOrder = counts(plan.toOrder);
    final ordered = counts(plan.ordered);
    final pl = StringBuffer(
        'Projekt „$project”: ${plan.welds} spoin, gotowe linie ${plan.readyLines}/${plan.lines.length}.');
    final en = StringBuffer(
        'Project "$project": ${plan.welds} welds, ready lines ${plan.readyLines}/${plan.lines.length}.');
    pl.write(toOrder.isEmpty ? ' Nic nowego do zlecenia.' : ' Do zlecenia: $toOrder.');
    en.write(toOrder.isEmpty ? ' Nothing new to order.' : ' To order: $toOrder.');
    if (ordered.isNotEmpty) {
      pl.write(' Zlecone bez wyniku: $ordered.');
      en.write(' Ordered without result: $ordered.');
    }
    if (plan.shortfalls.isNotEmpty) {
      pl.write(' Brakuje spoin do wybrania w ${plan.shortfalls.length} grupach.');
      en.write(' ${plan.shortfalls.length} groups lack welds to select.');
    }
    if (!rules.intact) {
      pl.write(' Zapis reguł jest uszkodzony — sprawdź w module.');
      en.write(' The saved rules are damaged — check in the module.');
    }
    pl.write(' Wybór spoin i zlecenie zrobisz w module.');
    en.write(' Pick welds and print the order in the module.');
    return AnswerResult(
        AssistantAnswer(text: AssistantText(pl.toString(), en.toString())),
        show: ShowInModule(toolId, {'project': project}));
  }
}
