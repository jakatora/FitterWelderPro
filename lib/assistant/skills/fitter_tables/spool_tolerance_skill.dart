import '../../../domain/spool_check/spool_check_sources.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/labelled_numbers.dart';
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  if (u.mentionsDn) out['dn'] = u.dn() ?? double.nan;
  final drawing = lengthNear(u, const ['rysun', 'drawing', 'projekt', 'nominal']) ??
      numberAfterLabel(u, (w) => w.startsWith('rysun') || w == 'drawing');
  if (drawing != null) out['drawing_mm'] = drawing;
  final measured = lengthNear(u, const ['zmierz', 'pomiar', 'measured', 'jest']) ??
      numberAfterLabel(
          u, (w) => w.startsWith('zmierz') || w.startsWith('pomiar') || w == 'measured');
  if (measured != null) out['measured_mm'] = measured;
  final diameter = lengthNear(u, const ['srednic', 'diameter', 'od']);
  if (diameter != null) out['diameter_mm'] = diameter;
  if (u.hasStem(const ['obrot', 'skret', 'rotation', 'dwuotwor'])) {
    out['item'] = 'rotation';
  } else if (u.hasStem(const ['nachyl', 'czola', 'czolo', 'tilt', 'alignment'])) {
    out['item'] = 'tilt';
  }
  return out;
}

/// Tolerancje prefabrykacji wg PFI ES-3 — te same liczby co w module
/// „Tolerancje spoola”. Protokoły z pozycjami zostają na ekranie.
class SpoolToleranceSkill extends AssistantSkill {
  @override
  String get id => 'spool.tolerance';
  @override
  String get toolId => 'spool_check';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Jaka tolerancja wymiaru spoola DN200',
            'What is the spool dimension tolerance DN200'),
        SkillExample('Tolerancja spoola DN100 rysunek 1500 mm zmierzone 1503 mm',
            'Spool tolerance DN100 drawing 1500 mm measured 1503 mm'),
        SkillExample('Tolerancja obrotu otworów kołnierza na spoolu',
            'Spool flange bolt hole rotation tolerance'),
        SkillExample('Tolerancja nachylenia czoła kołnierza spoola średnica 219,1 mm',
            'Spool flange face tilt tolerance diameter 219.1 mm'),
        SkillExample('Ile wolno odchyłki na spoolu DN400',
            'How much deviation is allowed on a DN400 spool'),
        SkillExample('Sprawdź tolerancję spoola', 'Check the spool tolerance'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz tolerancje spoola', routesTo: 'tool.open'),
        SkillRejection('do czego służą tolerancje spoola',
            routesTo: 'tool.explain'),
        SkillRejection('ile podtopienia dopuszcza ISO 5817 na poziomie C'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['spool', 'prefabryk'])) return null;
    final s = _slots(u);
    // „tolerancja wymiaru spoola DN200” nie jest długością wstawki.
    final tolerance = u.hasStem(const ['toleranc', 'odchyl', 'deviation']);
    return SkillMatch(this, tolerance ? .97 : (s.isNotEmpty ? .92 : .74),
        slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    const note = (
      'PFI ES-3; wiążą tolerancje z rysunku / specyfikacji, jeśli są inne. Protokół z pozycjami zrobisz w module.',
      'PFI ES-3; drawing / specification tolerances govern where different. Build the item protocol in the module.'
    );
    final item = m.slots['item'];
    if (item == 'rotation') {
      final t = kEs3RotationMm;
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Obrót otworów kołnierza: ±${f(t)} mm (1/16″) mierzone na łuku podziałki śrub. ${note.$1}',
                  'Flange bolt hole rotation: ±${f(t)} mm (1/16″) measured on the bolt circle arc. ${note.$2}')),
          show: const ShowInModule('spool_check'));
    }
    if (item == 'tilt') {
      final d = m.slots['diameter_mm'];
      if (d is! num || !d.isFinite || d <= 0) {
        return AskResult(
            'diameter_mm',
            const AssistantText('Na jakiej średnicy mierzysz nachylenie czoła (mm)?',
                'On what diameter do you measure the face tilt (mm)?'),
            partial: m);
      }
      final limit = es3FaceAlignmentLimitMm(d.toDouble());
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Nachylenie czoła kołnierza na średnicy ${f(d)} mm: najwyżej ${f(limit)} mm (3/64″ na stopę, min. 1/32″). ${note.$1}',
                  'Flange face tilt on a ${f(d)} mm diameter: at most ${f(limit)} mm (3/64″ per foot, min 1/32″). ${note.$2}')),
          show: const ShowInModule('spool_check'));
    }
    final dn = m.slots['dn'];
    if (dn is! num || !dn.isFinite) {
      return AskResult(
          'dn',
          const AssistantText('Jakie DN spoola?', 'Which spool DN?'),
          partial: m);
    }
    final band = es3LinearBandFor(dn.toInt());
    if (band == null) {
      return const FailedResult(AssistantText(
          'ES-3 nie podaje tolerancji liniowej powyżej DN900 — weź ją z projektu.',
          'ES-3 gives no linear tolerance above DN900 — take it from the project.'));
    }
    final tol = band.mm;
    final drawing = m.slots['drawing_mm'], measured = m.slots['measured_mm'];
    var pl = 'Wymiary liniowe spoola DN${dn.toInt()} (${band.sizeLabel(en: false)}): ±${f(tol)} mm.';
    var en = 'Linear spool dimensions DN${dn.toInt()} (${band.sizeLabel(en: true)}): ±${f(tol)} mm.';
    if (drawing is num && measured is num && drawing.isFinite && measured.isFinite) {
      final dev = measured - drawing;
      final ok = dev.abs() <= tol + 1e-9;
      pl += ' Odchyłka ${dev >= 0 ? '+' : ''}${f(dev)} mm — ${ok ? 'w tolerancji' : 'POZA tolerancją'}.';
      en += ' Deviation ${dev >= 0 ? '+' : ''}${f(dev)} mm — ${ok ? 'within tolerance' : 'OUT of tolerance'}.';
    }
    return AnswerResult(
        AssistantAnswer(text: AssistantText('$pl ${note.$1}', '$en ${note.$2}')),
        show: const ShowInModule('spool_check'));
  }
}
