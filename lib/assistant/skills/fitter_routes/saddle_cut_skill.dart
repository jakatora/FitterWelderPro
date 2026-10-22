import '../../../data/pipe_schedules.dart';
import '../../../services/saddle_geometry.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

const _headerLabels = ['glown', 'header', 'magistral', 'kolektor', 'run'];
const _branchLabels = ['odgalez', 'odejsc', 'odnog', 'branch'];

/// OD z DN (tabela rur) — `null`, gdy DN nie ma w tabeli.
double? _odOfDn(int dn) => kPipeWalls.where((r) => r.dn == dn).firstOrNull?.od;

/// Średnice z wypowiedzi: jawne etykiety (rura główna / odgałęzienie) albo
/// dwie średnice bez etykiet — mniejsza to zawsze odgałęzienie (większe od
/// rury głównej nie istnieje). Sprzeczne wartości → NaN, żeby dopytać.
Map<String, Object?> saddleDiameterSlots(Utterance u) {
  final out = <String, Object?>{};
  final header = lengthNear(u, _headerLabels);
  final branch = lengthNear(u, _branchLabels);
  if (header != null) out['header_od_mm'] = header;
  if (branch != null) out['branch_od_mm'] = branch;
  if (header != null && branch != null) return out;

  final sizes = <double>[];
  if (u.mentionsDn) {
    final markers = RegExp(r'\b(?:dn|d n|de en)\s*\d').allMatches(u.folded);
    final values = u.dnValues;
    for (final dn in values) {
      sizes.add(_odOfDn(dn) ?? double.nan);
    }
    // „DN100 na DN100” — dwa znaczniki, jedna wartość: trójnik równoprzelotowy.
    if (values.length == 1 && markers.length == 2) sizes.add(sizes.single);
  }
  for (var i = 0; i + 1 < u.items.length; i++) {
    final scale = lengthUnitScale(u.items[i + 1].word);
    if (u.items[i].isNumber && scale != null) {
      sizes.add(signedQuantity(u, i) * scale);
    }
  }
  // „60 na 114” bez jednostek: milimetry OD, chyba że obie liczby wyglądają
  // jak DN z tabeli („50 na 100”) — wtedy nie zgadujemy (pytanie o średnicę).
  if (sizes.isEmpty && header == null && branch == null) {
    final items = u.items;
    for (var i = 0; i + 2 < items.length; i++) {
      if (items[i].isNumber &&
          const {'na', 'x', 'i', 'and', 'on', 'into', 'w'}
              .contains(items[i + 1].word) &&
          items[i + 2].isNumber) {
        final a = items[i].value!, b = items[i + 2].value!;
        bool dnLike(double v) =>
            v == v.roundToDouble() && kPipeWalls.any((r) => r.dn == v);
        if (!(dnLike(a) && dnLike(b))) sizes.addAll([a, b]);
        break;
      }
    }
  }
  if (sizes.length > 2) {
    out['header_od_mm'] = double.nan;
    return out;
  }
  if (sizes.length == 2 && header == null && branch == null) {
    sizes.sort();
    out['branch_od_mm'] = sizes.first;
    out['header_od_mm'] = sizes.last;
  } else if (sizes.length == 1 && header == null && branch == null) {
    out['header_od_mm'] = sizes.single;
  } else if (sizes.isNotEmpty && (header == null) != (branch == null)) {
    // Jedna etykieta + druga średnica bez etykiety.
    final known = header ?? branch!;
    final other = sizes.where((s) => s != known).toList();
    if (other.length == 1) {
      out[header == null ? 'header_od_mm' : 'branch_od_mm'] = other.single;
    }
  }
  return out;
}

