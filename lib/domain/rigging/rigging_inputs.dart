/// Ostatnie dane wejściowe kalkulatora zawiesi (JSON w SharedPreferences).
///
/// Zapisywane są tylko dane kalkulatora: masa / rura, rodzaj zawiesia,
/// konfiguracja, kąt, WLL, kolor. NIE są zapisywane: potwierdzenie etykiety
/// ani lista kontrolna — przed każdym podniesieniem od nowa.
///
/// Odczyt nigdy nie rzuca: nieczytelny JSON, inny typ albo nieznana wartość
/// pola → wartość domyślna tego pola i `intact == false` (ekran mówi, że
/// wczytano wartości domyślne).
///
/// Czysty Dart.
library;

import 'dart:convert';

import '../fitter/fitter_calcs.dart' show PipeMaterial;
import 'rigging_calc.dart';
import 'rigging_colors.dart';

class RiggingSavedInputs {
  /// Masa liczona z rury (spool) zamiast wpisanej.
  final bool fromPipe;
  final MassUnit unit;

  /// Teksty pól — dokładnie tak, jak wpisał monter.
  final String mass;
  final String od;
  final String wall;
  final String length;
  final String extra;
  final PipeMaterial material;
  final SlingType sling;
  final HitchMode mode;
  final bool chokedLegs;
  final AngleKind angleKind;
  final String angle;
  final bool asymmetric;
  final String wll;

  /// `null` — nie wybrano koloru.
  final SlingColour? colour;

  const RiggingSavedInputs({
    this.fromPipe = false,
    this.unit = MassUnit.kg,
    this.mass = '',
    this.od = '',
    this.wall = '',
    this.length = '',
    this.extra = '',
    this.material = PipeMaterial.cs,
    this.sling = SlingType.webbing,
    this.mode = HitchMode.twoLeg,
    this.chokedLegs = false,
    this.angleKind = AngleKind.fromVertical,
    this.angle = '',
    this.asymmetric = false,
    this.wll = '',
    this.colour,
  });

  Map<String, Object?> toJson() => {
        'v': 1,
        'fromPipe': fromPipe,
        'unit': unit.name,
        'mass': mass,
        'od': od,
        'wall': wall,
        'length': length,
        'extra': extra,
        'material': material.name,
        'sling': sling.name,
        'mode': mode.name,
        'chokedLegs': chokedLegs,
        'angleKind': angleKind.name,
        'angle': angle,
        'asymmetric': asymmetric,
        'wll': wll,
        'colour': colour?.name,
      };
}

/// Wynik odczytu: dane i to, czy zapis był nienaruszony.
class RiggingInputsDecode {
  final RiggingSavedInputs inputs;
  final bool intact;
  const RiggingInputsDecode(this.inputs, {required this.intact});
}

String encodeRiggingInputs(RiggingSavedInputs inputs) =>
    jsonEncode(inputs.toJson());

/// Najdłuższy tekst pola przyjmowany z zapisu (dłuższy = uszkodzony).
const int _maxFieldLength = 32;

RiggingInputsDecode decodeRiggingInputs(String raw) {
  const d = RiggingSavedInputs();
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const RiggingInputsDecode(d, intact: false);
  }
  if (decoded is! Map) return const RiggingInputsDecode(d, intact: false);
  final m = decoded;
  var intact = true;

  T pick<T>(String key, T fallback, T? Function(Object? v) read) {
    if (!m.containsKey(key)) {
      intact = false;
      return fallback;
    }
    final v = read(m[key]);
    if (v == null) {
      intact = false;
      return fallback;
    }
    return v;
  }

  bool? asBool(Object? v) => v is bool ? v : null;
  String? asText(Object? v) =>
      v is String && v.length <= _maxFieldLength ? v : null;
  E? Function(Object?) asEnum<E extends Enum>(List<E> values) =>
      (v) => v is String ? values.where((e) => e.name == v).firstOrNull : null;

  final inputs = RiggingSavedInputs(
    fromPipe: pick('fromPipe', d.fromPipe, asBool),
    unit: pick('unit', d.unit, asEnum(MassUnit.values)),
    mass: pick('mass', d.mass, asText),
    od: pick('od', d.od, asText),
    wall: pick('wall', d.wall, asText),
    length: pick('length', d.length, asText),
    extra: pick('extra', d.extra, asText),
    material: pick('material', d.material, asEnum(PipeMaterial.values)),
    sling: pick('sling', d.sling, asEnum(SlingType.values)),
    mode: pick('mode', d.mode, asEnum(HitchMode.values)),
    chokedLegs: pick('chokedLegs', d.chokedLegs, asBool),
    angleKind: pick('angleKind', d.angleKind, asEnum(AngleKind.values)),
    angle: pick('angle', d.angle, asText),
    asymmetric: pick('asymmetric', d.asymmetric, asBool),
    wll: pick('wll', d.wll, asText),
    colour: _colour(m, () => intact = false),
  );
  return RiggingInputsDecode(inputs, intact: intact);
}

/// Kolor: `null` w zapisie to poprawne „nie wybrano”; nieznana nazwa albo
/// inny typ → uszkodzone.
SlingColour? _colour(Map<dynamic, dynamic> m, void Function() damaged) {
  if (!m.containsKey('colour')) {
    damaged();
    return null;
  }
  final v = m['colour'];
  if (v == null) return null;
  final c = v is String
      ? SlingColour.values.where((e) => e.name == v).firstOrNull
      : null;
  if (c == null) damaged();
  return c;
}
