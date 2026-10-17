/// Ostatnie wejścia ekranu „Dymy spawalnicze i odciąg” — zapis JSON.
///
/// Zapisujemy dane sprzętu i wyboru (materiał, proces, odciąg, ssawka,
/// prędkość, ŚOI), ale NIE listę kontrolną — stare „ptaszki” nie mogą
/// udawać aktualnego sprawdzenia stanowiska.
///
/// Odczyt jest ostrożny: uszkodzony JSON → wartości domyślne
/// i [FumeDecoded.corrupt]; uszkodzone pole → domyślne tego pola
/// i [FumeDecoded.corrupt]. Prędkość uchwycenia poniżej minimum dla procesu
/// NIE jest przyjmowana (próg tylko zaostrzalny).
///
/// Czysty Dart.
library;

import 'dart:convert';

import 'fume_assessment.dart';
import 'fume_capture.dart';
import 'fume_hazards.dart';
import 'fume_sources.dart';

/// Klucz w SharedPreferences (wersja w nazwie).
const String kFumeInputsPrefsKey = 'fume_inputs_v1';

class FumeInputs {
  const FumeInputs({
    this.material,
    this.process,
    this.lev,
    this.rpe,
    this.flow,
    this.flowUnit = FumeFlowUnit.m3h,
    this.shape = FumeHoodShape.round,
    this.diameter,
    this.width,
    this.height,
    this.lengthUnit = FumeLengthUnit.mm,
    this.flanged = false,
    this.velocity = kFumeCaptureDefaultMs,
    this.distance,
  });

  final FumeMaterial? material;
  final FumeProcess? process;
  final FumeLevStatus? lev;
  final FumeRpe? rpe;
  final double? flow;
  final FumeFlowUnit flowUnit;
  final FumeHoodShape shape;
  final double? diameter;
  final double? width;
  final double? height;
  final FumeLengthUnit lengthUnit;
  final bool flanged;
  final double velocity;
  final double? distance;

  Map<String, Object?> toJson() => {
        if (material != null) 'material': material!.name,
        if (process != null) 'process': process!.name,
        if (lev != null) 'lev': lev!.name,
        if (rpe != null) 'rpe': rpe!.name,
        if (flow != null) 'flow': flow,
        'flowUnit': flowUnit.name,
        'shape': shape.name,
        if (diameter != null) 'diameter': diameter,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        'lengthUnit': lengthUnit.name,
        'flanged': flanged,
        'velocity': velocity,
        if (distance != null) 'distance': distance,
      };
}

class FumeDecoded {
  const FumeDecoded(this.inputs, {required this.corrupt});
  final FumeInputs inputs;

  /// Zapis był uszkodzony (w całości albo w którymś polu) — część wartości
  /// wróciła do domyślnych.
  final bool corrupt;
}

String encodeFumeInputs(FumeInputs i) => jsonEncode(i.toJson());

/// Odczyt zapisu. `null` (brak zapisu) → domyślne, bez flagi.
FumeDecoded decodeFumeInputs(String? raw) {
  if (raw == null) return const FumeDecoded(FumeInputs(), corrupt: false);
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const FumeDecoded(FumeInputs(), corrupt: true);
  }
  if (decoded is! Map) return const FumeDecoded(FumeInputs(), corrupt: true);
  final Map<Object?, Object?> data = decoded;

  var corrupt = false;

  /// Enum z nazwy: brak klucza → null; zła nazwa → null + uszkodzenie.
  T? pick<T>(String key, T? Function(Object?) byName) {
    if (!data.containsKey(key) || data[key] == null) return null;
    final v = byName(data[key]);
    if (v == null) corrupt = true;
    return v;
  }

  T pickOr<T>(String key, T? Function(Object?) byName, T fallback) =>
      pick(key, byName) ?? fallback;

  /// Liczba > 0 i skończona, nie większa niż [maxSi] po przeliczeniu.
  double? number(String key, double Function(double) toSi, double maxSi) {
    if (!data.containsKey(key) || data[key] == null) return null;
    final v = data[key];
    if (v is! num) {
      corrupt = true;
      return null;
    }
    final d = v.toDouble();
    if (!d.isFinite || d <= 0 || toSi(d) > maxSi + kFumeEps) {
      corrupt = true;
      return null;
    }
    return d;
  }

  final material = pick('material', FumeMaterial.byName);
  final process = pick('process', FumeProcess.byName);
  final lev = pick('lev', FumeLevStatus.byName);
  final rpe = pick('rpe', FumeRpe.byName);
  final flowUnit = pickOr('flowUnit', FumeFlowUnit.byName, FumeFlowUnit.m3h);
  final shape = pickOr('shape', FumeHoodShape.byName, FumeHoodShape.round);
  final lengthUnit =
      pickOr('lengthUnit', FumeLengthUnit.byName, FumeLengthUnit.mm);

  // Bez jednostki z zapisu nie wiadomo, co znaczy liczba — pole puste.
  final flowUnitOk = !data.containsKey('flowUnit') ||
      FumeFlowUnit.byName(data['flowUnit']) != null;
  final lengthUnitOk = !data.containsKey('lengthUnit') ||
      FumeLengthUnit.byName(data['lengthUnit']) != null;

  final flow =
      flowUnitOk ? number('flow', flowUnit.toM3s, kFumeMaxFlowM3s) : null;
  double? len(String key, double maxM) =>
      lengthUnitOk ? number(key, lengthUnit.toM, maxM) : null;
  final diameter = len('diameter', kFumeMaxOpeningM);
  final width = len('width', kFumeMaxOpeningM);
  final height = len('height', kFumeMaxOpeningM);
  final distance = len('distance', kFumeMaxDistanceM);

  var flanged = false;
  if (data.containsKey('flanged')) {
    final f = data['flanged'];
    if (f is bool) {
      flanged = f;
    } else {
      corrupt = true;
    }
  }

  final minV = fumeCaptureMinFor(process);
  var velocity = minV;
  if (data.containsKey('velocity')) {
    final v = data['velocity'];
    if (v is num &&
        v.isFinite &&
        v >= minV - kFumeEps &&
        v <= kFumeMaxCaptureMs + kFumeEps) {
      velocity = v.toDouble();
    } else {
      corrupt = true;
    }
  }

  return FumeDecoded(
    FumeInputs(
      material: material,
      process: process,
      lev: lev,
      rpe: rpe,
      flow: flow,
      flowUnit: flowUnit,
      shape: shape,
      diameter: diameter,
      width: width,
      height: height,
      lengthUnit: lengthUnit,
      flanged: flanged,
      velocity: velocity,
      distance: distance,
    ),
    corrupt: corrupt,
  );
}
