// Czas formowania (purge) rury — czyste funkcje, bez Fluttera.
//
// Model idealnego wymieszania: C(t) = C₀ · e^(−Q·t/V)
//   ⇒ t = (V / Q) · ln(C₀ / C_cel),   liczba wymian objętości N = ln(C₀ / C_cel)
//
// Model zakłada pełne wymieszanie gazu w rurze; w praktyce (martwe strefy,
// nieszczelne korki, rozwarstwienie Ar/powietrze) czas bywa inny — wynik jest
// orientacyjny i trzeba go zweryfikować analizatorem O₂.

import 'dart:math' as math;

/// Powód, dla którego nie da się policzyć czasu formowania.
enum PurgeInputError {
  /// OD / ścianka / długość ≤ 0 albo OD ≤ 2 × ścianka.
  geometry,

  /// Przepływ ≤ 0.
  flow,

  /// Stężenie startowe ≤ 0.
  initialConcentration,

  /// Cel ≤ 0 ppm — model wykładniczy nigdy nie osiąga zera.
  target,

  /// Cel ≥ stężenie startowe — nie ma czego wypłukiwać.
  targetNotBelowInitial,
}

class PurgeEstimate {
  const PurgeEstimate({
    required this.volumeL,
    required this.timeSec,
    required this.volumeChanges,
  });

  /// Objętość wewnętrzna odcinka [L].
  final double volumeL;

  /// Czas do osiągnięcia celu [s].
  final double timeSec;

  /// Liczba wymian objętości N = ln(C₀ / C_cel).
  final double volumeChanges;
}

/// Wynik: albo [estimate], albo [error].
class PurgeResult {
  const PurgeResult.ok(PurgeEstimate this.estimate) : error = null;
  const PurgeResult.invalid(PurgeInputError this.error) : estimate = null;

  final PurgeEstimate? estimate;
  final PurgeInputError? error;
}

bool _positive(double x) => x.isFinite && x > 0;

PurgeResult estimatePurge({
  required double odMm,
  required double wallMm,
  required double lengthMm,
  required double flowLpm,
  required double initialPpm,
  required double targetPpm,
}) {
  if (!_positive(odMm) || !_positive(wallMm) || !_positive(lengthMm)) {
    return const PurgeResult.invalid(PurgeInputError.geometry);
  }
  final idMm = odMm - 2.0 * wallMm;
  if (idMm <= 0) return const PurgeResult.invalid(PurgeInputError.geometry);
  if (!_positive(flowLpm)) {
    return const PurgeResult.invalid(PurgeInputError.flow);
  }
  if (!_positive(initialPpm)) {
    return const PurgeResult.invalid(PurgeInputError.initialConcentration);
  }
  if (!_positive(targetPpm)) {
    return const PurgeResult.invalid(PurgeInputError.target);
  }
  if (targetPpm >= initialPpm) {
    return const PurgeResult.invalid(PurgeInputError.targetNotBelowInitial);
  }
  final volumeL = math.pi * (idMm / 2.0) * (idMm / 2.0) * lengthMm / 1e6;
  final changes = math.log(initialPpm / targetPpm);
  final timeSec = volumeL / (flowLpm / 60.0) * changes;
  return PurgeResult.ok(PurgeEstimate(
    volumeL: volumeL,
    timeSec: timeSec,
    volumeChanges: changes,
  ));
}
