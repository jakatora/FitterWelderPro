import 'fitter_calcs.dart';

class PipeWeightResult {
  const PipeWeightResult({required this.kgPerM, this.kgPerPiece, this.kgTotal});
  final double kgPerM;
  final double? kgPerPiece, kgTotal;
}

/// Optional length and quantity stay absent; no hidden 1 m / 1 piece defaults.
PipeWeightResult? pipeWeight(
    {required double odMm,
    required double wallMm,
    required PipeMaterial material,
    double? lengthMm,
    double? quantity}) {
  if (!odMm.isFinite ||
      odMm <= 0 ||
      !wallMm.isFinite ||
      wallMm <= 0 ||
      wallMm >= odMm / 2) {
    return null;
  }
  if (lengthMm != null && (!lengthMm.isFinite || lengthMm <= 0)) return null;
  if (quantity != null &&
      (lengthMm == null ||
          !quantity.isFinite ||
          quantity <= 0 ||
          quantity != quantity.roundToDouble() ||
          quantity > 2147483647)) {
    return null;
  }
  final kgm = pipeMassKgPerM(odMm, wallMm, kPipeDensityKgM3[material]!);
  final piece = lengthMm == null ? null : kgm * lengthMm / 1000;
  final total = quantity == null || piece == null ? null : piece * quantity;
  if (!kgm.isFinite ||
      (piece != null && !piece.isFinite) ||
      (total != null && !total.isFinite)) {
    return null;
  }
  return PipeWeightResult(kgPerM: kgm, kgPerPiece: piece, kgTotal: total);
}
