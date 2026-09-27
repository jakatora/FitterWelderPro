/// Rury → AMP / Startowe / Wolfram: JEDNO źródło prądu, elektrody i gazu
/// palnika dla ręcznego TIG rur.
///
/// * Prąd — z punktów startowych („Startowe”, tabela `approved_weld_params`).
///   Ta sama rura daje w kalkulatorze AMP dokładnie liczbę z listy
///   „Startowe”; między punktami — interpolacja, poza danymi — brak wyniku.
/// * Elektroda — z pasm DC− w `lib/data/tungsten.dart` ([sizeForCurrent]),
///   tak jak na ekranie Wolfram.
/// * Gaz palnika — z tabeli dysza/gaz dla średnicy elektrody
///   ([tungstenExtrasFor]), tak jak na ekranie Wolfram.
///
/// Stal węglowa bez własnych punktów: prąd nierdzewnej / 0,9 — stal
/// nierdzewna wymaga ok. 10 % mniej prądu niż węglowa (niższa przewodność
/// cieplna; mig-welding.co.uk „TIG calculator”: „The amps required to weld
/// stainless are about 10% lower than the amps used for mild steel”).
library;

import 'dart:math' as math;

import '../../data/tungsten.dart';

class PipeStartPoint {
  final String material; // SS / CS / DUPLEX / AL
  final String method; // TIG_WIRE / TIG_AUTOGEN
  final double odMm;
  final double wallMm;
  final double amps;

  const PipeStartPoint({
    required this.material,
    required this.method,
    required this.odMm,
    required this.wallMm,
    required this.amps,
  });
}

enum PipeCurrentSource {
  /// Punkt startowy dla tej rury (OD ±2 %, t ±0,05 mm).
  exact,

  /// Interpolacja między punktami tego samego materiału i metody.
  interpolated,

  /// Punkty tylko z jednej strony grubości: prąd × t / t_punktu (≤ 1 mm).
  scaledByWall,

  /// Stal węglowa bez danych: nierdzewna / 0,9.
  fromStainless,

  /// Brak danych — brak liczby.
  none,
}

class PipeCurrent {
  final double? amps;
  final PipeCurrentSource source;

  /// Punkt dokładny (dla [PipeCurrentSource.exact]).
  final PipeStartPoint? point;

  const PipeCurrent(this.amps, this.source, {this.point});

  bool get hasResult => amps != null;
}

/// Mnożnik prądu nierdzewna → węglowa (nierdzewna ≈ 10 % mniej prądu).
const double kStainlessToCarbonCurrent = 1 / 0.9;

bool _sameOd(double a, double b) =>
    (a - b).abs() <= math.max(1.0, 0.02 * math.max(a, b));

