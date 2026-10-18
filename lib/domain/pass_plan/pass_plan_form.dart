// Plan ściegów i elektrod — formularz ekranu jako mapa tekstów: zapis
// ostatnich wejść (JSON w SharedPreferences, wersja w kluczu) i odczyt
// liczb niezależny od przecinka / kropki. Uszkodzony zapis → wartości
// domyślne i flaga `lossy` (ekran pokazuje informację, magazyn trzyma
// kopię surowego zapisu). Czysty Dart.
library;

import 'dart:convert';

import '../../data/pipe_schedules.dart';
import '../../utils/decimal_parse.dart';
import '../quotes/quote_process.dart';
import '../quotes/weld_geometry.dart';
import '../welding/electrode_exposure.dart';
import 'pass_plan.dart';
import 'pass_plan_sources.dart';

/// Klucze pól formularza.
abstract final class PassPlanField {
  static const kind = 'kind';
  static const dn = 'dn';
  static const sch = 'sch';
  static const od = 'od';
  static const wall = 'wall';
  static const throat = 'throat';
  static const length = 'length';
  static const count = 'count';
  static const groove = 'groove';
  static const angle = 'angle';
  static const rootFace = 'rootFace';
  static const gap = 'gap';
  static const root = 'root';
  static const hot = 'hot';
  static const fill = 'fill';
  static const cap = 'cap';
  static const long = 'long';
  static const rod = 'rod';
  static const stub = 'stub';
  static const reserve = 'reserve';
  static const electrodeClass = 'class';
  static const source = 'source';
  static const limit = 'limit';
  static const order = 'order';
  static const shift = 'shift';

  static String bead(PassConsumable c) => 'bead.${c.name}';
  static String arcOn(QuoteProcess p) => 'arcOn.${p.code}';

  /// Pola liczbowe (tekst wpisany przez spawacza).
  static List<String> get numeric => [
        od,
        wall,
        throat,
        length,
        count,
        angle,
        rootFace,
        gap,
        stub,
        reserve,
        limit,
        shift,
        for (final c in PassConsumable.values) bead(c),
        for (final p in kPassPlanProcesses) arcOn(p),
      ];
}

/// Wartość „brak” dla pól wyboru z opcją „bez”.
const String kPassPlanNone = 'none';

/// Klucz z wersją — zmiana formatu = nowy klucz.
const String kPassPlanPrefsKey = 'pass_plan_form_v1';

/// Kopia surowego zapisu odczytanego ze stratą (tylko pierwsza).
const String kPassPlanCorruptPrefsKey = 'pass_plan_form_v1_corrupt';

/// Najdłuższy tekst pola liczbowego przyjmowany z zapisu.
const int _maxFieldLength = 32;

