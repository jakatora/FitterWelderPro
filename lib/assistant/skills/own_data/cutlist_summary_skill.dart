import '../../../database/project_dao.dart';
import '../../../database/segment_dao.dart';
import '../../../models/project.dart';
import '../../../models/segment.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';

final _projectRe = RegExp(
    r'\s+(?:w\s+projekcie|dla\s+projektu|projekt|in\s+(?:the\s+)?project|for\s+project)\s+(.+?)\s*\??$',
    caseSensitive: false);

/// Lista cięć: liczba odcinków i suma długości do cięcia w projekcie
/// (nazwanym albo ostatnio używanym). Tylko odczyt.
class CutListSummarySkill extends AssistantSkill {
  CutListSummarySkill({
    Future<List<Project>> Function()? projects,
    Future<List<Segment>> Function(String projectId)? segments,
  })  : _projects = projects ?? (() => ProjectDao().listAll()),
        _segments = segments ?? ((id) => SegmentDao().listForProject(id));
  final Future<List<Project>> Function() _projects;
  final Future<List<Segment>> Function(String projectId) _segments;

  @override
  String get id => 'cutlist.summary';
  @override
  String get toolId => 'cut_list';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile odcinków do cięcia', 'How many pieces to cut'),
        SkillExample('Lista cięć w projekcie Alfa', 'Cut list in project Alfa'),
        SkillExample('Ile metrów rury do pocięcia', 'How many metres of pipe to cut'),
        SkillExample('Podsumuj listę cięć', 'Summarise the cut list'),
        SkillExample('Ile mam odcinków w liście cięć', 'How many pieces in my cut list'),
        SkillExample('Pokaż listę cięć', 'Show the cut list'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz listę cięć', routesTo: 'tool.open'),
        SkillRejection('do czego służy lista cięć', routesTo: 'tool.explain'),
        SkillRejection('ile waży sześć metrów rury DN100 ścianka 4 mm'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|open|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    final cut = u.hasAny(const ['lista ciec', 'liste ciec', 'liscie ciec', 'cut list']) ||
        (u.hasStem(const ['odcink', 'pieces', 'metr']) &&
            u.hasStem(const ['ciec', 'pocie', 'cut']));
    if (!cut) return null;
    if (u.hasStem(const ['waz', 'waga', 'weigh', 'kg'])) return null;
    final project = _projectRe.firstMatch(u.raw)?.group(1)?.trim();
    return SkillMatch(this, .9,
        slots: {if (project != null && project.isNotEmpty) 'project': project},
        utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final List<Project> all;
    try {
      all = await _projects();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać projektów.', 'Could not read the projects.'));
    }
    if (all.isEmpty) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText('Nie masz jeszcze projektów listy cięć.',
                  'You have no cut list projects yet.')),
          show: ShowInModule('cut_list'));
    }
    String name(Project p) => (p.name?.trim().isNotEmpty ?? false)
        ? p.name!.trim()
        : (p.lineNo ?? p.isoNo ?? p.id);
    final wanted = m.slots['project'] as String?;
    final project = wanted == null
        ? all.first
        : all.where((p) => name(p).toLowerCase() == wanted.toLowerCase()).firstOrNull;
    if (project == null) {
      return FailedResult(AssistantText(
          'Nie ma projektu „$wanted”. Projekty: ${all.take(5).map(name).join(', ')}.',
          'No project "$wanted". Projects: ${all.take(5).map(name).join(', ')}.'));
    }
    final segs = await _segments(project.id);
    final total = segs.fold(0.0, (s, x) => s + x.cutMm);
    final longest = segs.isEmpty
        ? 0.0
        : segs.map((s) => s.cutMm).reduce((a, b) => a > b ? a : b);
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                segs.isEmpty
                    ? 'Projekt „${name(project)}”: brak odcinków do cięcia.'
                    : 'Projekt „${name(project)}”: ${segs.length} odcinków, razem ${f(total / 1000)} m do cięcia, najdłuższy ${f(longest)} mm. Rozkrój na sztangi i szczegóły w module.',
                segs.isEmpty
                    ? 'Project "${name(project)}": no pieces to cut.'
                    : 'Project "${name(project)}": ${segs.length} pieces, ${f(total / 1000)} m in total to cut, longest ${f(longest)} mm. Stock layout and details in the module.')),
        show: ShowInModule(toolId));
  }
}
