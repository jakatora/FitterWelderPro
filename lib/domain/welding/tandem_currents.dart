/// Tandem TIG (dwóch spawaczy, zbiorniki SS): prądy palnika zewnętrznego
/// (z drutem) i wewnętrznego (bez drutu) z punktów startowych.
///
/// Zasady (przegląd G4, 2026-09-26):
/// * wynik tylko w zakresie danych — poniżej najmniejszej i powyżej
///   największej grubości efektywnej nie ma liczby (dawniej zwracany był
///   skrajny punkt opisany jako „wyliczony z zatwierdzonych”);
/// * jeden punkt danych daje wynik tylko dla swojej grubości;
/// * prąd malejący przy rosnącej grubości w użytym przedziale → ostrzeżenie;
/// * pion bez własnego wpisu: poziom × (pion/poziom) z pary odniesienia,
///   która istnieje w danych dla obu pozycji (dziś 3/3: 70/40 i 140/72).
///
/// Grubość efektywna t_eff = max(t1, t2) — tak jak dotąd; to parametr
/// danych, nie reguła normy. Wszystkie wartości są startowe: wiąże WPS
/// i próbka.
library;

import 'dart:math' as math;

const double _eps = 1e-4;

class TandemPoint {
  final double t1;
  final double t2;
  final double outsideA;
  final double insideA;

  const TandemPoint({
    required this.t1,
    required this.t2,
    required this.outsideA,
    required this.insideA,
  });

  double get effMm => math.max(t1, t2);
  double get minMm => math.min(t1, t2);

  bool samePair(double a, double b) {
    final lo = math.min(a, b);
    final hi = math.max(a, b);
    return (minMm - lo).abs() < _eps && (effMm - hi).abs() < _eps;
  }
}

enum TandemStatus {
  /// Wpis dla dokładnie tej pary t1/t2.
  exact,

  /// Punkt o tej samej t_eff, ale innej parze t1/t2.
  sameEffective,

  /// Interpolacja liniowa między dwoma punktami.
  interpolated,

  /// Pion: poziom × współczynnik z pary odniesienia.
  scaledFromHorizontal,

  /// Grubość poza zakresem danych — brak wyniku.
  outOfRange,

  /// Brak danych dla tego filtra — brak wyniku.
  noData,
}

class TandemEstimate {
  final TandemStatus status;
  final double? outsideA;
  final double? insideA;

  /// Grubość efektywna zapytania.
  final double effMm;

  /// Zakres t_eff w danych (null, gdy brak danych).
  final double? minEffMm;
  final double? maxEffMm;

  /// Punkty użyte do wyniku (dla exact/sameEffective low == high).
  final TandemPoint? low;
  final TandemPoint? high;
  final double? k;

  /// Prąd maleje przy rosnącej grubości w użytym przedziale.
  final bool nonMonotonic;

  /// Kilka punktów o tej samej t_eff z różnymi prądami (użyto średniej).
  final bool conflicting;

  /// Pion: para odniesienia i współczynniki.
  final TandemPoint? verticalRef;
  final TandemPoint? horizontalRef;
  final TandemEstimate? horizontal;

  const TandemEstimate({
    required this.status,
    required this.effMm,
    this.outsideA,
    this.insideA,
    this.minEffMm,
    this.maxEffMm,
    this.low,
    this.high,
    this.k,
    this.nonMonotonic = false,
    this.conflicting = false,
    this.verticalRef,
    this.horizontalRef,
    this.horizontal,
  });

  bool get hasResult => outsideA != null && insideA != null;
}

class _Group {
  final double eff;
  final List<TandemPoint> pts;
  _Group(this.eff, this.pts);
  double get out => pts.map((p) => p.outsideA).reduce((a, b) => a + b) / pts.length;
  double get inn => pts.map((p) => p.insideA).reduce((a, b) => a + b) / pts.length;
  bool get conflicting => pts.any((p) =>
      (p.outsideA - pts.first.outsideA).abs() > _eps ||
      (p.insideA - pts.first.insideA).abs() > _eps);
}

List<_Group> _groups(List<TandemPoint> pts) {
  final sorted = [...pts]..sort((a, b) => a.effMm.compareTo(b.effMm));
  final out = <_Group>[];
  for (final p in sorted) {
    if (out.isNotEmpty && (out.last.eff - p.effMm).abs() < _eps) {
      out.last.pts.add(p);
    } else {
      out.add(_Group(p.effMm, [p]));
    }
  }
  return out;
}

