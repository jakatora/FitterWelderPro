// Zużycie gazu osłonowego i liczba butli — czyste funkcje, bez Fluttera.
//
// Butla opisana jest POJEMNOŚCIĄ WODNĄ (np. 50 L) i ciśnieniem napełnienia
// (np. 200 bar). Ilość gazu po rozprężeniu do ~1 bar to w przybliżeniu gazu
// doskonałego:
//
//   V_gazu [L] ≈ V_wodna [L] × (p_napełnienia − p_rezerwy) [bar]
//
// 50 L × 200 bar ≈ 10 000 L = 10 m³. Dostawcy podają dla argonu 50 L /
// 200 bar ok. 10,7 m³ (np. tabela F.U.H. ALWI „Rodzaj butli / ilość gazu”),
// bo argon przy 200 bar odbiega od gazu doskonałego — przybliżenie jest więc
// o ok. 7 % zachowawcze (wychodzi trochę więcej butli). Współczynnika
// ściśliwości celowo nie wprowadzamy.

/// Rozbicie zużycia gazu na składniki [L].
class GasConsumption {
  const GasConsumption({
    required this.torchL,
    required this.prePostFlowL,
    required this.purgeL,
  });

  /// Gaz w czasie jarzenia łuku.
  final double torchL;

  /// Gaz z wypływu wstępnego i końcowego (pre/post-flow) palnika.
  final double prePostFlowL;

  /// Gaz formujący (purge).
  final double purgeL;

  double get totalL => torchL + prePostFlowL + purgeL;
}

/// Zużycie gazu dla [welds] spoin.
///
///   palnik   = n × t_spawania [min] × Q_palnika [L/min]
///   pre/post = n × (t_pre + t_post) [s] / 60 × Q_palnika
///   purge    = n × t_purge [min] × Q_purge   (0, gdy nie podano)
///
/// Zwraca `null` dla danych, z których nie da się liczyć.
GasConsumption? estimateGasConsumption({
  required double welds,
  required double weldMinutes,
  required double torchLpm,
  double preFlowS = 0,
  double postFlowS = 0,
  double purgeLpm = 0,
  double purgeMinutes = 0,
}) {
  final all = [
    welds,
    weldMinutes,
    torchLpm,
    preFlowS,
    postFlowS,
    purgeLpm,
    purgeMinutes,
  ];
  if (all.any((x) => !x.isFinite || x < 0)) return null;
  if (welds <= 0 || weldMinutes <= 0 || torchLpm <= 0) return null;
  final purge = (purgeLpm > 0 && purgeMinutes > 0)
      ? welds * purgeMinutes * purgeLpm
      : 0.0;
  return GasConsumption(
    torchL: welds * weldMinutes * torchLpm,
    prePostFlowL: welds * (preFlowS + postFlowS) / 60.0 * torchLpm,
    purgeL: purge,
  );
}

/// Użyteczna ilość gazu w jednej butli [L przy ~1 bar], przybliżenie gazu
/// doskonałego: V × (p − p_rezerwy). `null` gdy dane nie mają sensu
/// (pojemność ≤ 0, rezerwa ≥ ciśnienia napełnienia).
double? usableCylinderGasL({
  required double waterCapacityL,
  required double fillPressureBar,
  double reserveBar = 0,
}) {
  if (!waterCapacityL.isFinite || waterCapacityL <= 0) return null;
  if (!fillPressureBar.isFinite || fillPressureBar <= 0) return null;
  if (!reserveBar.isFinite || reserveBar < 0) return null;
  if (reserveBar >= fillPressureBar) return null;
  return waterCapacityL * (fillPressureBar - reserveBar);
}

/// Liczba butli (ułamkowa) potrzebna na [totalGasL].
double? cylindersNeeded({
  required double totalGasL,
  required double usableGasPerCylinderL,
}) {
  if (!totalGasL.isFinite || totalGasL < 0) return null;
  if (!usableGasPerCylinderL.isFinite || usableGasPerCylinderL <= 0) {
    return null;
  }
  return totalGasL / usableGasPerCylinderL;
}
