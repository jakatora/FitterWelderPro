/// Ostatnie USTAWIENIA kalkulatora zawiesi (JSON w SharedPreferences).
///
/// Zapisywane są tylko wybory, które monter widzi od razu na ekranie:
/// masa wpisana czy z rury, jednostka, materiał rury, rodzaj zawiesia,
/// sposób zawiązania, cięgna na zadusznik, konwencja kąta.
///
/// CELOWO NIE są zapisywane żadne liczby ani nic, co opisuje dzisiejszy
/// ładunek albo dzisiejsze zawiesie: masa, wymiary rury, dodatki, kąt, WLL,
/// kolor pasa, co podaje zawieszka, niesymetria, etykieta, lista kontrolna.
/// Wczorajsze WLL 5 t z pasa, którego dziś nie ma, plus jedno kliknięcie
/// „etykieta czytelna” dałoby zielony werdykt dla innego pasa.
///
/// Odczyt nigdy nie rzuca: nieczytelny JSON, inny typ albo nieznana wartość
/// pola → wartość domyślna tego pola i `intact == false` (ekran mówi, że
/// wczytano wartości domyślne). Klucze z wcześniejszej wersji zapisu
/// (mass, wll, colour…) są ignorowane.
///
/// Czysty Dart.
library;

import 'dart:convert';

import '../fitter/fitter_calcs.dart' show PipeMaterial;
import 'rigging_calc.dart';

class RiggingSavedInputs {
  /// Masa liczona z rury (spool) zamiast wpisanej.
  final bool fromPipe;
  final MassUnit unit;
  final PipeMaterial material;
  final SlingType sling;
  final HitchMode mode;
  final bool chokedLegs;
  final AngleKind angleKind;

  const RiggingSavedInputs({
    this.fromPipe = false,
    this.unit = MassUnit.kg,
    this.material = PipeMaterial.cs,
    this.sling = SlingType.webbing,
    this.mode = HitchMode.twoLeg,
    this.chokedLegs = false,
    this.angleKind = AngleKind.fromVertical,
  });

  Map<String, Object?> toJson() => {
        'v': 2,
        'fromPipe': fromPipe,
        'unit': unit.name,
        'material': material.name,
        'sling': sling.name,
        'mode': mode.name,
        'chokedLegs': chokedLegs,
        'angleKind': angleKind.name,
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
  E? Function(Object?) asEnum<E extends Enum>(List<E> values) =>
      (v) => v is String ? values.where((e) => e.name == v).firstOrNull : null;

  final inputs = RiggingSavedInputs(
    fromPipe: pick('fromPipe', d.fromPipe, asBool),
    unit: pick('unit', d.unit, asEnum(MassUnit.values)),
    material: pick('material', d.material, asEnum(PipeMaterial.values)),
    sling: pick('sling', d.sling, asEnum(SlingType.values)),
    mode: pick('mode', d.mode, asEnum(HitchMode.values)),
    chokedLegs: pick('chokedLegs', d.chokedLegs, asBool),
    angleKind: pick('angleKind', d.angleKind, asEnum(AngleKind.values)),
  );
  return RiggingInputsDecode(inputs, intact: intact);
}
