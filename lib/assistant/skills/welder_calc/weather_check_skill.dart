import '../../../domain/welding/weather_conditions.dart';
import '../../../features/weather_check/weather_check_store.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/labelled_numbers.dart';
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

bool _degree(String w) =>
    w == 'c' || w.startsWith('stopn') || w.startsWith('degree') || w.startsWith('cels');

/// Temperatura powietrza: po etykiecie albo pierwsza wartość w °C, która
/// nie dotyczy powierzchni/WPS. „5 stopni mrozu” → −5.
double? _ambient(Utterance u) {
  final labelled = numberAfterLabel(
      u,
      (w) =>
          w.startsWith('temperatur') ||
          w.startsWith('powietrz') ||
          w == 'temp' ||
          w == 'air' ||
          w == 'dworze' ||
          w == 'outside',
      skip: const {'powietrza', 'air', 'na', 'dworze'});
  var v = labelled;
  if (v == null) {
    final found = <double>{};
    final items = u.items;
    for (var i = 0; i + 1 < items.length; i++) {
      if (!items[i].isNumber || !_degree(items[i + 1].word)) continue;
      final before = i > 0 ? items[i - 1].word : '';
      final ctx = i > 1 ? items[i - 2].word : '';
      if (const ['powierzchni', 'rury', 'materialu', 'zlacza', 'surface']
              .any((s) => before.startsWith(s) || ctx.startsWith(s)) ||
          before.startsWith('podgrzew') ||
          ctx.startsWith('podgrzew') ||
          before == 'wps') {
        continue;
      }
      found.add(signedQuantity(u, i));
    }
    v = found.length > 1 ? double.nan : found.singleOrNull;
  }
  if (v != null && v > 0 && u.hasStem(const ['mroz', 'frost'])) v = -v;
  return v;
}

double? _wind(Utterance u) {
  if (u.hasAny(const ['bez wiatru', 'brak wiatru', 'no wind', 'cisza', 'calm'])) {
    return 0;
  }
  final items = u.items;
  final found = <double>{};
  for (var i = 0; i + 1 < items.length; i++) {
    if (!items[i].isNumber) continue;
    final a = items[i + 1].word;
    final b = i + 2 < items.length ? items[i + 2].word : '';
    if (a == 'ms' || (a == 'm' && (b == 's' || b == 'na')) ||
        a.startsWith('metr') && b.startsWith('na')) {
      found.add(items[i].value!);
    } else if (a == 'kmh' || (a == 'km' && (b == 'h' || b == 'na'))) {
      found.add(items[i].value! / 3.6);
    }
  }
  if (found.isEmpty) {
    final after = numberAfterLabel(u, (w) => w.startsWith('wiat') || w == 'wind',
        skip: const {'wieje', 'ma'});
    if (after != null) found.add(after);
  }
  return found.length > 1 ? double.nan : found.singleOrNull;
}

double? _humidity(Utterance u) {
  final pct = percentValue(u);
  if (pct != null) return pct;
  return numberAfterLabel(
      u, (w) => w.startsWith('wilgotn') || w == 'humidity' || w == 'rh');
}