String _canon(double v) {
  var s = v.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// Formularz startowy — przykład z warsztatu (DN150 Sch 40: 168,3 × 7,11,
/// rowek V 60°, 8 złączy, grań TIG, ścieg gorący Ø2,5, reszta Ø3,2).
/// Liczby z kropką; ekran pokazuje je po polsku z przecinkiem.
Map<String, String> passPlanDefaultForm() {
  const i = PassPlanInput();
  return {
    PassPlanField.kind: i.kind.code,
    PassPlanField.dn: '150',
    PassPlanField.sch: '40',
    PassPlanField.od: _canon(i.odMm),
    PassPlanField.wall: _canon(i.wallMm),
    PassPlanField.throat: _canon(i.throatMm),
    PassPlanField.length: _canon(i.lengthM),
    PassPlanField.count: _canon(i.count),
    PassPlanField.groove: i.groove.code,
    PassPlanField.angle: _canon(i.angleDeg),
    PassPlanField.rootFace: _canon(i.rootFaceMm),
    PassPlanField.gap: _canon(i.gapMm),
    PassPlanField.root: i.root.name,
    PassPlanField.hot: i.hot?.name ?? kPassPlanNone,
    PassPlanField.fill: i.fill.name,
    PassPlanField.cap: i.cap.name,
    PassPlanField.long: i.longElectrodes ? '1' : '0',
    PassPlanField.rod: _canon(i.tigRodMm),
    PassPlanField.stub: _canon(i.stubMm),
    PassPlanField.reserve: _canon(i.reservePct),
    PassPlanField.electrodeClass: i.electrodeClass?.name ?? kPassPlanNone,
    PassPlanField.source: i.source.name,
    PassPlanField.limit: '',
    PassPlanField.order: i.order.name,
    PassPlanField.shift: _canon(i.shiftH),
    for (final c in PassConsumable.values)
      PassPlanField.bead(c): _canon(c.defaultBeadAreaMm2),
    for (final p in kPassPlanProcesses)
      PassPlanField.arcOn(p): _canon(defaultArcOnPct(p)),
  };
}

/// Czy wartość pola jest dopuszczalna w zapisie.
bool passPlanFieldValid(String key, String value) {
  if (PassPlanField.numeric.contains(key)) {
    return value.length <= _maxFieldLength &&
        (value.trim().isEmpty || parseDecimal(value) != null);
  }
  switch (key) {
    case PassPlanField.kind:
      return kPassPlanJointKinds.any((k) => k.code == value);
    case PassPlanField.dn:
      return value.isEmpty || kPipeWalls.any((r) => '${r.dn}' == value);
    case PassPlanField.sch:
      return value.isEmpty || kSchedulesCarbon.contains(value);
    case PassPlanField.groove:
      return GrooveType.values.any((g) => g.code == value);
    case PassPlanField.root:
      return kRootChoices.any((c) => c.name == value);
    case PassPlanField.hot:
      return value == kPassPlanNone || kHotChoices.any((c) => c.name == value);
    case PassPlanField.fill:
      return kFillChoices.any((c) => c.name == value);
    case PassPlanField.cap:
      return kCapChoices.any((c) => c.name == value);
    case PassPlanField.long:
      return value == '0' || value == '1';
    case PassPlanField.rod:
      final d = parseDecimal(value);
      return d != null && kTigRodDiametersMm.contains(d);
    case PassPlanField.electrodeClass:
      return value == kPassPlanNone ||
          ElectrodeClass.values.any((c) => c.name == value);
    case PassPlanField.source:
      return ElectrodeSource.values.any((s) => s.name == value);
    case PassPlanField.order:
      return WorkOrder.values.any((o) => o.name == value);
  }
  return false;
}

String encodePassPlanForm(Map<String, String> form) => jsonEncode({
      'v': 1,
      'f': {
        for (final e in form.entries)
          if (passPlanDefaultForm().containsKey(e.key)) e.key: e.value,
      },
    });

/// Odczyt zapisu: formularz (brakujące / złe pola — domyślne) i czy coś
/// stracono. Uszkodzony JSON albo inna wersja → same domyślne, `lossy`.
/// Brak pola (starsza wersja zapisu) nie jest stratą.
({Map<String, String> form, bool lossy}) decodePassPlanFormDetailed(
    String raw) {
  final defaults = passPlanDefaultForm();
  final Object? json;
  try {
    json = jsonDecode(raw);
  } catch (_) {
    return (form: defaults, lossy: true);
  }
  if (json is! Map || json['v'] != 1 || json['f'] is! Map) {
    return (form: defaults, lossy: true);
  }
  final stored = json['f'] as Map;
  var lossy = false;
  final out = Map<String, String>.of(defaults);
  for (final key in defaults.keys) {
    if (!stored.containsKey(key)) continue;
    final v = stored[key];
    if (v is String && passPlanFieldValid(key, v)) {
      out[key] = v;
    } else {
      lossy = true;
    }
  }
  return (form: out, lossy: lossy);
}

double _num(String? text) => parseDecimal(text) ?? double.nan;

/// Dane do rachunku z formularza. Puste albo nieczytelne pole liczbowe →
/// NaN (problem, nie zero); pusty limit → z tabeli.
PassPlanInput passPlanInputFromForm(Map<String, String> form) {
  final d = passPlanDefaultForm();
  String v(String key) => form[key] ?? d[key]!;
  String choice(String key) =>
      passPlanFieldValid(key, v(key)) ? v(key) : d[key]!;

  final limitText = v(PassPlanField.limit).trim();
  final hot = choice(PassPlanField.hot);
  final cls = choice(PassPlanField.electrodeClass);
  return PassPlanInput(
    kind: JointKind.fromCode(choice(PassPlanField.kind)),
    odMm: _num(v(PassPlanField.od)),
    wallMm: _num(v(PassPlanField.wall)),
    throatMm: _num(v(PassPlanField.throat)),
    lengthM: _num(v(PassPlanField.length)),
    count: _num(v(PassPlanField.count)),
    groove: GrooveType.fromCode(choice(PassPlanField.groove)),
    angleDeg: _num(v(PassPlanField.angle)),
    rootFaceMm: _num(v(PassPlanField.rootFace)),
    gapMm: _num(v(PassPlanField.gap)),
    root: PassConsumable.byName(choice(PassPlanField.root))!,
    hot: hot == kPassPlanNone ? null : PassConsumable.byName(hot),
    fill: PassConsumable.byName(choice(PassPlanField.fill))!,
    cap: PassConsumable.byName(choice(PassPlanField.cap))!,
    longElectrodes: choice(PassPlanField.long) == '1',
    tigRodMm: _num(choice(PassPlanField.rod)),
    stubMm: _num(v(PassPlanField.stub)),
    reservePct: _num(v(PassPlanField.reserve)),
    beadAreasMm2: {
      for (final c in PassConsumable.values) c: _num(v(PassPlanField.bead(c))),
    },
    arcOnPct: {
      for (final p in kPassPlanProcesses) p: _num(v(PassPlanField.arcOn(p))),
    },
    electrodeClass:
        cls == kPassPlanNone ? null : ElectrodeClass.values.byName(cls),
    source: ElectrodeSource.values.byName(choice(PassPlanField.source)),
    limitMinutes: limitText.isEmpty ? null : _num(limitText),
    order: WorkOrder.values.byName(choice(PassPlanField.order)),
    shiftH: _num(v(PassPlanField.shift)),
  );
}