/// Interpolacja po t_eff = max(t1, t2) tylko w zakresie danych.
TandemEstimate estimateTandem(List<TandemPoint> points, double t1, double t2) {
  final eff = math.max(t1, t2);
  if (!(t1 > 0) || !(t2 > 0) || !eff.isFinite) {
    return TandemEstimate(status: TandemStatus.noData, effMm: eff);
  }
  if (points.isEmpty) {
    return TandemEstimate(status: TandemStatus.noData, effMm: eff);
  }

  for (final p in points) {
    if (p.samePair(t1, t2)) {
      return TandemEstimate(
        status: TandemStatus.exact,
        effMm: eff,
        outsideA: p.outsideA,
        insideA: p.insideA,
        low: p,
        high: p,
        k: 0,
      );
    }
  }

  final gs = _groups(points);
  final minEff = gs.first.eff;
  final maxEff = gs.last.eff;
  if (eff < minEff - _eps || eff > maxEff + _eps) {
    return TandemEstimate(
      status: TandemStatus.outOfRange,
      effMm: eff,
      minEffMm: minEff,
      maxEffMm: maxEff,
    );
  }

  // Czy w przedziale(ach) dotykających t_eff prąd maleje z grubością?
  bool decreasingAround() {
    for (var i = 0; i + 1 < gs.length; i++) {
      final a = gs[i];
      final b = gs[i + 1];
      if (eff < a.eff - _eps || eff > b.eff + _eps) continue;
      if (b.out < a.out - _eps || b.inn < a.inn - _eps) return true;
    }
    return false;
  }

  final nonMono = decreasingAround();

  for (final g in gs) {
    if ((g.eff - eff).abs() < _eps) {
      final p = g.pts.first;
      return TandemEstimate(
        status: TandemStatus.sameEffective,
        effMm: eff,
        outsideA: g.out,
        insideA: g.inn,
        minEffMm: minEff,
        maxEffMm: maxEff,
        low: p,
        high: p,
        k: 0,
        nonMonotonic: nonMono,
        conflicting: g.conflicting,
      );
    }
  }

  late _Group lo;
  late _Group hi;
  for (var i = 0; i + 1 < gs.length; i++) {
    if (gs[i].eff < eff && gs[i + 1].eff > eff) {
      lo = gs[i];
      hi = gs[i + 1];
      break;
    }
  }
  final k = (eff - lo.eff) / (hi.eff - lo.eff);
  return TandemEstimate(
    status: TandemStatus.interpolated,
    effMm: eff,
    outsideA: lo.out + (hi.out - lo.out) * k,
    insideA: lo.inn + (hi.inn - lo.inn) * k,
    minEffMm: minEff,
    maxEffMm: maxEff,
    low: lo.pts.first,
    high: hi.pts.first,
    k: k,
    nonMonotonic: nonMono,
    conflicting: lo.conflicting || hi.conflicting,
  );
}

/// Pion: własny wpis dokładny, a w pozostałych przypadkach poziom
/// przeskalowany parą odniesienia obecną w obu pozycjach.
TandemEstimate estimateTandemVerticalFromHorizontal({
  required List<TandemPoint> horizontal,
  required List<TandemPoint> vertical,
  required double t1,
  required double t2,
}) {
  final eff = math.max(t1, t2);
  if (!(t1 > 0) || !(t2 > 0)) {
    return TandemEstimate(status: TandemStatus.noData, effMm: eff);
  }
  for (final p in vertical) {
    if (p.samePair(t1, t2)) {
      return TandemEstimate(
        status: TandemStatus.exact,
        effMm: eff,
        outsideA: p.outsideA,
        insideA: p.insideA,
        low: p,
        high: p,
        k: 0,
      );
    }
  }

  TandemPoint? vRef;
  TandemPoint? hRef;
  for (final v in vertical) {
    for (final h in horizontal) {
      if (h.samePair(v.t1, v.t2) && h.outsideA > 0 && h.insideA > 0) {
        vRef = v;
        hRef = h;
        break;
      }
    }
    if (vRef != null) break;
  }
  if (vRef == null || hRef == null) {
    return TandemEstimate(status: TandemStatus.noData, effMm: eff);
  }

  final h = estimateTandem(horizontal, t1, t2);
  if (!h.hasResult) {
    return TandemEstimate(
      status: h.status,
      effMm: eff,
      minEffMm: h.minEffMm,
      maxEffMm: h.maxEffMm,
      horizontal: h,
    );
  }
  return TandemEstimate(
    status: TandemStatus.scaledFromHorizontal,
    effMm: eff,
    outsideA: h.outsideA! * vRef.outsideA / hRef.outsideA,
    insideA: h.insideA! * vRef.insideA / hRef.insideA,
    minEffMm: h.minEffMm,
    maxEffMm: h.maxEffMm,
    low: h.low,
    high: h.high,
    k: h.k,
    nonMonotonic: h.nonMonotonic,
    conflicting: h.conflicting,
    verticalRef: vRef,
    horizontalRef: hRef,
    horizontal: h,
  );
}