class SaddleCutSkill extends AssistantSkill {
  @override
  String get id => 'saddle.cut';
  @override
  String get toolId => 'saddle_cut';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Siodło rura główna 168,3 mm odgałęzienie 114,3 mm',
            'Saddle header 168.3 mm branch 114.3 mm'),
        SkillExample('Wycięcie siodłowe DN50 na DN100',
            'Saddle cut DN50 on DN100'),
        SkillExample('Siodełko 60,3 mm na 88,9 mm',
            'Fish mouth 60.3 mm on 88.9 mm'),
        SkillExample('Siodło odgałęzienie 48,3 mm rura główna 60,3 mm',
            'Saddle branch 48.3 mm header 60.3 mm'),
        SkillExample('Wcinka DN80 w DN150', 'Saddle cut DN80 into DN150'),
        SkillExample('Oblicz siodło', 'Calculate a saddle'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz siodło', routesTo: 'tool.open'),
        SkillRejection('do czego służy siodło 90', routesTo: 'tool.explain'),
        SkillRejection('wydrukuj szablon siodła'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    // Dowolny kąt i wydruk należą do szablonu siodła.
    final angle = angleValue(u);
    if (u.hasStem(const ['szablon', 'template', 'druk', 'print', 'pdf']) ||
        (angle != null && angle != 90)) {
      return null;
    }
    if (!u.hasStem(const ['siodl', 'siodel', 'wcink', 'saddle']) &&
        !u.hasAny(const ['fish mouth', 'fishmouth'])) {
      return null;
    }
    final s = saddleDiameterSlots(u);
    return SkillMatch(
        this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'policz', 'calculate'])
            ? .92
            : .65,
        slots: s,
        utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      saddleDiameterSlots(u);

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = saddleDiameterSlots(u);
    if (s.containsKey(slot)) return {slot: s[slot]};
    // Odpowiedź na pytanie o jedną średnicę: „114,3 mm” albo „DN100”.
    final single = s['header_od_mm'];
    if (single is num && s.length == 1) return {slot: single};
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final header = m.slots['header_od_mm'];
    if (header is! num || !header.isFinite || header <= 0 || header > 2000) {
      return ask(
          'header_od_mm',
          'Jaka jest średnica zewnętrzna rury głównej? Podaj mm albo DN, np. 168,3 mm.',
          'What is the header outside diameter? Give mm or DN, e.g. 168.3 mm.');
    }
    final branch = m.slots['branch_od_mm'];
    if (branch is! num || !branch.isFinite || branch <= 0) {
      return ask(
          'branch_od_mm',
          'Jaka jest średnica zewnętrzna odgałęzienia? Podaj mm albo DN, np. 114,3 mm.',
          'What is the branch outside diameter? Give mm or DN, e.g. 114.3 mm.');
    }
    if (branch > header) {
      return const FailedResult(AssistantText(
          'Odgałęzienie nie może być większe od rury głównej. Podaj średnice jeszcze raz.',
          'The branch cannot be larger than the header. Please give the diameters again.'));
    }
    final geometry = SaddleGeometry(
        headerOdMm: header.toDouble(),
        branchOdMm: branch.toDouble(),
        angleDeg: 90);
    final depth = geometry.maxDepthMm;
    if (!depth.isFinite) {
      return const FailedResult(AssistantText(
          'Nie można obliczyć profilu. Sprawdź średnice.',
          'Cannot calculate the profile. Check the diameters.'));
    }
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Siodło 90°: rura główna ${f(header)} mm, odgałęzienie ${f(branch)} mm. Największa głębokość wycięcia ${f(depth)} mm — w punktach 0° i 180° (płaszczyzna obu osi); na 90° i 270° głębokość 0. Profil co 15° jest w module. Bez grubości ścianki, ukosowania i szczeliny — sprawdź na materiale przed cięciem.',
                '90° saddle: header ${f(header)} mm, branch ${f(branch)} mm. Maximum cut depth ${f(depth)} mm — at 0° and 180° (plane of both axes); 0 at 90° and 270°. The 15° profile is in the module. Wall thickness, bevel and gap are not included — check on the material before cutting.')),
        show: ShowInModule(toolId, {
          'header_od_mm': header.toDouble(),
          'branch_od_mm': branch.toDouble()
        }));
  }
}
