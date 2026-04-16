import 'dart:math';
import '../../database/tandem_amp_param_dao.dart';

class TandemCalcResult {
  final int insideA;
  final int outsideA;
  final String status; // APPROVED | MY | ESTIMATE
  final String note;
  const TandemCalcResult({required this.insideA, required this.outsideA, required this.status, required this.note});
}

class TandemCalculator {
  TandemCalculator(this._dao);
  final TandemAmpParamDao _dao;

  Future<TandemCalcResult> calculate({
    required String position,
    required double t1Mm,
    required double t2Mm,
    required String tempo,
  }) async {
    final approved = await _dao.getExact(position: position, t1Mm: t1Mm, t2Mm: t2Mm, tempo: tempo, approved: true);
    if (approved != null) {
      return TandemCalcResult(insideA: approved.insideAmps, outsideA: approved.outsideAmps, status: 'APPROVED', note: 'Z biblioteki zatwierdzonych');
    }
    final my = await _dao.getExact(position: position, t1Mm: t1Mm, t2Mm: t2Mm, tempo: tempo, approved: false);
    if (my != null) {
      return TandemCalcResult(insideA: my.insideAmps, outsideA: my.outsideAmps, status: 'MY', note: 'Z moich parametrów');
    }

    final avg = (t1Mm + t2Mm) / 2.0;
    final diff = (t1Mm - t2Mm).abs();

    final pts = await _dao.listPureThickness(position: position, tempo: tempo, approved: true);
    if (pts.isEmpty) {
      final baseIn = (20 + avg * 20).round();
      final baseOut = (40 + avg * 35).round();
      return TandemCalcResult(
        insideA: max(10, baseIn + (6 * diff).round()),
        outsideA: max(10, baseOut + (10 * diff).round()),
        status: 'ESTIMATE',
        note: 'Estymata (brak danych bazowych)',
      );
    }

    var lo = pts.first;
    var hi = pts.last;
    for (final p in pts) {
      if (p.t1Mm <= avg) lo = p;
      if (p.t1Mm >= avg) { hi = p; break; }
    }

    double lerp(double a, double b, double t) => a + (b - a) * t;
    double baseIn;
    double baseOut;

    if ((hi.t1Mm - lo.t1Mm).abs() < 1e-9) {
      baseIn = lo.insideAmps.toDouble();
      baseOut = lo.outsideAmps.toDouble();
    } else {
      final t = ((avg - lo.t1Mm) / (hi.t1Mm - lo.t1Mm)).clamp(0.0, 1.0);
      baseIn = lerp(lo.insideAmps.toDouble(), hi.insideAmps.toDouble(), t);
      baseOut = lerp(lo.outsideAmps.toDouble(), hi.outsideAmps.toDouble(), t);
    }

    final inside = (baseIn + 6.0 * diff).round();
    final outside = (baseOut + 10.0 * diff).round();

    return TandemCalcResult(
      insideA: max(10, inside),
      outsideA: max(10, outside),
      status: 'ESTIMATE',
      note: 'Estymata (interpolacja + korekta różnicy ścianek)',
    );
  }
}
