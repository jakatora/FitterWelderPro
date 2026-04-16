import '../i18n/app_language.dart';

/// Rod optimization utilities for cutting pipe segments into stock bars
/// Uses FFD (First-Fit Decreasing) algorithm for optimal nesting
class BarPlan {
  final List<double> piecesMm;
  final double stockLengthMm;
  final double kerfMm;

  BarPlan({required this.stockLengthMm, required this.kerfMm}) : piecesMm = [];

  /// Number of cuts needed
  int get cutsCount => piecesMm.isEmpty ? 0 : piecesMm.length - 1;

  /// Total length used (pieces + kerf losses)
  double get usedLength {
    if (piecesMm.isEmpty) return 0;
    final kerfLoss = cutsCount * kerfMm;
    return piecesMm.fold<double>(0, (sum, piece) => sum + piece) + kerfLoss;
  }

  /// Remaining length on the bar
  double get remainingLength => (stockLengthMm - usedLength).clamp(0, stockLengthMm);

  /// Whether a piece fits on this bar
  bool canFit(double pieceMm) {
    if (piecesMm.isEmpty) return pieceMm <= stockLengthMm;
    return usedLength + kerfMm + pieceMm <= stockLengthMm;
  }

  /// Add a piece to this bar
  bool addPiece(double pieceMm) {
    if (!canFit(pieceMm)) return false;
    if (piecesMm.isNotEmpty) {
      // Add kerf for the cut before this piece
      piecesMm.add(kerfMm);
    }
    piecesMm.add(pieceMm);
    return true;
  }

  /// Get summary string for the bar
  String summary({int barNumber = 1, AppLanguage language = AppLanguage.pl}) {
    String trL({required String pl, required String en}) => language == AppLanguage.en ? en : pl;

    final pieces = piecesMm.map((m) => m.toStringAsFixed(0)).join(' + ');
    final barLabel = trL(pl: 'Sztanga', en: 'Bar');
    final leftLabel = trL(pl: 'Zostaje', en: 'Left');
    return '$barLabel $barNumber: $pieces = ${usedLength.toStringAsFixed(0)}mm | $leftLabel: ${remainingLength.toStringAsFixed(0)}mm';
  }
}

/// FFD (First-Fit Decreasing) Rod Optimizer
/// Optimally nests cut pieces into stock bars using the FFD algorithm
class RodOptimizer {
  final double stockLengthMm;
  final double kerfMm;

  RodOptimizer({required this.stockLengthMm, required this.kerfMm});

  /// Optimize a list of cut pieces using FFD algorithm
  /// Returns list of BarPlans with pieces nested
  List<BarPlan> optimize(List<double> piecesMm) {
    // Sort pieces in descending order (First-Fit Decreasing)
    final sortedPieces = List<double>.from(piecesMm)
      ..sort((a, b) => b.compareTo(a));

    final bars = <BarPlan>[];

    for (final piece in sortedPieces) {
      bool placed = false;

      // Try to fit in existing bars (First-Fit)
      for (final bar in bars) {
        if (bar.addPiece(piece)) {
          placed = true;
          break;
        }
      }

      // If not placed, create a new bar
      if (!placed) {
        final newBar = BarPlan(stockLengthMm: stockLengthMm, kerfMm: kerfMm);
        newBar.addPiece(piece);
        bars.add(newBar);
      }
    }

    return bars;
  }

  /// Calculate summary statistics for the optimization
  OptimizationResult calculateResult(List<double> piecesMm) {
    final bars = optimize(piecesMm);
    final totalUsed = bars.fold<double>(0, (sum, bar) => sum + bar.usedLength);
    final totalRemaining = bars.fold<double>(0, (sum, bar) => sum + bar.remainingLength);

    return OptimizationResult(
      bars: bars,
      totalBarsNeeded: bars.length,
      totalPieces: piecesMm.length,
      totalUsedLength: totalUsed,
      totalRemainingLength: totalRemaining,
      totalKerfLoss: bars.fold<double>(0, (sum, bar) => sum + (bar.cutsCount * kerfMm)),
      efficiency: piecesMm.isEmpty ? 0 : (piecesMm.reduce((a, b) => a + b) / totalUsed) * 100,
    );
  }
}

/// Result of rod optimization
class OptimizationResult {
  final List<BarPlan> bars;
  final int totalBarsNeeded;
  final int totalPieces;
  final double totalUsedLength;
  final double totalRemainingLength;
  final double totalKerfLoss;
  final double efficiency;

  OptimizationResult({
    required this.bars,
    required this.totalBarsNeeded,
    required this.totalPieces,
    required this.totalUsedLength,
    required this.totalRemainingLength,
    required this.totalKerfLoss,
    required this.efficiency,
  });

  /// Get summary string for display
  String getSummary({AppLanguage language = AppLanguage.pl}) {
    String trL({required String pl, required String en}) => language == AppLanguage.en ? en : pl;

    final barsLabel = trL(pl: 'Sztang', en: 'Bars');
    final wasteLabel = trL(pl: 'Odpad', en: 'Waste');
    final efficiencyLabel = trL(pl: 'Efektywność', en: 'Efficiency');
    return '$barsLabel: $totalBarsNeeded | $wasteLabel: ${totalRemainingLength.toStringAsFixed(0)}mm | $efficiencyLabel: ${efficiency.toStringAsFixed(1)}%';
  }

  /// Group pieces by diameter and thickness for multi-size optimization
  Map<String, List<double>> groupByDimensions(List<CutPiece> pieces) {
    final groups = <String, List<double>>{};
    for (final piece in pieces) {
      final key = '${piece.diameterMm.toStringAsFixed(0)}|${piece.wallThicknessMm.toStringAsFixed(1)}';
      groups.putIfAbsent(key, () => []).add(piece.cutMm);
    }
    return groups;
  }
}

/// Represents a cut piece with its dimensions
class CutPiece {
  final double cutMm;
  final double diameterMm;
  final double wallThicknessMm;
  final int? segmentId;
  final int? runId;

  CutPiece({
    required this.cutMm,
    required this.diameterMm,
    required this.wallThicknessMm,
    this.segmentId,
    this.runId,
  });

  /// Calculate waste percentage for this piece
  double getWasteRatio(double stockLength) {
    return (stockLength - cutMm) / stockLength * 100;
  }
}

/// Extended BarPlan that tracks piece origins
class TrackedBarPlan extends BarPlan {
  final List<BarPieceOrigin> pieceOrigins;

  TrackedBarPlan({required super.stockLengthMm, required super.kerfMm}) : pieceOrigins = [];

  @override
  bool addPiece(double pieceMm, {int? segmentId, int? runId}) {
    if (!canFit(pieceMm)) return false;
    if (piecesMm.isNotEmpty) {
      piecesMm.add(kerfMm);
      pieceOrigins.add(BarPieceOrigin(type: OriginType.kerf));
    }
    piecesMm.add(pieceMm);
    pieceOrigins.add(BarPieceOrigin(
      type: OriginType.piece,
      segmentId: segmentId,
      runId: runId,
    ));
    return true;
  }
}

enum OriginType { piece, kerf }

class BarPieceOrigin {
  final OriginType type;
  final int? segmentId;
  final int? runId;

  BarPieceOrigin({required this.type, this.segmentId, this.runId});
}
