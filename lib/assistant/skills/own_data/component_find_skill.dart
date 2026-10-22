import '../../../data/pipe_schedules.dart';
import '../../../database/component_library_dao.dart';
import '../../../models/library_component.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

String? _type(Utterance u) {
  final f = u.folded;
  if (RegExp(r'\bredukcj|\breducer').hasMatch(f)) return 'REDUCER';
  if (RegExp(r'\btrojnik|\btee\b').hasMatch(f)) return 'TEE';
  if (RegExp(r'\bzawor|\bvalve').hasMatch(f)) return 'VALVE';
  if (RegExp(r'\bkolnierz|\bflansz|\bflange').hasMatch(f)) return 'FLANGE';
  if (RegExp(r'\bkolan\w*|\belbow').hasMatch(f)) {
    return RegExp(r'\b45\b').hasMatch(f) ? 'ELB45' : 'ELB90';
  }
  return null;
}

const _names = {
  'ELB90': ('kolano 90°', 'elbow 90°'),
  'ELB45': ('kolano 45°', 'elbow 45°'),
  'TEE': ('trójnik', 'tee'),
  'REDUCER': ('redukcja', 'reducer'),
  'VALVE': ('zawór', 'valve'),
  'FLANGE': ('kołnierz', 'flange'),
};

/// Szukanie we własnej bibliotece komponentów (wymiar do osi / długość),
/// po rodzaju, średnicy (mm albo DN) i materiale SS/CS. Tylko odczyt.
class ComponentFindSkill extends AssistantSkill {
  ComponentFindSkill({Future<List<LibraryComponent>> Function()? load})
      : _load = load ?? (() => ComponentLibraryDao().listAll());
  final Future<List<LibraryComponent>> Function() _load;

  @override
  String get id => 'component.find';
  @override
  String get toolId => 'component_library';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Znajdź w bibliotece kolano 90 DN100',
            'Find in the library a 90 elbow DN100'),
        SkillExample('Jaki mam wymiar do osi kolana 114,3 mm w bibliotece',
            'What centre-to-face for a 114.3 mm elbow in my library'),
        SkillExample('Biblioteka komponentów trójnik DN50 SS',
            'Component library tee DN50 SS'),
        SkillExample('Czy mam w bibliotece redukcję 88,9 mm',
            'Do I have an 88.9 mm reducer in the library'),
        SkillExample('Pokaż zawory w bibliotece komponentów',
            'Show valves in the component library'),
        SkillExample('Moja biblioteka komponentów', 'My component library'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz bibliotekę komponentów', routesTo: 'tool.open'),
        SkillRejection('do czego służy biblioteka komponentów',
            routesTo: 'tool.explain'),
        SkillRejection('wymiar kolana DN80 90 stopni długi promień'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|open|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['bibliotec', 'bibliotek', 'library'])) return null;
    if (u.hasAny(const ['wps'])) return null;
    final out = <String, Object?>{};
    final t = _type(u);
    if (t != null) out['type'] = t;
    var d = lengthNear(u, const ['srednic', 'od', 'diameter']);
    if (d == null) {
      for (var i = 0; i + 1 < u.items.length; i++) {
        if (u.items[i].isNumber && lengthUnitScale(u.items[i + 1].word) == 1) {
          d = u.items[i].value;
          break;
        }
      }
    }
    if (d == null && u.mentionsDn && u.dn() != null) {
      d = kPipeWalls.where((r) => r.dn == u.dn()).firstOrNull?.od;
    }
    if (d != null) out['diameter_mm'] = d;
    if (u.hasAny(const ['ss', 'nierdzewna', 'nierdzewka', 'stainless'])) {
      out['material'] = 'SS';
    }
    if (u.hasAny(const ['cs', 'weglowa', 'czarna', 'carbon'])) {
      out['material'] = 'CS';
    }
    return SkillMatch(this, .9, slots: out, utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final List<LibraryComponent> all;
    try {
      all = await _load();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać biblioteki komponentów.',
          'Could not read the component library.'));
    }
    final type = m.slots['type'] as String?;
    final d = m.slots['diameter_mm'];
    final mat = m.slots['material'] as String?;
    final found = [
      for (final c in all)
        if ((type == null || c.type == type) &&
            (mat == null || c.materialGroup == mat) &&
            (d is! num ||
                (c.diameterMm - d).abs() <= 1.0 ||
                (c.diameterOutMm != null &&
                    (c.diameterOutMm! - d).abs() <= 1.0)))
          c
    ];
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    String line(LibraryComponent c, bool en) {
      final n = _names[c.type];
      final kind = n == null ? c.type : (en ? n.$2 : n.$1);
      final size = c.diameterOutMm == null
          ? '${f(c.diameterMm)} × ${f(c.wallThicknessMm)}'
          : '${f(c.diameterMm)}/${f(c.diameterOutMm!)} × ${f(c.wallThicknessMm)}';
      final dim = c.axisMm != null
          ? (en ? 'to axis ${f(c.axisMm!)} mm' : 'do osi ${f(c.axisMm!)} mm')
          : c.lengthMm != null
              ? (en
                  ? 'length ${f(c.lengthMm!)} mm'
                  : 'długość ${f(c.lengthMm!)} mm')
              : '';
      return '$kind ${c.materialGroup} $size${dim.isEmpty ? '' : ', $dim'}';
    }

    if (all.isEmpty || found.isEmpty) {
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  all.isEmpty
                      ? 'Biblioteka komponentów jest pusta — dodaj wymiary w module.'
                      : 'Nie masz w bibliotece pasującego komponentu.',
                  all.isEmpty
                      ? 'The component library is empty — add dimensions in the module.'
                      : 'No matching component in your library.')),
          show: ShowInModule(toolId));
    }
    final more = found.length > 3 ? ' (+${found.length - 3})' : '';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'W bibliotece (${found.length})$more: ${found.take(3).map((c) => line(c, false)).join('; ')}.',
                'In the library (${found.length})$more: ${found.take(3).map((c) => line(c, true)).join('; ')}.')),
        show: ShowInModule(toolId));
  }
}