/// Prąd z punktów jednej grupy (materiał + metoda).
PipeCurrent _fromPoints(List<PipeStartPoint> pts, double od, double t) {
  if (pts.isEmpty) return const PipeCurrent(null, PipeCurrentSource.none);
  for (final p in pts) {
    if (_sameOd(p.odMm, od) && (p.wallMm - t).abs() <= 0.05) {
      return PipeCurrent(p.amps, PipeCurrentSource.exact, point: p);
    }
  }

  // Grupy po ściance; w każdej prąd liniowo po OD w zakresie danych
  // (±2 % na końcach — nominalne 60 vs 60,3).
  final byWall = <double, List<PipeStartPoint>>{};
  for (final p in pts) {
    final key = byWall.keys.firstWhere((w) => (w - p.wallMm).abs() <= 0.05,
        orElse: () => p.wallMm);
    byWall.putIfAbsent(key, () => []).add(p);
  }

  double? atOd(List<PipeStartPoint> g) {
    final s = [...g]..sort((a, b) => a.odMm.compareTo(b.odMm));
    // Kilka punktów z tym samym OD — średnia.
    final ods = <double>[];
    final amps = <double>[];
    for (final p in s) {
      if (ods.isNotEmpty && _sameOd(ods.last, p.odMm)) {
        final n = ods.length;
        amps[n - 1] = (amps[n - 1] + p.amps) / 2;
      } else {
        ods.add(p.odMm);
        amps.add(p.amps);
      }
    }
    if (od < ods.first * 0.98 || od > ods.last * 1.02) return null;
    if (od <= ods.first) return amps.first;
    if (od >= ods.last) return amps.last;
    for (var i = 0; i + 1 < ods.length; i++) {
      if (od >= ods[i] && od <= ods[i + 1]) {
        final k = (od - ods[i]) / (ods[i + 1] - ods[i]);
        return amps[i] + (amps[i + 1] - amps[i]) * k;
      }
    }
    return null;
  }

  double? loW, loA, hiW, hiA;
  for (final e in byWall.entries) {
    final a = atOd(e.value);
    if (a == null) continue;
    final w = e.key;
    if (w <= t && (loW == null || w > loW)) {
      loW = w;
      loA = a;
    }
    if (w >= t && (hiW == null || w < hiW)) {
      hiW = w;
      hiA = a;
    }
  }
  if (loW != null && hiW != null) {
    if ((hiW - loW).abs() < 1e-9) {
      return PipeCurrent(loA, PipeCurrentSource.interpolated);
    }
    final k = (t - loW) / (hiW - loW);
    return PipeCurrent(loA! + (hiA! - loA) * k, PipeCurrentSource.interpolated);
  }
  // Tylko z jednej strony: proporcjonalnie do ścianki, najwyżej o 1 mm.
  final w = loW ?? hiW;
  final a = loA ?? hiA;
  if (w != null && a != null && (t - w).abs() <= 1.0) {
    return PipeCurrent(a * t / w, PipeCurrentSource.scaledByWall);
  }
  return const PipeCurrent(null, PipeCurrentSource.none);
}

/// Prąd startowy dla rury [odMm] × [wallMm] z punktów startowych.
PipeCurrent pipeStartCurrent({
  required List<PipeStartPoint> points,
  required String material,
  required String method,
  required double odMm,
  required double wallMm,
}) {
  if (!(odMm > 0) || !(wallMm > 0)) {
    return const PipeCurrent(null, PipeCurrentSource.none);
  }
  List<PipeStartPoint> group(String m) =>
      points.where((p) => p.material == m && p.method == method).toList();
  final own = _fromPoints(group(material), odMm, wallMm);
  if (material != 'CS') return own;
  // Stal węglowa: własny punkt albo interpolacja między własnymi punktami
  // wygrywa; gdy CS ma tylko punkty z jednej strony grubości (albo żadnych),
  // pewniejsza jest nierdzewna tej samej rury / 0,9 — i nigdy mniej niż SS.
  final ss = _fromPoints(group('SS'), odMm, wallMm);
  final ssAsCs = ss.hasResult
      ? PipeCurrent(ss.amps! * kStainlessToCarbonCurrent,
          PipeCurrentSource.fromStainless)
      : null;
  // Własny punkt CS zostaje zawsze (lista „Startowe” pokazuje tę samą
  // liczbę) — nawet gdy seed jest sprzeczny z SS (np. 219 × 6: CS 220 A,
  // SS 310 A — poza zakresem kalkulatora t ≤ 3 mm).
  if (own.source == PipeCurrentSource.exact) return own;
  if (own.source == PipeCurrentSource.interpolated) {
    final ssFromData = ss.source == PipeCurrentSource.exact ||
        ss.source == PipeCurrentSource.interpolated;
    if (ssAsCs != null && ssFromData && own.amps! < ss.amps!) return ssAsCs;
    return own;
  }
  return ssAsCs ?? own;
}

/// Elektroda dla prądu — ta sama funkcja co ekran Wolfram.
double pipeElectrodeMm(double amps) =>
    (sizeForCurrent(amps) ?? kTungstenSizes.first).diaMm;

/// Gaz palnika [L/min] dla elektrody — ta sama tabela co ekran Wolfram.
({int min, int max}) pipeTorchGasLpm(double electrodeMm) {
  final e = tungstenExtrasFor(electrodeMm) ??
      tungstenExtrasFor(kTungstenSizes.first.diaMm)!;
  return (min: e.argonMinLpm, max: e.argonMaxLpm);
}
