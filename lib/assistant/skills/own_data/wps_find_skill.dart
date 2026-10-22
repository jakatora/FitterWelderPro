import '../../../database/wps_dao.dart';
import '../../../domain/wps/wps_record.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';
import '../core/skill_guards.dart';

final _processRe = RegExp(r'\b(111|114|121|131|135|136|138|141|142|311|15)\b');
final _wpsNoRe = RegExp(r'\bwps\s*(?:nr|numer|no)?\s*([a-z0-9][a-z0-9.\-/]*)');
final _groupRe = RegExp(r'\b(?:grup\w*|group|gr)\s*(\d{1,2}(?:[.,]\d{1,2})?)\b');

Map<String, Object?> _slots(Utterance u) {
  final terms = <String>[];
  final f = u.folded;
  final no = _wpsNoRe.firstMatch(f)?.group(1);
  if (no != null && !_processRe.hasMatch(' $no ') && no != 'na' && no != 'do') {
    terms.add(no);
  }
  for (final m in _processRe.allMatches(f)) {
    if (!terms.contains(m[1])) terms.add(m[1]!);
  }
  if (RegExp(r'\btig\w*').hasMatch(f) && !terms.contains('141')) terms.add('141');
  if (RegExp(r'\bmigomag\w*|\bmag\b').hasMatch(f) && !terms.contains('135')) {
    terms.add('135');
  }
  if (RegExp(r'\belektrod\w*|\bmma\b').hasMatch(f) && !terms.contains('111')) {
    terms.add('111');
  }
  final group = _groupRe.firstMatch(f)?.group(1);
  if (group != null) terms.add(group.replaceAll(',', '.'));
  final out = <String, Object?>{'query': terms.join(' ')};
  final t = lengthNear(u, const ['grubos', 'scian', 'blach', 'thickness', 'na']);
  if (t != null) out['thickness_mm'] = t;
  return out;
}

bool _matches(WpsRecord w, List<String> terms) {
  final hay = [
    w.wpsNo,
    w.revision,
    w.pqrRef,
    w.processes,
    w.materialGroup,
    w.filler,
    w.notes,
  ].join(' ').toLowerCase();
  return terms.every(hay.contains);
}

/// Szukanie we WŁASNEJ bibliotece WPS (konto) — te same zasady co pole
/// szukania w module; grubość zawęża do zakresu WPS.
class WpsFindSkill extends AssistantSkill {
  WpsFindSkill({Future<List<WpsRecord>> Function()? load})
      : _load = load ?? (() => WpsDao().listAll());
  final Future<List<WpsRecord>> Function() _load;

  @override
  String get id => 'wps.find';
  @override
  String get toolId => 'wps_library';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Znajdź WPS na 141', 'Find a WPS for 141'),
        SkillExample('Pokaż WPS 001', 'Show WPS 001'),
        SkillExample('Jaka WPS na TIG grubość 8 mm', 'Which WPS for TIG thickness 8 mm'),
        SkillExample('Znajdź WPS 135 grupa 1.1', 'Find WPS 135 group 1.1'),
        SkillExample('Mam WPS na elektrodę 12 mm', 'Do I have a WPS for stick 12 mm'),
        SkillExample('Pokaż moje WPS', 'Show my WPS'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz bibliotekę WPS', routesTo: 'tool.open'),
        SkillRejection('do czego służy biblioteka WPS', routesTo: 'tool.explain'),
        SkillRejection('jakie spoiwo dać do stali 316L'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kOpenOrAboutStartNoShow.hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasAny(const ['wps']) && !u.hasStem(const ['wps'])) return null;
    // Zapis (także spoiny z numerem WPS) i słownik/tłumaczenie to inne
    // moduły — „WPS” jest tam tylko słowem albo polem wpisu.
    if (u.hasStem(const [
      'dodaj', 'zapisz', 'dopisz', 'wpisz', 'nowa', 'nowy', 'add', 'new', 'log',
      'slownik', 'slowniku', 'przetlumacz', 'tlumacz', 'dictionar', 'glossar',
      'translat'
    ])) {
      return null;
    }
    if (RegExp(r'po (?:niemiecku|angielsku|norwesku|holendersku|polsku)')
        .hasMatch(u.folded)) {
      return null;
    }
    return SkillMatch(this, .9, slots: _slots(u), utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final List<WpsRecord> all;
    try {
      all = await _load();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać biblioteki WPS.',
          'Could not read the WPS library.'));
    }
    final query = (m.slots['query'] as String? ?? '').trim();
    final terms = [
      for (final t in query.toLowerCase().split(RegExp(r'\s+')))
        if (t.isNotEmpty) t
    ];
    final t = m.slots['thickness_mm'];
    final found = [
      for (final w in all)
        if (_matches(w, terms) &&
            (t is! num ||
                ((w.thicknessMinMm == null || w.thicknessMinMm! <= t + 1e-9) &&
                    (w.thicknessMaxMm == null ||
                        w.thicknessMaxMm! >= t - 1e-9))))
          w
    ];
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    String line(WpsRecord w) {
      final range = w.thicknessMinMm != null || w.thicknessMaxMm != null
          ? ' ${w.thicknessMinMm == null ? '…' : f(w.thicknessMinMm!)}–${w.thicknessMaxMm == null ? '…' : f(w.thicknessMaxMm!)} mm'
          : '';
      final rev = w.revision.isEmpty ? '' : ' rev. ${w.revision}';
      final group = w.materialGroup.isEmpty ? '' : ', gr. ${w.materialGroup}';
      return 'WPS ${w.wpsNo}$rev — ${w.processes}$group$range';
    }

    final show = ShowInModule(toolId, {'query': query});
    final what = [
      if (query.isNotEmpty) query,
      if (t is num) '${f(t)} mm',
    ].join(', ');
    if (all.isEmpty) {
      return AnswerResult(
          const AssistantAnswer(
              text: AssistantText(
                  'Twoja biblioteka WPS jest pusta — dodaj WPS w module.',
                  'Your WPS library is empty — add a WPS in the module.')),
          show: show);
    }
    if (found.isEmpty) {
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Nie masz WPS pasującej do: $what.',
                  'You have no WPS matching: $what.')),
          show: show);
    }
    final shown = found.take(3).map(line).join('; ');
    final more = found.length > 3 ? ' (+${found.length - 3})' : '';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Pasujące WPS (${found.length})$more: $shown. Zakres i parametry sprawdź w karcie WPS.',
                'Matching WPS (${found.length})$more: $shown. Check range and parameters on the WPS card.')),
        show: show);
  }
}