WeatherProcess? _process(Utterance u) {
  final f = u.folded;
  final found = <WeatherProcess>{
    if (RegExp(r'\b111\b|\bmma\b|\belektrod').hasMatch(f)) WeatherProcess.mma111,
    if (RegExp(r'\b13[58]\b|\bmag\b|\bmigomag').hasMatch(f))
      WeatherProcess.mag135,
    if (RegExp(r'\b136\b|\bfcaw g\b').hasMatch(f)) WeatherProcess.fcawG136,
    if (RegExp(r'\b114\b|\bsamoslon|\bfcaw s\b|\bself shielded').hasMatch(f))
      WeatherProcess.fcawS114,
    if (RegExp(r'\b141\b|\btig\w*').hasMatch(f)) WeatherProcess.tig141,
    if (RegExp(r'\b131\b|\bmig\b').hasMatch(f)) WeatherProcess.mig131,
    if (RegExp(r'\b121\b|\bsaw\b|\bpod topnikiem\b|\bkryt\w*').hasMatch(f))
      WeatherProcess.saw121,
    if (RegExp(r'\b311\b|\bgazow\w*|\bacetylen').hasMatch(f))
      WeatherProcess.gas311,
  };
  return found.length == 1 ? found.single : null;
}

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final ambient = _ambient(u);
  if (ambient != null) out['ambient_c'] = ambient;
  final rh = _humidity(u);
  if (rh != null) out['rh_pct'] = rh;
  final wind = _wind(u);
  if (wind != null) out['wind_ms'] = wind;
  final process = _process(u);
  if (process != null) out['process'] = process.name;
  if (u.hasStem(const ['nierdzew', 'stainless']) ||
      RegExp(r'\b31[6]l?\b|\b304l?\b').hasMatch(u.folded)) {
    out['material'] = WeatherMaterial.stainless.name;
  } else if (u.hasStem(const ['alumin'])) {
    out['material'] = WeatherMaterial.aluminium.name;
  } else if (u.hasStem(const ['weglow', 'czarn', 'carbon'])) {
    out['material'] = WeatherMaterial.carbonSteel.name;
  }
  if (u.hasStem(const ['mzawk', 'drizzl'])) {
    out['precipitation'] = Precipitation.drizzle.name;
  } else if (u.hasStem(const ['deszcz', 'pada', 'rain'])) {
    out['precipitation'] = Precipitation.rain.name;
  } else if (u.hasStem(const ['snieg', 'sniez', 'snow'])) {
    out['precipitation'] = Precipitation.snow.name;
  }
  if (u.hasStem(const ['namiot', 'obudow', 'tent', 'enclosure'])) {
    out['shelter'] = WeatherShelter.enclosure.name;
  } else if (u.hasStem(const ['parawan', 'windbreak', 'ekran'])) {
    out['shelter'] = WeatherShelter.windbreak.name;
  }
  if (u.hasStem(const ['oblodz', 'szron', 'lod', 'frozen', 'ice'])) {
    out['surface_state'] = SurfaceState.frozen.name;
  } else if (u.hasAny(const ['mokra', 'mokre', 'mokry', 'wet'])) {
    out['surface_state'] = SurfaceState.wet.name;
  } else if (u.hasAny(const ['sucha', 'suche', 'suchy', 'dry'])) {
    out['surface_state'] = SurfaceState.dry.name;
  }
  return out;
}

T? _byName<T extends Enum>(List<T> values, Object? name) =>
    values.where((v) => v.name == name).firstOrNull;

class WeatherCheckSkill extends AssistantSkill {
  WeatherCheckSkill({WeatherCheckStore store = const WeatherCheckStore()})
      : _store = store;
  final WeatherCheckStore _store;

