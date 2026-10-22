import '../../../domain/weld_symbols/weld_symbol.dart';
import '../../../domain/weld_symbols/weld_symbol_catalog.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_guards.dart';

/// Opis słowny → rodzaj symbolu. Najpierw dłuższe/węższe nazwy (½Y przed Y,
/// ½V przed V, ½U/J przed U).
WeldKind? _kind(Utterance u) {
  final f = u.folded;
  bool has(String re) => RegExp(re).hasMatch(f);
  if (has(r'\btrojkat|\btriangle|\bpachwin|\bfillet')) return WeldKind.fillet;
  if (has(r'\b(?:pol ?y|1 2 y|half ?y)\b')) return WeldKind.singleBevelRootFace;
  if (has(r'\b(?:pol ?v|1 2 v|half ?v|bevel)\b|jeden brzeg')) {
    return WeldKind.singleBevel;
  }
  if (has(r'\b(?:pol ?u|1 2 u)\b|\bna j\b|\bj groove\b|\bsymbol j\b')) {
    return WeldKind.singleJ;
  }
  if (has(r'\bna y\b|\by groove\b|\bsymbol y\b|litera y')) {
    return WeldKind.singleVRootFace;
  }
  if (has(r'\bna u\b|\bu groove\b|\bsymbol u\b|litera u')) return WeldKind.singleU;
  if (has(r'\bna v\b|\bv groove\b|\bsymbol v\b|litera v')) return WeldKind.singleV;
  if (has(r'dwie (?:rownolegle |pionowe )?kreski|\bna i\b|bez ukosowania|square')) {
    return WeldKind.squareButt;
  }
  if (has(r'\botworow|\bplug\b|\bslot\b')) return WeldKind.plug;
  if (has(r'\bpunktow|\bspot\b')) return WeldKind.spot;
  if (has(r'\bliniow\w* (?:spoin|zgrzein)|\bseam\b')) return WeldKind.seam;
  if (has(r'\bnapawan|\bsurfacing')) return WeldKind.surfacing;
  if (has(r'\bbrzezn|\bedge weld')) return WeldKind.edge;
  return null;
}

class WeldSymbolSkill extends AssistantSkill {
  @override
  String get id => 'weld.symbol';
  @override
  String get toolId => 'weld_symbols';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  // Bez „co oznacza / what does” — to dla mózgu cytat do tłumaczenia; takie
  // pytania i tak trafiają przez model do tej umiejętności.
  List<SkillExample> get examples => const [
        SkillExample('Jaka spoina ma symbol trójkąta',
            'Which weld has a triangle symbol'),
        SkillExample('Symbol spoiny na V', 'V groove weld symbol'),
        SkillExample('Chorągiewka na symbolu spoiny', 'Flag on a weld symbol'),
        SkillExample('Symbol spoiny pół V', 'Half V weld symbol'),
        SkillExample('Kółko na linii odniesienia symbolu spoiny',
            'Circle on the weld symbol reference line'),
        SkillExample('Jaki symbol ma spoina otworowa',
            'Which symbol does a plug weld have'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz symbole spawalnicze', routesTo: 'tool.open'),
        SkillRejection('do czego służą symbole spawalnicze',
            routesTo: 'tool.explain'),
        SkillRejection('nośność spoiny pachwinowej a4 długość 100 mm 2 spoiny S355 blacha 10 mm',
            routesTo: 'fillet.strength'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kOpenOrAboutStart.hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['symbol', 'oznacz', 'znak', 'rysunk', 'drawing', 'mean'])) {
      return null;
    }
    final flag = u.hasStem(const ['choragiew', 'flag', 'montazow']);
    final circle = u.hasStem(const ['kolk', 'okrag', 'circle', 'dookol', 'obwod']);
    final kind = _kind(u);
    if (kind == null && !flag && !circle) return null;
    return SkillMatch(this, .9,
        slots: {
          if (kind != null) 'kind': kind.name,
          if (flag) 'flag': true,
          if (circle) 'circle': true,
        },
        utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    if (m.slots['flag'] == true) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Chorągiewka na załamaniu linii strzałki = spoina montażowa (wykonywana na budowie, nie w warsztacie) — EN ISO 2553 i AWS A2.4 tak samo.',
                  'A flag at the arrow line break = field weld (made on site, not in the shop) — same in EN ISO 2553 and AWS A2.4.')),
          show: ShowInModule('weld_symbols'));
    }
    if (m.slots['circle'] == true) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Kółko na załamaniu linii strzałki = spoina dookoła (obwodowa, np. rura do blachy) — EN ISO 2553 i AWS A2.4.',
                  'A circle at the arrow line break = weld all around (e.g. pipe to plate) — EN ISO 2553 and AWS A2.4.')),
          show: ShowInModule('weld_symbols'));
    }
    final kind =
        WeldKind.values.where((k) => k.name == m.slots['kind']).firstOrNull;
    final info = basicSymbolCatalog.where((s) => s.kind == kind).firstOrNull;
    if (info == null) {
      return const FailedResult(AssistantText(
          'Tego symbolu nie ma w ściądze modułu.',
          'This symbol is not in the module cheat sheet.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText('${info.bodyPl} ${info.awsPl} (EN ISO 2553).',
                '${info.bodyEn} ${info.awsEn} (EN ISO 2553).')),
        show: ShowInModule(toolId));
  }
}
