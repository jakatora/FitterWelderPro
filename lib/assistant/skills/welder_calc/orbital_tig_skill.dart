import '../../../services/orbital_tig.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/labelled_numbers.dart';
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';
import '../core/skill_guards.dart';

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  // Rurki orbitalne zawsze w mm — liczba po etykiecie bez jednostki to mm
  // (z jednostką liczy wyżej lengthNear).
  final od = lengthNear(u, const ['od', 'rur', 'srednic', 'tube', 'diameter']) ??
      numberAfterLabel(
          u,
          (w) =>
              w == 'od' ||
              w.startsWith('rur') ||
              w.startsWith('srednic') ||
              w == 'tube' ||
              w == 'diameter',
          skip: const {'zewnetrzna', 'outside'});
  if (od != null) out['od_mm'] = od;
  final wall = lengthNear(u, const ['scian', 'grubos', 'wall', 'thickness']) ??
      numberAfterLabel(
          u,
          (w) =>
              w.startsWith('scian') ||
              w.startsWith('grubos') ||
              w == 'wall' ||
              w == 'thickness',
          skip: const {'scianki'});
  if (wall != null) out['wall_mm'] = wall;
  final volts = numberBeforeUnit(u, (w) => w == 'v' || w.startsWith('wolt') || w.startsWith('volt'));
  if (volts != null) out['volts'] = volts;
  // „25,4 × 1,65 mm” bez etykiet: większa to OD, mniejsza ścianka.
  if (od == null && wall == null) {
    final sizes = <double>[];
    final items = u.items;
    for (var i = 0; i < items.length; i++) {
      if (!items[i].isNumber) continue;
      final next = i + 1 < items.length ? items[i + 1].word : '';
      final pair = i + 2 < items.length &&
          const {'x', 'na', 'by'}.contains(next) &&
          items[i + 2].isNumber;
      if (lengthUnitScale(next) == 1 || pair) sizes.add(items[i].value!);
    }
    if (sizes.length == 2) {
      sizes.sort();
      out['wall_mm'] = sizes.first;
      out['od_mm'] = sizes.last;
    }
  }
  return out;
}

class OrbitalTigSkill extends AssistantSkill {
  @override
  String get id => 'orbital.tig';
  @override
  String get toolId => 'orbital_tig';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Parametry orbitala rura 25,4 mm ścianka 1,65 mm',
            'Orbital parameters tube 25.4 mm wall 1.65 mm'),
        SkillExample('Orbital TIG rura 12,7 mm ścianka 1 mm napięcie 9 V',
            'Orbital TIG tube 12.7 mm wall 1 mm voltage 9 V'),
        SkillExample('Jaki prąd na głowicę orbitalną rura 50,8 mm ścianka 1,5 mm',
            'What current for an orbital head tube 50.8 mm wall 1.5 mm'),
        SkillExample('Spawanie orbitalne 38,1 mm ścianka 2 mm',
            'Orbital welding 38.1 mm wall 2 mm'),
        SkillExample('Orbital rura 76,2 mm ścianka 2,5 mm 11 V',
            'Orbital tube 76.2 mm wall 2.5 mm 11 V'),
        SkillExample('Policz parametry orbitala', 'Calculate orbital parameters'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz orbital TIG', routesTo: 'tool.open'),
        SkillRejection('do czego służy orbital TIG', routesTo: 'tool.explain'),
        SkillRejection('jaki wolfram do aluminium na 150 amper'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kOpenOrAboutStart.hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['orbital'])) return null;
    // „Checklista przed spawaniem orbitalnym” to lista kontrolna, nie prąd.
    if (u.hasStem(const ['checklist', 'list', 'sprawdz', 'kontrol'])) return null;
    final s = _slots(u);
    return SkillMatch(this, s.isNotEmpty ? .93 : .75, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot)) return {slot: s[slot]};
    final n = u.items.where((i) => i.isNumber).toList();
    if (n.length == 1 && (slot == 'od_mm' || slot == 'wall_mm')) {
      return {slot: n.single.value};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final od = m.slots['od_mm'];
    if (od is! num || !od.isFinite || od <= 0 || od > 1000) {
      return ask('od_mm', 'Jaka średnica zewnętrzna rurki w mm?',
          'What is the tube outside diameter in mm?');
    }
    final wall = m.slots['wall_mm'];
    if (wall is! num || !wall.isFinite || wall <= 0 || wall > 25) {
      return ask('wall_mm', 'Jaka grubość ścianki w mm?',
          'What is the wall thickness in mm?');
    }
    final voltsSlot = m.slots['volts'];
    final volts = voltsSlot is num && voltsSlot.isFinite ? voltsSlot : 10;
    if (volts < 6 || volts > 20) {
      return const FailedResult(AssistantText(
          'Napięcie łuku w module: 6–20 V.', 'Arc voltage in the module: 6–20 V.'));
    }
    if (wall > od / 2) {
      return const FailedResult(AssistantText(
          'Ścianka nie może być większa niż połowa OD.',
          'Wall cannot exceed half the OD.'));
    }
    switch (checkOrbitalRange(odMm: od.toDouble(), wallMm: wall.toDouble())) {
      case OrbitalRange.wallTooThick:
        return FailedResult(AssistantText(
            'Ścianka powyżej ${kOrbitalMaxWallMm.toStringAsFixed(0)} mm — poza orbitalem autogenicznym (bez drutu). Potrzebna faza, drut i kilka przejść — parametry wg WPS i programu głowicy.',
            'Wall above ${kOrbitalMaxWallMm.toStringAsFixed(0)} mm — outside autogenous orbital welding. A bevel, wire and several passes are needed — parameters per WPS and head program.'));
      case OrbitalRange.currentTooHigh:
        return const FailedResult(AssistantText(
            'Prąd bazowy ponad 200 A — poza zakresem modelu cienkościennego.',
            'Base current above 200 A — outside the thin-wall model range.'));
      case OrbitalRange.ok:
        break;
    }
    final e = estimateOrbital(
        odMm: od.toDouble(), wallMm: wall.toDouble(), arcVolts: volts.toDouble());
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    final levels = e.levelCurrentA.map((a) => a.round()).join(' / ');
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Orbital TIG bez drutu, rurka ${f(od)} × ${f(wall)} mm: prąd na poziomach 1–4: $levels A, posuw ${f(e.travelSpeedMmMin.roundToDouble())} mm/min, obrót ok. ${f(e.weldTimeSec.roundToDouble())} s, przejść: ${e.passes}. To szacunek startowy — wiąże program głowicy i próbka.',
                'Autogenous orbital TIG, tube ${f(od)} × ${f(wall)} mm: level 1–4 current $levels A, travel ${f(e.travelSpeedMmMin.roundToDouble())} mm/min, revolution approx. ${f(e.weldTimeSec.roundToDouble())} s, passes: ${e.passes}. A starting estimate — the head program and a test piece govern.')),
        show: ShowInModule(toolId, {
          'od_mm': od.toDouble(),
          'wall_mm': wall.toDouble(),
          if (voltsSlot is num) 'volts': volts.toDouble(),
        }));
  }
}