  @override
  String get id => 'weather.check';
  @override
  String get toolId => 'weather_check';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Czy mogę spawać temperatura minus 5 stopni wilgotność 85% wiatr 4 m/s TIG',
            'Can I weld temperature minus 5 degrees humidity 85% wind 4 m/s TIG'),
        SkillExample(
            'Warunki do spawania temperatura 12 stopni wilgotność 90% wiatr 2 m/s MMA deszcz',
            'Welding conditions temperature 12 degrees humidity 90% wind 2 m/s MMA rain'),
        SkillExample(
            'Czy da się spawać migomagiem na dworze temperatura 3 stopnie wilgotność 70% wiatr 6 m/s parawan',
            'Can I MAG weld outside temperature 3 degrees humidity 70% wind 6 m/s windbreak'),
        SkillExample(
            'Sprawdź warunki spawania temperatura 0 stopni wilgotność 95% bez wiatru 111 nierdzewka',
            'Check welding conditions temperature 0 degrees humidity 95% no wind 111 stainless'),
        SkillExample(
            'Warunki do spawania temperatura 20 stopni wilgotność 60% wiatr 1 m/s 141 powierzchnia sucha',
            'Welding conditions temperature 20 degrees humidity 60% wind 1 m/s 141 surface dry'),
        SkillExample('Sprawdź warunki do spawania', 'Check welding conditions'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz warunki do spawania', routesTo: 'tool.open'),
        SkillRejection('do czego służą warunki do spawania',
            routesTo: 'tool.explain'),
        SkillRejection('jaka temperatura międzyściegowa dla P91'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (u.hasStem(const ['miedzysciegow', 'interpass', 'podgrzew', 'preheat'])) {
      return null;
    }
    final asks = u.hasAny(const [
          'czy moge spawac',
          'czy da sie spawac',
          'czy mozna spawac',
          'warunki do spawania',
          'warunki spawania',
          'can i weld',
          'welding conditions',
          'weather'
        ]) ||
        (u.hasStem(const ['pogod', 'wiatr', 'wilgotn', 'wind', 'humid']) &&
            u.hasStem(const ['spaw', 'weld']));
    if (!asks) return null;
    final s = _slots(u);
    return SkillMatch(this, s.isNotEmpty ? .92 : .7, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot)) return {slot: s[slot]};
    final numbers = u.items.where((i) => i.isNumber).toList();
    if (numbers.length != 1) return null;
    final i = u.items.indexOf(numbers.single);
    final v = signedQuantity(u, i);
    return switch (slot) {
      'ambient_c' => {slot: u.hasStem(const ['mroz']) ? -v.abs() : v},
      'rh_pct' || 'wind_ms' => {slot: v},
      _ => null,
    };
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final ambient = m.slots['ambient_c'];
    if (ambient is! num || !ambient.isFinite) {
      return ask('ambient_c', 'Jaka jest temperatura powietrza w °C?',
          'What is the air temperature in °C?');
    }
    final rh = m.slots['rh_pct'];
    if (rh is! num || !rh.isFinite) {
      return ask('rh_pct', 'Jaka jest wilgotność względna w procentach?',
          'What is the relative humidity in percent?');
    }
    final wind = m.slots['wind_ms'];
    if (wind is! num || !wind.isFinite) {
      return ask('wind_ms', 'Jaki wiatr przy stanowisku w m/s?',
          'What is the wind at the workplace in m/s?');
    }
    final process = _byName(WeatherProcess.values, m.slots['process']);
    if (process == null) {
      return ask(
          'process',
          'Jaką metodą spawasz: 111 (elektroda), 135 MAG, 136, 114, 141 TIG, 131 MIG, 121 czy 311?',
          'Which process: 111 (stick), 135 MAG, 136, 114, 141 TIG, 131 MIG, 121 or 311?');
    }
    final problems = validateWeatherFields(
        ambientC: ambient.toDouble(),
        rhPct: rh.toDouble(),
        surfaceC: null,
        windMs: wind.toDouble(),
        wpsPreheatC: null);
    if (problems.isNotEmpty) {
      return const FailedResult(AssistantText(
          'Poza zakresem modułu: powietrze od −60 do 60 °C, wilgotność 0–100 %, wiatr 0–60 m/s.',
          'Outside the module range: air −60 to 60 °C, humidity 0–100 %, wind 0–60 m/s.'));
    }
    final materialGiven = m.slots['material'] != null;
    final material = _byName(WeatherMaterial.values, m.slots['material']) ??
        WeatherMaterial.carbonSteel;
    final precipitation =
        _byName(Precipitation.values, m.slots['precipitation']) ??
            Precipitation.none;
    final shelter = _byName(WeatherShelter.values, m.slots['shelter']) ??
        WeatherShelter.none;
    final surface = _byName(SurfaceState.values, m.slots['surface_state']) ??
        SurfaceState.unchecked;
    var thresholds = WeatherThresholds.defaults;
    try {
      thresholds = await _store.loadThresholds();
    } catch (_) {}
    final a = assessWeather(
        WeatherInput(
            ambientC: ambient.toDouble(),
            rhPct: rh.toDouble(),
            windMs: wind.toDouble(),
            precipitation: precipitation,
            process: process,
            shelter: shelter,
            material: material,
            surfaceState: surface),
        thresholds);
    if (a == null) {
      return const FailedResult(AssistantText(
          'Nie da się policzyć punktu rosy z tych danych.',
          'The dew point cannot be calculated from this data.'));
    }
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    String head(bool en) => switch (a.verdict) {
          WeatherVerdict.noGo => en ? 'Do not weld.' : 'Nie spawać.',
          WeatherVerdict.conditional => en
              ? 'Welding only after meeting the conditions.'
              : 'Spawać dopiero po spełnieniu warunków.',
          WeatherVerdict.go => en ? 'Welding is possible.' : 'Można spawać.',
        };
    String points(bool en) => [...a.stops, ...a.conditions]
        .take(3)
        .map((p) => en ? p.textEn : p.textPl)
        .join(' ');
    String text(bool en) {
      final b = StringBuffer(en
          ? '${head(true)} ${process.label(true)}, air ${f(ambient)} °C, RH ${f(rh)} %, wind ${f(wind)} m/s; dew point ${f(a.dewPointC)} °C.'
          : '${head(false)} ${process.label(false)}, powietrze ${f(ambient)} °C, wilgotność ${f(rh)} %, wiatr ${f(wind)} m/s; punkt rosy ${f(a.dewPointC)} °C.');
      final p = points(en);
      if (p.isNotEmpty) b.write(' $p');
      if (!materialGiven) {
        b.write(en
            ? ' Assumed carbon steel — say if it is stainless or aluminium.'
            : ' Przyjąłem stal węglową — powiedz, jeśli to nierdzewka albo aluminium.');
      }
      return b.toString();
    }

    return AnswerResult(
        AssistantAnswer(text: AssistantText(text(false), text(true))),
        show: ShowInModule(toolId, {
          'ambient_c': ambient.toDouble(),
          'rh_pct': rh.toDouble(),
          'wind_ms': wind.toDouble(),
          'process': process.name,
          'material': material.name,
          'precipitation': precipitation.name,
          'shelter': shelter.name,
          'surface_state': surface.name,
        }));
  }
}
